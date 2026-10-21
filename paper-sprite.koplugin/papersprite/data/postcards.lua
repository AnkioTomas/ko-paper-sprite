-- SPDX-License-Identifier: MIT
--[[--
分层明信片（原创）：一张 = 地点背景 + 阿页姿势 + 前景小物 + 天气/时刻层 + 一句短句。
  背景  assets/places/<place>.png / <place>_b.png  1200×600
  姿势  assets/sprite/<pose>.png     透明，320×320
  小物  assets/props/<prop>.png      透明，200×200（"none" 无）
  天气  assets/weather/<weather>.png 透明，1200×600（"clear" 无叠加）
组合数：40 地点 × 2 背景 × 24 姿势 × 25 小物 × 10 天气 ≈ 48 万种画面，再乘短句库。
存档里每张明信片记下自己的组合与短句（AI 写的或本地库的），离线可看。
--]]
local T = require("papersprite.l10n")
local Places = require("papersprite.data.places")
local R = require("papersprite.core.rng")

local M = {}

M.poses = { "sit", "read", "wave", "walk", "peek", "sleep", "look_up", "carry",
    "eat", "write", "fish", "boat", "umbrella", "sketch", "nap_book", "crane", "warm_lamp",
    "dance", "stargaze", "hold_souvenir", "sit_bench", "swing", "read_lying", "jump" }
M.props = { "none", "lantern", "teacup", "paper_boat", "umbrella", "books", "flower",
    "kite", "bench", "signpost", "mailbox", "campfire", "bottle_letter", "basket", "mushroom",
    "paper_snowman", "candle", "telescope", "fishing_rod", "paper_crane", "leaf_pile", "globe",
    "birdhouse", "ladder", "suitcase" }
M.weathers = { "clear", "drizzle", "snow", "mist", "dusk", "night", "wind", "starry", "sunrise", "petals" }
M.weather_names = { clear = T("晴"), drizzle = T("小雨"), snow = T("落纸屑"), mist = T("起雾"), dusk = T("黄昏"), night = T("夜里"),
    wind = T("起风"), starry = T("星夜"), sunrise = T("日出"), petals = T("飘花瓣") }

--- 搭配限制：某些姿势/小物/天气只在合适的地点出现（tag）
local WATERY = { water = true, sea = true }
M.only = {
    pose = { fish = WATERY, boat = WATERY },
    prop = { paper_boat = WATERY, bottle_letter = WATERY, fishing_rod = WATERY,
        paper_snowman = { snow = true, mountain = true } },
}
--- 室内 / 地下的地点不下雨雪
M.indoor_weathers = { clear = true, dusk = true, night = true, mist = true }
local INDOOR = { indoor = true, underground = true }

local function allowed(kind, id, tag)
    local t = M.only[kind][id]
    return not t or t[tag] == true
end

