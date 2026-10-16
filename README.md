# 阿页的阁楼 · ko-paper-sprite

KOReader 插件，也可作为[月读](https://github.com/AnkioTomas/moon)扩展使用。完全离线。

## 设定
书页里住着一只小纸灵 **阿页**：一张旧书签变的，折纸身子，头上翘着一个书角。
它住在阅读器里的小阁楼：书桌、油灯、藤筐，还有一面贴明信片的墙。

- **收拾行囊**：往藤筐放干粮、护身物、随身小书各一样，决定它去哪儿、去多久。
- **自己出门**：行囊收好后过一阵（20–90 分钟）它会悄悄出发，留下一张纸条；旅程 3–30 小时，按真实时间计。
- **寄回明信片**：途中寄回 1–2 张黑白明信片，地点都在书中世界：墨水湖、雾里的旧书市、折页山……
- **带回特产**：回家时带回小物件。
- **家里常备**：饼干、铅笔头、地图册取之不尽；其他物品要用灵感换。
- **灵感**：在 KOReader 里读书翻页会攒灵感（骨架：每 20 次有效翻页 = 1 灵感），用来在小铺买干粮和道具（第 3 批）。
- **访客**：墨点虫、回形针蜗牛、书灯萤、邮票龟偶尔来串门，走时留点灵感。
- **AI 文案（可选）**：在月读里且已配置 AI 时，每趟旅行的明信片短句、旁白由 AI 现写并存进存档，见 [docs/ai.md](docs/ai.md)。
- 没有失败和惩罚。

## 安装
把 `paper-sprite.koplugin` 复制到 KOReader 的 `plugins/`，在主菜单「工具 → 阿页的阁楼」打开。
装了月读时，首页组件里会多一张「阿页」卡片，点按全屏打开阁楼。

## 结构
```
paper-sprite.koplugin/
  _meta.lua  main.lua  moon_source.lua(ext.papersprite)
  papersprite/
    host/   interface / koreader / moon   宿主适配
    core/   state(存档+版本迁移) travel(真实时间结算) rng reading(阅读账本)
    data/   places items postcards(分层明信片：地点+姿势+小物+天气+短句)
    ui/     screen(全屏浮层，KOReader/月读两套皮肤) moon_card(首页卡片)
    game.lua
  assets/   正式素材（4 级灰）+ 规格（assets/README.md）
spec/headless.lua   虚拟时钟冒烟测试
tools/process_art.py   原图 → 4 级灰抖动素材；生成天气层
```
旅行不依赖后台定时器：每次打开时按「上次到现在」的真实时间一次性结算；界面开着时只在下一件事到点时刷新。

调试：设置 `debug_fast = true`（KOReader：`settings/papersprite.lua` 里 `setting_debug_fast`；月读：`ext.papersprite.settings.debug_fast`）后，分钟变秒、小时变 10 秒。

## 测试
```
lua spec/headless.lua
for f in $(find . -name '*.lua'); do luac -p "$f"; done
```

## 路线图
1. ✅ 项目骨架
2. ✅ 旅行与明信片：分层明信片（14 地点 × 8 姿势 × 7 小物 × 6 天气）、4 位访客、特产柜、小铺、可选 AI 文案、正式美术
3. 灵感细化（阅读时长）、物品效果、访客礼物
4. 更多内容、明信片包加载器
5. 月读打磨与发布

详见 [docs/roadmap.md](docs/roadmap.md)。

## 文档
- [世界与角色设定](docs/world.md)
- [玩法说明与数值](docs/gameplay.md)
- [架构](docs/architecture.md)
- [数据格式](docs/data-format.md)
- [素材规格与明信片包投稿](docs/assets.md)
- [测试与模拟器](docs/testing.md)
- [可选 AI 文案层](docs/ai.md)
- [路线图](docs/roadmap.md)

## 协议
MIT，见 LICENSE / NOTICE。所有内容原创。
