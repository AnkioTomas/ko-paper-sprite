-- SPDX-License-Identifier: MIT
--[[-- 行囊物品（原创占位）。slot: food 干粮 / charm 护身物 / book 随身小书。
  price 单位：灵感。trip 修正旅程：hours_bias 增减时长，tags 影响去哪儿。 --]]
return {
    { id = "oat_biscuit", slot = "food",  name = "燕麦饼干",   price = 0,  tags = { "lake" },   hours_bias = 0 },
    { id = "tea_bag",     slot = "food",  name = "陈皮茶包",   price = 6,  tags = { "market" }, hours_bias = 2 },
    { id = "pencil_stub", slot = "charm", name = "铅笔头",     price = 0,  tags = { "mountain" } },
    { id = "paper_umbrella", slot = "charm", name = "纸伞",    price = 10, tags = { "lake", "market" } },
    { id = "tiny_atlas",  slot = "book",  name = "火柴盒地图册", price = 0, tags = { "mountain", "market" }, hours_bias = 3 },
    { id = "poem_slip",   slot = "book",  name = "一页短诗",   price = 4,  tags = { "lake" },   hours_bias = -1 },
}
