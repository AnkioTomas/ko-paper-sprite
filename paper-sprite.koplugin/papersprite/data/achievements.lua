-- SPDX-License-Identifier: MIT
-- 成就：ok(c) 读 core/quest.lua 的 counts 表；达成自动记入并发灵感。
local T = require("papersprite.l10n")
local Postcards = require("papersprite.data.postcards")

local list = {}
local function add(id, name, desc, reward, ok) list[#list + 1] = { id = id, name = name, desc = desc, reward = reward, ok = ok } end

for _, n in ipairs({ 1, 10, 50 }) do
    add("trips" .. n, T("远行 %d 趟", n), T("阿页回家 %d 趟。", n), n == 1 and 3 or n, function(c) return c.trips >= n end)
end
for _, n in ipairs({ 10, 50, 200 }) do
    add("cards" .. n, T("集信 %d 张", n), T("收到 %d 张明信片。", n), math.floor(n / 5) + 2, function(c) return c.cards >= n end)
end
for _, n in ipairs({ 10, 50, 100 }) do
    add("souv" .. n, T("特产 %d 种", n), T("特产柜里收齐 %d 种不同的特产。", n), math.floor(n / 4) + 2, function(c) return c.souvenirs >= n end)
end
for _, n in ipairs({ 10, 30 }) do
    add("places" .. n, T("足迹 %d 处", n), T("阿页去过 %d 个不同的地点。", n), n, function(c) return c.places >= n end)
end
for _, n in ipairs({ 5, 15, 30 }) do
    add("guests" .. n, T("来客 %d 位", n), T("见过 %d 位不同的小客人。", n), n, function(c) return c.guests >= n end)
end
add("book1", T("读完一本书"), T("读完一整本书。"), 8, function(c) return c.books >= 1 end)
add("book5", T("读书五本"), T("读完五本书。"), 25, function(c) return c.books >= 5 end)
add("pages1000", T("翻页千次"), T("累计翻页 1000 页。"), 20, function(c) return c.pages >= 1000 end)
add("gifts5", T("好客的阁楼"), T("招待访客 5 次。"), 8, function(c) return c.gifts >= 5 end)
add("bond8", T("老朋友"), T("和一位访客的交情到 8。"), 15, function(c) return c.max_bond >= 8 end)
add("events5", T("见多识广"), T("旅途上遇到 5 次事件。"), 10, function(c) return c.events >= 5 end)
add("rare3", T("稀罕物"), T("收齐 3 样稀有特产。"), 15, function(c) return c.rare >= 3 end)
add("level3", T("小纸灵"), T("阿页成长到第 3 阶。"), 10, function(c) return c.level >= 3 end)
add("level5", T("书页使者"), T("阿页成长到第 5 阶。"), 25, function(c) return c.level >= 5 end)
for _, w in ipairs(Postcards.weathers) do
    add("weather_" .. w, T("「%s」成册", Postcards.weather_names[w]), T("收到 3 张「%s」的明信片。", Postcards.weather_names[w]), 4,
        function(c) return (c.weather[w] or 0) >= 3 end)
end

return list
