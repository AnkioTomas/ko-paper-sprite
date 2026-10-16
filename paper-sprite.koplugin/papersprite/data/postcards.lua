-- SPDX-License-Identifier: MIT
--[[--
明信片：分层合成。每张 = 地点背景(place) + 阿页姿势(pose) + 前景小物(prop) + 天气(weather) + 一句原创短句(line)。
图层文件：assets/places/<place>.png, assets/sprite/<pose>.png, assets/props/<prop>.png, assets/weather/<weather>.png
外部明信片包同格式，见 assets/README.md。
--]]
local M = {}

M.poses = { "sit", "wave", "peek" }
M.props = { "none", "lantern", "teacup" }
M.weathers = { "clear", "drizzle", "mist" }

M.cards = {
    { id = "ink_lake_01",   place = "ink_lake",   pose = "sit",  prop = "lantern", weather = "mist",
      line = "湖水是墨做的，我没敢把脚伸进去，怕回来变成一个逗号。" },
    { id = "ink_lake_02",   place = "ink_lake",   pose = "wave", prop = "none",    weather = "clear",
      line = "对岸有人在晾一整页的字，风一吹，句子就散了。" },
    { id = "fog_market_01", place = "fog_market", pose = "peek", prop = "teacup",  weather = "mist",
      line = "雾里有个摊子只卖结尾，我买了一个圆满的。" },
    { id = "fog_market_02", place = "fog_market", pose = "sit",  prop = "none",    weather = "drizzle",
      line = "旧书们排着队晒潮气，我帮最薄的那本翻了个身。" },
    { id = "fold_peak_01",  place = "fold_peak",  pose = "wave", prop = "none",    weather = "clear",
      line = "爬到折痕最深的地方，能看见整本书的书脊。" },
    { id = "fold_peak_02",  place = "fold_peak",  pose = "sit",  prop = "lantern", weather = "drizzle",
      line = "山顶下了一场小雨，我的角又卷了一点，不要紧。" },
}

M.souvenirs = {
    lake_pebble  = { name = "墨湖小石子",   note = "握久了手心会留一点蓝。" },
    torn_ticket  = { name = "半张旧书票",   note = "印着一个没人记得的书店名。" },
    crease_stone = { name = "折痕石",       note = "上面有一道整整齐齐的折线。" },
}

function M.byPlace(place)
    local out = {}
    for _, c in ipairs(M.cards) do if c.place == place then out[#out + 1] = c end end
    return out
end

function M.get(id)
    for _, c in ipairs(M.cards) do if c.id == id then return c end end
end

return M
