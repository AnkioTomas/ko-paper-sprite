-- SPDX-License-Identifier: MIT
--[[-- 书中世界的地点（全部原创）。
  tag：与物品 tags 匹配，命中越多越可能去；bg：assets/places/<id>.png（无角色的空景）；
  souvenirs：可能带回的特产 id（data/souvenirs.lua）；lines：本地明信片短句库（≤ 40 字，阿页口吻）。 --]]
return {
    { id = "ink_lake", name = "墨水湖", tag = "water", souvenirs = { "lake_pebble", "ink_shell" }, lines = {
        "湖水是墨做的，我没敢把脚伸进去，怕回来变成一个逗号。",
        "对岸有人在晾一整页的字，风一吹，句子就散了。",
        "我叠了一只小纸船放下去，它慢慢变成了深蓝色。" } },
    { id = "fog_market", name = "雾里的旧书市", tag = "market", souvenirs = { "torn_ticket", "tiny_bookend" }, lines = {
        "雾里有个摊子只卖结尾，我买了一个圆满的。",
        "旧书们排着队晒潮气，我帮最薄的那本翻了个身。",
        "有人想用三个开头换我的书角，我没换。" } },
    { id = "fold_peak", name = "折页山", tag = "mountain", souvenirs = { "crease_stone" }, lines = {
        "爬到折痕最深的地方，能看见整本书的书脊。",
        "山顶下了一场小雨，我的角又卷了一点，不要紧。",
        "每一道山脊都是别人读到一半时折的。" } },
    { id = "spine_corridor", name = "书脊长廊", tag = "indoor", souvenirs = { "gold_thread" }, lines = {
        "走廊很长，两边的书都背对着我，好像在偷偷听。",
        "尽头有光，我走了好久，光也往前走了好久。",
        "我数到第一千本书的时候，忘了从哪本开始数的。" } },
    { id = "footnote_town", name = "脚注小镇", tag = "town", souvenirs = { "tiny_asterisk" }, lines = {
        "这里的人说话都很小声，像是怕吵醒正文。",
        "镇上每户人家门口都挂着一个小小的编号。",
        "我在一条很短的街上住了一晚，街名比街还长。" } },
    { id = "blank_snowfield", name = "空白页雪原", tag = "snow", souvenirs = { "blank_flake" }, lines = {
        "这里什么也没写，走起来特别安静。",
        "我留下一串脚印，像一行没人读得懂的字。",
        "雪是纸屑，落在身上不冷，就是有点痒。" } },
    { id = "index_station", name = "目录车站", tag = "travel", souvenirs = { "punched_ticket" }, lines = {
        "火车只停有名字的站，我在一个没名字的站下了车。",
        "站台上的人都在等下一章。",
        "我坐过了一站，又走回来，刚好看见日落。" } },
    { id = "bookmark_forest", name = "书签森林", tag = "forest", souvenirs = { "ribbon_leaf" }, lines = {
        "树是一条条丝带书签，风一吹，整片森林都在翻页。",
        "我在一棵最旧的书签树下打了个盹，梦见了你。",
        "这里好多亲戚，可它们都不会说话。" } },
    { id = "errata_harbor", name = "勘误港", tag = "water", souvenirs = { "correction_shell" }, lines = {
        "港口专门停靠写错了的船，修好了再出海。",
        "灯塔是一支铅笔，夜里会把海面描一遍。",
        "我帮一条船改了一个错别字，船长请我喝了茶。" } },
    { id = "margin_desert", name = "页边沙漠", tag = "desert", souvenirs = { "margin_sand" }, lines = {
        "沙漠沿着一条直直的线走，从来不越界。",
        "这里很少有人来，只偶尔有一行批注路过。",
        "太阳晒得我有点发黄，像一本旧书。" } },
    { id = "binding_bridge", name = "装订线大桥", tag = "mountain", souvenirs = { "binding_knot" }, lines = {
        "桥是用线缝起来的，走在上面能听见针脚的声音。",
        "桥下是两页之间的深谷，望不到底，也不可怕。",
        "我走到桥中间，正好是一本书最中间的地方。" } },
    { id = "reading_room", name = "灯下阅览室", tag = "indoor", souvenirs = { "lamp_glass" }, lines = {
        "每盏小绿灯下面都坐着一个看不见的读者。",
        "我找了个空位坐下，看完了一本很薄的书。",
        "这里规定不许说话，所以我只写信。" } },
    { id = "torn_cliffs", name = "撕页崖", tag = "sea", souvenirs = { "torn_edge" }, lines = {
        "悬崖的边是毛的，像被谁急着撕下来带走了。",
        "海风很大，我抓紧了石头，没被吹成一张便条。",
        "崖下的海在念一封很长的信。" } },
    { id = "cloud_archive", name = "云上书库", tag = "sky", souvenirs = { "cloud_label" }, lines = {
        "书架浮在云上，梯子要自己找。",
        "我借了一本云写的书，还的时候它下雨了。",
        "从这里往下看，你的阁楼只有一个句号那么大。" } },
}
