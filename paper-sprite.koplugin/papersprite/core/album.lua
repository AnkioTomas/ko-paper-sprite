-- SPDX-License-Identifier: MIT
--[[--
地点剪贴簿 / 来客簿：在现有旅行数据上聚合「可收齐」进度。
不引入外来主题合集；纯函数，不写存档。
--]]
local Places = require("papersprite.data.places")
local Visitors = require("papersprite.data.visitors")
local Postcards = require("papersprite.data.postcards")

local A = {}

A.WISH_COST = 5

--- 某地点：去过几次、明信片张数、特产收齐情况
function A.place(s, place)
    local trips = (s.place_trips or {})[place.id] or 0
    local cards = 0
    for _, c in ipairs(s.postcards or {}) do if c.place == place.id then cards = cards + 1 end end
    local have, total = 0, #(place.souvenirs or {})
    for _, id in ipairs(place.souvenirs or {}) do
        if (s.souvenirs or {})[id] and (s.souvenirs[id] or 0) > 0 then have = have + 1 end
    end
    return {
        place = place,
        trips = trips,
        cards = cards,
        have = have,
        total = total,
        done = trips > 0 and total > 0 and have >= total,
        wished = s.wish_place == place.id,
    }
end

--- 全部地点进度（按名字排序）；返回列表与「收齐页数 / 总地点」
function A.places(s)
    local list, done = {}, 0
    for _, p in ipairs(Places) do
        local row = A.place(s, p)
        list[#list + 1] = row
        if row.done then done = done + 1 end
    end
    table.sort(list, function(a, b) return a.place.name < b.place.name end)
    return list, done, #Places
end

--- 来客簿：访客是否见过（人数随 data/visitors.lua）
function A.visitors(s)
    local seen = s.seen_visitors or {}
    local list, have = {}, 0
    for _, v in ipairs(Visitors) do
        local at = seen[v.id]
        local row = { visitor = v, at = at, seen = at ~= nil }
        if row.seen then have = have + 1 end
        list[#list + 1] = row
    end
    table.sort(list, function(a, b)
        if a.seen ~= b.seen then return a.seen end
        if a.seen and b.seen then return (a.at or 0) < (b.at or 0) end
        return a.visitor.name < b.visitor.name
    end)
    return list, have, #Visitors
end

--- 从旧存档补地点出行次数（按 trip 去重；没有 trip 的旧明信片 / 仅有特产 → 记至少 1）
function A.rebuildTrips(s)
    local by = {}
    for _, c in ipairs(s.postcards or {}) do
        if c.place then
            by[c.place] = by[c.place] or {}
            if c.trip then by[c.place][c.trip] = true
            else by[c.place]._ = true end
        end
    end
    for _, p in ipairs(Places) do
        for _, id in ipairs(p.souvenirs or {}) do
            if (s.souvenirs or {})[id] and (s.souvenirs[id] or 0) > 0 then
                by[p.id] = by[p.id] or {}
                -- 已有 trip 记录就别再加占位，避免「1 趟 + 特产」变成 2
                local empty = true
                for _ in pairs(by[p.id]) do empty = false break end
                if empty then by[p.id]._ = true end
            end
        end
    end
    s.place_trips = s.place_trips or {}
    for id, set in pairs(by) do
        local n = 0
        for _ in pairs(set) do n = n + 1 end
        if (s.place_trips[id] or 0) < n then s.place_trips[id] = n end
    end
end

function A.souvenirName(id)
    local sv = Postcards.souvenirs[id]
    return sv and sv.name or id
end

return A
