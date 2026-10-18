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
    drizzle = { T("下了点小雨，我躲在一片大字底下等它停。"), T("雨点落在纸上，晕开成一个个小月亮。"), T("我把伞借给了一个句号，自己淋了一会儿。") },
    snow = { T("天上落纸屑了，我接住一片，上面什么也没写。"), T("纸屑积了薄薄一层，踩上去像翻书。"), T("我堆了一个很小的雪人，它没有字，也很好看。") },
    mist = { T("雾太大，我只好跟着自己的书角走。"), T("雾把远处的字都藏起来了，只剩近处的标点。"), T("在雾里，每个人说话都像旁白。") },
    dusk = { T("黄昏的时候，所有的影子都像书签。"), T("太阳下山前把整页都染成了旧纸的颜色。"), T("黄昏很短，像一个分号。") },
    night = { T("夜里很静，我借着别人的台灯给你写信。"), T("夜里的书页会轻轻地呼吸，我听见了。"), T("睡前我把今天折成一个小角，明天还能找到。") },
    clear = { T("今天天气很好，适合被读。"), T("阳光把我的影子写得很长。"), T("天很蓝，像一张还没开始写的纸。") },
    wind = { T("起风了，我抓着书角才没被翻到下一页。"), T("风把一句话吹得老远，我追了半天。"), T("风里有好多页的味道，我闻出了三本书。") },
    starry = { T("满天都是星号，我数着它们找脚注。"), T("星星一闪一闪，像有人在远处翻页。"), T("我躺着看星星，它们排成了一行省略号。") },
    sunrise = { T("我起了个大早，看太阳从页脚升起来。"), T("日出的时候，整本书都亮了一下。"), T("早晨的光是新的，像刚印好的字。") },
    petals = { T("花瓣落下来，夹在哪里都像书签。"), T("风里飘着纸花瓣，我接了一片给你。"), T("花瓣落了一身，我变成了一页插画。") },
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

local function texts(p, pose, weather)
    local out = {}
    for li, line in ipairs(p.lines) do out[#out + 1] = { line, "p:" .. li } end
    for gi, line in ipairs(M.generic[weather] or {}) do out[#out + 1] = { line, "g:" .. gi } end
    if M.pose_lines[pose] then out[#out + 1] = { M.pose_lines[pose], "s:" .. pose } end
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

--- 用存档种子拼一张明信片。返回 seed, card（card.key 为身份）
---@param collected table|nil key -> 最近一次收到的时间
---@param exclude table|nil 本趟已选的 key（同一趟不重复）
--- 规则：只挑没收集过、且本趟没选过的组合；全部收集过才退回「最久没见过」的那张。
--- 组合太多，先随机抽样最多 64 次找新的；抽不到再全量枚举。
function M.compose(seed, place_id, collected, exclude)
    collected, exclude = collected or {}, exclude or {}
    local p = M.place(place_id)
    local poses, props, weathers, bgs = lists(p)
    local v, pose, prop, weather, t
    for _ = 1, 64 do
        seed, v = R.pick(seed, bgs)
        seed, pose = R.pick(seed, poses)
        seed, prop = R.pick(seed, props)
        seed, weather = R.pick(seed, weathers)
        seed, t = R.pick(seed, texts(p, pose, weather))
        local c = make(p, v, pose, prop, weather, t)
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
    if c.weather and c.weather ~= "clear" then out.weather = "weather/" .. c.weather .. ".png" end
    return out
end

return M
