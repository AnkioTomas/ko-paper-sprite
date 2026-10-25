# 素材规格

全部原创。场景、角色、访客、物品、小物由作者用本地图像生成工具（Teamo imagegen）按统一风格生成，
以 `art-samples/01-character-sheet.png`（阿页设定图，未入库）为角色参照；天气 / 时刻层由
`tools/process_art.py` 程序生成。原图经 `tools/process_art.py` 裁切、缩放、4 级灰有序抖动后放在这里。

## 通用要求
- PNG 灰度，**只用 4 级灰**：`#000` `#555` `#AAA` `#FFF`；中间调用 Bayer 4×4 有序抖动表现。
- 透明图层的 alpha 只有 0 / 255（墨水屏上不出半透明脏边）。
- 黑白墨线 + 网点，不写任何文字。阿页：折纸长方身子、中缝、右上角折角、两个黑点眼睛、**没有嘴**、细线手脚。

## 尺寸
| 目录 | 内容 | 尺寸 | 透明 |
|---|---|---|---|
| `attic/` | 阁楼全矩阵：`attic_<season>_<tod>_<weather>[_empty].png`（season=spring/summer/autumn/winter，tod=day/dusk/night，weather=clear/drizzle/snow/mist）；旧名 `attic_<season\|night>[_empty]` 仍保留作回落 | 1200×600 | 否 |
| `places/` | 明信片背景（空景，不含角色），每处 `<id>.png` + `<id>_b.png`，共 80 张 | 1200×600 | 否 |
| `sprite/` | 阿页姿势（底部对齐），24 种 | 320×320 | 是 |
| `visitors/` | 访客 `<id>.png` + `<id>_2.png`，50 位 × 2 | 200×200 | 是 |
| `items/` | 行囊物品图标，36 种 | 128×128 | 是 |
| `souvenirs/` | 特产图标（也是阁楼装饰），300 种 | 128×128 | 是 |
| `props/` | 明信片前景小物，36 种（含 12 个节日小物 `fest_*`：newyear spring lantern bookday children dragon midautumn national doubleninth halloween christmas term） | 200×200 | 是 |
| `weather/` | 天气 / 时刻层（程序生成）：drizzle snow mist dusk night wind starry sunrise petals | 1200×600 | 是 |

明信片 = 背景 + 姿势 + 小物 + 天气，外加一句短文案（≤ 40 字），见 `docs/data-format.md`。

## 明信片包格式（投稿 / 扩展用）
见 `docs/assets.md`。
