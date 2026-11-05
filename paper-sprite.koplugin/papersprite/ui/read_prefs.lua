-- SPDX-License-Identifier: MIT
--[[-- 阅读页开关：允许打扰、伴读、角落、透明度。存在宿主设置里，不进游戏存档。 --]]
local P = {}

local CORNERS = { "sw", "se", "nw", "ne" }
-- 点一下换一档。20 是默认：20% 透明。
local FADES = { 20, 0, 40, 60, 80, 100 }
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
        -- 透明度、角落每帧直接读设置。这里只把阅读页标脏，不依赖 poke 是否跑完。
        require("ui/uimanager"):setDirty("all", "partial")
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

function P.cycleCorner()
    local c = P.corner()
    local i = 1
    for n, x in ipairs(CORNERS) do if x == c then i = n end end
    P.set("companion_corner", CORNERS[i % #CORNERS + 1])
    refresh()
    return P.corner()
end

function P.cycleFade()
    local cur = P.fade()
    local i = 0
    for n, x in ipairs(FADES) do if x == cur then i = n break end end
    P.set("companion_fade", i > 0 and FADES[i % #FADES + 1] or 20)
    refresh()
    return P.fade()
end

return P
