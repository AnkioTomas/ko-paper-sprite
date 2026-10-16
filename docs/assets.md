# 素材规格与明信片包投稿

详细尺寸表见 [`paper-sprite.koplugin/assets/README.md`](../paper-sprite.koplugin/assets/README.md)。

## 规范
- PNG 灰度，只用 4 级灰 `#000 #555 #AAA #FFF`，中间调用网点。
- 线稿为主，线宽 ≥ 2px。阿页要保持一致：折纸身子 + 头顶卷起的书角。
- 当前占位图由 `python3 tools/gen_placeholders.py` 生成（纯几何图形）。

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
4. 提交前用 `lua spec/headless.lua` 跑一遍。

明信片包加载器在第 4 批实现。
