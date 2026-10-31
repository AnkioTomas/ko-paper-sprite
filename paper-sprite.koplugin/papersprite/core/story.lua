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

local Story = { TIMEOUT = 180, MAX_LINE = 40, MAX_NARR = 80, MAX_TRIES = 2, MAX_NOTE = 40 }

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

--- 字数上限是按中文写的；回答语言是英文时同样意思要多出几倍字符，放宽上限（月读 AI 回答语言设置，离线测试里没有月读客户端）
local function slack()
    local ok, Client = pcall(require, "ai.client")
    local lang = ok and Client.language and Client.language()
    return lang and lang.name == "English" and 3 or 1
end

local function clean(s, max)
    if type(s) ~= "string" then return nil end
    max = max * slack()
    s = s:gsub("[\r\n\t]+", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub('^["“「]', ""):gsub('["”」]$', "")
    if s == "" then return nil end
    local n = 0
    for _ in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end
    if n > max then return nil end
    if s:find("[<>{}]") or s:lower():find("http") then return nil end
    return s
end

Story.clean = clean

--- 只有用户提示的消息（系统提示固定）
function Story.plain(user) return { { role = "system", content = SYSTEM }, { role = "user", content = user } } end

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

local BANDS = { { "dawn", "清晨" }, { "day", "白天" }, { "dusk", "傍晚" }, { "night", "夜里" } }
local PER_BAND = 3

local function bandKey(hour)
    if hour >= 5 and hour < 9 then return "dawn", "清晨" end
    if hour >= 9 and hour < 17 then return "day", "白天" end
    if hour >= 17 and hour < 21 then return "dusk", "傍晚" end
    return "night", "夜里"
end
function Story.band(hour) return select(2, bandKey(hour)) end

--- 一批小纸条一次要回来：每个时段 PER_BAND 张，存进 s.pool.notes，之后每个时段取一张，不再临时等请求
local function validateNotes(r)
    if type(r) ~= "table" then return nil end
    local out = {}
    for _, b in ipairs(BANDS) do
        out[b[1]] = {}
        for i = 1, PER_BAND do
            local t = type(r[b[1]]) == "table" and clean(r[b[1]][i], Story.MAX_NOTE) or nil
            if t then out[b[1]][#out[b[1]] + 1] = t end
        end
    end
    return out
end

--- 阁楼「今天的纸条」：每个「日期 + 时段」一张，先从预取池里取；池里某个时段见底时，后台一次补一批。返回是否发起请求
function Story.maybeDaily(host, s, on_done)
    local sp = s.sprite
    if sp.status == "away" then return false end
    local now = host:now()
    local day = os.date("%Y-%m-%d", now)
    local hour = os.date("*t", now).hour
    local bk, bname = bandKey(hour)
    local key = day .. bname
    s.pool = s.pool or {}
    s.pool.notes = s.pool.notes or {}
    local pn = s.pool.notes
    if not (s.daily and s.daily.key == key) and pn[bk] and #pn[bk] > 0 then
        s.daily = { key = key, text = table.remove(pn[bk], 1) }
    end
    local low = false
    for _, b in ipairs(BANDS) do if not pn[b[1]] or #pn[b[1]] < 1 then low = true end end
    local try = s.daily_try
    if not low or (try and (try.n >= Story.MAX_TRIES or (try.busy and now - try.busy < Story.TIMEOUT))) then return false end
    if type(host.ai) ~= "function" or not host:ai() then return false end
    local n0 = try and try.n or 0
    local fest = require("papersprite.core.festival").at(s, now)
    local log = s.log[#s.log]
    local user = table.concat({
        "为阿页在阁楼里（没有出门）的日子，预先写一批书桌上的小纸条，说它此刻在做什么 / 想什么。",
        "分四个时段：dawn 清晨、day 白天、dusk 傍晚、night 夜里，每个时段 " .. PER_BAND .. " 张，每张≤" .. Story.MAX_NOTE .. "字，第三人称或自言自语均可，同一批里别重复。",
        fest and ("近期有「" .. fest.name .. "」，可以带一点气氛。") or "",
        log and ("阁楼里最近的一件事：" .. log) or "阁楼里最近很安静。",
        '只输出 JSON：{"dawn":["…"],"day":["…"],"dusk":["…"],"night":["…"]}',
    }, "\n")
    s.daily_try = { n = n0, busy = now }
    local started = ask(host, { { role = "system", content = SYSTEM }, { role = "user", content = user } }, validateNotes, function(result)
        local cur = reload(host)
        cur.daily_try = { n = n0 + 1 }
        if result then
            cur.pool = cur.pool or {}
            cur.pool.notes = cur.pool.notes or {}
            for _, b in ipairs(BANDS) do
                local dst = cur.pool.notes[b[1]] or {}
                for _, t in ipairs(result[b[1]]) do dst[#dst + 1] = t end
                cur.pool.notes[b[1]] = dst
            end
            cur.daily_try = nil
        end
        host:saveState(cur)
        if result and on_done then pcall(on_done, cur) end
    end)
    if not started then s.daily_try = try end
    return started
end

--- 来客时预取它被招待时的反应（送了想要的 / 随便一件），存在 visitor.react，招待时直接用，不用等
function Story.maybeGuest(host, s, on_done)
    local v = s.visitor
    if not v or v.fed or v.react or s.sprite.status == "away" then return false end
    local now = host:now()
    if (v.react_fails or 0) >= Story.MAX_TRIES or (v.react_req and now - v.react_req < Story.TIMEOUT) then return false end
    if type(host.ai) ~= "function" or not host:ai() then return false end
    local def
    for _, x in ipairs(require("papersprite.data.visitors")) do if x.id == v.id then def = x end end
    local want = v.request and Postcards.souvenirs[v.request]
    v.react_req = now
    local user = table.concat({
        "阿页阁楼里来了小客人「" .. (def and def.name or v.id) .. "」。阿页递给它一件特产，写客人收下时的反应。",
        want and ("它其实想要「" .. want.name .. "」。") or "它没有特别想要的东西。",
        "写两句，各≤" .. Story.MAX_LINE .. "字，客人口吻或第三人称描写均可：",
        'match = 递的正是它想要的；plain = 递的是别的特产（依然高兴）。',
        "另写 here：它在阁楼里待着时的一句描写（≤" .. Story.MAX_LINE .. "字）。",
        '只输出 JSON：{"match":"…","plain":"…","here":"…"}',
    }, "\n")
    local id = v.id
    return ask(host, { { role = "system", content = SYSTEM }, { role = "user", content = user } }, function(r)
        if type(r) ~= "table" then return nil end
        local m, p = clean(r.match, Story.MAX_LINE), clean(r.plain, Story.MAX_LINE)
        return m and p and { match = m, plain = p, here = clean(r.here, Story.MAX_LINE) } or nil
    end, function(result)
        local cur = reload(host)
        local cv = cur.visitor
        if not cv or cv.id ~= id or cv.fed then return end
        if result then
            cv.react = { match = result.match, plain = result.plain }
            cv.line = cv.line or result.here
        else cv.react_req, cv.react_fails = nil, (cv.react_fails or 0) + 1 end
        host:saveState(cur)
        if result and on_done then pcall(on_done, cur) end
    end)
end

return Story
