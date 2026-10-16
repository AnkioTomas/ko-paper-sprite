# 测试与模拟器

## 无头测试
```
lua spec/headless.lua
for f in $(find . -name '*.lua'); do luac -p "$f"; done
```
虚拟时钟覆盖：收拾行囊 → 自动出门 → 关闭后时间流逝再打开一次性结算 → 明信片墙 → 单张；关闭后不残留定时器；存档版本兼容；首页卡片摘要；50 趟长跑确定性；200 趟明信片不重复、耗尽后退回最久没见过；AI 桩（成功 / 不合规 / 报错 / 超时 / 重复句）；v2 → v3 迁移（旧 key 不变）、背景变体 key 与图层、搭配限制（沙漠不钓鱼、室内不下雨）、四季/夜晚阁楼、特产摆进阁楼与访客姿势叠加；**所有被数据引用的图片都必须存在**（开发中可用 `SKIP_ASSETS=1` 跳过这一项）；首页组件数据（只读、不改存档、新的在前、新角标、n/48、分页）；明信片墙分页（网格 12 / 列表 4，切换视图，新角标在同一次进墙内保留）。

## 模拟器（月读仓库自带的 KOReader 模拟器）
1. 用独立数据目录（不碰真实数据），例如 `emu-home/`，`settings.reader.lua` 里：
   ```lua
   ["extra_plugin_paths"] = { "/path/to/emu-home/plugins-extra" },
   ```
2. 把插件软链进去：`ln -s /path/to/ko-paper-sprite/paper-sprite.koplugin emu-home/plugins-extra/`
3. 启动（540×720 竖屏）：
   ```
   cd moon/koreader/koreader-emulator-*/koreader
   KO_HOME=/path/to/emu-home EMULATE_READER_W=540 EMULATE_READER_H=720 EMULATE_READER_DPI=160 ./reader.lua
   ```
4. 开 `debug_fast`（见 [gameplay.md](gameplay.md)），几分钟走完一趟。
5. 月读方式：把月读也软链进去 `ln -s /path/to/moon/book.koplugin emu-home/plugins-extra/`，
   在月读首页组件里添加「阿页」卡片（或在 `.moon/settings/home.lua` 的 `home_widgets` 加 `ext.papersprite.home`），点按全屏打开。
   模拟器驱动（moon `tools/emu.sh`）可发 `BookOpenShelf` 事件直接进月读首页。
6. 注意：模拟器逻辑分辨率为 1080×1440（窗口 540×720 是缩放显示），合成点按坐标按 1080×1440 算。
