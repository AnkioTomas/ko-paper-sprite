-- SPDX-License-Identifier: MIT
--[[-- 阅读页开关：允许打扰、伴读、角落、透明度。存在宿主设置里，不进游戏存档。 --]]
local P = {}

local CORNERS = { "sw", "se", "nw", "ne" }
P.CORNER_NAME = { sw = "左下", se = "右下", nw = "左上", ne = "右上" }

function P.host() return require("papersprite.host.moon").new() end

function P.get(key, default) return P.host():getSetting(key, default) end

function P.set(key, value) P.host():setSetting(key, value) end

function P.disturb() return P.get("disturb", false) == true end

function P.companion() return P.get("companion", false) == true end

function P.corner()
    local c = P.get("companion_corner", "sw")
    for _, x in ipairs(CORNERS) do if x == c then return c end end
    return "sw"
end

function P.cornerName()
    return require("papersprite.l10n")(P.CORNER_NAME[P.corner()] or "左下")
end

function P.fade()
    local n = tonumber(P.get("companion_fade", 20))
    if not n then return 20 end
    if n < 0 then return 0 end
    if n > 100 then return 100 end
    return math.floor(n)
end

function P.fadeName()
    return string.format("%d%%", P.fade())
end

local function refresh()
    pcall(function()
        local M = require("papersprite.ui.reader_overlay")
        M.refreshCompanion()
        M.poke()
        M.applyAvoid()
    end)
end

function P.toggleDisturb()
    local on = not P.disturb()
    P.set("disturb", on)
    if on then
        local h = P.host()
        local State = require("papersprite.core.state")
        local s = State.load(h:loadState(), h:now())
        require("papersprite.core.disturb").arm(s)
        h:saveState(s)
    end
    refresh()
    return on
end

function P.toggleCompanion()
    P.set("companion", not P.companion())
    refresh()
    return P.companion()
end

function P.setCorner(corner)
    for _, value in ipairs(CORNERS) do
        if value == corner then
            P.set("companion_corner", value)
            refresh()
            return
        end
    end
    error("invalid companion corner: " .. tostring(corner))
end

function P.setFade(fade)
    if fade ~= 0 and fade ~= 20 and fade ~= 40 and fade ~= 60 and fade ~= 80 and fade ~= 100 then
        error("invalid companion fade: " .. tostring(fade))
    end
    P.set("companion_fade", fade)
    refresh()
end

return P
