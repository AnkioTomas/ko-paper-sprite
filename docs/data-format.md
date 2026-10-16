# 数据格式

## places.lua
```lua
{ id = "ink_lake", name = "墨水湖", tag = "lake", bg = "ink_lake.png", souvenirs = { "lake_pebble" } }
```
- `tag`：与物品 `tags` 匹配，影响去这里的概率。
- `bg`：`assets/places/` 下的背景层。
- `souvenirs`：可能带回的特产 id（定义在 postcards.lua 的 `souvenirs`）。

## items.lua
```lua
{ id = "tea_bag", slot = "food", name = "陈皮茶包", price = 6, tags = { "market" }, hours_bias = 2 }
```
- `slot`：`food` / `charm` / `book`。
- `price`：灵感；0 表示家里常备、无限。
- `hours_bias`：旅程时长修正（小时，可负）。

## postcards.lua（分层明信片）
```lua
{ id = "fog_market_01", place = "fog_market", pose = "peek", prop = "teacup", weather = "mist",
  line = "雾里有个摊子只卖结尾，我买了一个圆满的。" }
```
合成顺序（下 → 上）：
1. `assets/places/<place 的 bg>`
2. `assets/sprite/<pose>.png`
3. `assets/props/<prop>.png`（`"none"` 表示无）
4. `assets/weather/<weather>.png`

`line` ≤ 40 字，第一人称，阿页口吻。`poses / props / weathers` 列出可用图层名。
`souvenirs = { id = { name, note } }`。

骨架版本界面只显示背景层，图层合成在第 2 批实现。
