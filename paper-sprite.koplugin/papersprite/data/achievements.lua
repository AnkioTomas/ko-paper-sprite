-- SPDX-License-Identifier: MIT
-- 成就：ok(c) 读 core/quest.lua 的 counts 表；达成自动记入并发灵感。
local T = require("papersprite.l10n")
local Postcards = require("papersprite.data.postcards")

local list = {}
local function add(id, name, desc, reward, ok, voice, progress)
    list[#list + 1] = { id = id, name = name, desc = desc, reward = reward, ok = ok, voice = voice, progress = progress }
end

for _, n in ipairs({ 1, 10, 50 }) do
    add("trips" .. n, T("远行 %d 趟", n), T("阿页带回了 %d 趟旅途里的故事。", n), n == 1 and 3 or n,
        function(c) return c.trips >= n end, nil, function(c) return c.trips, n end)
end
for _, n in ipairs({ 10, 50, 200 }) do
    add("cards" .. n, T("集信 %d 张", n), T("把 %d 张来自远方的明信片收进墙里。", n), math.floor(n / 5) + 2,
        function(c) return c.cards >= n end, nil, function(c) return c.cards, n end)
end
for _, n in ipairs({ 10, 50, 100 }) do
    add("souv" .. n, T("特产 %d 种", n), T("让 %d 种旅途特产住进阁楼。", n), math.floor(n / 4) + 2,
        function(c) return c.souvenirs >= n end, nil, function(c) return c.souvenirs, n end)
end
for _, n in ipairs({ 10, 30 }) do
    add("places" .. n, T("足迹 %d 处", n), T("在地图上点亮 %d 个不同的地方。", n), n,
        function(c) return c.places >= n end, nil, function(c) return c.places, n end)
end
for _, n in ipairs({ 5, 15, 30 }) do
    add("guests" .. n, T("来客 %d 位", n), T("认识 %d 位来过阁楼的小客人。", n), n,
        function(c) return c.guests >= n end, nil, function(c) return c.guests, n end)
end
add("errand1", T("纸船出发"), T("完成一位小客人交来的第一张纸条。"), 6,
    function(c) return (c.errands or 0) >= 1 end, T("纸条被折成很小的一只船。"), function(c) return c.errands or 0, 1 end)
add("errand5", T("阁楼邮差"), T("把五件访客委托一一送到目的地。"), 12,
    function(c) return (c.errands or 0) >= 5 end, T("桌上的纸条叠成了一小叠。"), function(c) return c.errands or 0, 5 end)
add("match1", T("心意正好"), T("送出一件正合访客心意的特产。"), 8,
    function(c) return (c.matches or 0) >= 1 end, T("它把那件特产抱得很紧。"), function(c) return c.matches or 0, 1 end)
add("book1", T("合上第一本"), T("读完一本书，让它在读书墙留下书签。"), 8,
    function(c) return c.books >= 1 end, nil, function(c) return c.books, 1 end)
add("book5", T("五本书的夜晚"), T("读完五本书，阁楼里也多了五段回忆。"), 25,
    function(c) return c.books >= 5 end, nil, function(c) return c.books, 5 end)
add("pages1000", T("千页旅程"), T("陪着阿页翻过一千页书。"), 20,
    function(c) return c.pages >= 1000 end, nil, function(c) return c.pages, 1000 end)
add("gifts5", T("灯火留客"), T("在阁楼里招待访客五次。"), 8,
    function(c) return c.gifts >= 5 end, nil, function(c) return c.gifts, 5 end)
add("bond8", T("再熟悉不过"), T("和一位访客的交情达到八分。"), 15,
    function(c) return c.max_bond >= 8 end, nil, function(c) return c.max_bond, 8 end)
add("events5", T("故事总在路上"), T("旅途中遇见五次意料之外的事。"), 10,
    function(c) return c.events >= 5 end, nil, function(c) return c.events, 5 end)
add("rare3", T("藏起三件珍宝"), T("收集三样稀有特产，送出后也仍算收藏。"), 15,
    function(c) return c.rare >= 3 end, nil, function(c) return c.rare, 3 end)
add("level3", T("折角生灵"), T("陪阿页长成第三级的小纸灵。"), 10,
    function(c) return c.level >= 3 end, nil, function(c) return c.level, 3 end)
add("level5", T("书页的使者"), T("陪阿页长成第五级的书页使者。"), 25,
    function(c) return c.level >= 5 end, nil, function(c) return c.level, 5 end)
for _, w in ipairs(Postcards.weathers) do
    add("weather_" .. w, T("收集「%s」", Postcards.weather_names[w]), T("把三张「%s」天气的明信片装订成册。", Postcards.weather_names[w]), 4,
        function(c) return (c.weather[w] or 0) >= 3 end, T("「%s」的三张订成了一小册。", Postcards.weather_names[w]),
        function(c) return c.weather[w] or 0, 3 end)
end

return list
