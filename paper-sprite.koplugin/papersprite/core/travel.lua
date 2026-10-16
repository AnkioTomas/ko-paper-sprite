-- SPDX-License-Identifier: MIT
--[[--
旅行调度：不用后台定时器。每次打开（或界面刷新）时用「现在 - 上次」的真实时间一次性结算。
状态机：home →(放满行囊) packed →(等待) away →(旅程结束) home
  packed：packed_at，depart_at
  away：trip（唯一编号），place，left_at，return_at，mail = { {at, card} }（出发时排好，card 为分层组合）
  sprite.ai：可选的 AI 文案（core/story.lua 异步写入），寄达 / 回家时优先使用，缺了用本地库
时长（原创数值）：出发等待 20–90 分钟，旅程 3–30 小时；debug_fast 时分钟→秒、小时→10 秒。
--]]
local Items = require("papersprite.data.items")
local Places = require("papersprite.data.places")
local Postcards = require("papersprite.data.postcards")
local Visitors = require("papersprite.data.visitors")
local R = require("papersprite.core.rng")
local State = require("papersprite.core.state")

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

local function choosePlace(s)
    local weight = {}
    for _, slot in ipairs(T.SLOTS) do
        local it = item(s.basket[slot])
        for _, tag in ipairs(it and it.tags or {}) do weight[tag] = (weight[tag] or 0) + 2 end
    end
    local pool = {}
    for _, p in ipairs(Places) do
        for _ = 1, 1 + (weight[p.tag] or 0) do pool[#pool + 1] = p end
    end
    local p
    s.seed, p = R.pick(s.seed, pool)
    return p
end

function T.place(id) for _, p in ipairs(Places) do if p.id == id then return p end end end

local function depart(s, at, u)
    local place = choosePlace(s)
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
    local ret = at + hours * u.hour
    local mail = {}
    s.seed, f = R.next(s.seed)
    local n = (f < 0.5) and 1 or (f < 0.85 and 2 or 3) -- 每趟 1–3 张
    s.collected = s.collected or {}
    local picked = {}
    for i = 1, n do
        local card
        s.seed, card = Postcards.compose(s.seed, place.id, s.collected, picked)
        picked[card.key] = true
        mail[#mail + 1] = { at = at + math.floor((ret - at) * i / (n + 1)), card = card }
    end
    local sv
    s.seed, sv = R.pick(s.seed, place.souvenirs)
    s.trips = (s.trips or 0) + 1
    s.sprite = { status = "away", trip = s.trips, place = place.id, left_at = at, return_at = ret,
        mail = mail, souvenir = sv, basket = basket, hours = hours }
    s.note = "出去走走，别担心。"
    State.log(s, "阿页背上藤筐出门了，书桌上留了张纸条。")
end

--- 本趟 AI 文案（core/story.lua 写入）；只认同一趟的
local function aiFor(sp) return type(sp.ai) == "table" and sp.ai.trip == sp.trip and sp.ai or nil end

T.VISITOR_CHANCE = 0.4 -- 每次回家有客人来的总概率；具体是谁按 chance 加权
local function arriveVisitor(s, at, u)
    local f
    s.seed, f = R.next(s.seed)
    if f >= T.VISITOR_CHANCE then return end
    local total = 0
    for _, v in ipairs(Visitors) do total = total + v.chance end
    s.seed, f = R.next(s.seed)
    f = f * total
    for _, v in ipairs(Visitors) do
        f = f - v.chance
        if f < 0 or v == Visitors[#Visitors] then
            local pose
            s.seed, pose = R.pick(s.seed, v.poses or { "" })
            s.visitor = { id = v.id, pose = pose, until_at = at + v.stay * u.hour }
            State.log(s, v.arrive)
            return v
        end
    end
end

function T.visitor(id) for _, v in ipairs(Visitors) do if v.id == id then return v end end end

function T.settle(s, now, debug_fast)
    local u = T.timing(debug_fast)
    local events = {}
    local sp = s.sprite
    if sp.status == "packed" and now >= sp.depart_at then
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
                card.at = m.at
                if card.key then s.collected[card.key] = m.at end
                table.insert(s.postcards, card)
                State.log(s, "邮差夹进来一张明信片。")
                events[#events + 1] = "postcard"
            end
        end
        if now >= sp.return_at then
            local p = T.place(sp.place)
            local sv = sp.souvenir
            s.souvenirs[sv] = (s.souvenirs[sv] or 0) + 1
            local back = "阿页从" .. p.name .. "回来了，带回了" .. Postcards.souvenirs[sv].name .. "。"
            if ai and ai.narration then back = back .. ai.narration end
            if ai and ai.souvenir_note then
                s.souvenir_notes = s.souvenir_notes or {}
                s.souvenir_notes[sv] = ai.souvenir_note
            end
            State.log(s, back)
            s.basket, s.note = {}, nil
            s.sprite = { status = "home", back_at = sp.return_at }
            events[#events + 1] = "return"
            local v = arriveVisitor(s, sp.return_at, u)
            if v then
                events[#events + 1] = "visitor"
                if ai and ai.visitor_line then s.visitor.line = ai.visitor_line end
            end
        end
    end
    if s.visitor and now >= s.visitor.until_at then
        local v = T.visitor(s.visitor.id) or Visitors[1]
        s.visitor = nil
        s.inspiration = s.inspiration + v.gift
        State.log(s, v.leave)
    end
    return events
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
