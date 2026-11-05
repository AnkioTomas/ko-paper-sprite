-- SPDX-License-Identifier: MIT
--[[--
阅读页打扰。打开时 arm，只报之后发生的事，不把历史倒出来。
一次一件：未看的明信片、出门、回家、新访客、新成就。关掉不删 notice，再打开不会重放已确认的。
--]]
local D = {}

local function box(s)
    s.notice = s.notice or { cards = 0, back_at = 0, visitor = "", ach = {} }
    s.notice.ach = s.notice.ach or {}
    return s.notice
end

function D.arm(s)
    local n = box(s)
    n.cards = #s.postcards
    n.left_at = (s.sprite and s.sprite.left_at) or 0
    n.back_at = (s.sprite and s.sprite.back_at) or 0
    n.visitor = (s.visitor and s.sprite and s.sprite.status ~= "away") and (s.visitor.id .. "@" .. tostring(s.visitor.until_at)) or ""
    for id, at in pairs(s.achieved or {}) do n.ach[id] = n.ach[id] or at or 0 end
    s.notice_armed = true
end

--- 下一件要叠到阅读页上的事。没武装或没有就 nil。
function D.next(s)
    if not s.notice_armed then return nil end
    local n = box(s)
    if #s.postcards > (n.cards or 0) then
        return { kind = "card", index = (n.cards or 0) + 1 }
    end
    local left = s.sprite and s.sprite.status == "away" and s.sprite.left_at or 0
    if left > (n.left_at or 0) then return { kind = "away", at = left } end
    local back = s.sprite and s.sprite.status == "home" and s.sprite.back_at or 0
    if back > (n.back_at or 0) then return { kind = "home", at = back } end
    if s.visitor and s.sprite and s.sprite.status ~= "away" then
        local key = s.visitor.id .. "@" .. tostring(s.visitor.until_at)
        if key ~= (n.visitor or "") then return { kind = "visitor", key = key } end
    end
    for id, at in pairs(s.achieved or {}) do
        if not n.ach[id] then return { kind = "ach", id = id, at = at } end
    end
end

function D.ack(s, note)
    if not note then return end
    local n = box(s)
    if note.kind == "card" then n.cards = math.max(n.cards or 0, note.index or #s.postcards) end
    if note.kind == "away" then n.left_at = note.at or n.left_at end
    if note.kind == "home" then n.back_at = note.at or n.back_at end
    if note.kind == "visitor" then n.visitor = note.key or n.visitor end
    if note.kind == "ach" and note.id then n.ach[note.id] = note.at or 1 end
end

return D