--- 天气 / 时刻专属的通用短句（任何地点可用）
M.generic = {
    drizzle = { T("下了点小雨，我躲在一片大字底下等它停。"), T("雨点落在纸上，晕开成一个个小月亮。"), T("我把伞借给了一个句号，自己淋了一会儿。"),
        T("雨丝像很细的笔画，我站着看它们写满窗。"), T("我躲进一本倒扣的书里，听雨敲封面。"), T("雨天的墨水跑得慢，我的字也跟着慢下来。"),
        T("一滴雨落在句号上，句号变成了小水塘。"), T("我把书角朝下，雨水顺着滑走了，一点没湿。"), T("雨声是很好的背景音，我在里面睡了半页。"),
        T("邮筒打了个喷嚏，吐出一张潮潮的明信片。"), T("我数雨点数到一百，被一片叶子打断了。"), T("雨后的纸有点软，我走路都轻轻的。") },
    snow = { T("天上落纸屑了，我接住一片，上面什么也没写。"), T("纸屑积了薄薄一层，踩上去像翻书。"), T("我堆了一个很小的雪人，它没有字，也很好看。"),
        T("纸屑落在肩上，我成了一页会走路的信笺。"), T("我在纸屑里写了个大大的你，转头就被盖住了。"), T("纸屑太软了，我躺下去，像躺在一叠新信纸上。"),
        T("我把手缩进袖子里，纸屑就不好意思地躲开了。"), T("脚印排成一行，我回头检查有没有错别字。"), T("这场纸屑下得很守规矩，一片也没落在标题上。"),
        T("我把一片纸屑当围巾，围了三圈，还是很薄。"), T("纸屑吸走了钟声，世界静得像一条脚注。"), T("我捧着一小捧纸屑，想寄给你，又怕它化。") },
    mist = { T("雾太大，我只好跟着自己的书角走。"), T("雾把远处的字都藏起来了，只剩近处的标点。"), T("在雾里，每个人说话都像旁白。"),
        T("雾里的路牌只剩一个箭头，我选了它指的方向。"), T("我在雾里碰到一个逗号，它也迷路了，我们同行。"), T("雾打湿了我的书角，卷得更有个性了。"),
        T("雾像一张半透明的衬纸，隔在我和世界之间。"), T("远处的钟声被雾包好了才送到我这里。"), T("我伸手去摸雾，摸到了一手很淡的灰。"),
        T("雾里的灯一小团一小团的，像没写完的省略号。"), T("我走得很慢，雾也走得很慢，谁也不催谁。"), T("雾散了一点，露出半行字，我读成了半个故事。") },
    dusk = { T("黄昏的时候，所有的影子都像书签。"), T("太阳下山前把整页都染成了旧纸的颜色。"), T("黄昏很短，像一个分号。"),
        T("天边烧成了橙色的页脚，今天快读完了。"), T("路灯一盏盏亮起来，像在给街道加批注。"), T("我在晚霞里站了一会儿，边角也染上了暖色。"),
        T("太阳把最后一点光折好，放进了山的口袋。"), T("归鸟排成一行，像天空顺手写的短句。"), T("黄昏的风有点凉，我把书角朝里卷了一圈。"),
        T("影子被拉成了长长的书脊，一路跟着我。"), T("晚饭的香味从各家窗里飘出来，我只负责闻。"), T("云被染成了旧信封的颜色，我想把它寄给你。") },
    night = { T("夜里很静，我借着别人的台灯给你写信。"), T("夜里的书页会轻轻地呼吸，我听见了。"), T("睡前我把今天折成一个小角，明天还能找到。"),
        T("夜里的路灯很客气，每走一段就递给我一小圈光。"), T("我听见远处一页纸翻了个身，大概是谁睡着了。"), T("夜深了，字都缩成小小的一团，安心地睡。"),
        T("我借来一盏台灯，把今天的见闻写成了三行。"), T("夜里的墨水更黑一点，写出来的字特别踏实。"), T("月光落在桌上，我把它当成一张免费的信纸。"),
        T("窗外有只夜虫在念很短的诗，我听完了。"), T("夜太静，我翻身之前先跟被子打了声招呼。"), T("我数着窗格里的灯，数到最后一盏就困了。") },
    clear = { T("今天天气很好，适合被读。"), T("阳光把我的影子写得很长。"), T("天很蓝，像一张还没开始写的纸。"),
        T("晴天的纸都是脆的，翻起来有轻轻的响。"), T("我把自己晾在阳光里，边角翘得很精神。"), T("云淡得像铅笔轻轻擦过，只留了一点痕迹。"),
        T("今天的影子特别清楚，连书角的卷度都看得见。"), T("风很小，我的字稳稳地坐在纸上。"), T("阳光落在书页上，每个字都镀了一层金边。"),
        T("我在太阳底下眯了眯眼，世界像一张刚拆封的纸。"), T("天气好得让我想把所有的信都拿出来晒一晒。"), T("蓝天上有一道飞机划的线，像谁把天折了一下。") },
    wind = { T("起风了，我抓着书角才没被翻到下一页。"), T("风把一句话吹得老远，我追了半天。"), T("风里有好多页的味道，我闻出了三本书。"),
        T("风翻开了身边的一本书，我顺手给它压了块石头。"), T("我顶着风走，像一张逆着读的纸。"), T("风把我的书角吹得哗啦哗啦，像在打招呼。"),
        T("路边的纸片追着风跑，我追着纸片跑。"), T("风太大，我的话还没说完就被送到了别处。"), T("我躲在一棵树后面，风绕过来，又绕过去。"),
        T("风筝在天上拉着线，我在地上拉着自己。"), T("这阵风一定读过很多书，吹得特别有条理。"), T("风停的那一秒，整条街的纸都轻轻落了地。") },
    starry = { T("满天都是星号，我数着它们找脚注。"), T("星星一闪一闪，像有人在远处翻页。"), T("我躺着看星星，它们排成了一行省略号。"),
        T("星星太多，我数乱了，只好重新从北边数起。"), T("有颗星星眨眼的速度，跟我翻页一样慢。"), T("我在星空下摊开手心，接住了一小格安静。"),
        T("银河像一条很长的装订线，缝着整个夜晚。"), T("我给最亮的那颗取了个名字，不告诉你。"), T("流星一闪而过，像谁的钢笔甩出了一个墨点。"),
        T("夜空是一页深蓝的纸，星星是还没落款的字。"), T("我对着星星小声读了一页，它们听得很认真。"), T("抬头太久，脖子有点酸，可是很值得。") },
    sunrise = { T("我起了个大早，看太阳从页脚升起来。"), T("日出的时候，整本书都亮了一下。"), T("早晨的光是新的，像刚印好的字。"),
        T("天边先亮起一条细细的白，像书页的切口。"), T("清晨的露水挂在书角上，凉凉的，很清醒。"), T("第一缕光落在我身上，我像刚被熨平的纸。"),
        T("早起的鸟已经开始念今天的第一行。"), T("日出把云镶了金边，我也想镶一个。"), T("我伸了个懒腰，书角啪地展开了。"),
        T("晨光里，连最旧的纸也显得很年轻。"), T("太阳慢慢爬上来，像在认真地翻开新的一天。"), T("早晨的空气是薄荷味的，闻一闻，字都清楚了。") },
    petals = { T("花瓣落下来，夹在哪里都像书签。"), T("风里飘着纸花瓣，我接了一片给你。"), T("花瓣落了一身，我变成了一页插画。"),
        T("一片花瓣落在我头上，我就顶着它走了一路。"), T("花瓣在地上排成了一个很大的逗号。"), T("我在花瓣雨里转了个圈，转出了一页香气。"),
        T("花瓣落进茶杯里，这杯茶就有了名字。"), T("风一停，花瓣就睡在了我的脚边。"), T("我捡了几片最软的，打算夹进下一本书里。"),
        T("花瓣掉在信纸上，那封信就不用再画插图了。"), T("满地花瓣，我走得很小心，怕踩疼了春天。"), T("花瓣落了又落，像一场没有声音的掌声。") },
}

