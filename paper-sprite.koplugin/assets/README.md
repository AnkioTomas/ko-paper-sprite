# 素材规格

所有素材均为原创，当前全部是 `tools/gen_placeholders.py` 用几何图形生成的占位图。

## 通用要求
- PNG，灰度（可带 alpha），**只用 4 级灰**：`#000000` `#555555` `#AAAAAA` `#FFFFFF`；需要中间调用网点表现。
- 线稿为主，线宽 ≥ 2px（墨水屏缩放后不断线）。

## 尺寸
| 目录 | 内容 | 尺寸 | 透明 |
|---|---|---|---|
| `attic/` | 阁楼场景 | 600×300 | 否 |
| `places/` | 明信片背景（地点） | 600×300 | 否 |
| `sprite/` | 阿页姿势层 | 120×160 | 是 |
| `props/` | 前景小物 | ≤120×120 | 是 |
| `weather/` | 天气 / 光影层 | 600×300 | 是 |

明信片 = 背景 + 姿势 + 小物 + 天气 叠加，外加一句短文案（≤ 40 字）。

## 明信片包格式（投稿 / 扩展用）
```
my-pack/
  pack.lua          -- return { id, name, author, license, places = {...}, cards = {...}, souvenirs = {...} }
  places/*.png  sprite/*.png  props/*.png  weather/*.png
```
`places` / `cards` / `souvenirs` 字段与 `papersprite/data/places.lua`、`data/postcards.lua` 相同。
包必须原创或有明确可再分发授权，`license` 必填。加载器在第 4 批实现。
