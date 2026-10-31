# 架构

```
paper-sprite.koplugin/
  main.lua           KOReader 插件：菜单入口、翻页记账
  moon_source.lua    月读扩展（ext.papersprite）：首页卡片
  papersprite/
    host/            宿主适配
    core/            state / travel / album（剪贴簿/来客簿聚合）/ rng / reading / story（AI，可选）
    data/            places / items / souvenirs / visitors / postcards（纯数据）
    ui/              screen（全屏浮层）/ moon_card（首页卡片）/ moon_widgets（阁楼·明信片·纪念物柜组件）
                     widget_data（组件数据，纯函数）/ compose（分层画面合成 + 位图缓存）
    game.lua         控制器：结算 → 生成 view → host:showScreen
```

## 宿主适配（host/）
`host/interface.lua` 定义游戏可用的全部外部能力：`showScreen / closeScreen / schedule / unschedule / loadState / saveState / getSetting / setSetting / notify / now`。
- `koreader.lua`：UIManager 显示与定时；存档用 LuaSettings，文件由 `core/storage.lua` 给出（见下文「存档位置」）。
- `moon.lua`：继承 KOReader 宿主；存档与 KOReader 宿主共用同一个文件；只有设置还写在月读扩展独立表 `utils.settings.getSource("ext.papersprite").settings`，界面用月读主题皮肤，提示用月读 Toast。月读模块缺失时自动回落。
- 测试用宿主见 `spec/run.lua`（虚拟时钟）。

## 多语言与自更新
- `papersprite/l10n.lua`：源字符串是简体中文，`T("文案 %s", x)` 先翻译再 `string.format`；按 KOReader 语言加载 `l10n/en.lua` / `l10n/zh_TW.lua`，没有译文回落原文。新增文案要同步加两份译文，键不能重复。数据表（地点 / 物品 / 明信片句子等）在 require 时取译文，语言切换需重启。
- `papersprite/version.lua`：版本占位符，`tools/package.sh <版本> [zip]` 打包时注入，源码运行显示 `0.0.0-dev`。
- `papersprite/update.lua`：复用月读的 GitHub Release 管线自更新（只在月读里可用，月读模块惰性 require）；资产名必须是 `paper-sprite.koplugin-<版本>.zip`（版本不带 v）。月读首页组件出现 5 秒后自动检查（24h 一次，只提示不静默安装）。

## 界面
`ui/screen.lua` 是 `covers_fullscreen + modal` 的全屏浮层，在月读里盖住首页和底部导航；新界面先 show 再 close 旧的，并整屏刷新（`"ui"`），避免墨水屏残影。只用月读 `ui.themes` 组件（入口 `need_moon.lua` 保证月读已装，没装只弹提示）；见 [widgets.md](widgets.md)。
`ui/moon_card.lua`：首页卡片，每次绘制时在存档**副本**上结算出近况摘要（不写盘），摘要变了才重建。

## 单实例
`Game.current`：菜单和月读卡片都能打开阁楼，新实例打开时关闭旧实例；每次结算前重读存档，以落盘数据为准，避免两个实例互相覆盖。

## 存档与版本
`core/state.lua`：存档是纯数据表，带 `version`。`State.load` 依次执行 `MIGRATIONS[v]` 升到 `State.VERSION`，缺字段补默认；无法识别则新开档。新增字段只需在 `State.fresh` 里加默认值；改结构时版本 +1 并写迁移函数。

## 离线实时结算
`core/travel.lua` 是状态机 `home → packed → away → home`：
- 收好行囊时就算好 `depart_at`；出发时一次性排好 `return_at` 和每张明信片的寄达时刻 `mail[].at`。
- `Travel.settle(state, now)` 把所有已到时刻的事件依次落地；`Travel.nextAt` 给出下一件事的时刻，界面开着时只在那时（最多 60 秒）刷新一次，关掉即停。
- 随机数用存档里的种子（`core/rng.lua`，Park–Miller 乘同余，乘积在 double 内精确），同一存档同一时刻结果确定，便于测试复现。

## 阅读账本
`core/reading.lua`：`main.lua` 的 `onPageUpdate` 只记次数（不读书的内容），写 `.moon/game/paper-sprite/reading.lua`；打开阁楼时按差值折算灵感。两种宿主共用这本账。

## 节日
`core/festival.lua` + `data/festivals.lua`：公历节日离线，农历 / 节气来自节日接口，详见 [festival.md](festival.md)。

## 可选 AI
`host:ai()`（仅月读宿主）→ `core/story.lua` 异步请求、校验、写存档；详见 [ai.md](ai.md)。

## 画面
`view.scene = { bg, overlays = { {img, x, y, h, full?} }, frame }`：`ui/screen.lua` 用 OverlapGroup 叠 ImageWidget（alpha）。
明信片的图层位置在 `Game.cardScene`；访客在阁楼里的位置在 `VISITOR_POS`。

## 存档位置
`core/storage.lua`：所有落盘数据放在 `DataStorage:getDataDir() .. "/.moon/game/paper-sprite"`（会一层层建好目录）。
- `save.lua`：`state`（存档，含 AI 写下的明信片短句 / 旁白）和 KOReader 宿主的设置 `setting_*`。
- `reading.lua`：阅读账本。
- 缩略图 / 合成缓存只在内存里（`ui/compose` 的 LRU），不落盘。

迁移：新文件不存在时，从旧位置复制。来源有三个：`settings/papersprite.lua`、`settings/papersprite_reading.lua`，以及月读的 `ext.papersprite.state`。两份存档都有时，取「明信片数 + 旅行次数」更大的那份。新文件 flush 后写入 `migrated_from`。旧文件不删，留作备份。
