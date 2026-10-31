-- SPDX-License-Identifier: MIT
--[[--
旅行调度：不用后台定时器。每次打开（或界面刷新）时用「现在 - 上次」的真实时间一次性结算。
状态机：home →(放满行囊) packed →(等待) away →(旅程结束) home
  packed：packed_at，depart_at
  away：trip（唯一编号），place，left_at，return_at，mail = { {at, card} }（出发时排好，card 为分层组合）
  sprite.ai：可选的 AI 文案（core/story.lua 异步写入），寄达 / 回家时优先使用，缺了用本地库
时长（原创数值）：出发等待 20–90 分钟，旅程 3–30 小时；debug_fast 时分钟→秒、小时→10 秒。
--]]
local L = require("papersprite.l10n")
local Items = require("papersprite.data.items")
local Places = require("papersprite.data.places")
local Postcards = require("papersprite.data.postcards")
local Visitors = require("papersprite.data.visitors")
local R = require("papersprite.core.rng")
local Lines = require("papersprite.data.lines")
local Notes = require("papersprite.data.notes")
local Festival = require("papersprite.core.festival")
local State = require("papersprite.core.state")
local Quest = require("papersprite.core.quest")
local Events = require("papersprite.data.events")
local Reading = require("papersprite.core.reading")

local T = {}

T.SLOTS = { "food", "charm", "book" }

function T.timing(debug_fast)
    if debug_fast then return { min = 1, hour = 10 } end
    return { min = 60, hour = 3600 }
end

local function item(id) for _, it in ipairs(Items) do if it.id == id then return it end end end
T.item = item

--- 家里常备（price = 0）的东西取之不尽
function T.staple(id) local it = item(id) return it and it.price == 0 end
function T.count(s, id) if T.staple(id) then return math.huge end return s.inventory[id] or 0 end

function T.basketFull(s)
    for _, slot in ipairs(T.SLOTS) do if not s.basket[slot] then return false end end
    return true
end

function T.put(s, id, now, debug_fast)
    local it = item(id)
    if not it or T.count(s, id) <= 0 or s.sprite.status == "away" then return false end
    local old = s.basket[it.slot]
    if old and not T.staple(old) then s.inventory[old] = (s.inventory[old] or 0) + 1 end
    if not T.staple(id) then s.inventory[id] = s.inventory[id] - 1 end
    s.basket[it.slot] = id
    if T.basketFull(s) and s.sprite.status == "home" then
        local u = T.timing(debug_fast)
        local f
        s.seed, f = R.next(s.seed)
        s.sprite = { status = "packed", packed_at = now, depart_at = now + math.floor((20 + f * 70) * u.min) }
    end
    return true
end

