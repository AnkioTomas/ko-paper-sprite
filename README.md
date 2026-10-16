# 阿页的阁楼 · ko-paper-sprite

KOReader 插件，也可作为[月读](https://github.com/AnkioTomas/moon)扩展使用。完全离线。

## 设定
书页里住着一只小纸灵 **阿页**：一张旧书签变的，折纸身子，头上翘着一个书角。
它住在阅读器里的小阁楼：书桌、油灯、藤筐，还有一面贴明信片的墙。

- **收拾行囊**：往藤筐放干粮、护身物、随身小书各一样，决定它去哪儿、去多久。
- **自己出门**：行囊收好后过一阵（20–90 分钟）它会悄悄出发，留下一张纸条；旅程 3–30 小时，按真实时间计。
- **寄回明信片**：途中寄回 1–2 张黑白明信片，地点都在书中世界：墨水湖、雾里的旧书市、折页山……
- **带回特产**：回家时带回小物件。
- **灵感**：在 KOReader 里读书翻页会攒灵感（骨架：每 20 次有效翻页 = 1 灵感），用来在小铺买干粮和道具（第 3 批）。
- **访客**：墨点虫偶尔顺着书脊爬来串门，走时留点灵感。
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
  assets/   占位图 + 素材规格与明信片包格式（assets/README.md）
spec/headless.lua   虚拟时钟冒烟测试
tools/gen_placeholders.py   生成占位图
```
旅行不依赖后台定时器：每次打开时按「上次到现在」的真实时间一次性结算；界面开着时只在下一件事到点时刷新。

调试：设置 `debug_fast = true`（KOReader：`settings/papersprite.lua` 里 `setting_debug_fast`；月读：`ext.papersprite.settings.debug_fast`）后，分钟变秒、小时变 10 秒。

## 测试
```
lua spec/headless.lua
for f in $(find . -name '*.lua'); do luac -p "$f"; done
```

## 路线图
1. ✅ 项目骨架：宿主适配、阁楼 / 行囊 / 明信片墙、真实时间旅行、存档版本、占位图
2. 旅行与明信片系统：旅途事件、明信片分层合成渲染、特产柜、纸条文案池
3. 小铺与灵感：阅读时长 + 翻页折算、小铺、物品效果、墨点虫礼物
4. 美术管线与首批 30–40 张原创明信片、明信片包加载器
5. 月读打磨与发布（CI、Release）

## 协议
MIT，见 LICENSE / NOTICE。所有内容原创。
