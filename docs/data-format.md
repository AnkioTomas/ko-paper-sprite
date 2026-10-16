# 数据格式

## places.lua
```lua
{ id = "ink_lake", name = "墨水湖", tag = "water", souvenirs = { "lake_pebble", "ink_shell" },
  lines = { "湖水是墨做的……", ... } }
```
- `bgs = { "a", "b" }`：背景 `a` 为 `assets/places/<id>.png`，`b` 为 `<id>_b.png`（同一地点换角度/时刻，空景，不含角色）。
- `tag` 与物品 `tags` 匹配；`souvenirs` 引用 `souvenirs.lua`；`lines` 是本地短句库（≤ 40 字）。

## items.lua
```lua
{ id = "tea_bag", slot = "food", name = "陈皮茶包", price = 6, tags = { "market", "indoor" }, hours_bias = 2 }
```
`slot`：food / charm / book；`price` 0 = 常备无限；图标 `assets/items/<id>.png`。

## souvenirs.lua
`id = { name, note }`；图标 `assets/souvenirs/<id>.png`（128×128 透明），也用作阁楼装饰。

## visitors.lua
```lua
{ id = "inkbug", name = "墨点虫", chance = 0.20, stay = 2, gift = 2, poses = { "", "_2" }, arrive = "…", here = "…", leave = "…" }
```
图片 `assets/visitors/<id><pose>.png`（每位两种姿势，来访时随机一种）。`chance` 是权重：回家时先按 `Travel.VISITOR_CHANCE`（0.4）判定有没有客人，再按权重挑一位。

## postcards.lua（分层明信片）
存档里的一张明信片：
```lua
{ place = "fog_market", variant = "a"|"b", pose = "peek", prop = "teacup", weather = "mist", line = "…", text_id = "p:1", key = "…", at = 1760000000, ai = true|nil }
```
合成顺序（下 → 上）：`places/<place>.png`（变体 b 为 `<place>_b.png`） → `sprite/<pose>.png` → `props/<prop>.png` → `weather/<weather>.png`。
- `poses`（24）：sit read wave walk peek sleep look_up carry eat write fish boat umbrella sketch nap_book crane warm_lamp dance stargaze hold_souvenir sit_bench swing read_lying jump
- `props`（24 + none）：lantern teacup paper_boat umbrella books flower kite bench signpost mailbox campfire bottle_letter basket mushroom paper_snowman candle telescope fishing_rod paper_crane leaf_pile globe birdhouse ladder suitcase
- `weathers`（10）：clear drizzle snow mist dusk night wind starry sunrise petals（`clear` 不叠加）
- `generic[weather]`：天气专属的通用短句（每种 3 句）；`pose_lines[pose]`：姿势专属短句
- `only`：搭配限制（fish/boat、纸船/漂流瓶/鱼竿只在 water/sea；纸雪人只在 snow/mountain）；indoor/underground 地点只用 clear/dusk/night/mist
- `Postcards.compose(seed, place)` 用存档种子随机组合；AI 文案见 [ai.md](ai.md)。

## 去重
- 每张明信片的身份 `key = place[@变体]|pose|prop|weather|text_id`（变体 a 不写，和旧版 key 完全一致；b 写成 `ink_lake@b`。`text_id`：`p:<序号>` 地点句、`g:<序号>` 天气通用句、`s:<姿势>` 姿势句、`ai:<归一化文本>` AI 句）。
- 存档 `collected[key] = 最近收到时间`；出门时只从**没收集过**的组合里挑，同一趟内也不重复。
- 组合很多（每地点约 10 万种），出门时先随机抽样最多 64 次找没收过的；抽不到才全量枚举。某地点全部组合都收集过之后，才退回「最久没见过」的那张。
- `texts[归一化文本]`：收到过的所有文案。AI 句和其中任何一句几乎相同（去空白与标点后相同）就不用，保留本地句；同一回复里有两句相同则整套丢弃。

## 存档版本
v2 起明信片为上面的组合格式；v1 的固定 id 明信片在加载时自动迁移（`core/state.lua`）。
v3：明信片加 `variant`（旧卡补 `"a"`，key 不变，收集记录继续有效）；新增 `decor`（阁楼里摆的特产 id 列表，最多 4 个）；访客记录加 `pose`。
