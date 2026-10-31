-- SPDX-License-Identifier: MIT
--[[--
AI 预取池：在后台提前要好一批文案存进存档（s.pool），用到时直接取，不等请求；池空 / 没 AI 就用本地文案。
四类：地点明信片句（pool.lines[地点]）、旅途事件改写（pool.events[事件]）、委托托词（挂在 quests.list[i].flavor）、
来客的「在家」描写（visitor.line，随招待反应一起要）。请求外壳、超时、重试都复用 Story.ask。
详见 docs/ai.md。
--]]
local Story = require("papersprite.core.story")
local State = require("papersprite.core.state")
local Postcards = require("papersprite.data.postcards")
local Places = require("papersprite.data.places")
local Events = require("papersprite.data.events")

local Pool = { PER_PLACE = 4, PLACES_PER_REQ = 4, PER_EVENT = 2, MAX_LINE = 40 }

local function bucket(s, name)
    s.pool = s.pool or {}
    s.pool[name] = s.pool[name] or {}
    return s.pool[name]
end

--- 取一句没收到过的地点句（池里已见过的直接丢）；没有返回 nil
---@param seen fun(s: table, text: string): boolean
function Pool.takeLine(s, place, seen)
    local list = bucket(s, "lines")[place]
    while list and #list > 0 do
        local line = table.remove(list, 1)
        if not seen(s, line) then return line end
    end
    return nil
end

--- 事件的文字：池里有改写版就用一条，否则原文
function Pool.eventText(s, ev)
    local list = bucket(s, "events")[ev.id]
    if list and #list > 0 then return table.remove(list, 1) end
    return ev.text
end

local function reload(host) return State.load(host:loadState(), host:now()) end

--- 一类预取的统一收口：busy / 失败次数记在 s.pool_try[kind]；返回是否发起
local function fill(host, s, kind, user, validate, apply, on_done)
    if type(host.ai) ~= "function" or not host:ai() then return false end
    local now = host:now()
    s.pool_try = s.pool_try or {}
    local try = s.pool_try[kind]
    if try and (try.n >= Story.MAX_TRIES or (try.busy and now - try.busy < Story.TIMEOUT)) then return false end
    local n0 = try and try.n or 0
    s.pool_try[kind] = { n = n0, busy = now }
    local ok = Story.ask(host, Story.plain(user), validate, function(result)
        local cur = reload(host)
        cur.pool_try = cur.pool_try or {}
        cur.pool_try[kind] = { n = n0 + 1 }
        if result and apply(cur, result) then cur.pool_try[kind] = nil end
        host:saveState(cur)
        if result and on_done then pcall(on_done, cur) end
    end)
    if not ok then s.pool_try[kind] = try end
    return ok
end

local function lines5(r, key, max)
    local out = {}
    for _, t in ipairs(type(r) == "table" and type(r[key]) == "table" and r[key] or {}) do
        t = Story.clean(t, max)
        if t then out[#out + 1] = t end
    end
    return out
end

local function fillLines(host, s, on_done)
    local stock = bucket(s, "lines")
    local order = {}
    for _, p in ipairs(Places) do
        if #(stock[p.id] or {}) < 2 then order[#order + 1] = p end
    end
    if #order == 0 then return false end
    table.sort(order, function(a, b)
        local pt = s.place_trips or {}
        return (pt[a.id] or 0) > (pt[b.id] or 0) end)
    local ids, parts = {}, {}
    for i = 1, math.min(Pool.PLACES_PER_REQ, #order) do
        local p = order[i]
        ids[#ids + 1] = p.id
        parts[#parts + 1] = p.id .. "：" .. p.name .. "；参考语气：" .. p.lines[1]
    end
    local user = table.concat({
        "为阿页的旅行明信片预先写短句。下面每个地点写 " .. Pool.PER_PLACE .. " 句，第一人称（阿页口吻），每句≤" .. Pool.MAX_LINE .. "字，同一地点的句子互不相同，要有具体的画面：",
        table.concat(parts, "\n"),
        '只输出 JSON，键是地点 id：{"' .. ids[1] .. '":["…"]}',
    }, "\n")
    return fill(host, s, "lines", user, function(r)
        if type(r) ~= "table" then return nil end
        local out, any = {}, false
        for _, id in ipairs(ids) do
            out[id] = lines5(r, id, Pool.MAX_LINE)
            any = any or #out[id] > 0
        end
        return any and out or nil
    end, function(cur, out)
        local st = bucket(cur, "lines")
        for id, list in pairs(out) do
            st[id] = st[id] or {}
            for _, t in ipairs(list) do st[id][#st[id] + 1] = t end
        end
        return true
    end, on_done)
end

local function fillEvents(host, s, on_done)
    local stock = bucket(s, "events")
    local low = false
    for _, e in ipairs(Events) do if #(stock[e.id] or {}) < 1 then low = true end end
    if not low then return false end
    local parts = {}
    for _, e in ipairs(Events) do parts[#parts + 1] = e.id .. "：" .. e.text end
    local user = table.concat({
        "阿页旅途中会遇到下面这些小事件。为每个事件改写 " .. Pool.PER_EVENT .. " 种说法，意思和结果不变（比如「多寄一张」「特产多一份」「得到灵感」），语气温柔，每句≤" .. Pool.MAX_LINE .. "字：",
        table.concat(parts, "\n"),
        '只输出 JSON，键是事件 id：{"' .. Events[1].id .. '":["…","…"]}',
    }, "\n")
    return fill(host, s, "events", user, function(r)
        if type(r) ~= "table" then return nil end
        local out, any = {}, false
        for _, e in ipairs(Events) do
            out[e.id] = lines5(r, e.id, Pool.MAX_LINE)
            any = any or #out[e.id] > 0
        end
        return any and out or nil
    end, function(cur, out)
        local st = bucket(cur, "events")
        for id, list in pairs(out) do
            st[id] = st[id] or {}
            for _, t in ipairs(list) do st[id][#st[id] + 1] = t end
        end
        return true
    end, on_done)
end

local function fillQuests(host, s, on_done)
    local todo = {}
    for i, q in ipairs((s.quests or {}).list or {}) do
        if not q.flavor then todo[#todo + 1] = { i = i, id = q.id, text = require("papersprite.core.quest").describe(q) } end
    end
    if #todo == 0 then return false end
    local parts = {}
    for n, q in ipairs(todo) do parts[#parts + 1] = n .. ". " .. q.text end
    local user = table.concat({
        "阿页的阁楼里贴着一些小委托（给玩家的小目标）。为下面每条写一句像「书桌上的便签」一样的托词，说明阿页为什么想要这个，口吻温柔有画面，≤" .. Pool.MAX_LINE .. "字，不要重复委托原文里的数字：",
        table.concat(parts, "\n"),
        '只输出 JSON，按顺序：{"flavors":["…"]}',
    }, "\n")
    return fill(host, s, "quests", user, function(r)
        local list = lines5(r, "flavors", Pool.MAX_LINE)
        return #list > 0 and list or nil
    end, function(cur, list)
        local ql = (cur.quests or {}).list or {}
        for n, q in ipairs(todo) do
            if list[n] and ql[q.i] and ql[q.i].id == q.id and not ql[q.i].flavor then ql[q.i].flavor = list[n] end
        end
        return true
    end, on_done)
end

--- 每次刷新时调用：哪类见底就后台补哪类，互不阻塞
function Pool.maybeFill(host, s, on_done)
    local a = fillLines(host, s, on_done)
    local b = fillEvents(host, s, on_done)
    local c = fillQuests(host, s, on_done)
    return a or b or c
end

return Pool
