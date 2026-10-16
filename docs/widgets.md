# 月读首页组件、快捷面板与界面皮肤

## 首页组件（`moon_source.lua` → `provides.home_widgets`）
都是**只读视图**：在存档的副本上按当前时间结算后显示，不写存档，不在组件里玩；点按全屏打开阁楼对应页面。

| 组件 id | 名称 | 内容 | 点按 |
|---|---|---|---|
| `ext.papersprite.home` | 阿页 | 图标 + 近况两行（原有卡片） | 打开阁楼 |
| `ext.papersprite.attic` | 阿页的阁楼 | 当前阁楼画面（季节 / 夜晚、在家 / 出门、摆的特产、来访小客人）+ 一行近况 | 打开阁楼 |
| `ext.papersprite.postcards` | 阿页的明信片 | 两种模式：**最近列表**（缩略图 + 地点 · 天气 + 短句 + 日期）/ **迷你墙**（4 列缩略图网格）；新的在前，「新」角标；标题行带翻页条（n / m） | 点某张打开那张；点空白打开明信片墙 |
| `ext.papersprite.cabinet` | 纪念物柜 | 已收集特产图标 + 数量，标题「纪念物柜 n/48」；放不下的最后一格显示 +N | 打开特产柜 |

### 设置（首页编辑态里组件的设置按钮，`settings(desktop, id)`）
- 尺寸：小 / 中 / 大（决定默认高度和行数）。
  - 阁楼：小 = 左图右字一行；中 / 大 = 通栏画面（高 0.42 / 0.5 宽）+ 两行字。
  - 明信片列表：2 / 3 / 5 行；迷你墙：1 / 2 / 3 行 × 4 列。
  - 纪念物柜：1 / 2 / 4 行。
- 明信片另可选「最近列表 / 迷你墙」。
- 设置存在扩展自己的月读配置里（`w_<组件>_size`、`w_postcards_mode`），保存后发 `home_refresh` 重建首页。

### 高度与适配
- `heightRange` 按所选档位和组件宽度报内容高度；用户在月读里把高度改成像素 / 填充，或者整页放不下被等比压缩时，
  组件按实际分到的高度重新算能放几行（至少一行；纪念物柜连一行都放不下时缩小图标）。
- 内容贴卡片左上；卡片框、文字、翻页条用月读 `ui.themes`（Box / Text / Pager），拿不到主题时退回 KOReader 原生控件。

### 性能（墨水屏）
- `ui/compose.lua` 把分层画面（背景 + 装饰 + 访客 + 天气）一次合成到离屏位图，按「画面签名 + 尺寸」缓存（最多 24 张，最久未用先释放）。
  缩略图、图标同样走这份缓存，重绘不再解码缩放 PNG。
- 每次绘制前比对显示数据签名（`widget_data.sig`），变了才重建内容。
- 数据层 `ui/widget_data.lua` 是纯函数（headless 测试覆盖）。

## 顶部下拉快捷面板
### 阁楼卡（运行时注入，默认开）
月读面板主体 `features/panel/widget/body.lua` 的 `Body:updateView()` 把内容排进一个 `VerticalGroup`（`self[1]`）：
阅读面板时先放书名头 `header`，再放动作网格、滑杆。本插件照同样的方式往桌面面板里放一张紧凑阁楼卡（月读仓库不改）：

- `moon_source.lua` 加载时调用 `papersprite/ui/panel_inject.lua` 的 `install()`：包一层 `Body.updateView`——
  原函数照常执行后，若**桌面面板**（无 header）、**非编辑态**、设置开着，就在 `self[1]` 最前面插入卡片 + 10px 间距，
  再按新高度重算 `self.dimen`。月读的 `wrapPanel` 在 `Body:new` 之后才量高度，所以面板框自然变高。
- 卡片：左阁楼画面（2:1，高约 56–96px，按宽度定）+ 右边近况一行 + 灵感小字，月读主题卡片框 / 文字（不可用时原生）。
  画面走合成缓存；面板每次打开 / 刷新（`Menu.refresh` → `updateItems` → 新建 Body）都会重新结算。
- 点卡片：调用面板自己的 `body.on_action("ext.papersprite.attic")`，月读 `Registry.execute` 先关面板再运行「阿页」动作打开阁楼
  （动作没注册时退回直接打开阁楼）。
- 开关：首页「阁楼」组件设置里「下拉面板显示阁楼 / 不显示」（设置键 `panel_attic`，默认开）。

**防护**：模块缺失 / `updateView` 不是函数 → 不装；`self[1]` 不是带 `getSize` 的组、宽度异常 → 本次不插；
注入整体 pcall，出错只记日志、面板照常；只 patch 一次（`Body._papersprite_attic` 存原函数，`uninstall()` 可还原）。

**脆弱点**：依赖月读内部结构（模块路径、`updateView` 名字、`self[1]` 是纵向组、`header`/`editing`/`on_action`/`width` 字段、
`Registry.execute` 先关面板再跑动作）。月读改了这些时最坏是卡片不出现或点了不关面板，不会弄坏面板；
如果月读将来在 updateView 之外再缓存高度，面板可能和卡片高度对不上（目前没有）。长期还是建议月读开放正式的面板内容挂点（见下）。

### 正式挂点（月读本身）
月读对扩展只正式开放「动作开关」：`provides.features.panel.actions()` 返回 `{ id, scope, title, icon, run }`。
本插件也注册了「阿页」开关（id `ext.papersprite.attic`，需在面板编辑里加入）。
理想做法是月读新增 `provides.features.panel.widgets = { { id, height(w), build(w, h) } }`，由 body.lua 渲染并 pcall 隔离，届时可去掉运行时注入。

## 全屏界面皮肤（`ui/screen.lua`）
- 默认 `ui_skin = "auto"`：只要能 `require("ui.themes")`（装了月读，不论从月读还是 KOReader 菜单打开）就用月读组件：
  标题栏（TitleBar，带关闭图标）、卡片 / 图片框（Box）、文字（Text.box / Text.line）、按钮（Button）、翻页条（Pager）、主题色。
- **每个组件单独 pcall**：某个主题组件失败只有它退回原生控件，其余照常。
- `ui_skin = "native"`：强制 KOReader 原生控件（用来对照 / 排错）。
- 已在模拟器里对照：月读主题 paper / bold / soft 与原生皮肤。

## 明信片墙
- 两种视图（`wall_mode`，墙页底部按钮切换）：
  - 网格：3 列 × 4 行 = 每页 12 张，缩略图 + 地点名，「新」角标；
  - 列表：每页 4 张，左缩略图，右边「地点 · 天气 / 短句 / 日期」。
- 新的在前；翻页条显示 n / m（月读 Pager，原生退回「上一页 / n / m / 下一页」）。
- 「新」= 进墙前还没看过的；同一次进墙里翻页、切视图、看单张回来，角标都保留。
