-- SPDX-License-Identifier: MIT
--[[--
旅行调度：不用后台定时器。每次打开（或界面刷新）时用「现在 - 上次」的真实时间一次性结算。
状态机：home →(放满行囊) packed →(等待 depart_delay) away →(旅程结束) home
  packed：packed_at，depart_at
  away：place，left_at，return_at，mail = { {at, card} }（寄出时刻已在出发时排好）
时长（原创数值）：正常模式 出发等待 20–90 分钟，旅程 3–30 小时；
调试模式（settings.debug_fast）把分钟换成秒、小时换成 10 秒。
--]]
local Items = require("papersprite.data.items")
local Places = require("papersprite.data.places")
local Postcards = require("papersprite.data.postcards")
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

function T.basketFull(s)
    for _, slot in ipairs(T.SLOTS) do if not s.basket[slot] then return false end end
    return true
end

--- 放一件东西进行囊（从库存扣除；同格旧物退回库存）。
function T.put(s, id, now, debug_fast)
    local it = item(id)
    if not it or (s.inventory[id] or 0) <= 0 or s.sprite.status == "away" then return false end
    local old = s.basket[it.slot]
    if old then s.inventory[old] = (s.inventory[old] or 0) + 1 end
    s.inventory[id] = s.inventory[id] - 1
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
        for _, tag in ipairs(it and it.tags or {}) do weight[tag] = (weight[tag] or 0) + 1 end
    end
    local pool = {}
    for _, p in ipairs(Places) do
        for _ = 1, 1 + (weight[p.tag] or 0) do pool[#pool + 1] = p end
    end
    local p
    s.seed, p = R.pick(s.seed, pool)
    return p
end

local function depart(s, at, u)
    local place = choosePlace(s)
    local hours = 3
    for _, slot in ipairs(T.SLOTS) do
        local it = item(s.basket[slot])
        hours = hours + (it and it.hours_bias or 0)
    end
    local f
    s.seed, f = R.next(s.seed)
    hours = math.max(3, math.min(30, hours + math.floor(f * 12)))
    local ret = at + hours * u.hour
    local mail = {}
    local cards = Postcards.byPlace(place.id)
    s.seed, f = R.next(s.seed)
    local n = (f < 0.6) and 1 or 2 -- 每趟 1–2 张
    for i = 1, n do
        local c
        s.seed, c = R.pick(s.seed, cards)
        mail[#mail + 1] = { at = at + math.floor((ret - at) * i / (n + 1)), card = c.id }
    end
    s.sprite = { status = "away", place = place.id, left_at = at, return_at = ret, mail = mail }
    s.note = "出去走走，别担心。——阿页"
    State.log(s, "阿页背上藤筐出门了，书桌上留了张纸条。")
end

local function placeName(id) for _, p in ipairs(Places) do if p.id == id then return p end end end
T.place = placeName

--- 结算到 now。返回本次发生的事件列表（字符串），供界面提示。
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
        for i = #sp.mail, 1, -1 do
            local m = sp.mail[i]
            if now >= m.at then
                table.insert(s.postcards, { id = m.card, at = m.at })
                table.remove(sp.mail, i)
                State.log(s, "邮差夹进来一张明信片。")
                events[#events + 1] = "postcard"
            end
        end
        if now >= sp.return_at then
            local p = placeName(sp.place)
            local sv
            s.seed, sv = R.pick(s.seed, p.souvenirs)
            s.souvenirs[sv] = (s.souvenirs[sv] or 0) + 1
            State.log(s, "阿页从" .. p.name .. "回来了，带回了" .. Postcards.souvenirs[sv].name .. "。")
            s.basket, s.note = {}, nil
            s.sprite = { status = "home", back_at = sp.return_at }
            events[#events + 1] = "return"
            -- 墨点虫：阿页在家时偶尔来串门（30%，停留 2 小时）
            local f
            s.seed, f = R.next(s.seed)
            if f < 0.3 then
                s.visitor = { until_at = sp.return_at + 2 * u.hour }
                State.log(s, "一只墨点虫顺着书脊爬进来串门。")
                events[#events + 1] = "visitor"
            end
        end
    end
    if s.visitor and now >= s.visitor.until_at then
        s.visitor = nil
        s.inspiration = s.inspiration + 2
        State.log(s, "墨点虫走了，在桌角留下两点灵感。")
    end
    return events
end

--- 下一件将要发生的事的时刻（界面据此决定多久后刷新），无则 nil。
function T.nextAt(s)
    local sp, t = s.sprite, nil
    local function m(x) if x and (not t or x < t) then t = x end end
    if sp.status == "packed" then m(sp.depart_at) end
    if sp.status == "away" then
        m(sp.return_at)
        for _, x in ipairs(sp.mail) do m(x.at) end
    end
    if s.visitor then m(s.visitor.until_at) end
    return t
end

return T
