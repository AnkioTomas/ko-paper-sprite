-- SPDX-License-Identifier: MIT
--[[--
成长系统：统计、委托（每日 3 条 + 每周 1 条）、成就、阿页的阶、访客交情与招待、特产稀有度。
全部是存档里的纯数据；统计只由 Quest.note 一处累加，委托进度跟着同一个入口走。
--]]
local T = require("papersprite.l10n")
local R = require("papersprite.core.rng")
local State = require("papersprite.core.state")
local Quests = require("papersprite.data.quests")
local Achievements = require("papersprite.data.achievements")
local Places = require("papersprite.data.places")
local Visitors = require("papersprite.data.visitors")
local Items = require("papersprite.data.items")
local Postcards = require("papersprite.data.postcards")

local Q = {}

local KIND = { trip = "trips", card = "cards", visit = "visits", gift = "gifts", book = "books", pages = "pages", event = "events" }

local function stats(s)
    local st = s.stats or {}
    s.stats = st
    for _, k in pairs(KIND) do st[k] = st[k] or 0 end
    st.weather, st.tag = st.weather or {}, st.tag or {}
    return st
end

local function ymd(now) return tonumber(os.date("%Y%m%d", now)) end
local function weekOf(now) return math.floor((now + (tonumber(os.date("%z", now)) or 0) * 36) / 604800) end

local function describe(q)
    local def
    for _, d in ipairs(Quests.defs) do if d.id == q.id then def = d end end
    if not def then return "" end
    if q.key then
        local name = Quests.TAG_NAME[q.key] or Postcards.weather_names[q.key] or q.key
        return def.text:format(q.target, name)
    end
    return def.text:format(q.target)
end
Q.describe = describe

