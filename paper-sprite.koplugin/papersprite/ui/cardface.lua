-- SPDX-License-Identifier: MIT
--[[-- 明信片正反面的纯数据。画面在 front，文字在 back。不碰 KOReader。 --]]
local T = require("papersprite.l10n")

local M = {}

function M.of(c)
    local Travel = require("papersprite.core.travel")
    local P = require("papersprite.data.postcards")
    local Game = require("papersprite.game")
    local place = Travel.place(c.place)
    return {
        place = place and place.name or c.place or "",
        weather = P.weather_names[c.weather] or "",
        scene = Game.cardScene(c),
        line = c.line or "",
        date = os.date("%Y-%m-%d", c.at or 0),
        stamp = os.date("%m.%d", c.at or 0),
        zip = place and place.zip or "",
        dear = T("致"),
        you = T("你"),
        sign = T("——阿页"),
    }
end

return M
