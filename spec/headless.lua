-- SPDX-License-Identifier: MIT
-- 无 KOReader 冒烟测试（虚拟时钟）：lua spec/headless.lua
package.path = "paper-sprite.koplugin/?.lua;" .. package.path
local H = { clock = 1000000, queue = {}, saved = nil, view = nil, settings = { debug_fast = true }, shows = 0 }
H.host = {
    showScreen = function(_, v) H.view = v H.shows = H.shows + 1 end,
    closeScreen = function() H.view = nil end,
    schedule = function(_, s, fn) H.queue[#H.queue + 1] = { at = H.clock + s, fn = fn } end,
    unschedule = function(_, fn) for i = #H.queue, 1, -1 do if H.queue[i].fn == fn then table.remove(H.queue, i) end end end,
    loadState = function() return H.saved end, saveState = function(_, t) H.saved = t end,
    getSetting = function(_, k, d) local v = H.settings[k] if v == nil then return d end return v end,
    setSetting = function(_, k, v) H.settings[k] = v end, notify = function() end,
    now = function() return H.clock end,
}
require("papersprite.host.interface").check(H.host)
package.loaded["papersprite.core.reading"] = { collect = function(s) return 0 end }

local function advance(secs)
    local stop = H.clock + secs
    while true do
        table.sort(H.queue, function(a, b) return a.at < b.at end)
        local t = H.queue[1]
        if not t or t.at > stop then break end
        table.remove(H.queue, 1); H.clock = math.max(H.clock, t.at); t.fn()
    end
    H.clock = stop
end
local function btns()
    local out = {}
    for _, b in ipairs(H.view.buttons) do
        if b[1] then for _, c in ipairs(b) do out[#out + 1] = c end else out[#out + 1] = b end
    end
    return out
end
local function click(prefix)
    for _, b in ipairs(btns()) do if b.text:sub(1, #prefix) == prefix then b.callback() return end end
    local t = {} for _, b in ipairs(btns()) do t[#t + 1] = b.text end
    error("no button " .. prefix .. " in " .. table.concat(t, " / "))
end
local function text()
    local t = {} for _, l in ipairs(H.view.lines) do t[#t + 1] = type(l) == "table" and l.text or l end
    return table.concat(t, "\n")
end

-- 1. 打开，收拾行囊
local Game = require("papersprite.game")
local g = Game.new(H.host):show()
assert(H.view.title == "阿页的阁楼")
click("收拾行囊"); click("燕麦饼干"); click("铅笔头"); click("火柴盒地图册")
assert(H.saved.sprite.status == "packed", "should be packed")
click("回阁楼"); assert(text():find("快要出门"))

-- 2. 界面开着：到点自动出门（调试模式：分钟→秒）
advance(100)
assert(H.saved.sprite.status == "away", "should be away: " .. H.saved.sprite.status)
assert(text():find("纸条"))

-- 3. 关掉插件，真实时间流逝后再打开：一次性结算（无后台定时器）
g:close(); assert(#H.queue == 0, "timers left after close")
local n = H.shows; advance(10000); assert(H.shows == n, "render after close")
g = Game.new(H.host):show()
assert(H.saved.sprite.status == "home", "should be home")
assert(#H.saved.postcards >= 1, "no postcard")
local sv = 0 for _, c in pairs(H.saved.souvenirs) do sv = sv + c end
assert(sv == 1, "souvenir")
-- 4. 明信片墙 → 单张（分层画面）
click("明信片墙"); click(""); assert(H.view.scene and H.view.scene.bg and #H.view.lines == 2, "card view")
assert(H.view.scene.overlays[1].img:find("^sprite/"), "pose layer")
click("回明信片墙"); click("回阁楼"); click("特产柜"); assert(H.view.lines[2]:find("×1"), "cabinet")
click("回阁楼"); click("小铺"); click("回阁楼")
g:close()

-- 5. 存档版本：坏存档 / 旧字段缺失 / v1 → v2 迁移
local State = require("papersprite.core.state")
assert(State.load(nil, 1).version == State.VERSION)
assert(State.load({ version = 1 }, 1).sprite.status == "home")
local mig = State.load({ version = 1, postcards = { { id = "ink_lake_01", at = 5 }, { id = "gone", at = 6 }, { id = "ink_lake_01", at = 7 } },
    wall_seen = 2, visitor = { until_at = 9 }, sprite = { status = "home" } }, 10)
assert(#mig.postcards == 1 and mig.postcards[1].place == "ink_lake" and mig.postcards[1].line, "migrate cards")
assert(mig.wall_seen == 1 and mig.visitor.id == "inkbug", "migrate misc")

-- 6. 首页卡片摘要（纯函数）
package.path = package.path -- moon_card 只在 build 时 require KOReader 控件
local Card = require("papersprite.ui.moon_card")
local s = Card.summary(H.saved, H.clock, true); assert(s.line1 and s.line2)

-- 7. 确定性：同存档同时刻结果一致；长期跑 50 趟不出错
local Travel = require("papersprite.core.travel")
local st = State.fresh(0); st.inventory = { tea_bag = 99, paper_umbrella = 99, poem_slip = 99 }
local t = 0
for i = 1, 50 do
    local ids = ({ { "oat_biscuit", "pencil_stub", "tiny_atlas" }, { "tea_bag", "paper_umbrella", "poem_slip" } })[i % 2 + 1]
    for _, id in ipairs(ids) do assert(Travel.put(st, id, t, false)) end
    t = t + 40 * 3600; Travel.settle(st, t, false)
    assert(st.sprite.status == "home", "trip " .. i)
end
-- 多样性：50 趟去过的地点与画面组合
local seenPlace, seenCombo = {}, {}
for _, c in ipairs(st.postcards) do seenPlace[c.place] = true seenCombo[c.place .. c.pose .. c.prop .. c.weather] = true end
local np, nc = 0, 0 for _ in pairs(seenPlace) do np = np + 1 end for _ in pairs(seenCombo) do nc = nc + 1 end
assert(np >= 8, "place variety " .. np)

-- 8. AI 文案层（桩）：成功 / 不合规 / 报错 / 不回调（超时）都不影响旅行
local Story = require("papersprite.core.story")
local function trip(ai_impl)
    H.saved, H.queue = nil, {}
    H.host.ai = ai_impl and function() return ai_impl end or nil
    local g2 = Game.new(H.host):show()
    click("收拾行囊"); click("燕麦饼干"); click("铅笔头"); click("火柴盒地图册")
    advance(100)                     -- 出门，触发 AI 请求
    assert(H.saved.sprite.status == "away")
    advance(400)                     -- 回家
    assert(H.saved.sprite.status == "home", "trip finishes regardless of AI")
    g2:close()
    return H.saved
end
local calls = 0
local good = { json = function(msgs, cb)
    calls = calls + 1
    assert(msgs[1].role == "system" and msgs[2].content:find("明信片"), "prompt")
    local n = select(2, msgs[2].content:gsub("%d%. 天气", ""))
    local lines = {} for i = 1, n do lines[i] = "AI 写的第" .. i .. "句。" end
    cb({ lines = lines, narration = "它把风叠好放进了口袋。", souvenir_note = "AI 小注。", visitor_line = "AI 访客。" })
end }
local sv = trip(good)
assert(calls == 1, "one request per trip")
local ai_cards = 0 for _, c in ipairs(sv.postcards) do if c.ai then ai_cards = ai_cards + 1 assert(c.line:find("AI")) end end
assert(ai_cards >= 1, "ai lines cached into save")
assert(sv.log[#sv.log]:find("把风叠好") or table.concat(sv.log, "|"):find("把风叠好"), "narration")
-- 不合规：句子太长 → 整体放弃，用本地句
local bad = { json = function(_, cb) cb({ lines = { string.rep("长", 80) } }) end }
sv = trip(bad); for _, c in ipairs(sv.postcards) do assert(not c.ai, "invalid ai rejected") end
-- 报错
sv = trip({ json = function() error("boom") end }); assert(#sv.postcards >= 1)
-- 永不回调（超时）
sv = trip({ json = function() return { cancel = function() end } end }); assert(#sv.postcards >= 1)
-- 校验函数
assert(Story.validate({ lines = { "好" } }, 1).lines[1] == "好")
assert(not Story.validate({ lines = { "<script>" } }, 1))
assert(not Story.validate({ lines = {} }, 1))

-- 9. 明信片去重：200 趟不重复；同一趟不重复；全部收集后退回最久没见过的
local P = require("papersprite.data.postcards")
local st2 = State.fresh(0); st2.inventory = {}
local tt, keys = 0, {}
for i = 1, 200 do
    for _, id in ipairs({ "oat_biscuit", "pencil_stub", "tiny_atlas" }) do assert(Travel.put(st2, id, tt, false)) end
    tt = tt + 40 * 3600; Travel.settle(st2, tt, false)
end
for _, c in ipairs(st2.postcards) do
    assert(c.key, "card has key")
    assert(not keys[c.key], "duplicate postcard " .. c.key)
    keys[c.key] = true
end
print("  200 trips, " .. #st2.postcards .. " postcards, all unique")
-- 耗尽：只剩 2 张没收过 → 先给这 2 张，再给最久没见过的那张
local all = P.candidates("ink_lake")
local col = {}
for i, c in ipairs(all) do col[P.key(c)] = 1000 + i end
local k1, k2 = P.key(all[10]), P.key(all[20])
col[k1], col[k2] = nil, nil
col[P.key(all[5])] = 1 -- 最久没见过
local seed, ex, got = 42, {}, {}
for i = 1, 3 do
    local c
    seed, c = P.compose(seed, "ink_lake", col, ex)
    ex[c.key] = true; got[i] = c.key
end
assert((got[1] == k1 or got[1] == k2) and (got[2] == k1 or got[2] == k2) and got[1] ~= got[2], "fresh first")
assert(got[3] == P.key(all[5]), "then least recently seen")
-- AI 去重：每趟都返回同样的句子 → 只有第一次被采用
H.saved = nil
local same = { json = function(msgs, cb)
    local n = select(2, msgs[2].content:gsub("%d%. 天气", ""))
    local lines = {} for i = 1, n do lines[i] = "同一句话，第" .. i .. "张。" end
    cb({ lines = lines })
end }
sv = trip(same)
local first_ai = 0 for _, c in ipairs(sv.postcards) do if c.ai then first_ai = first_ai + 1 end end
local function again()
    H.host.ai = function() return same end
    local g3 = Game.new(H.host):show()
    click("收拾行囊"); click("燕麦饼干"); click("铅笔头"); click("火柴盒地图册")
    advance(100); advance(400); g3:close()
    return H.saved
end
sv = again()
local ai2 = 0 for _, c in ipairs(sv.postcards) do if c.ai then ai2 = ai2 + 1 end end
assert(first_ai >= 1 and ai2 == first_ai, "repeated AI lines rejected: " .. first_ai .. " vs " .. ai2)
-- 同一回复里两句相同 → 整体放弃
assert(not Story.validate({ lines = { "一样。", "一样！" } }, 2), "dup within response")
local wk = {} for _, c in ipairs(sv.postcards) do assert(not wk[c.key], "dup in save") wk[c.key] = true end

-- 10. 第 3 批：v2 → v3 迁移、背景变体、搭配限制、阁楼季节与装饰、访客姿势
local m3 = State.load({ version = 2, postcards = { { place = "ink_lake", pose = "sit", prop = "none", weather = "clear", text_id = "p:1", key = "ink_lake|sit|none|clear|p:1" } },
    collected = { ["ink_lake|sit|none|clear|p:1"] = 1 }, visitor = { id = "inkbug", until_at = 9 } }, 0)
assert(m3.version == 3 and m3.postcards[1].variant == "a" and type(m3.decor) == "table" and m3.visitor.pose == "")
assert(P.key(m3.postcards[1]) == "ink_lake|sit|none|clear|p:1", "old key stays valid")
local cb = { place = "ink_lake", variant = "b", pose = "fish", prop = "none", weather = "clear", text_id = "p:1" }
assert(P.key(cb) == "ink_lake@b|fish|none|clear|p:1" and P.layers(cb).bg == "places/ink_lake_b.png")
local sd = 7
for _ = 1, 300 do
    local c; sd, c = P.compose(sd, "margin_desert", {}, {})
    assert(c.pose ~= "fish" and c.pose ~= "boat" and c.prop ~= "paper_boat", "water pose in desert")
    local c2; sd, c2 = P.compose(sd, "reading_room", {}, {})
    assert(P.indoor_weathers[c2.weather], "rain indoors")
end
assert(Game.atticBg(os.time({ year = 2026, month = 4, day = 1, hour = 12 })) == "attic/attic_spring.png")
assert(Game.atticBg(os.time({ year = 2026, month = 1, day = 1, hour = 23 }), true) == "attic/attic_night_empty.png")
-- 特产摆进阁楼
H.saved.souvenirs = { lake_pebble = 1, fog_jar = 2 }
H.saved.visitor = { id = "seal_bear", pose = "_2", until_at = H.clock + 99999 }
local g4 = Game.new(H.host):show()
click("特产柜"); click("一瓶雾"); assert(H.saved.decor[1] == "fog_jar")
click("回阁楼")
local ov = {} for _, o in ipairs(H.view.scene.overlays) do ov[o.img] = true end
assert(ov["souvenirs/fog_jar.png"] and ov["visitors/seal_bear_2.png"], "decor + visitor pose overlays")
click("特产柜"); click("✓ 一瓶雾"); assert(#H.saved.decor == 0)
g4:close()
-- 资源齐全：每个被引用的图都在 assets 里
local A = "paper-sprite.koplugin/assets/"
local function has(f) local h = io.open(A .. f, "rb") if h then h:close() return true end end
local miss = {}
local function need(f) if not has(f) then miss[#miss + 1] = f end end
for _, pl in ipairs(require("papersprite.data.places")) do need("places/" .. pl.id .. ".png") need("places/" .. pl.id .. "_b.png") end
for _, x in ipairs(P.poses) do need("sprite/" .. x .. ".png") end
for _, x in ipairs(P.props) do if x ~= "none" then need("props/" .. x .. ".png") end end
for _, x in ipairs(P.weathers) do if x ~= "clear" then need("weather/" .. x .. ".png") end end
for id in pairs(P.souvenirs) do need("souvenirs/" .. id .. ".png") end
for _, it in ipairs(require("papersprite.data.items")) do need("items/" .. it.id .. ".png") end
for _, v in ipairs(require("papersprite.data.visitors")) do need("visitors/" .. v.id .. ".png") need("visitors/" .. v.id .. "_2.png") end
for _, v in ipairs({ "spring", "summer", "autumn", "winter", "night" }) do need("attic/attic_" .. v .. ".png") need("attic/attic_" .. v .. "_empty.png") end
if os.getenv("SKIP_ASSETS") then print("  assets missing (skipped): " .. #miss)
else assert(#miss == 0, "missing assets: " .. table.concat(miss, ", ")) end

print("headless ok: postcards=" .. #st.postcards .. " places=" .. np .. " combos=" .. nc)
