-- SPDX-License-Identifier: MIT
--[[--
节日：阿页出门那天赶上节日，明信片里会混进节日专属的短句，阁楼也会提一句。全部原创。
  md     公历月日（离线可用）
  lunar  农历月日文字（来自节日接口，如「八月十五」）
  match  节日接口 festival / holiday 字段里会出现的名字
  weather  天气权重倍数（节日偏爱的天色）
  lines  明信片短句（每张节日明信片 50% 概率用这里的）
  here   节日当天阁楼里的一句话
--]]
local T = require("papersprite.l10n")

return {
    { id = "newyear", md = { 1, 1 }, name = T("元旦"), weather = { sunrise = 4, snow = 2 },
      here = T("新的一年，书页还是空白的，阿页把第一行留给了你。"),
      lines = { T("新年的第一页，我什么都没写，先留着。"), T("日历翻到了第一页，我在页角折了个小记号。") } },
    { id = "spring", lunar = "正月初一", match = { "春节", "除夕" }, name = T("春节"), weather = { night = 2, starry = 2, snow = 2 },
      here = T("窗上贴了一张小小的红纸，阿页说那是福字。"),
      lines = { T("今天到处都是红纸和笑声，我也沾了一点喜气。"), T("有人把一整年的话折成了红包，我收到了一个。") } },
    { id = "lantern", lunar = "正月十五", match = { "元宵" }, name = T("元宵节"), weather = { night = 4, starry = 3 },
      here = T("阿页把油灯举到窗边，说今晚的月亮是圆的。"),
      lines = { T("灯一盏接一盏，像一行没有标点的长句。"), T("我提着一盏纸灯，把路照成了一页插画。") } },
    { id = "bookday", md = { 4, 23 }, name = T("世界读书日"), weather = { clear = 2, sunrise = 2 },
      here = T("今天是读书的日子，阿页坐得比平时更直一点。"),
      lines = { T("今天是书的节日，每一页都在悄悄伸懒腰。"), T("我替所有的书签向读书的人问好。") } },
    { id = "children", md = { 6, 1 }, name = T("儿童节"), weather = { clear = 2, petals = 2 },
      here = T("阿页把藤筐倒过来当帽子，在阁楼里转了两圈。"),
      lines = { T("今天可以不讲道理，只讲故事。"), T("我折了一只很小的纸飞机，它飞出了三个句子那么远。") } },
    { id = "dragon", lunar = "五月初五", match = { "端午" }, name = T("端午节"), weather = { drizzle = 3, clear = 1 },
      here = T("桌上多了一个小小的粽子，阿页说是邮差留下的。"),
      lines = { T("河上有纸船在赛跑，我押了最小的那只。"), T("粽叶的香气顺着书脊爬了进来。") } },
    { id = "midautumn", lunar = "八月十五", match = { "中秋" }, name = T("中秋节"), weather = { night = 4, starry = 3, clear = 1 },
      here = T("阿页把窗帘拉开一条缝，让月亮刚好落在书桌上。"),
      lines = { T("月亮圆得像一枚还没盖的邮戳。"), T("我把一小块月饼分成了四页，每页都是甜的。") } },
    { id = "national", md = { 10, 1 }, name = T("国庆节"), weather = { clear = 3, sunrise = 2 },
      here = T("长假的第一天，阿页把行囊又检查了一遍。"),
      lines = { T("假期里的风都是慢的，连书页都翻得很轻。"), T("今天到处都有人出门，我也混在人群里当了一枚书签。") } },
    { id = "doubleninth", lunar = "九月初九", match = { "重阳" }, name = T("重阳节"), weather = { wind = 3, clear = 2 },
      here = T("阿页说今天适合登高，哪怕只是爬上书堆。"),
      lines = { T("我爬到了很高的地方，看见整页的字都变小了。"), T("秋风里有菊花的味道，像一页晒干的信。") } },
    { id = "halloween", md = { 10, 31 }, name = T("万圣节"), weather = { night = 3, mist = 3, dusk = 2 },
      here = T("阿页披了一张空白纸，假装自己是一页幽灵。"),
      lines = { T("夜里的灯笼笑得有点夸张，我也笑了。"), T("雾里有个裹着白纸的小影子，原来是我自己。") } },
    { id = "christmas", md = { 12, 25 }, name = T("圣诞节"), weather = { snow = 4, night = 2, starry = 2 },
      here = T("阿页在窗台上挂了一枚小纸星，等不知名的客人。"),
      lines = { T("纸屑下得很轻，我把它们当成了今年的最后一封信。"), T("每扇亮着的窗，都像一页写了字的纸。") } },
}