local function choosePlace(s, at)
    -- 灵感「惦记」：下一趟直达该地，用过即清
    if s.wish_place then
        local wish = T.place(s.wish_place)
        s.wish_place = nil
        if wish then return wish end
    end
    local weight = {}
    for _, slot in ipairs(T.SLOTS) do
        local it = item(s.basket[slot])
        for _, tag in ipairs(it and it.tags or {}) do weight[tag] = (weight[tag] or 0) + 2 end
    end
    -- 刚读的书把阿页往对应的地方引
    if s.read_tag and s.read_tag_at and at - s.read_tag_at <= Reading.TAG_TTL then weight[s.read_tag] = (weight[s.read_tag] or 0) + 3 end
    local pool = {}
    for _, p in ipairs(Places) do
        for _ = 1, 1 + (weight[p.tag] or 0) do pool[#pool + 1] = p end
    end
    local p
    s.seed, p = R.pick(s.seed, pool)
    return p
end

function T.place(id) for _, p in ipairs(Places) do if p.id == id then return p end end end

T.EVENT_CHANCE = { careful = 0.15, free = 0.3, bold = 0.5 }

--- 按遇事态度抽一个旅途事件：谨慎不遇延误和奇遇，随性不遇大胆专属，大胆什么都可能遇到
local function rollEvent(s)
    local att = s.attitude or "free"
    local f
    s.seed, f = R.next(s.seed)
    if f >= (T.EVENT_CHANCE[att] or 0.3) + (Quest.level(s) >= 5 and 0.1 or 0) then return nil end
    local pool, total = {}, 0
    for _, e in ipairs(Events) do
        local ok = att == "bold" or (not e.bold and (att == "free" or not e.hours))
        if ok then pool[#pool + 1] = e total = total + e.weight end
    end
    s.seed, f = R.next(s.seed)
    f = f * total
    for _, e in ipairs(pool) do
        f = f - e.weight
        if f < 0 then return e end
    end
    return pool[#pool]
end

local function depart(s, at, u)
    local place = choosePlace(s, at)
    local hours = 3
    local basket = {}
    for _, slot in ipairs(T.SLOTS) do
        local it = item(s.basket[slot])
        hours = hours + (it and it.hours_bias or 0)
        basket[#basket + 1] = it and it.name or nil
    end
    local f
    s.seed, f = R.next(s.seed)
    hours = math.max(3, math.min(30, hours + math.floor(f * 12)))
    local ev = rollEvent(s)
    if ev then hours = hours + (ev.hours or 0) end
    local ret = at + hours * u.hour
    local mail = {}
    s.seed, f = R.next(s.seed)
    local n = (f < 0.5) and 1 or (f < 0.85 and 2 or 3) -- 每趟 1–3 张
    s.seed, f = R.next(s.seed)
    if f < (Quest.level(s) >= 3 and 0.25 or 0) then n = n + 1 end
    if ev then n = n + (ev.mail or 0) end
    s.collected = s.collected or {}
    local picked = {}
    for i = 1, n do
        local card
        local mt = at + math.floor((ret - at) * i / (n + 1))
        s.seed, card = Postcards.compose(s.seed, place.id, s.collected, picked, Festival.context(s, mt))
        picked[card.key] = true
        mail[#mail + 1] = { at = mt, card = card }
    end
    local sv
    s.seed, sv = R.pick(s.seed, place.souvenirs)
    s.trips = (s.trips or 0) + 1
    s.sprite = { status = "away", trip = s.trips, place = place.id, left_at = at, return_at = ret,
        mail = mail, souvenir = sv, basket = basket, hours = hours, event = ev and ev.id or nil }
    local pick
    s.seed, pick = R.pick(s.seed, Notes.away)
    s.note = pick
    s.seed, pick = R.pick(s.seed, Lines.depart)
    State.log(s, pick, at)
end

--- 本趟 AI 文案（core/story.lua 写入）；只认同一趟的
local function aiFor(sp) return type(sp.ai) == "table" and sp.ai.trip == sp.trip and sp.ai or nil end

T.VISIT_HOUR_CHANCE = 0.02 -- 阿页在家时每小时有客人来的概率（约一天四成）
T.FESTIVAL_VISIT_HOUR_CHANCE = 0.06 -- 节日 / 节气当天
T.VISIT_LOOKBACK = 72 -- 最多回溯的小时数

local function arriveVisitor(s, at, u)
    local total = 0
    for _, v in ipairs(Visitors) do total = total + v.chance end
    local f
    s.seed, f = R.next(s.seed)
    f = f * total
    for _, v in ipairs(Visitors) do
        f = f - v.chance
        if f < 0 or v == Visitors[#Visitors] then
            local pose
            s.seed, pose = R.pick(s.seed, v.poses or { "" })
            s.visitor = { id = v.id, pose = pose, until_at = at + v.stay * u.hour, request = Quest.request(s) }
            Quest.note(s, "visit")
            s.seen_visitors = s.seen_visitors or {}
            if not s.seen_visitors[v.id] then s.seen_visitors[v.id] = at end
            State.log(s, v.arrive, at)
            return v
        end
    end
end

function T.visitor(id) for _, v in ipairs(Visitors) do if v.id == id then return v end end end

local function visitorLeaves(s)
    local v = T.visitor(s.visitor.id) or Visitors[1]
    local left_at = s.visitor.until_at
    s.visitor = nil
    s.inspiration = s.inspiration + v.gift
    State.log(s, v.leave, left_at)
end

--- 阿页在家的这段时间 (from, to] 里按小时抽客人；来客时阿页一定在家，走时才结算灵感
local function rollVisits(s, from, to, u)
    from = math.max(from, to - T.VISIT_LOOKBACK * u.hour)
    local t = from + u.hour
    while t <= to do
        if s.visitor and s.visitor.until_at <= t then visitorLeaves(s) end
        if not s.visitor then
            local f
            s.seed, f = R.next(s.seed)
            if f < (Festival.at(s, t) and T.FESTIVAL_VISIT_HOUR_CHANCE or T.VISIT_HOUR_CHANCE) then
                arriveVisitor(s, t, u)
            end
        end
        t = t + u.hour
    end
end

function T.settle(s, now, debug_fast)
    local u = T.timing(debug_fast)
    local events = {}
    local sp = s.sprite
    s.visit_check = s.visit_check or now
    Quest.refresh(s, now)
    if sp.status == "packed" and now >= sp.depart_at then
        rollVisits(s, s.visit_check, sp.depart_at, u)
        s.visit_check = sp.depart_at
        depart(s, sp.depart_at, u)
        events[#events + 1] = "depart"
        sp = s.sprite
    end
    if sp.status == "away" then
        local ai = aiFor(sp)
        local i = 0
        while i < #sp.mail do
            i = i + 1
            local m = sp.mail[i]
            if not m.sent and now >= m.at then
                m.sent = true
                local card = m.card
                local line = ai and ai.lines and ai.lines[i]
                -- AI 句子去重：和收到过的任何一句（AI 或本地）几乎相同就不用，保留本地句
                if line and not T.seenText(s, line) then
                    card.line, card.ai = line, true
                    card.key = card.key and (card.key:gsub("|[^|]*$", "|ai:" .. T.norm(line))) or nil
                end
                T.markText(s, card.line)
                card.at, card.trip = m.at, sp.trip
                if card.key then s.collected[card.key] = m.at end
                table.insert(s.postcards, card)
                Quest.note(s, "card", card.weather)
                local ml
                s.seed, ml = R.pick(s.seed, Lines.mail)
                State.log(s, ml, m.at)
                events[#events + 1] = "postcard"
            end
        end
        if now >= sp.return_at then
            local p = T.place(sp.place)
            local sv = sp.souvenir
            local ev
            for _, e in ipairs(Events) do if e.id == sp.event then ev = e end end
            s.souvenirs[sv] = (s.souvenirs[sv] or 0) + ((ev and ev.double) and 2 or 1)
            s.seen_souvenirs = s.seen_souvenirs or {}
            s.seen_souvenirs[sv] = true
            Quest.note(s, "trip", p.tag)
            s.place_trips = s.place_trips or {}
            s.place_trips[sp.place] = (s.place_trips[sp.place] or 0) + 1
            local bl
            s.seed, bl = R.pick(s.seed, Lines.back)
            local back = bl:format(p.name, Postcards.souvenirs[sv].name)
            if ai and ai.narration then back = back .. ai.narration end
            if ai and ai.souvenir_note then
                s.souvenir_notes = s.souvenir_notes or {}
                s.souvenir_notes[sv] = ai.souvenir_note
            end
            State.log(s, back, sp.return_at)
            if ev then
                Quest.note(s, "event")
                s.inspiration = s.inspiration + (ev.ink or 0)
                if ev.item then
                    local it
                    s.seed, it = R.pick(s.seed, Quest.shopItems())
                    s.inventory[it.id] = (s.inventory[it.id] or 0) + 1
                    State.log(s, ev.text .. L("（得到%s）", it.name), sp.return_at)
                else
                    State.log(s, ev.text, sp.return_at)
                end
            end
            s.basket, s.note = {}, nil
            if not ai and #sp.mail > 0 then -- 没赶上 AI：留个底，之后补写
                s.recap = { trip = sp.trip, place = sp.place, souvenir = sv, hours = sp.hours, basket = sp.basket,
                    left_at = sp.left_at, cards = {} }
                for _, m in ipairs(sp.mail) do s.recap.cards[#s.recap.cards + 1] = m.card end
            else
                s.recap = nil
            end
            s.sprite = { status = "home", back_at = sp.return_at }
            events[#events + 1] = "return"
            s.visit_check = sp.return_at
        end
    end
    if s.sprite.status ~= "away" then
        local before = s.visitor
        rollVisits(s, s.visit_check, now, u)
        s.visit_check = now
        local v = s.visitor
        if v and v ~= before then
            events[#events + 1] = "visitor"
            local ai = aiFor(sp)
            if ai and ai.visitor_line then v.line = ai.visitor_line end
        end
        -- 结算时才发现已过了停留时间：从此刻起再留一阵，保证玩家见得到
        if v and now >= v.until_at then v.until_at = now + (T.visitor(v.id) or Visitors[1]).stay * u.hour end
    elseif s.visitor and now >= s.visitor.until_at then
        visitorLeaves(s)
    end
    if #Quest.check(s, now) > 0 then events[#events + 1] = "achievement" end
    return events
end

--- 迟到的 AI 文案：改写那一趟已入册的明信片句子（保持 text 去重）、特产小注；客人还在就换台词
function T.applyRecap(s, ai)
    local rc = s.recap
    if not rc then return end
    local i = 0
    for _, c in ipairs(s.postcards) do
        if c.trip == rc.trip and not c.ai then
            i = i + 1
            local line = ai.lines and ai.lines[i]
            if line and not T.seenText(s, line) then
                s.collected[c.key or ""] = nil
                c.line, c.ai = line, true
                c.key = c.key and (c.key:gsub("|[^|]*$", "|ai:" .. T.norm(line))) or nil
                if c.key then s.collected[c.key] = c.at end
                T.markText(s, line)
            end
        end
    end
    if ai.souvenir_note then
        s.souvenir_notes = s.souvenir_notes or {}
        s.souvenir_notes[rc.souvenir] = ai.souvenir_note
    end
    if ai.visitor_line and s.visitor and not s.visitor.line then s.visitor.line = ai.visitor_line end
    s.recap = nil
end

--- 文案归一化：去空白与标点，用于「几乎相同」判断
function T.norm(text)
    return (tostring(text or ""):gsub("[%s%p]", ""):gsub("\227\128[\129-\130]", ""):gsub("\239\188[\129-\160]", ""))
end
function T.seenText(s, text) return s.texts ~= nil and s.texts[T.norm(text)] ~= nil end
function T.markText(s, text) s.texts = s.texts or {} s.texts[T.norm(text)] = true end

function T.nextAt(s)
    local sp, t = s.sprite, nil
    local function m(x) if x and (not t or x < t) then t = x end end
    if sp.status == "packed" then m(sp.depart_at) end
    if sp.status == "away" then
        m(sp.return_at)
        for _, x in ipairs(sp.mail) do if not x.sent then m(x.at) end end
    end
    if s.visitor then m(s.visitor.until_at) end
    return t
end

return T
