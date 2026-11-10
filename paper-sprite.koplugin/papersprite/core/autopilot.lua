-- SPDX-License-Identifier: MIT
--[[--
托管模式：阿页在有灵感时自己买小铺里的东西，并自己收拾行囊出门。
开关在宿主设置里（read_prefs.autopilot，默认关）；次数与时间戳跟游戏存档走。

节奏（有意保守，避免一次结算把钱花光、或刚到家又出门）：
  · 买东西：至少隔 2 小时（debug_fast 下为 2 个「小时」单位，即 20 秒）才买一次；
    每次最多一件；留下至少 RESERVE 点灵感；已有 ≥ OWNED_CAP 件的货物不买。
    在付得起的货物里，优先挑库存最少的，再用存档种子随机选一件。
  · 出门：沿用 Travel.put 的三格行囊和 packed → away 流程，伴读空椅、打扰、
    阁楼与回家结算都和玩家自己收拾的一样。
    两次托管出门至少隔 1 小时（从上一趟托管回家算；若刚从玩家发起的旅途回来，
    也等满 1 小时）。一天最多 3 次，只计托管出发，不计玩家自己收拾的出行。
    「一天」是本地日历日（os.date("%Y-%m-%d")），与节日 / 阁楼日期一致。
  · 灵感不足（买不起或已是 0）则不买也不自己出门；有钱后在间隔和每日上限内再继续。
  · 家里有客人、行囊已被玩家放了东西、或已经 packed/away 时不插手。
  · 只在会写回存档的结算路径上行动（打开阁楼 Game:tick、阅读页 loadState）。
    首页卡片在副本上 settle，不会触发托管，以免只读摘要改了档。
  · 一次结算最多买一件、出发一趟（打包发生在「现在」，出发仍要等 20–90 分钟）；
    离线很久回来也不会一次性补买、补出门。
--]]
local T = require("papersprite.l10n")
local Items = require("papersprite.data.items")
local R = require("papersprite.core.rng")
local State = require("papersprite.core.state")

local A = {}

A.TRIPS_PER_DAY = 3
A.RESERVE = 3
A.OWNED_CAP = 3
A.BUY_HOURS = 2
A.TRIP_HOURS = 1

function A.enabled()
    local ok, on = pcall(function()
        return require("papersprite.ui.read_prefs").autopilot()
    end)
    return ok and on == true
end

function A.dayKey(now)
    return os.date("%Y-%m-%d", now)
end

local function mem(s)
    s.autopilot = s.autopilot or {}
    return s.autopilot
end

local function timing(debug_fast)
    return require("papersprite.core.travel").timing(debug_fast)
end

function A.onDepart(s, at)
    local ap = mem(s)
    if not ap.pending then return end
    ap.pending = nil
    if s.sprite then s.sprite.autopilot = true end
    local day = A.dayKey(at)
    if ap.trip_day ~= day then
        ap.trip_day, ap.trips = day, 0
    end
    ap.trips = (ap.trips or 0) + 1
    ap.last_depart_at = at
end

function A.onReturn(s, at, was_auto)
    if not was_auto then return end
    mem(s).last_trip_at = at
end

local function affordable(s)
    local out = {}
    local budget = (s.inspiration or 0) - A.RESERVE
    if budget < 1 then return out end
    for _, it in ipairs(Items) do
        if it.price and it.price > 0 and it.price <= budget
            and (s.inventory[it.id] or 0) < A.OWNED_CAP then
            out[#out + 1] = it
        end
    end
    return out
end

function A.maybeBuy(s, now, debug_fast)
    local ap = mem(s)
    local u = timing(debug_fast)
    if ap.last_buy_at and now < ap.last_buy_at + A.BUY_HOURS * u.hour then return false end
    local pool = affordable(s)
    if #pool == 0 then return false end
    local fewest = nil
    for _, it in ipairs(pool) do
        local n = s.inventory[it.id] or 0
        if not fewest or n < fewest then fewest = n end
    end
    local pick = {}
    for _, it in ipairs(pool) do
        if (s.inventory[it.id] or 0) == fewest then pick[#pick + 1] = it end
    end
    local it
    s.seed, it = R.pick(s.seed, pick)
    if not it then return false end
    s.inspiration = s.inspiration - it.price
    s.inventory[it.id] = (s.inventory[it.id] or 0) + 1
    ap.last_buy_at = now
    State.log(s, T("阿页自己去小铺买了%s。", it.name), now)
    return it
end

local function basketEmpty(s)
    local Travel = require("papersprite.core.travel")
    for _, slot in ipairs(Travel.SLOTS) do
        if s.basket[slot] then return false end
    end
    return true
end

local function slotChoices(s, slot)
    local Travel = require("papersprite.core.travel")
    local paid, staples = {}, {}
    for _, it in ipairs(Items) do
        if it.slot == slot and Travel.count(s, it.id) > 0 then
            if Travel.staple(it.id) then
                staples[#staples + 1] = it.id
            else
                paid[#paid + 1] = it.id
            end
        end
    end
    if #paid > 0 then return paid end
    return staples
end

function A.maybeTravel(s, now, debug_fast)
    if (s.inspiration or 0) < 1 then return false end
    local sp = s.sprite
    if not sp or sp.status ~= "home" then return false end
    if s.visitor then return false end
    if not basketEmpty(s) then return false end
    local ap = mem(s)
    local u = timing(debug_fast)
    local waited = ap.last_trip_at or sp.back_at
    if waited and now < waited + A.TRIP_HOURS * u.hour then return false end
    local day = A.dayKey(now)
    local trips = (ap.trip_day == day) and (ap.trips or 0) or 0
    if trips >= A.TRIPS_PER_DAY then return false end
    local Travel = require("papersprite.core.travel")
    for _, slot in ipairs(Travel.SLOTS) do
        local ids = slotChoices(s, slot)
        if #ids == 0 then return false end
        local id
        s.seed, id = R.pick(s.seed, ids)
        if not Travel.put(s, id, now, debug_fast) then return false end
    end
    if s.sprite.status ~= "packed" then return false end
    ap.pending = true
    State.log(s, T("阿页自己收拾好行囊，过一会儿就出门。"), now)
    return true
end

--- 在会写盘的结算之后调用。一次最多买一件、打包一趟。
function A.tick(s, now, debug_fast)
    if not A.enabled() or type(s) ~= "table" or type(now) ~= "number" then return end
    A.maybeBuy(s, now, debug_fast)
    A.maybeTravel(s, now, debug_fast)
end

return A
