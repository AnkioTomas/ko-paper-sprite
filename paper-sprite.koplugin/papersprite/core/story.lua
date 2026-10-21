-- SPDX-License-Identifier: MIT
--[[--
可选 AI 文案层。阿页出门后，若宿主提供 AI（月读已配置 AI 时，host:ai() 非 nil），
异步请求本趟的旅行旁白、每张明信片的短句、特产小注和访客台词，结构化 JSON 校验后写进存档
（sprite.ai，按 trip 编号对号入座），之后离线也能看。
任何失败（未配置 / 离线 / 超时 / 返回不合规）都静默放弃，旅行照常使用本地文案库。
从不阻塞界面：请求在后台进行，结果到了只写存档，下次刷新时生效。
详见 docs/ai.md。
--]]
local Postcards = require("papersprite.data.postcards")
local State = require("papersprite.core.state")

local Story = { TIMEOUT = 180, MAX_LINE = 40, MAX_NARR = 80, MAX_TRIES = 2 }

local SYSTEM = table.concat({
    "你为一个阅读器里的小游戏写文案。主角「阿页」是一张旧书签变成的小纸灵：折纸身子，头顶一个卷起的书角，没有嘴，话少、好奇、温柔。",
    "世界是原创的「书中世界」，地点都由书和纸的意象构成。",
    "要求：简体中文；第一人称（阿页口吻）写明信片；不提任何真实的书名、作者、游戏、动画、品牌或人物；不出现暴力、悲伤或说教；",
    "只输出一个 JSON 对象，不要任何解释或 Markdown。",
}, "")

--- 构造本趟的提示词（纯函数，便于测试）
---@param ctx table|nil { festival = 节日定义, recent = { 最近收到的几句 } }：节日写进提示，最近的句子让 AI 避开
function Story.messages(sp, ctx)
    ctx = ctx or {}
    local p = Postcards.place(sp.place)
    local sv = Postcards.souvenirs[sp.souvenir]
    local cards = {}
    for i, m in ipairs(sp.mail) do
        cards[#cards + 1] = string.format("%d. 天气/时刻：%s；阿页的姿势：%s；画面里的小物：%s",
            i, Postcards.weather_names[m.card.weather] or m.card.weather, m.card.pose, m.card.prop)
    end
    local parts = {
        "这一趟：阿页去了「" .. p.name .. "」，大约 " .. (sp.hours or 6) .. " 小时。",
        "行囊里带了：" .. table.concat(sp.basket or {}, "、") .. "。",
        "会带回的特产：" .. sv.name .. "（" .. sv.note .. "）。",
        "要寄回 " .. #sp.mail .. " 张明信片，画面分别是：\n" .. table.concat(cards, "\n"),
        "参考这个地点的语气：" .. p.lines[1],
    }
    if ctx.festival then
        parts[#parts + 1] = "出门这天是「" .. ctx.festival.name .. "」，可以自然地带一点节日的气氛，但不要照搬节日常见套话。"
    end
    if ctx.recent and #ctx.recent > 0 then
        parts[#parts + 1] = "最近寄过这些句子，请避免雷同：\n" .. table.concat(ctx.recent, "\n")
    end
    for _, x in ipairs({
        "按下面的 JSON 结构输出：",
        '{"lines":["每张明信片一句，≤' .. Story.MAX_LINE .. '字，数量与明信片相同"],',
        '"narration":"回家时的一句旁白，第三人称，≤' .. Story.MAX_NARR .. '字",',
        '"souvenir_note":"特产的一句小注，≤30字",',
        '"visitor_line":"如果有小访客来串门，阁楼里的一句描写，≤40字"}',
    }) do parts[#parts + 1] = x end
    local user = table.concat(parts, "\n")
    return { { role = "system", content = SYSTEM }, { role = "user", content = user } }
end

local function clean(s, max)
    if type(s) ~= "string" then return nil end
    s = s:gsub("[\r\n\t]+", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub('^["“「]', ""):gsub('["”」]$', "")
    if s == "" then return nil end
    local n = 0
    for _ in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end
    if n > max then return nil end
    if s:find("[<>{}]") or s:lower():find("http") then return nil end
    return s
end

--- 校验 AI 结果，返回规范化后的表或 nil
function Story.validate(r, n_cards)
    if type(r) ~= "table" or type(r.lines) ~= "table" then return nil end
    local out = { lines = {} }
    local seen = {}
    local norm = require("papersprite.core.travel").norm
    for i = 1, n_cards do
        local l = clean(r.lines[i], Story.MAX_LINE)
        if not l then return nil end -- 句数不够或有不合规的整体放弃，保持同一趟风格一致
        local k = norm(l)
        if seen[k] then return nil end -- 同一趟里两句一样：整体放弃
        seen[k] = true
        out.lines[i] = l
    end
    out.narration = clean(r.narration, Story.MAX_NARR)
    out.souvenir_note = clean(r.souvenir_note, 30)
    out.visitor_line = clean(r.visitor_line, Story.MAX_LINE)
    return out
end

--- 若需要，为当前这趟发起请求。返回是否发起。
---@param host table 宿主（host:ai() 可选）
---@param s table 存档（会被标记 ai_req）
---@param on_done fun(s: table)|nil 写入后回调（界面刷新用）
function Story.maybeRequest(host, s, on_done)
    local sp = s.sprite
    if sp.status ~= "away" or sp.ai_req == sp.trip or (sp.ai and sp.ai.trip == sp.trip) or (sp.ai_fails or 0) >= Story.MAX_TRIES then return false end
    local ai = type(host.ai) == "function" and host:ai() or nil
    if not ai then return false end
    sp.ai_req = sp.trip
    local trip, n = sp.trip, #sp.mail
    local done = false
    local handle
    local function finish(result)
        if done then return end
        done = true
        -- 回调时界面可能已关、存档可能已被别处改过：重读存档，同一趟才写
        local cur = State.load(host:loadState(), host:now())
        if cur.sprite.trip ~= trip or cur.sprite.status ~= "away" then return end
        if not result then -- 失败：放开请求标记，下次刷新再试（最多 MAX_TRIES 次）
            cur.sprite.ai_req = nil
            cur.sprite.ai_fails = (cur.sprite.ai_fails or 0) + 1
            host:saveState(cur)
            return
        end
        result.trip = trip
        cur.sprite.ai = result
        host:saveState(cur)
        if on_done then pcall(on_done, cur) end
    end
    local recent = {}
    for i = math.max(1, #s.postcards - 4), #s.postcards do
        if s.postcards[i].line then recent[#recent + 1] = s.postcards[i].line end
    end
    local ctx = { festival = require("papersprite.core.festival").at(s, sp.left_at), recent = recent }
    local ok = pcall(function()
        handle = ai.json(Story.messages(sp, ctx), function(r, _err)
            finish(Story.validate(r, n))
        end)
    end)
    if not ok then done = true return false end
    host:schedule(Story.TIMEOUT, function()
        if not done then
            if handle and handle.cancel then pcall(handle.cancel) end
            finish(nil)
        end
    end)
    return true
end

return Story
