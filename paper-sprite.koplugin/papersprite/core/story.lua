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

local Story = { TIMEOUT = 180, MAX_LINE = 40, MAX_NARR = 80, MAX_TRIES = 2, MAX_NOTE = 40, MAX_LETTER = 140 }

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
        '{"note":"出门前留在书桌上的一张小纸条，≤24字",',
        '"lines":["每张明信片一句，≤' .. Story.MAX_LINE .. '字，数量与明信片相同"],',
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
    out.note = clean(r.note, 24)
    out.narration = clean(r.narration, Story.MAX_NARR)
    out.souvenir_note = clean(r.souvenir_note, 30)
    out.visitor_line = clean(r.visitor_line, Story.MAX_LINE)
    return out
end

--- 统一的请求外壳：有 AI 才发；抛错 / 超时（自动 cancel）/ 校验不过都回调 nil。返回是否发起。
---@param validate fun(r: any): any|nil
---@param on_done fun(result: any|nil)
local function ask(host, messages, validate, on_done)
    local ai = type(host.ai) == "function" and host:ai() or nil
    if not ai then return false end
    local done, handle = false, nil
    local function finish(result)
        if done then return end
        done = true
        on_done(result)
    end
    local ok = pcall(function()
        handle = ai.json(messages, function(r, _err) finish(validate(r)) end)
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
Story.ask = ask

local function lastLines(s, n)
    local recent = {}
    for i = math.max(1, #s.postcards - n + 1), #s.postcards do
        if s.postcards[i].line then recent[#recent + 1] = s.postcards[i].line end
    end
    return recent
end

--- 重读存档再改：回调时界面可能已关、存档可能已被别处改过
local function reload(host) return State.load(host:loadState(), host:now()) end

--- 若需要，为当前这趟发起请求。返回是否发起。
---@param host table 宿主（host:ai() 可选）
---@param s table 存档（会被标记 ai_req）
---@param on_done fun(s: table)|nil 写入后回调（界面刷新用）
function Story.maybeRequest(host, s, on_done)
    local sp = s.sprite
    local now = host:now()
    -- 请求在飞（TIMEOUT 内）不重发；界面中途关掉没等到回调的，过了 TIMEOUT 允许再来
    local inflight = sp.ai_req == sp.trip and now - (sp.ai_req_at or 0) < Story.TIMEOUT
    if sp.status ~= "away" or inflight or (sp.ai and sp.ai.trip == sp.trip) or (sp.ai_fails or 0) >= Story.MAX_TRIES then return false end
    if type(host.ai) ~= "function" or not host:ai() then return false end
    sp.ai_req, sp.ai_req_at = sp.trip, now
    local trip, n = sp.trip, #sp.mail
    local ctx = { festival = require("papersprite.core.festival").at(s, sp.left_at), recent = lastLines(s, 5) }
    return ask(host, Story.messages(sp, ctx), function(r) return Story.validate(r, n) end, function(result)
        local cur = reload(host)
        if cur.sprite.trip ~= trip or cur.sprite.status ~= "away" then return end
        if not result then -- 失败：放开请求标记，下次刷新再试（最多 MAX_TRIES 次）
            cur.sprite.ai_req, cur.sprite.ai_req_at = nil, nil
            cur.sprite.ai_fails = (cur.sprite.ai_fails or 0) + 1
            host:saveState(cur)
            return
        end
        result.trip = trip
        cur.sprite.ai = result
        if result.note then cur.note = result.note end
        host:saveState(cur)
        if on_done then pcall(on_done, cur) end
    end)
end

--- 整趟旅行在界面关着时就走完了（没赶上请求）：回家时 Travel 留下 s.recap，之后补写，改写那几张明信片的句子和特产小注
function Story.maybeRecap(host, s, on_done)
    local rc = s.recap
    local now = host:now()
    if not rc or (rc.req and now - rc.req < Story.TIMEOUT) or (rc.fails or 0) >= Story.MAX_TRIES then return false end
    if type(host.ai) ~= "function" or not host:ai() then return false end
    rc.req = now
    local sp = { place = rc.place, souvenir = rc.souvenir, hours = rc.hours, basket = rc.basket, mail = {} }
    for _, c in ipairs(rc.cards) do sp.mail[#sp.mail + 1] = { card = c } end
    local ctx = { festival = require("papersprite.core.festival").at(s, rc.left_at), recent = lastLines(s, 5) }
    local trip, n = rc.trip, #rc.cards
    return ask(host, Story.messages(sp, ctx), function(r) return Story.validate(r, n) end, function(result)
        local cur = reload(host)
        local c = cur.recap
        if not c or c.trip ~= trip then return end
        if not result then
            c.req, c.fails = nil, (c.fails or 0) + 1
            host:saveState(cur)
            return
        end
        require("papersprite.core.travel").applyRecap(cur, result)
        host:saveState(cur)
        if on_done then pcall(on_done, cur) end
    end)
end

local function band(hour)
    if hour >= 5 and hour < 9 then return "清晨" end
    if hour >= 9 and hour < 17 then return "白天" end
    if hour >= 17 and hour < 21 then return "傍晚" end
    return "夜里"
end
Story.band = band

--- 阁楼「今天的纸条」：阿页在家（或收拾好等出门）时，一天一张；每天最多试 MAX_TRIES 次
---@return boolean 是否发起
function Story.maybeDaily(host, s, on_done)
    local sp = s.sprite
    if sp.status == "away" then return false end
    local now = host:now()
    local day = os.date("%Y-%m-%d", now)
    local hour = os.date("*t", now).hour
    local key = day .. band(hour)
    if s.daily and s.daily.key == key then return false end
    local try = s.daily_try
    if try and try.key == key and (try.n >= Story.MAX_TRIES or (try.busy and now - try.busy < Story.TIMEOUT)) then return false end
    if type(host.ai) ~= "function" or not host:ai() then return false end
    local n0 = try and try.key == key and try.n or 0
    s.daily_try = { key = key, n = n0, busy = now }
    local fest = require("papersprite.core.festival").at(s, now)
    local log = s.log[#s.log]
    local user = table.concat({
        "现在是" .. day .. "的" .. band(hour) .. "，阿页在阁楼里（没有出门）。",
        fest and ("今天是「" .. fest.name .. "」。") or "今天不是什么特别的日子。",
        log and ("阁楼里最近的一件事：" .. log) or "阁楼里最近很安静。",
        "写一张阿页留在书桌上的小纸条，说它此刻在做什么 / 想什么，≤" .. Story.MAX_NOTE .. "字，第三人称或自言自语均可，别和上面的事一字不差。",
        '只输出 JSON：{"note":"……"}',
    }, "\n")
    local messages = { { role = "system", content = SYSTEM }, { role = "user", content = user } }
    local started = ask(host, messages, function(r) return type(r) == "table" and clean(r.note, Story.MAX_NOTE) or nil end, function(result)
        local cur = reload(host)
        cur.daily_try = { key = key, n = n0 + 1 }
        if result then cur.daily = { key = key, text = result } end
        host:saveState(cur)
        if result and on_done then pcall(on_done, cur) end
    end)
    if not started then s.daily_try = try end
    return started
end

--- 明信片的长信：玩家在明信片页点「请阿页多写几句」才发起；写进 postcard.letter
---@param idx integer 明信片序号
---@param on_done fun(s: table|nil)
function Story.requestLetter(host, s, idx, on_done)
    local c = s.postcards[idx]
    if not c or c.letter then return false end
    local p = Postcards.place(c.place)
    local user = table.concat({
        "阿页在「" .. (p and p.name or c.place) .. "」寄回一张明信片：天气/时刻 " .. (Postcards.weather_names[c.weather] or c.weather)
            .. "，姿势 " .. c.pose .. "，小物 " .. c.prop .. "。",
        "明信片上原本只有一句：" .. (c.line or ""),
        "请阿页再多写几句，像明信片背面的话，第一人称，" .. Story.MAX_LETTER .. "字以内，和原来那句不要重复，别说教。",
        '只输出 JSON：{"letter":"……"}',
    }, "\n")
    local messages = { { role = "system", content = SYSTEM }, { role = "user", content = user } }
    local at, key = c.at, c.key
    return ask(host, messages, function(r) return type(r) == "table" and clean(r.letter, Story.MAX_LETTER) or nil end, function(result)
        if not result then return on_done(nil) end
        local cur = reload(host)
        for _, pc in ipairs(cur.postcards) do
            if pc.key == key and pc.at == at then pc.letter = result host:saveState(cur) return on_done(cur) end
        end
        on_done(nil)
    end)
end

return Story
