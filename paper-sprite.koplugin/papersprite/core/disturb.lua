-- SPDX-License-Identifier: MIT
--[[--
阅读页打扰。打开时 arm，只报之后发生的事，不把历史倒出来。
一次只弹一件：离开久了攒下好几件时挑最要紧的那件（在家的客人 > 最新一张明信片 > 回家 > 出门 > 成就），
关掉即把当时攒着的全算看过，不再一件件补弹。关掉不删 notice，再打开不会重放已确认的。
--]]
local Vault = require("papersprite.core.vault")

local D = {}

local function box(s)
    s.notice = s.notice or { cards = 0, back_at = 0, visitor = "", ach = {} }
    s.notice.ach = s.notice.ach or {}
    return s.notice
end

function D.arm(s)
    local n = box(s)
    n.cards = Vault.cardCount()
    n.left_at = (s.sprite and s.sprite.left_at) or 0
    n.back_at = (s.sprite and s.sprite.back_at) or 0
    n.visitor = (s.visitor and s.sprite and s.sprite.status ~= "away") and (s.visitor.id .. "@" .. tostring(s.visitor.until_at)) or ""
    for id, at in pairs(Vault.all("achieved")) do n.ach[id] = n.ach[id] or at or 0 end
    s.notice_armed = true
end

--- 下一件要叠到阅读页上的事。没武装或没有就 nil。
function D.next(s)
    if not s.notice_armed then return nil end
    local n = box(s)
    if s.visitor and s.sprite and s.sprite.status ~= "away" then
        local key = s.visitor.id .. "@" .. tostring(s.visitor.until_at)
        if key ~= (n.visitor or "") then return { kind = "visitor", key = key } end
    end
    local cards = Vault.cardCount()
    if cards > (n.cards or 0) then return { kind = "card", index = cards } end
    local left = s.sprite and s.sprite.status == "away" and s.sprite.left_at or 0
    if left > (n.left_at or 0) then return { kind = "away", at = left } end
    local back = s.sprite and s.sprite.status == "home" and s.sprite.back_at or 0
    if back > (n.back_at or 0) then return { kind = "home", at = back } end
    for id, at in pairs(Vault.all("achieved")) do
        if not n.ach[id] then return { kind = "ach", id = id, at = at } end
    end
end

--- 看过一件：这件和同时攒着的都算看过。
function D.ack(s, note)
    if note then D.arm(s) end
end

return D
