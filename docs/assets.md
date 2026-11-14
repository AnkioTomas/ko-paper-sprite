# 素材规格与明信片包投稿

详细尺寸表见 [`paper-sprite.koplugin/assets/README.md`](../paper-sprite.koplugin/assets/README.md)。

## 规范
- 入库的是一套彩色 PNG。透明图层的 alpha 只有 0 / 255（墨水屏上不出半透明脏边）。
- 运行时按设备显色（见 `papersprite.ui.display`）：
  - 黑白墨水屏（大多数 Kindle，或用户关掉「彩色渲染」）：收成 3 级灰 `#000 #AAA #FFF`，Bayer 4×4 有序抖动，合成走 BB8。
  - 彩色墨水屏（Kindle Colorsoft、Kobo Kaleido 等）：彩色合成，只做轻微色域适配，画面仍明显是彩色。
  - 彩色液晶（Android / 模拟器等）：最鲜艳，接近入库的彩色原图。
- 线稿为主，线宽 ≥ 2px。阿页要保持一致：折纸身子 + 头顶卷起的书角。
- 淡彩 / 线稿原图放 `art-samples/v3/`、`art-samples/v4/`（不入库）。用 `python3 tools/colorize_art.py` 经 Teamo image edit 上成鲜明彩色，写入 `art-samples/v5/`（可重复跑，已成功的会跳过）。成就原图在 `skills-workspace/achievements/raw/`，伴读椅子姿势在 `skills-workspace/companion/` 与 `skills-workspace/aye-turn/`。运行 `python3 tools/process_art.py` 生成 `assets/`（默认按 v3、v4、v5 顺序，后面的同名文件覆盖前面的）。
- 需要对照旧版灰度时：`python3 tools/process_art.py --gray`（覆盖默认目录）或 `--gray-dir <目录>`（另外写一份，不占用插件目录）。本机有 `pngquant` 时会再压一档。

## 明信片包
```
my-pack/
  pack.lua
  places/*.png  sprite/*.png  props/*.png  weather/*.png
```
```lua
-- pack.lua
return {
  id = "my-pack", name = "我的明信片包", author = "你的名字", license = "CC-BY-4.0",
  places = { ... },     -- 同 data/places.lua
  cards = { ... },      -- 同 data/postcards.lua 的 cards
  souvenirs = { ... },
}
```
## 投稿要求
1. 必须是你的原创作品，或有明确允许再分发的授权；`license` 必填。
2. 不得使用任何商业游戏、动画、绘本的角色、画面或文案，也不得描摹。
3. 每张明信片配一句原创短句。
4. 提交前用 `lua spec/run.lua` 跑一遍。

明信片包加载器在第 4 批实现。
