-- SPDX-License-Identifier: MIT
-- 地点类型的名字。读书墙、阅读加权用。访客委托在 data/errands.lua。
local T = require("papersprite.l10n")

local M = {}

M.TAG_NAME = { water = T("水边"), forest = T("森林"), market = T("集市"), indoor = T("屋里"), town = T("小镇"), travel = T("车站"), snow = T("雪地"),
    sky = T("天上"), mountain = T("山里"), desert = T("沙丘"), sea = T("海边"), garden = T("花园"), night = T("夜里"), underground = T("地下") }

return M