--- 新的一天 / 一周换委托；同一天内保持不变（未领取的昨日委托作废）
function Q.refresh(s, now)
    local qs = s.quests or {}
    s.quests = qs
    local day, week = ymd(now), weekOf(now)
    if qs.day ~= day then
        qs.day = day
        local keep = {}
        for _, q in ipairs(qs.list or {}) do if q.weekly and qs.week == week then keep[#keep + 1] = q end end
        qs.list = keep
        local seed = day * 31 + 7
        local pool = {}
        for _, d in ipairs(Quests.defs) do if d.daily then pool[#pool + 1] = d end end
        for _ = 1, Quests.DAILY_COUNT do
            local d
            seed, d = R.pick(seed, pool)
            for i, x in ipairs(pool) do if x == d then table.remove(pool, i) break end end
            local key
            if d.keys then seed, key = R.pick(seed, d.keys) end
            qs.list[#qs.list + 1] = { id = d.id, kind = d.kind, key = key, target = d.daily, p = 0, reward = Quests.DAILY_REWARD }
        end
        if qs.week ~= week then
            local wp = {}
            for _, d in ipairs(Quests.defs) do if d.weekly then wp[#wp + 1] = d end end
            local d
            seed, d = R.pick(seed + week, wp)
            local key
            if d.keys then seed, key = R.pick(seed, d.keys) end
            qs.week = week
            qs.list[#qs.list + 1] = { id = d.id, kind = d.kind, key = key, target = d.weekly, p = 0, reward = Quests.WEEKLY_REWARD, weekly = true }
        end
    end
end

--- 记一笔：累加统计，并推进同类委托（key 对不上的不算）
function Q.note(s, kind, key, n)
    n = n or 1
    local st = stats(s)
    st[KIND[kind]] = st[KIND[kind]] + n
    if key then
        local m = kind == "card" and st.weather or st.tag
        m[key] = (m[key] or 0) + n
    end
    for _, q in ipairs((s.quests or {}).list or {}) do
        if not q.claimed and q.kind == kind and (not q.key or q.key == key) then q.p = math.min(q.target, q.p + n) end
    end
end

function Q.claim(s, i)
    local q = ((s.quests or {}).list or {})[i]
    if not q or q.claimed or q.p < q.target then return false end
    q.claimed = true
    s.inspiration = s.inspiration + q.reward
    return true, q.reward
end

--- 可领取委托数（首页红点用）
function Q.claimable(s)
    local n = 0
    for _, q in ipairs((s.quests or {}).list or {}) do if not q.claimed and q.p >= q.target then n = n + 1 end end
    return n
end

----- 稀有度 / 特产归属 -----
local RARITY = { { id = "rare", name = T("稀有") }, { id = "uncommon", name = T("少见") }, { id = "common", name = T("常见") } }
local function hash(id)
    local h = 7
    for i = 1, #id do h = (h * 31 + id:byte(i)) % 1000003 end
    return h % 100
end
--- 稳定的稀有度：约 8% 稀有、22% 少见、其余常见（只看特产 id，存档无关）
function Q.rarity(id)
    local h = hash(id)
    if h < 8 then return RARITY[1] elseif h < 30 then return RARITY[2] end
    return RARITY[3]
end

----- 成长 -----
local LEVELS = { 0, 12, 35, 80, 150, 260, 400 }
local LEVEL_NAME = { T("纸片"), T("折角"), T("书签"), T("小纸灵"), T("书页使者"), T("阁楼主人"), T("故事守护者") }
function Q.exp(s)
    local st = stats(s)
    return st.trips * 3 + st.cards + st.books * 8 + st.visits * 2 + st.gifts * 2 + st.events * 2
end

function Q.level(s)
    local e = Q.exp(s)
    local lv = 1
    for i, need in ipairs(LEVELS) do if e >= need then lv = i end end
    return lv, LEVEL_NAME[lv], LEVELS[lv + 1], e
end

----- 访客交情 -----
local function visitorDef(id) for _, v in ipairs(Visitors) do if v.id == id then return v end end end

function Q.bond(s, id) return (s.bonds or {})[id] or 0 end

local STAGE_LINE = {
    [3] = T("%s悄悄告诉阿页一个好地方，下一趟就去那里。"),
    [5] = T("%s留下了一样礼物，放进了藤筐的行囊里。"),
    [8] = T("%s成了阁楼的常客，说好以后常来。"),
}

local function shopItems()
    local out = {}
    for _, it in ipairs(Items) do if it.price > 0 then out[#out + 1] = it end end
    return out
end
Q.shopItems = shopItems

--- 把特产送给在阁楼里的访客：消耗一件特产，交情 +1，换灵感；对上它想要的那一件加倍；交情到 3 / 5 / 8 有额外回礼
function Q.give(s, sv, now)
    local v = s.visitor
    if not v or s.sprite.status == "away" then return false, T("现在没有客人") end
    if v.fed then return false, T("这位客人已经招待过了") end
    if not Postcards.souvenirs[sv] or (s.souvenirs[sv] or 0) <= 0 then return false, T("没有这件特产") end
    local def = visitorDef(v.id)
    s.souvenirs[sv] = s.souvenirs[sv] - 1
    if s.souvenirs[sv] <= 0 then
        s.souvenirs[sv] = nil
        for i = #(s.decor or {}), 1, -1 do if s.decor[i] == sv then table.remove(s.decor, i) end end
    end
    v.fed = true
    s.bonds = s.bonds or {}
    local match = v.request == sv
    local b = (s.bonds[v.id] or 0) + (match and 2 or 1)
    local prev = s.bonds[v.id] or 0
    s.bonds[v.id] = b
    local gain = (def and def.gift or 2) + (match and 3 or 0)
    s.inspiration = s.inspiration + gain
    local msgs = { match and T("正是想要的！灵感 +%d", gain) or T("客人很高兴，灵感 +%d", gain) }
    if v.react then table.insert(msgs, 1, match and v.react.match or v.react.plain) end
    for _, stage in ipairs({ 3, 5, 8 }) do
        if prev < stage and b >= stage then
            local name = def and def.name or ""
            State.log(s, STAGE_LINE[stage]:format(name), now)
            msgs[#msgs + 1] = STAGE_LINE[stage]:format(name)
            if stage == 3 and not s.wish_place then
                local p
                s.seed, p = R.pick(s.seed, Places)
                s.wish_place = p.id
            elseif stage == 5 then
                local it
                s.seed, it = R.pick(s.seed, shopItems())
                s.inventory[it.id] = (s.inventory[it.id] or 0) + 1
            elseif stage == 8 then
                s.inspiration = s.inspiration + 10
            end
        end
    end
    Q.note(s, "gift")
    return true, table.concat(msgs, "\n")
end

--- 访客来时有概率提出想要的特产
function Q.request(s)
    local f
    s.seed, f = R.next(s.seed)
    if f >= 0.5 then return nil end
    local ids = {}
    for id in pairs(Postcards.souvenirs) do ids[#ids + 1] = id end
    table.sort(ids)
    local id
    s.seed, id = R.pick(s.seed, ids)
    return id
end

----- 成就 -----
function Q.counts(s)
    local st = stats(s)
    local c = { trips = st.trips, cards = #s.postcards, books = st.books, pages = st.pages, gifts = st.gifts, events = st.events,
        weather = st.weather, souvenirs = 0, rare = 0, places = 0, guests = 0, max_bond = 0 }
    for id in pairs(s.souvenirs or {}) do
        if Postcards.souvenirs[id] then
            c.souvenirs = c.souvenirs + 1
            if Q.rarity(id).id == "rare" then c.rare = c.rare + 1 end
        end
    end
    -- 稀有特产被送走后仍算收集过：以 seen_souvenirs 为准
    for id in pairs(s.seen_souvenirs or {}) do
        if not (s.souvenirs or {})[id] and Postcards.souvenirs[id] then
            c.souvenirs = c.souvenirs + 1
            if Q.rarity(id).id == "rare" then c.rare = c.rare + 1 end
        end
    end
    for _ in pairs(s.place_trips or {}) do c.places = c.places + 1 end
    for _ in pairs(s.seen_visitors or {}) do c.guests = c.guests + 1 end
    for _, b in pairs(s.bonds or {}) do if b > c.max_bond then c.max_bond = b end end
    c.level = Q.level(s)
    return c
end

--- 判定成就并自动发奖；阶数提升写日志。返回新达成的成就 id 列表
function Q.check(s, now)
    s.achieved = s.achieved or {}
    local lv, name = Q.level(s)
    if (s.level or 1) < lv then State.log(s, T("阿页长大了一点，现在是「%s」。", name), now) end
    s.level = lv
    local c = Q.counts(s)
    local new = {}
    for _, a in ipairs(Achievements) do
        if not s.achieved[a.id] and a.ok(c) then
            s.achieved[a.id] = now
            s.inspiration = s.inspiration + a.reward
            State.log(s, T("成就「%s」达成，灵感 +%d。", a.name, a.reward), now)
            new[#new + 1] = a.id
        end
    end
    return new
end

return Q
