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
    for _, c in ipairs(H.view.grid and H.view.grid.cells or {}) do out[#out + 1] = { text = c.caption, callback = c.callback } end
    for _, c in ipairs(H.view.list and H.view.list.rows or {}) do out[#out + 1] = { text = c.title, callback = c.callback } end
    for _, c in ipairs(H.view.shelf and H.view.shelf.cells or {}) do out[#out + 1] = { text = c.title or c.name, callback = c.callback } end
    for _, c in ipairs(H.view.shelf2 and H.view.shelf2.cells or {}) do out[#out + 1] = { text = c.title or c.name, callback = c.callback } end
    if H.view.switch then out[#out + 1] = { text = "switch:" .. H.view.switch.text, callback = H.view.switch.callback } end
    for _, c in ipairs(H.view.tabs or {}) do out[#out + 1] = { text = "tab:" .. c.text, callback = c.callback } end
    for _, b in ipairs(H.view.buttons or {}) do
        if b[1] then for _, c in ipairs(b) do out[#out + 1] = c end else out[#out + 1] = b end
    end
    return out
end
local function click(prefix)
    for _, b in ipairs(btns()) do if b.text:sub(1, #prefix) == prefix then b.callback() return end end
    local t = {} for _, b in ipairs(btns()) do t[#t + 1] = b.text end
    error("no button " .. prefix .. " in " .. table.concat(t, " / "))
end
local function back() assert(H.view.back, "sub-screen must have back") H.view.back() end
local function text()
    local t = {}
    if H.view.status then t[#t + 1] = (H.view.status.title or "") .. "\n" .. (H.view.status.caption or "") .. "\n" .. (H.view.status.meta or "") end
    if H.view.empty then t[#t + 1] = H.view.empty.title .. "\n" .. (H.view.empty.caption or "") end
    for _, c in ipairs(H.view.shelf and H.view.shelf.cells or {}) do t[#t + 1] = (c.title or c.name or "") .. " " .. (c.meta or "") .. " " .. (c.caption or c.desc or "") end
    for _, l in ipairs(H.view.lines2 or {}) do t[#t + 1] = type(l) == "table" and l.text or l end
    for _, l in ipairs(H.view.lines or {}) do t[#t + 1] = type(l) == "table" and l.text or l end
    return table.concat(t, "\n")
end

-- 1. 打开，收拾行囊
local Game = require("papersprite.game")
local g = Game.new(H.host):show()
assert(H.view.title == "阿页的阁楼")
click("收拾行囊"); click("燕麦饼干"); click("铅笔头"); click("火柴盒地图册")
assert(H.saved.sprite.status == "packed", "should be packed")
back(); assert(text():find("快要出门"))

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
click("明信片墙"); click(""); assert(H.view.scene and H.view.scene.bg and H.view.status.caption:find("阿页"), "card view")
assert(H.view.scene.overlays[1].img:find("^sprite/"), "pose layer")
back(); back(); click("特产柜"); assert(text():find("×1"), "cabinet")
click(H.view.shelf.cells[1].title); assert(H.view.status and H.view.buttons[1].text == "摆到阁楼里", "souvenir detail")
click("摆到阁楼里"); assert(#g.state.decor == 1); back()
back(); click("小铺"); back()
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
    if not msgs[2].content:find("明信片") then return cb(nil) end -- 每日纸条等其他请求不计
    calls = calls + 1
    assert(msgs[1].role == "system")
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

-- 8b. 迟到的 AI：界面没开着时整趟走完 → 留 recap，之后补写；每日纸条
do
    local only_other = { json = function(msgs, cb)
        local c = msgs[2].content
        if c:find("没有出门") then return cb({ note = "阿页在擦灯罩。" }) end
        local n = select(2, c:gsub("%d%. 天气", ""))
        local lines = {} for i = 1, n do lines[i] = "迟到的第" .. i .. "句。" end
        cb({ lines = lines, souvenir_note = "迟到小注。" })
    end }
    H.saved, H.queue = nil, {}
    H.host.ai = nil
    local g3 = Game.new(H.host):show()
    click("收拾行囊"); click("燕麦饼干"); click("铅笔头"); click("火柴盒地图册")
    advance(100); advance(400)
    assert(H.saved.sprite.status == "home" and H.saved.recap, "recap kept")
    H.host.ai = function() return only_other end
    g3:tick()
    local cur = H.saved
    assert(not cur.recap, "recap consumed")
    local late = 0 for _, c in ipairs(cur.postcards) do if c.line:find("迟到") then late = late + 1 end end
    assert(late >= 1, "late lines patched")
    assert(cur.daily and cur.daily.text == "阿页在擦灯罩。", "daily note")
    g3:close()
end

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
local dup1 = 0 for _, c in ipairs(sv.postcards) do if c.line == "同一句话，第1张。" then dup1 = dup1 + 1 end end
assert(first_ai >= 1 and dup1 == 1 and ai2 >= first_ai, "repeated AI lines rejected: " .. dup1)
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
H.saved.decor = {}
H.saved.visitor = { id = "seal_bear", pose = "_2", until_at = H.clock + 99999 }
local g4 = Game.new(H.host):show()
click("特产柜"); click("一瓶雾"); click("摆到阁楼里"); assert(H.saved.decor[1] == "fog_jar")
back(); back()
local ov = {} for _, o in ipairs(H.view.scene.overlays) do ov[o.img] = true end
assert(ov["souvenirs/fog_jar.png"] and ov["visitors/seal_bear_2.png"], "decor + visitor pose overlays")
click("特产柜"); click("一瓶雾"); click("从阁楼收起"); assert(#H.saved.decor == 0)
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

-- 11. 月读首页组件数据（纯函数）：阁楼 / 明信片 / 纪念物柜；只读副本，不改存档
local WD = require("papersprite.ui.widget_data")
local raw = H.saved
local before = WD.sig(raw)
local vw = WD.view(raw, H.clock, true)
local da = WD.attic(vw, H.clock, true)
assert(da.scene.bg:match("^attic/attic_") and type(da.line) == "string" and da.sub:find("灵感"))
local dp = WD.postcards(vw, 3)
assert(dp.total == #vw.postcards and #dp.cards == math.min(3, dp.total))
for k = 2, #dp.cards do assert(dp.cards[k - 1].index > dp.cards[k].index, "newest first") end
if dp.cards[1] then assert(dp.cards[1].scene.bg:match("^places/") and dp.cards[1].place ~= "") end
vw.wall_seen = #vw.postcards - 1
local dp2 = WD.postcards(vw, 3)
assert(dp2.new == 1 and dp2.cards[1].new and (not dp2.cards[2] or not dp2.cards[2].new), "new mark")
vw.souvenirs = { fog_jar = 2, lake_pebble = 1, gone_item = 3 }
local dc = WD.cabinet(vw)
assert(dc.total == 48 and dc.have == 2 and dc.items[1].icon:match("^souvenirs/"), "cabinet n/48")
assert(WD.sig(raw) == before, "widget data must not touch the save")
assert(WD.sig({ a = 1, b = { 2 } }) == WD.sig({ b = { 2 }, a = 1 }))
local empty = WD.view(nil, 0, false)
assert(#WD.postcards(empty, 5).cards == 0 and WD.cabinet(empty).have == 0 and WD.attic(empty, 0, false).scene)

-- 12. 明信片墙分页：网格 12 张 / 列表 5 张一页，新的在前；切换视图
local sw = State.fresh(0)
for k = 1, 30 do sw.postcards[k] = { place = "ink_lake", pose = "sit", prop = "none", weather = "clear", line = "l" .. k, at = k } end
local ids, pg, pgs = Game.wallPage(sw, "grid", 1)
assert(#ids == 12 and ids[1] == 30 and pg == 1 and pgs == 3)
ids, pg, pgs = Game.wallPage(sw, "grid", 9)
assert(pg == 3 and #ids == 6 and ids[#ids] == 1, "clamped last page")
ids, pg, pgs = Game.wallPage(sw, "list", 2)
assert(pgs == 8 and #ids == 4 and ids[1] == 26)
assert(select(3, Game.wallPage(State.fresh(0), "grid", 1)) == 1)
H.saved = sw
local g5 = Game.new(H.host):show()
click("明信片墙")
assert(H.view.grid and #H.view.grid.cells == 12 and H.view.pager.pages == 3 and H.view.grid.cells[1].new)
H.view.pager.next(); assert(H.view.pager.page == 2)
click("switch:列表"); assert(H.view.list and #H.view.list.rows == 4 and H.view.list.rows[1].date and H.view.pager.pages == 8)
assert(H.view.list.rows[1].new, "new badge survives re-render in the same wall visit")
click("switch:网格")
-- 界面按剩余高度回报每页数量：记住并重排；翻页条带 go（首页 / 末页）
H.view.grid.fit(9); assert(#H.view.grid.cells == 9 and H.view.pager.pages == 4 and H.view.grid.per == 9)
H.view.pager.go(4); assert(H.view.pager.page == 4 and #H.view.grid.cells == 3); assert(H.view.grid)
g5:close()

-- 13. 小铺：货架分页 / 分类 / 详情 / 购买；每件可买物品都有介绍，效果行与数据一致
local Items = require("papersprite.data.items")
for _, it in ipairs(Items) do
    assert(type(it.desc) == "string" and #it.desc > 0, "desc " .. it.id)
    local short, long = Game.itemEffect(it)
    assert(short:find("爱去") and #long >= 3)
    if (it.hours_bias or 0) > 0 then assert(short:find("+" .. it.hours_bias, 1, true)) end
end
local list, sp, sps, total = Game.shopPage("all", 1)
assert(#list == 6 and sp == 1 and sps == math.ceil(total / 6))
assert(select(2, Game.shopPage("all", 99)) == sps)
for _, it in ipairs((Game.shopPage("food", 1))) do assert(it.slot == "food" and it.price > 0) end
local sb = State.fresh(0); sb.inspiration = 100
H.saved = sb
local g6 = Game.new(H.host):show()
click("小铺")
assert(H.view.shelf and #H.view.shelf.cells == 6 and H.view.pager.pages == sps)
assert(H.view.shelf.cells[1].desc and H.view.shelf.cells[1].price and H.view.shelf.cells[1].owned)
H.view.pager.next(); assert(H.view.pager.page == 2)
click("tab:护身物"); assert(H.view.pager.page == 1)
local first = H.view.shelf.cells[1].name
click(first); assert(H.view.title == first)
local before_insp = g6.state.inspiration
click("买一个"); assert(g6.state.inspiration < before_insp)
back(); assert(H.view.shelf)
g6:close()

-- 14. 子页面没有「回…」按钮；标题栏返回到上一级，阁楼页没有 back
H.saved = State.fresh(0)
local g7 = Game.new(H.host):show()
assert(not H.view.back)
for _, pg in ipairs({ "basket", "shop", "wall", "cabinet" }) do
    g7:go(pg)
    for _, b in ipairs(btns()) do assert(not (b.text:find("^回阁楼") or b.text:find("^回小铺") or b.text:find("^回明信片")), pg .. " still has " .. b.text) end
    back(); assert(g7.page == "attic")
end
g7:close()

-- 15. 阁楼主页分页：第 1 页画面 + 状态 + 入口；第 2 页来客 + 最近；日志多时更多页
local sa = State.fresh(0)
for k = 1, 15 do sa.log[k] = "事" .. k end
sa.visitor = { id = "inkbug", pose = "", until_at = 1e12 }
H.saved = sa
local g8 = Game.new(H.host):show()
assert(H.view.scene and H.view.shelf and #H.view.shelf.cells == 4 and H.view.pager.pages >= 2 and not H.view.notes)
H.view.pager.next(); assert(H.view.status.title:find("墨点虫") and H.view.notes and H.view.notes.rows[1].text == "事15")
H.view.notes.fit(5, 2); assert(H.view.pager.pages == 5 and #H.view.notes.rows == 3)
H.view.pager.go(3); assert(H.view.notes.rows[1].text == "事12" and #H.view.notes.rows == 5 and not H.view.status)
H.view.pager.go(5); assert(H.view.notes.rows[1].text == "事2" and #H.view.notes.rows == 2)
g8:close()

-- 16. 日志时间：新日志记时间；旧存档无时间不显示；格式
do
    local G = Game
    assert(G.when(1000, 1030) == "刚刚" and G.when(1000, 1000 + 180) == "3 分钟前" and G.when(1000, 1000 + 3 * 3600) == "3 小时前")
    assert(G.when(1000, 1000 + 3 * 86400) == os.date("%m-%d %H:%M", 1000) and G.when(0, 5) == nil and G.when(nil, 5) == nil)
    local old = State.fresh(0); old.log = { "旧1", "旧2" }; old.log_at = nil
    local ls = State.load(old, 0)
    assert(#ls.log_at == 2 and ls.log_at[1] == 0)
    State.log(ls, "新", 12345); assert(ls.log_at[3] == 12345)
    for k = 1, 30 do State.log(ls, "x" .. k, k) end
    assert(#ls.log == 20 and #ls.log_at == 20 and ls.log_at[20] == 30)
    H.saved = ls
    local g9 = Game.new(H.host):show(); H.view.pager.next()
    local r1 = H.view.notes.rows[1]; assert(r1.text == "x30" and r1.meta)
    g9:close()
end

-- 17. 存档位置与迁移：新目录 <data>/.moon/game/paper-sprite；旧 KOReader / 月读存档只复制不删，取进度多的
do
    local St = require("papersprite.core.storage")
    local files, made = {}, {}
    local function fake(path)
        files[path] = files[path] or { data = {} }
        local f = files[path]
        return { data = f.data, readSetting = function(_, k) return f.data[k] end,
            saveSetting = function(_, k, v) f.data[k] = v end, flush = function() f.flushed = true end }
    end
    local moon = { postcards = { 1, 2, 3 }, trips = 5 }
    St.deps = { dataDir = function() return "/D" end, settingsDir = function() return "/D/settings" end,
        open = fake, exists = function(p) return files[p] ~= nil end, mkdirp = function(p) made[#made + 1] = p end,
        moonState = function() return moon end }
    St._reset()
    fake("/D/settings/papersprite.lua").saveSetting(nil, "state", { postcards = { 1 }, trips = 1 })
    fake("/D/settings/papersprite.lua").saveSetting(nil, "setting_ui_skin", "native")
    fake("/D/settings/papersprite_reading.lua").saveSetting(nil, "pages", 42)
    local sv = St.open("save")
    assert(made[1] == "/D/.moon/game/paper-sprite" and files["/D/.moon/game/paper-sprite/save.lua"].flushed)
    assert(sv:readSetting("state") == moon and sv:readSetting("setting_ui_skin") == "native" and sv:readSetting("migrated_from"))
    assert(files["/D/settings/papersprite.lua"].data.state.trips == 1)   -- 旧文件原样保留
    assert(St.open("reading"):readSetting("pages") == 42)
    -- 已有新存档：不再迁移
    St._reset(); moon = { postcards = { 1, 2, 3, 4, 5, 6 }, trips = 9 }
    assert(St.open("save"):readSetting("state").trips == 5)
end

-- 18. 多语言：英文目录下各页没有残留中文（地点 / 物品 / 访客名也走译文），占位符数与中文一致
do
    local L10n = require("papersprite.l10n")
    L10n.load("en")
    -- 数据表在 require 时取译文，换语言后要重新加载（真实环境里语言切换必须重启）
    for k in pairs(package.loaded) do
        if k:find("^papersprite%.") and k ~= "papersprite.l10n" and k ~= "papersprite.core.reading" then package.loaded[k] = nil end
    end
    local GameEn, StateEn = require("papersprite.game"), require("papersprite.core.state")
    local function cjk(str) return str:find("[\228-\233]") end
    local function clean(where)
        local all = text()
        for _, b in ipairs(btns()) do all = all .. "\n" .. b.text end
        assert(not cjk(all), where .. " 有残留中文: " .. all)
    end
    H.saved = StateEn.fresh(0)
    for k, v in pairs(st.souvenirs or {}) do H.saved.souvenirs[k] = v end
    H.saved.postcards = st.postcards
    H.saved.inspiration = 50
    local ge = GameEn.new(H.host):show()
    clean("attic")
    for _, pg in ipairs({ "basket", "shop", "wall", "cabinet" }) do ge:go(pg) clean(pg) back() end
    ge.attic_page = 2 ge:render() clean("attic p2")
    ge:close()
    L10n.load("zh_CN")
    for k in pairs(package.loaded) do
        if k:find("^papersprite%.") and k ~= "papersprite.l10n" and k ~= "papersprite.core.reading" then package.loaded[k] = nil end
    end
end

-- 随机数：不再陷入短循环；种子越界也不崩
do
    local R = require("papersprite.core.rng")
    local seed0, seed, n = 20261022, 20261022, 0
    repeat seed = R.next(seed) n = n + 1 until seed == seed0 or n >= 300000
    assert(n >= 300000, "rng cycle too short: " .. n)
    local sd, f = R.next(0) assert(sd > 0 and f > 0 and f < 1)
    sd, f = R.next(2147483647 * 3) assert(sd > 0 and f < 1)
end

-- 天气按季节 / 钟点 / 节日加权；节日当天明信片混入节日短句
do
    local P, R = require("papersprite.data.postcards"), require("papersprite.core.rng")
    local function share(ctx, w)
        local seed, hit, N = 7, 0, 600
        for _ = 1, N do
            local c seed, c = P.compose(seed, "ink_lake", {}, {}, ctx)
            if c.weather == w then hit = hit + 1 end
        end
        return hit / N
    end
    assert(share({ month = 1, hour = 12 }, "snow") > 3 * share({ month = 7, hour = 12 }, "snow"), "snow favours winter")
    assert(share({ month = 7, hour = 13 }, "night") < 0.03 and share({ month = 7, hour = 23 }, "night") > 0.15, "night follows the clock")
    assert(share({ month = 4, hour = 12 }, "petals") > share({ month = 10, hour = 12 }, "petals"), "petals favour spring")
    local F = require("papersprite.core.festival")
    local fest = F.at({}, os.time({ year = 2026, month = 10, day = 1, hour = 12 }))
    assert(fest and fest.id == "national")
    local seed, n = 11, 0
    for _ = 1, 100 do
        local c seed, c = P.compose(seed, "ink_lake", {}, {}, { month = 10, hour = 12, festival = fest })
        if c.festival == "national" then n = n + 1 assert(c.key:find("|f:national:", 1, true)) end
    end
    assert(n > 25 and n < 75, "about half the cards carry festival lines: " .. n)
end

-- 节日接口：解析、按天缓存、农历 / 节气识别、失败后一小时再试
do
    local F = require("papersprite.core.festival")
    local daily = F.parse({ code = 200, data = { date = { ymd = "2026-09-25", lunar = "农历八月十五" },
        almanac = { festival = "", term = "" }, holiday = { label = "中秋节" } } })
    assert(daily and daily.ymd == "2026-09-25" and daily.holiday == "中秋节" and daily.term == nil)
    assert(F.parse({ code = 200, data = {} }) == nil and F.parse("x") == nil)
    local noon = os.time({ year = 2026, month = 9, day = 25, hour = 12 })
    local st = {}
    assert(F.store(st, daily, noon))
    assert(F.at(st, noon).id == "midautumn", "lunar festival by name")
    assert(F.at(st, noon + 86400 * 3) == nil, "cache only applies to its own day")
    st.almanac = { ymd = "2026-11-07", lunar = "农历九月十八", term = "立冬" }
    local t = F.at(st, os.time({ year = 2026, month = 11, day = 7, hour = 9 }))
    assert(t and t.id == "term" and t.name == "立冬" and #t.lines >= 1)
    local fresh = {}
    assert(F.needsFetch(fresh, noon))
    local calls = 0
    local host = { almanac = function(_, cb) calls = calls + 1 cb(nil) end, getSetting = function(_, _, d) return d end }
    assert(F.refresh(host, fresh, noon, function() end) and calls == 1)
    assert(not F.refresh(host, fresh, noon + 600, function() end) and calls == 1, "failure backs off for an hour")
    assert(F.refresh(host, fresh, noon + 3700, function() end) and calls == 2)
    host.getSetting = function(_, k, d) if k == "festival_online" then return false end return d end
    assert(not F.refresh(host, {}, noon, function() end), "setting turns the lookup off")
end

-- AI：失败后允许再试一次，之后放弃；提示词带节日与最近的句子
do
    local Story, State = require("papersprite.core.story"), require("papersprite.core.state")
    local sv = State.fresh(1000)
    sv.sprite = { status = "away", trip = 1, place = "ink_lake", mail = { { card = { weather = "clear", pose = "sit", prop = "none" } } },
        souvenir = next(require("papersprite.data.postcards").souvenirs), basket = {}, left_at = os.time({ year = 2026, month = 10, day = 1, hour = 9 }) }
    sv.postcards = { { line = "上一张的句子。" } }
    local store, reqs = sv, 0
    local host
    host = { loadState = function() return store end, saveState = function(_, t) store = t end, now = function() return 1000 end,
        schedule = function() end,
        ai = function() return { json = function(msgs, cb)
            reqs = reqs + 1
            host.last = msgs[2].content
            cb(nil, "boom")
        end } end }
    assert(Story.maybeRequest(host, store) and reqs == 1)
    assert(host.last:find("国庆节", 1, true) and host.last:find("上一张的句子", 1, true), "festival and recent lines in prompt")
    assert(store.sprite.ai_fails == 1 and store.sprite.ai_req == nil, "failure releases the request flag")
    assert(Story.maybeRequest(host, store) and reqs == 2)
    assert(store.sprite.ai_fails == 2)
    assert(not Story.maybeRequest(host, store) and reqs == 2, "gives up after MAX_TRIES")
end

print("headless ok: postcards=" .. #st.postcards .. " places=" .. np .. " combos=" .. nc)
