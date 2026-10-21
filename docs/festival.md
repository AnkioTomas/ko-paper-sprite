# 节日与时令

阿页出门那天赶上节日，明信片里会混进节日专属短句，阁楼会提一句，小客人也更爱来。

## 数据来源
| 类型 | 来源 | 离线 |
|---|---|---|
| 公历节日（元旦、读书日、儿童节、国庆、万圣节、圣诞） | `data/festivals.lua` 的 `md` | ✅ |
| 农历节日（春节、元宵、端午、中秋、重阳） | 节日接口 `https://api.ankio.net/myrl?type=json`（和月读首页时钟同一个） | 取过当天就可用 |
| 节气 | 同一个接口的 `almanac.term` | 同上 |

接口只返回「今天」，所以农历节日和节气只在当天出门时生效。

## 取数规则
- 界面打开 2 秒后取一次（`Game:_almanac`），先让界面上屏；一天一次，存进 `state.almanac`。
- 失败（没联网 / 超时 4 秒 / 解析失败）静默，一小时后再试（`Festival.RETRY`）。
- 月读宿主优先读月读 `online.myrl` 的缓存，没有再自己取。纯 KOReader 宿主只在 `NetworkMgr` 已连上时才发请求，不会弹联网提示。
- 只请求一个公开接口，不带任何用户数据。关闭：设置项 `festival_online = false`（KOReader：`.moon/game/paper-sprite/save.lua` 里 `["setting_festival_online"] = false`；月读：`settings.festival_online = false`）。

## 节日当天的效果
- 阁楼「阿页在家 · 节日名」，说明里换成节日的一句话。
- 明信片：每张 50% 概率用节日短句（text_id 为 `f:<节日>:<序号>`，算独立收藏，卡上 `festival = <id>`）。
- 天气：节日有偏爱的天色（如中秋多夜里 / 星夜、圣诞多落纸屑）。
- 回家时来客概率 40% → 70%（`Travel.FESTIVAL_VISITOR_CHANCE`）。
- AI：提示词写明节日。

## 天气加权
`Postcards.weatherWeight(ctx, weather)` = 季节 × 钟点 × 节日偏好，ctx 取明信片寄达时刻。冬天多落纸屑、春天多花瓣、夜里多夜里 / 星夜、清晨多日出、傍晚多黄昏；白天几乎不会是夜里。没有 ctx 时均匀随机。

## 加一个节日
在 `data/festivals.lua` 加一项：`md`（公历）或 `lunar`（农历月日文字，如「八月十五」）、`match`（接口 `festival` / `holiday` 字段里的名字）、`name`、`here`、`lines`（≥2 句）、`weather`（天气权重倍数），再补 `l10n/en.lua` 与 `l10n/zh_TW.lua`。
