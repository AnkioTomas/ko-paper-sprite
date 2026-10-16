-- SPDX-License-Identifier: MIT
--[[-- 行囊物品（原创）。slot: food 干粮 / charm 护身物 / book 随身小书。
  price：灵感，0 = 家里常备（无限）；tags：命中地点 tag 时提高去那里的概率；hours_bias：旅程时长修正（小时）。
  icon：assets/items/<id>.png --]]
return {
    { id = "oat_biscuit",    slot = "food",  name = "燕麦饼干",     price = 0,  tags = { "water", "forest" } },
    { id = "tea_bag",        slot = "food",  name = "陈皮茶包",     price = 6,  tags = { "market", "indoor" }, hours_bias = 2 },
    { id = "jam_cookie",     slot = "food",  name = "果酱夹心饼",   price = 8,  tags = { "town", "travel" }, hours_bias = 1 },
    { id = "mint_drop",      slot = "food",  name = "薄荷糖",       price = 5,  tags = { "snow", "sky" }, hours_bias = -1 },
    { id = "pencil_stub",    slot = "charm", name = "铅笔头",       price = 0,  tags = { "mountain", "desert" } },
    { id = "paper_umbrella", slot = "charm", name = "纸伞",         price = 10, tags = { "water", "sea", "market" } },
    { id = "paper_clip",     slot = "charm", name = "回形针",       price = 4,  tags = { "town", "indoor" } },
    { id = "paper_hat",      slot = "charm", name = "报纸帽",       price = 7,  tags = { "desert", "snow" }, hours_bias = 2 },
    { id = "tiny_atlas",     slot = "book",  name = "火柴盒地图册", price = 0,  tags = { "mountain", "travel", "market" }, hours_bias = 3 },
    { id = "poem_slip",      slot = "book",  name = "一页短诗",     price = 4,  tags = { "water", "sky" }, hours_bias = -1 },
    { id = "pocket_dict",    slot = "book",  name = "口袋词典",     price = 9,  tags = { "indoor", "town" }, hours_bias = 4 },
    { id = "paper_lamp",     slot = "book",  name = "小纸灯",       price = 12, tags = { "forest", "sea", "sky" }, hours_bias = 1 },
}
