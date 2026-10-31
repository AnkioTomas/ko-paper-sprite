-- SPDX-License-Identifier: MIT
-- 委托模板：daily / weekly 里是目标数；keys 有值时随机挑一个（天气 id 或地点 tag）。
-- kind 与 core/quest.lua 的 note 对应：trip（回家，key=地点 tag）/ card（收信，key=天气）/ pages / visit / gift / book。
local T = require("papersprite.l10n")

local M = {}

M.TAG_NAME = { water = T("水边"), forest = T("森林"), market = T("集市"), indoor = T("屋里"), town = T("小镇"), travel = T("车站"), snow = T("雪地"),
    sky = T("天上"), mountain = T("山里"), desert = T("沙丘"), sea = T("海边"), garden = T("花园"), night = T("夜里"), underground = T("地下") }

M.defs = {
    { id = "trip", kind = "trip", daily = 1, weekly = 5, text = T("让阿页回家 %d 趟") },
    { id = "trip_tag", kind = "trip", keys = { "water", "forest", "market", "town", "sky", "mountain", "garden", "sea" }, daily = 1, weekly = 3, text = T("让阿页去 %d 趟「%s」的地方") },
    { id = "card", kind = "card", daily = 2, weekly = 8, text = T("收到 %d 张明信片") },
    { id = "card_weather", kind = "card", keys = { "clear", "drizzle", "snow", "mist", "dusk", "night", "wind", "starry", "sunrise", "petals" }, daily = 1, weekly = 3, text = T("收到 %d 张「%s」的明信片") },
    { id = "pages", kind = "pages", daily = 30, weekly = 300, text = T("读 %d 页书") },
    { id = "visit", kind = "visit", daily = 1, weekly = 3, text = T("迎来 %d 次访客") },
    { id = "gift", kind = "gift", daily = 1, weekly = 3, text = T("招待访客 %d 次") },
    { id = "book", kind = "book", weekly = 1, text = T("读完 %d 本书") },
}

M.DAILY_COUNT, M.DAILY_REWARD, M.WEEKLY_REWARD = 3, 3, 12

return M
