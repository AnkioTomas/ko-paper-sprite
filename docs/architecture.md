# 架构

```
paper-sprite.koplugin/
  main.lua           KOReader 插件：菜单入口、翻页记账
  moon_source.lua    月读扩展（ext.papersprite）：首页卡片
  papersprite/
    host/            宿主适配
    core/            state / travel / rng / reading / story（AI，可选）
    data/            places / items / souvenirs / visitors / postcards（纯数据）
    ui/              screen（全屏浮层）/ moon_card（首页卡片）/ moon_widgets（阁楼·明信片·纪念物柜组件）
                     widget_data（组件数据，纯函数）/ compose（分层画面合成 + 位图缓存）
    game.lua         控制器：结算 → 生成 view → host:showScreen
```

## 宿主适配（host/）
`host/interface.lua` 定义游戏可用的全部外部能力：`showScreen / closeScreen / schedule / unschedule / loadState / saveState / getSetting / setSetting / notify / now`。
- `koreader.lua`：UIManager 显示与定时，`settings/papersprite.lua`（LuaSettings）存档。
- `moon.lua`：继承 KOReader 宿主；存档写月读扩展独立表 `utils.settings.getSource("ext.papersprite")`，界面用月读主题皮肤，提示用月读 Toast。月读模块缺失时自动回落。
- 测试用宿主见 `spec/headless.lua`（虚拟时钟）。

## 界面
`ui/screen.lua` 是 `covers_fullscreen + modal` 的全屏浮层，在月读里盖住首页和底部导航；新界面先 show 再 close 旧的，并整屏刷新（`"ui"`），避免墨水屏残影。两套皮肤：装了月读就用 `ui.themes` 组件（逐个 pcall，失败的单个组件退回原生），否则 KOReader 原生控件；见 [widgets.md](widgets.md)。
`ui/moon_card.lua`：首页卡片，每次绘制时在存档**副本**上结算出近况摘要（不写盘），摘要变了才重建。

## 单实例
`Game.current`：菜单和月读卡片都能打开阁楼，新实例打开时关闭旧实例；每次结算前重读存档，以落盘数据为准，避免两个实例互相覆盖。

## 存档与版本
`core/state.lua`：存档是纯数据表，带 `version`。`State.load` 依次执行 `MIGRATIONS[v]` 升到 `State.VERSION`，缺字段补默认；无法识别则新开档。新增字段只需在 `State.fresh` 里加默认值；改结构时版本 +1 并写迁移函数。

## 离线实时结算
`core/travel.lua` 是状态机 `home → packed → away → home`：
- 收好行囊时就算好 `depart_at`；出发时一次性排好 `return_at` 和每张明信片的寄达时刻 `mail[].at`。
- `Travel.settle(state, now)` 把所有已到时刻的事件依次落地；`Travel.nextAt` 给出下一件事的时刻，界面开着时只在那时（最多 60 秒）刷新一次，关掉即停。
- 随机数用存档里的种子（`core/rng.lua`，LCG），同一存档同一时刻结果确定，便于测试复现。

## 阅读账本
`core/reading.lua`：`main.lua` 的 `onPageUpdate` 只记次数（不读书的内容），写 `settings/papersprite_reading.lua`；打开阁楼时按差值折算灵感。两种宿主共用这本账。

## 可选 AI
`host:ai()`（仅月读宿主）→ `core/story.lua` 异步请求、校验、写存档；详见 [ai.md](ai.md)。

## 画面
`view.scene = { bg, overlays = { {img, x, y, h, full?} }, frame }`：`ui/screen.lua` 用 OverlapGroup 叠 ImageWidget（alpha）。
明信片的图层位置在 `Game.cardScene`；访客在阁楼里的位置在 `VISITOR_POS`。