--- 姿势专属短句
M.pose_lines = {
    eat = T("我在路边吃了半块饼干，另外半块留给明天的我。"), write = T("这张是坐着写的，字比平常整齐一点。"),
    fish = T("我钓了一下午，钓上来一个形容词。"), boat = T("我坐在自己折的小船里，水没有把我泡软。"),
    umbrella = T("撑着伞走路，雨就只能落在伞的那一页。"), sketch = T("我画了一张这里的画，画着画着，它比我先画完了。"),
    nap_book = T("我在一本很厚的书上睡了个午觉，梦见自己是第一页。"), crane = T("纸鹤带我飞了一小段，下面的字都变得好小。"),
    warm_lamp = T("我在一盏小灯旁边烤手，暖得边角都不卷了。"), dance = T("没人看的时候，我跳了一小段舞。"),
    stargaze = T("我躺下来，伸手指了一颗最亮的。"), hold_souvenir = T("找到一样好东西，我举起来给风看。"),
    sit_bench = T("长椅很小，正好坐得下一个我。"), swing = T("我坐在一条丝带上荡啊荡，荡到了下一段。"),
    read_lying = T("我趴着看书，一不小心看到了天黑。"), jump = T("我跳了一下，差点跳出这一页。"),
}

M.souvenirs = require("papersprite.data.souvenirs")

