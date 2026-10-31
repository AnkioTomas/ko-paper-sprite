-- SPDX-License-Identifier: MIT
-- 旅途事件：出发时按「遇事态度」抽取；hours 加旅程小时，mail 多寄几张，ink 加灵感，item 带回一件小铺物品，double 特产多一份。
-- bold = 只在大胆时遇到；careful 不会遇到延误（hours > 0）。
local T = require("papersprite.l10n")

return {
    { id = "rain_stay", text = T("路上遇雨，阿页在屋檐下多躲了一阵。"), hours = 2, weight = 3 },
    { id = "lost", text = T("走岔了路，倒多寄了一张明信片。"), hours = 1, mail = 1, weight = 3 },
    { id = "companion", text = T("遇到一位同路的小旅伴，一起走了一段，还分到一点灵感。"), ink = 3, weight = 3 },
    { id = "find_item", text = T("在路边捡到一样有用的东西。"), item = true, weight = 2 },
    { id = "old_friend", text = T("碰见一位老朋友，特产多带了一份。"), double = true, weight = 2 },
    { id = "rainbow", text = T("天边挂了道纸彩虹，阿页看了很久，多寄了一张。"), mail = 1, ink = 2, weight = 2, bold = true },
    { id = "wonder_gap", text = T("奇遇：书页夹缝里有一处没人去过的地方。"), mail = 1, ink = 6, double = true, weight = 1, bold = true, rare = true },
    { id = "wonder_star", text = T("奇遇：夜空落下一张空白明信片，阿页把它写满了。"), mail = 1, ink = 4, item = true, weight = 1, bold = true, rare = true },
}
