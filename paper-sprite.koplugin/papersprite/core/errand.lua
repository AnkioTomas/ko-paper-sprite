-- SPDX-License-Identifier: MIT
--[[--
访客委托。客人来时留下一张自己的纸条，不是系统每日任务。
同一位客人同时只有一张未领取的纸条。进度对照离开时记下的计数，不另存进度。
领取必须这位客人还在阁楼里。
--]]
local T = require("papersprite.l10n")
local R = require("papersprite.core.rng")
local State = require("papersprite.core.state")
local Errands = require("papersprite.data.errands")

local E = { REWARD = 4 }

local function templates(id)
    local out = {}
    for _, t in ipairs(Errands) do if t.visitor == id then out[#out + 1] = t end end
    return out
end

local function valid(t)
    if t.kind == "place" then
        for _, p in ipairs(require("papersprite.data.places")) do if p.id == t.key then return true end end
    elseif t.kind == "tag" then
        return require("papersprite.data.quests").TAG_NAME[t.key] ~= nil
    elseif t.kind == "weather" then
        for _, w in ipairs(require("papersprite.data.postcards").weathers) do if w == t.key then return true end end
    elseif t.kind == "book" or t.kind == "host" then
        return true
    end
end

function E.base(s, kind, key, visitor)
    if kind == "place" then return (s.place_trips or {})[key] or 0 end
    if kind == "tag" then return ((s.stats or {}).tag or {})[key] or 0 end
    if kind == "weather" then return ((s.stats or {}).weather or {})[key] or 0 end
    if kind == "book" then return (s.stats or {}).books or 0 end
    if kind == "host" then return (s.bonds or {})[visitor] or 0 end
    return 0
end

function E.progress(s, e)
    return E.base(s, e.kind, e.key, e.visitor) - (e.base or 0)
end

function E.done(s, e) return E.progress(s, e) > 0 end

function E.here(s, e)
    local v = s.visitor
    return v and v.id == e.visitor and s.sprite and s.sprite.status ~= "away"
end

--- 客人到达时留下纸条。已有未领取的就不重复留。
function E.leave(s, visitor_id, at)
    s.errands = s.errands or {}
    for _, e in ipairs(s.errands) do
        if e.visitor == visitor_id and not e.claimed then return end
    end
    local pool = {}
    for _, t in ipairs(templates(visitor_id)) do if valid(t) then pool[#pool + 1] = t end end
    if #pool == 0 then return end
    local last
    for i = #s.errands, 1, -1 do
        if s.errands[i].visitor == visitor_id then last = s.errands[i].kind .. "\0" .. (s.errands[i].key or "") break end
    end
    if last and #pool > 1 then
        local alt = {}
        for _, t in ipairs(pool) do if t.kind .. "\0" .. (t.key or "") ~= last then alt[#alt + 1] = t end end
        if #alt > 0 then pool = alt end
    end
    local pick
    s.seed, pick = R.pick(s.seed, pool)
    s.errands[#s.errands + 1] = {
        id = visitor_id .. ":" .. pick.kind .. ":" .. (pick.key or "") .. ":" .. tostring(at or 0),
        visitor = visitor_id, kind = pick.kind, key = pick.key ~= "" and pick.key or nil, say = pick.say,
        base = E.base(s, pick.kind, pick.key, visitor_id), at = at,
    }
end

function E.open(s)
    local out = {}
    for i, e in ipairs(s.errands or {}) do if not e.claimed then out[#out + 1] = i end end
    return out
end

function E.claimable(s)
    local n = 0
    for _, e in ipairs(s.errands or {}) do
        if not e.claimed and E.done(s, e) and E.here(s, e) then n = n + 1 end
    end
    return n
end

function E.hint(s, e)
    if e.claimed then return T("已领取") end
    if E.done(s, e) then
        if E.here(s, e) then return T("点这里领取 ✦ %d", E.REWARD) end
        local v = require("papersprite.core.travel").visitor(e.visitor)
        return T("做到了，等%s再来", v and v.name or "")
    end
    if e.kind == "place" or e.kind == "tag" then return T("还没做到，等阿页走一趟") end
    if e.kind == "weather" then return T("还没收到那样的明信片") end
    if e.kind == "book" then return T("还没读完") end
    if e.kind == "host" then return T("还没招待过这位") end
    return T("还没做到")
end

--- 领取。客人不在返回 false, "away"。返回 true, 灵感数。
function E.claim(s, i, now)
    local e = (s.errands or {})[i]
    if not e or e.claimed or not E.done(s, e) then return false end
    if not E.here(s, e) then return false, "away" end
    e.claimed = true
    s.inspiration = (s.inspiration or 0) + E.REWARD
    s.bonds = s.bonds or {}
    s.bonds[e.visitor] = (s.bonds[e.visitor] or 0) + 1
    s.stats = s.stats or {}
    s.stats.errands = (s.stats.errands or 0) + 1
    local v = require("papersprite.core.travel").visitor(e.visitor)
    State.log(s, T("灵感 +%d，交情 +1", E.REWARD) .. (v and (" · " .. v.name) or ""), now)
    require("papersprite.core.quest").check(s, now)
    return true, E.REWARD
end

return E
