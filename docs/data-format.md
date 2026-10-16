# 数据格式

## places.lua
```lua
{ id = "ink_lake", name = "墨水湖", tag = "water", souvenirs = { "lake_pebble", "ink_shell" },
  lines = { "湖水是墨做的……", ... } }
```
- 背景图固定为 `assets/places/<id>.png`（空景，不含角色）。
- `tag` 与物品 `tags` 匹配；`souvenirs` 引用 `souvenirs.lua`；`lines` 是本地短句库（≤ 40 字）。

## items.lua
```lua
{ id = "tea_bag", slot = "food", name = "陈皮茶包", price = 6, tags = { "market", "indoor" }, hours_bias = 2 }
```
`slot`：food / charm / book；`price` 0 = 常备无限；图标 `assets/items/<id>.png`。

## souvenirs.lua
`id = { name, note }`。

## visitors.lua
```lua
{ id = "inkbug", name = "墨点虫", chance = 0.20, stay = 2, gift = 2, arrive = "…", here = "…", leave = "…" }
```
图片 `assets/visitors/<id>.png`。

## postcards.lua（分层明信片）
存档里的一张明信片：
```lua
{ place = "fog_market", pose = "peek", prop = "teacup", weather = "mist", line = "…", at = 1760000000, ai = true|nil }
```
合成顺序（下 → 上）：`places/<place>.png` → `sprite/<pose>.png` → `props/<prop>.png` → `weather/<weather>.png`。
- `poses`：sit read wave walk peek sleep look_up carry
- `props`：none lantern teacup paper_boat umbrella books flower
- `weathers`：clear drizzle snow mist dusk night（`clear` 不叠加）
- `generic[weather]`：天气专属的通用短句
- `Postcards.compose(seed, place)` 用存档种子随机组合；AI 文案见 [ai.md](ai.md)。

## 去重
- 每张明信片的身份 `key = place|pose|prop|weather|text_id`（`text_id`：`p:<序号>` 地点句、`g:<序号>` 天气通用句、`ai:<归一化文本>` AI 句）。
- 存档 `collected[key] = 最近收到时间`；出门时只从**没收集过**的组合里挑，同一趟内也不重复。
- 某地点全部组合（8×7×6×4 = 1344 种）都收集过之后，才退回「最久没见过」的那张。
- `texts[归一化文本]`：收到过的所有文案。AI 句和其中任何一句几乎相同（去空白与标点后相同）就不用，保留本地句；同一回复里有两句相同则整套丢弃。

## 存档版本
v2 起明信片为上面的组合格式；v1 的固定 id 明信片在加载时自动迁移（`core/state.lua`）。