function M.place(id) for _, p in ipairs(Places) do if p.id == id then return p end end end

--- 背景变体："a" 用 places/<id>.png，"b" 用 places/<id>_b.png
local function placeSeg(c) return (c.variant and c.variant ~= "a") and (c.place .. "@" .. c.variant) or c.place end

--- 一张明信片的身份：图层组合 + 文案 id（地点句 p:<序号> / 天气通用句 g:<序号> / 姿势句 s:<姿势>）
--- 变体 a 的 key 与旧版相同，老存档的收集记录继续有效。
function M.key(c) return table.concat({ placeSeg(c), c.pose, c.prop, c.weather, c.text_id or "?" }, "|") end

local function seasonOf(m)
    if m >= 3 and m <= 5 then return "spring" elseif m >= 6 and m <= 8 then return "summer"
    elseif m >= 9 and m <= 11 then return "autumn" end
    return "winter"
end

local function texts(p, pose, weather, month)
    local out = {}
    for li, line in ipairs(p.lines) do out[#out + 1] = { line, "p:" .. li } end
    for gi, line in ipairs(M.generic[weather] or {}) do out[#out + 1] = { line, "g:" .. gi } end
    if M.pose_lines[pose] then out[#out + 1] = { M.pose_lines[pose], "s:" .. pose } end
    if month then
        local season = seasonOf(month)
        for zi, line in ipairs(require("papersprite.data.seasons")[season] or {}) do out[#out + 1] = { line, "z:" .. season .. ":" .. zi } end
    end
    return out
end

local function lists(p)
    local poses, props, weathers = {}, {}, {}
    for _, x in ipairs(M.poses) do if allowed("pose", x, p.tag) then poses[#poses + 1] = x end end
    for _, x in ipairs(M.props) do if allowed("prop", x, p.tag) then props[#props + 1] = x end end
    for _, x in ipairs(M.weathers) do if not INDOOR[p.tag] or M.indoor_weathers[x] then weathers[#weathers + 1] = x end end
    return poses, props, weathers, p.bgs or { "a" }
end

local function make(p, v, pose, prop, weather, t)
    local c = { place = p.id, variant = v, pose = pose, prop = prop, weather = weather, line = t[1], text_id = t[2] }
    c.key = M.key(c)
    return c
end

--- 某地点的全部候选（视觉组合 × 可用文案）；量大，只在兜底时用
local function candidates(place_id)
    local p = M.place(place_id)
    local poses, props, weathers, bgs = lists(p)
    local out = {}
    for _, v in ipairs(bgs) do for _, pose in ipairs(poses) do for _, prop in ipairs(props) do
        for _, weather in ipairs(weathers) do
            for _, t in ipairs(texts(p, pose, weather)) do out[#out + 1] = make(p, v, pose, prop, weather, t) end
        end
    end end end
    return out
end
M.candidates = candidates

--- 天气权重：季节 × 钟点 × 节日偏好。没有情境时全部为 1（均匀）。
local SEASON = {
    [12] = "winter", [1] = "winter", [2] = "winter", [3] = "spring", [4] = "spring", [5] = "spring",
    [6] = "summer", [7] = "summer", [8] = "summer", [9] = "autumn", [10] = "autumn", [11] = "autumn",
}
local SEASON_W = {
    winter = { snow = 3, mist = 1.5, petals = 0.15, drizzle = 0.6 },
    spring = { petals = 3, drizzle = 2, snow = 0.15, wind = 1.3 },
    summer = { drizzle = 1.5, starry = 1.5, snow = 0.1, petals = 0.5 },
    autumn = { wind = 2.5, mist = 1.5, dusk = 1.5, snow = 0.3, petals = 0.3 },
}
local function hourW(h, w)
    if h >= 21 or h < 5 then return (w == "night" or w == "starry") and 4 or ((w == "sunrise" or w == "clear") and 0.1 or 1) end
    if h < 8 then return w == "sunrise" and 5 or ((w == "night" or w == "starry") and 0.2 or 1) end
    if h >= 17 and h < 20 then return w == "dusk" and 5 or ((w == "night" or w == "starry" or w == "sunrise") and 0.2 or 1) end
    if h == 20 then return (w == "dusk" or w == "night") and 3 or ((w == "sunrise") and 0.1 or 1) end
    return (w == "night" or w == "starry") and 0.1 or (w == "sunrise" and 0.2 or (w == "dusk" and 0.3 or 1))
end
function M.weatherWeight(ctx, w)
    if not ctx then return 1 end
    local x = 1
    if ctx.month then x = x * ((SEASON_W[SEASON[ctx.month]] or {})[w] or 1) end
    if ctx.hour then x = x * hourW(ctx.hour, w) end
    if ctx.festival and ctx.festival.weather then x = x * (ctx.festival.weather[w] or 1) end
    return x
end

local function pickWeather(seed, list, ctx)
    if not ctx then return R.pick(seed, list) end
    local w, total = {}, 0
    for i, x in ipairs(list) do w[i] = M.weatherWeight(ctx, x) total = total + w[i] end
    local f
    seed, f = R.next(seed)
    f = f * total
    for i, x in ipairs(list) do
        f = f - w[i]
        if f < 0 then return seed, x end
    end
    return seed, list[#list]
end

--- 用存档种子拼一张明信片。返回 seed, card（card.key 为身份）
---@param collected table|nil key -> 最近一次收到的时间
---@param exclude table|nil 本趟已选的 key（同一趟不重复）
---@param ctx table|nil 出片情境 { month, hour, festival }：天气按季节 / 钟点 / 节日加权，节日当天一半概率用节日短句
--- 规则：只挑没收集过、且本趟没选过的组合；全部收集过才退回「最久没见过」的那张。
--- 组合太多，先随机抽样最多 64 次找新的；抽不到再全量枚举。
function M.compose(seed, place_id, collected, exclude, ctx)
    collected, exclude = collected or {}, exclude or {}
    local p = M.place(place_id)
    local poses, props, weathers, bgs = lists(p)
    local v, pose, prop, weather, t
    for _ = 1, 64 do
        seed, v = R.pick(seed, bgs)
        seed, pose = R.pick(seed, poses)
        seed, prop = R.pick(seed, props)
        seed, weather = pickWeather(seed, weathers, ctx)
        local fest = ctx and ctx.festival
        local f = 1
        if fest then seed, f = R.next(seed) end
        if fest and f < 0.5 then
            local n
            seed, n = R.next(seed)
            n = math.floor(n * #fest.lines) + 1
            t = { fest.lines[n], "f:" .. fest.id .. ":" .. n }
        else
            seed, t = R.pick(seed, texts(p, pose, weather, ctx and ctx.month))
        end
        local c = make(p, v, pose, prop, weather, t)
        if fest and t[2]:sub(1, 2) == "f:" then c.festival = fest.id end
        if not collected[c.key] and not exclude[c.key] then return seed, c end
    end
    local all = candidates(place_id)
    local fresh = {}
    for _, c in ipairs(all) do
        if not collected[c.key] and not exclude[c.key] then fresh[#fresh + 1] = c end
    end
    if #fresh > 0 then
        local pick
        seed, pick = R.pick(seed, fresh)
        return seed, pick
    end
    local best, bt
    for _, c in ipairs(all) do
        if not exclude[c.key] then
            local tm = collected[c.key] or 0
            if not bt or tm < bt then best, bt = c, tm end
        end
    end
    return seed, best or all[1]
end

--- 图层路径（assets 相对）
function M.layers(c)
    local bg = (c.variant and c.variant ~= "a") and (c.place .. "_" .. c.variant) or c.place
    local out = { bg = "places/" .. bg .. ".png", pose = "sprite/" .. c.pose .. ".png" }
    if c.prop and c.prop ~= "none" then out.prop = "props/" .. c.prop .. ".png" end
    if c.festival then out.prop = "props/fest_" .. c.festival .. ".png" end -- 节日短句的明信片，小物换成节日应景的
    if c.weather and c.weather ~= "clear" then out.weather = "weather/" .. c.weather .. ".png" end
    return out
end

return M
