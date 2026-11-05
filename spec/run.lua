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
    if H.view.tabbar and H.view.tabbar.active <= 2 then -- 阁楼的入口在首页，册子在收藏页
        H.view.tabbar.on_tab(3 - H.view.tabbar.active)
        for _, b in ipairs(btns()) do if b.text:sub(1, #prefix) == prefix then b.callback() return end end
    end
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
--- 阁楼首页：通栏画面 + 状态 + 三个操作入口（页签在底栏）
local function attic_home()
    assert(H.view.tabbar, "attic tabbar")
    if H.view.tabbar.active ~= 1 then H.view.tabbar.on_tab(1) end
    assert(H.view.scene and H.view.scene_wide and H.view.shelf and #H.view.shelf.cells == 3, "attic home")
end
local attic_ops = attic_home

-- 1. 打开，收拾行囊
local Game = require("papersprite.game")
local g = Game.new(H.host):show()
assert(H.view.title == "阿页的阁楼")
assert(H.view.scene and H.view.scene_wide and #H.view.shelf.cells == 3, "page1 has scene + 3 acts")
attic_ops(); click("收拾行囊"); click("燕麦饼干"); click("铅笔头"); click("火柴盒地图册")
assert(H.saved.sprite.status == "packed", "should be packed")
back(); attic_home(); assert(text():find("快要出门"))

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
local place_id = H.saved.postcards[1].place
assert((H.saved.place_trips or {})[place_id] == 1, "place_trips on return")
-- 4. 明信片墙：一页同时是正面和背面，不再翻面
attic_ops(); click("明信片墙")
assert(H.view.postcard and H.view.postcard.scene and H.view.postcard.scene.bg and H.view.postcard.scene.overlays[1].img:find("^sprite/"), "card view")
assert(H.view.postcard.side == nil and not H.view.buttons and H.view.switch and H.view.switch.icon == "share", "both sides, corner share, no flip")
back(); attic_ops(); click("特产柜"); assert(text():find("×1"), "cabinet")
click(H.view.shelf.cells[1].title); assert(H.view.status and H.view.buttons[1].text == "摆到阁楼里", "souvenir detail")
click("摆到阁楼里"); assert(#g.state.decor == 1); back()
back(); attic_ops(); click("小铺"); back()
-- 4b. 剪贴簿 / 来客簿
attic_ops(); click("剪贴簿"); assert(H.view.title == "地点剪贴簿" and H.view.shelf and #H.view.shelf.cells >= 1)
g:go("place", place_id); assert(H.view.buttons and H.view.buttons[1].text:find("惦记"))
local before_wish = g.state.inspiration
click("惦记"); assert(g.state.wish_place == place_id and g.state.inspiration == before_wish - 5)
back(); back()
attic_ops(); click("来客簿"); assert(H.view.title == "来客簿")
back()
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
    attic_ops(); click("收拾行囊"); click("燕麦饼干"); click("铅笔头"); click("火柴盒地图册")
    advance(100)                     -- 出门，触发 AI 请求
    assert(H.saved.sprite.status == "away")
    advance(400)                     -- 回家
    assert(H.saved.sprite.status == "home", "trip finishes regardless of AI")
    g2:close()
    return H.saved
end
local calls = 0
local good = { json = function(msgs, cb)
    if not msgs[2].content:find("天气/时刻", 1, true) then return cb(nil) end -- 每日纸条等其他请求不计
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
        if c:find("预先写一批") then
            local b = {}
            for _, k in ipairs({ "dawn", "day", "dusk", "night" }) do b[k] = { "阿页在擦灯罩。", "阿页在数书页。", "阿页在发呆。" } end
            return cb(b)
        end
        if c:find("预先写短句") then
            local r = {}
            for id in c:gmatch("\n([%w_]+)：") do r[id] = { "池里的" .. id .. "一。", "池里的" .. id .. "二。" } end
            return cb(r)
        end
        if c:find("改写") then
            local r = {}
            for id in c:gmatch("\n([%w_]+)：") do r[id] = { "改写的" .. id .. "。" } end
            return cb(r)
        end
        if c:find("小委托") then return cb({ flavors = { "便签一。", "便签二。", "便签三。", "便签四。", "便签五。", "便签六。" } }) end
        if c:find("递给它一件特产") then return cb({ match = "它眼睛一亮。", plain = "它收下了。" }) end
        local n = select(2, c:gsub("%d%. 天气", ""))
        local lines = {} for i = 1, n do lines[i] = "迟到的第" .. i .. "句。" end
        cb({ lines = lines, souvenir_note = "迟到小注。" })
    end }
    H.saved, H.queue = nil, {}
    H.host.ai = nil
    local g3 = Game.new(H.host):show()
    attic_ops(); click("收拾行囊"); click("燕麦饼干"); click("铅笔头"); click("火柴盒地图册")
    advance(100); advance(400)
    assert(H.saved.sprite.status == "home" and H.saved.recap, "recap kept")
    H.host.ai = function() return only_other end
    g3:tick()
    local cur = H.saved
    assert(not cur.recap, "recap consumed")
    local late = 0 for _, c in ipairs(cur.postcards) do if c.line:find("迟到") then late = late + 1 end end
    assert(late >= 1, "late lines patched")
    assert(next(cur.pool.lines) and next(cur.pool.events), "lines and events prefetched")
    if not (cur.errands and cur.errands[1] and cur.errands[1].aside) then
        require("papersprite.core.errand").leave(cur, "inkbug", 1)
        H.host:saveState(cur)
        g3:tick()
        cur = H.saved
    end
    assert(cur.errands and cur.errands[1] and cur.errands[1].aside == "便签一。", "errand aside")
    local pl = next(cur.pool.lines)
    local line = require("papersprite.core.pool").takeLine(cur, pl, function() return false end)
    assert(line and line:find("池里的"), "take a pooled line")
    local e1 = require("papersprite.data.events")[1]
    assert(require("papersprite.core.pool").eventText(cur, e1) == "改写的" .. e1.id .. "。", "event text from pool")
    assert(require("papersprite.core.pool").eventText(cur, e1) == e1.text, "falls back to local text when pool is empty")
    assert(cur.pool.notes.dawn and #cur.pool.notes.dawn + #cur.pool.notes.day == 6, "notes prefetched into pool")
    g3:tick()
    cur = H.saved
    assert(cur.daily and cur.daily.text == "阿页在擦灯罩。", "daily note taken from pool")
    assert(#cur.pool.notes.day + #cur.pool.notes.dawn + #cur.pool.notes.dusk + #cur.pool.notes.night == 11, "one consumed")
    cur.visitor = { id = "inkbug", until_at = H.clock + 99999, request = "shelf_plank" }
    H.host:saveState(cur)
    g3:tick()
    cur = H.saved
    assert(cur.visitor.react and cur.visitor.react.match == "它眼睛一亮。", "guest reaction prefetched")
    cur.souvenirs.shelf_plank = 1
    local ok, msg = require("papersprite.core.quest").give(cur, "shelf_plank", H.clock)
    assert(ok and msg:find("它眼睛一亮。", 1, true), "reaction shown when hosting: " .. tostring(msg))
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
    attic_ops(); click("收拾行囊"); click("燕麦饼干"); click("铅笔头"); click("火柴盒地图册")
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

-- 10. 第 3/4 批：v2 → v4 迁移、背景变体、搭配限制、阁楼季节与装饰、访客姿势、剪贴簿回填
local m3 = State.load({ version = 2, postcards = { { place = "ink_lake", pose = "sit", prop = "none", weather = "clear", text_id = "p:1", key = "ink_lake|sit|none|clear|p:1", trip = 1 } },
    collected = { ["ink_lake|sit|none|clear|p:1"] = 1 }, visitor = { id = "inkbug", until_at = 9 },
    souvenirs = { lake_pebble = 1 } }, 0)
assert(m3.version == State.VERSION and m3.postcards[1].variant == "a" and type(m3.decor) == "table" and m3.visitor.pose == "" and type(m3.errands) == "table")
assert(m3.place_trips.ink_lake == 1 and m3.seen_visitors.inkbug == 9, "v4 album migrate")
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
assert(Game.atticBg(os.time({ year = 2026, month = 4, day = 1, hour = 12 })):match("^attic/attic_spring_"))
assert(Game.atticBg(os.time({ year = 2026, month = 1, day = 1, hour = 23 }), true):match("night") and Game.atticBg(os.time({ year = 2026, month = 1, day = 1, hour = 23 }), true):find("_empty"))
-- 出门选图全矩阵：四季 × 三时段都必须落到 _empty 且文件存在（素材本身有没有画人靠 tools/fix_empty_attic.py 的名单，Lua 验不了像素）
for _, mo in ipairs({ 4, 7, 10, 1 }) do
    for _, hr in ipairs({ 12, 19, 23 }) do
        local bg = Game.atticBg(os.time({ year = 2026, month = mo, day = 1, hour = hr }), true)
        assert(bg:find("_empty"), "away bg not empty: " .. bg)
        local fh = io.open("paper-sprite.koplugin/assets/" .. bg, "rb") assert(fh, "missing " .. bg) fh:close()
    end
end
assert(Game.atticSeason(os.time({ year = 2026, month = 4, day = 1 })) == "spring")
assert(Game.atticTod(os.time({ year = 2026, month = 4, day = 1, hour = 12 })) == "day")
assert(Game.atticTod(os.time({ year = 2026, month = 4, day = 1, hour = 19 })) == "dusk")
assert(Game.atticTod(os.time({ year = 2026, month = 4, day = 1, hour = 23 })) == "night")
-- 特产摆进阁楼
H.saved.souvenirs = { lake_pebble = 1, fog_jar = 2 }
H.saved.decor = {}
H.saved.visitor = { id = "seal_bear", pose = "_2", until_at = H.clock + 99999 }
local g4 = Game.new(H.host):show()
attic_ops(); click("特产柜"); click("一瓶雾"); click("摆到阁楼里"); assert(H.saved.decor[1] == "fog_jar")
back(); back(); attic_home()
local ov = {} for _, o in ipairs(H.view.scene.overlays) do ov[o.img] = true end
assert(ov["souvenirs/fog_jar.png"] and ov["visitors/seal_bear_2.png"], "decor + visitor pose overlays")
attic_ops(); click("特产柜"); click("一瓶雾"); click("从阁楼收起"); assert(#H.saved.decor == 0)
g4:close()
-- 资源齐全：每个被引用的图都在 assets 里
local A = "paper-sprite.koplugin/assets/"
local function has(f) local h = io.open(A .. f, "rb") if h then h:close() return true end end
local miss = {}
local function need(f) if not has(f) then miss[#miss + 1] = f end end
do
    local seen_zip = {}
    for _, pl in ipairs(require("papersprite.data.places")) do
        need("places/" .. pl.id .. ".png") need("places/" .. pl.id .. "_b.png")
        assert(type(pl.zip) == "string" and pl.zip:match("^%d%d%d%d%d%d$"), "place zip " .. tostring(pl.id))
        assert(not seen_zip[pl.zip], "duplicate zip " .. pl.zip)
        seen_zip[pl.zip] = pl.id
    end
end
for _, x in ipairs(P.poses) do need("sprite/" .. x .. ".png") end
for _, x in ipairs(P.props) do if x ~= "none" then need("props/" .. x .. ".png") end end
for _, x in ipairs(P.weathers) do if x ~= "clear" then need("weather/" .. x .. ".png") end end
for id in pairs(P.souvenirs) do need("souvenirs/" .. id .. ".png") end
for _, it in ipairs(require("papersprite.data.items")) do need("items/" .. it.id .. ".png") end
for _, v in ipairs(require("papersprite.data.visitors")) do need("visitors/" .. v.id .. ".png") need("visitors/" .. v.id .. "_2.png") end
-- 旧四季 + 夜仍保留；新矩阵至少要有四季 day_clear（生成中可逐步补齐）
for _, v in ipairs({ "spring", "summer", "autumn", "winter", "night" }) do need("attic/attic_" .. v .. ".png") need("attic/attic_" .. v .. "_empty.png") end
for _, v in ipairs({ "spring", "summer", "autumn", "winter" }) do
    need("attic/attic_" .. v .. "_day_clear.png")
    need("attic/attic_" .. v .. "_day_clear_empty.png")
end
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
assert(dc.total == Game.souvenirTotal() and dc.have == 2 and dc.items[1].icon:match("^souvenirs/"), "cabinet n/total")
assert(WD.sig(raw) == before, "widget data must not touch the save")
assert(WD.sig({ a = 1, b = { 2 } }) == WD.sig({ b = { 2 }, a = 1 }))
local empty = WD.view(nil, 0, false)
assert(#WD.postcards(empty, 5).cards == 0 and WD.cabinet(empty).have == 0 and WD.attic(empty, 0, false).scene)

-- 12. 明信片墙：一页一张，新的在前
local sw = State.fresh(0)
for k = 1, 30 do sw.postcards[k] = { place = "ink_lake", pose = "sit", prop = "none", weather = "clear", line = "l" .. k, at = k } end
local i, pg, pgs = Game.cardIndex(sw, 1)
assert(i == 30 and pg == 1 and pgs == 30)
i, pg, pgs = Game.cardIndex(sw, 99)
assert(pg == 30 and i == 1, "clamped last page")
assert(select(3, Game.cardIndex(State.fresh(0), 1)) == 1)
H.saved = sw
local g5 = Game.new(H.host):show()
attic_ops(); click("明信片墙")
-- 进墙前 wall_seen 是 0：这一趟 30 张都是新的，翻到最旧那张角标还在
assert(H.view.postcard and H.view.postcard.new and H.view.postcard.index == 30 and H.view.pager.pages == 30 and H.view.pager.page == 1)
H.view.pager.next(); assert(H.view.pager.page == 2 and H.view.postcard.side == nil and H.view.postcard.new, "new badge survives")
H.view.pager.go(30); assert(H.view.pager.page == 30 and H.view.postcard.index == 1 and H.view.postcard.new, "unseen wall: oldest is new too")
back(); click("明信片墙")
assert(H.view.postcard.index == 30 and not H.view.postcard.new, "re-enter clears the badge")
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
attic_ops(); click("小铺")
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
for _, pg in ipairs({ "basket", "shop", "wall", "cabinet", "scrapbook", "guestbook" }) do
    g7:go(pg)
    for _, b in ipairs(btns()) do assert(not (b.text:find("^回阁楼") or b.text:find("^回小铺") or b.text:find("^回明信片")), pg .. " still has " .. b.text) end
    back(); assert(g7.page == "attic")
end
g7:close()

-- 15. 阁楼主页分页：第 1 页通栏画面 + 状态；第 2 页入口；第 3 页来客 + 最近；日志多时更多页
local sa = State.fresh(0)
for k = 1, 15 do sa.log[k] = "事" .. k end
sa.visitor = { id = "inkbug", pose = "", until_at = 1e12 }
H.saved = sa
local g8 = Game.new(H.host):show()
assert(H.view.scene and H.view.scene_wide and #H.view.shelf.cells == 3 and not H.view.notes and not H.view.pager and #H.view.tabbar.tabs == 3)
assert(H.view.status.title:find("墨点虫") and H.view.buttons[1].text == "招待客人")
H.view.tabbar.on_tab(2); assert(H.view.status.title:find("收藏") and #H.view.shelf.cells == 6)
H.view.tabbar.on_tab(1); assert(H.view.status.title:find("墨点虫") and H.view.buttons[1].text == "招待客人") -- 来客在首页替换阿页的状态卡
H.view.tabbar.on_tab(3); assert(not H.view.status and H.view.notes.rows[1].text == "事15")
H.view.notes.fit(5); assert(H.view.pager.pages == 3 and #H.view.notes.rows == 5 and H.view.tabbar.active == 3)
H.view.pager.go(3); assert(H.view.notes.rows[1].text == "事5" and #H.view.notes.rows == 5)
H.view.notes.fit(6); assert(H.view.pager.pages == 3 and #H.view.notes.rows == 5, "feed per only shrinks, no 4/5 flapping")
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
    local g9 = Game.new(H.host):show(); H.view.tabbar.on_tab(3)
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
    for _, pg in ipairs({ "basket", "shop", "wall", "cabinet", "quests", "achievements", "bookwall" }) do ge:go(pg) clean(pg) back() end
    ge.attic_page = 2 ge:render() clean("attic keeps")
    ge.attic_page = 3 ge:render() clean("attic feed")
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

-- 剪贴簿 / 来客簿 / 惦记直达
do
    local Album = require("papersprite.core.album")
    local st = State.fresh(0)
    st.place_trips = { ink_lake = 2 }
    st.souvenirs = { lake_pebble = 1, ink_shell = 1, quill_reed = 1 }
    st.postcards = { { place = "ink_lake", at = 1 }, { place = "ink_lake", at = 2 } }
    st.seen_visitors = { inkbug = 10 }
    local row = Album.place(st, Travel.place("ink_lake"))
    assert(row.done and row.have == 3 and row.cards == 2, "place page complete")
    local _, done, total = Album.places(st)
    assert(done == 1 and total == #require("papersprite.data.places"))
    local guests, have, gtotal = Album.visitors(st)
    assert(have == 1 and gtotal == #require("papersprite.data.visitors") and guests[1].visitor.id == "inkbug")
    -- 惦记：下一趟直达（只推进到出门，别把整趟走完）
    H.saved = State.fresh(0)
    H.saved.inspiration = 20
    H.saved.wish_place = "fold_peak"
    H.queue = {}
    local gw = Game.new(H.host):show()
    attic_ops(); click("收拾行囊"); click("燕麦饼干"); click("铅笔头"); click("火柴盒地图册")
    local dep = H.saved.sprite.depart_at
    advance(dep - H.clock + 1)
    assert(H.saved.sprite.status == "away" and H.saved.sprite.place == "fold_peak" and H.saved.wish_place == nil, "wish directs trip")
    gw:close()
end

print("headless ok: postcards=" .. #st.postcards .. " places=" .. np .. " combos=" .. nc)

do -- 访客：不出门也会来；节日更勤；出门时不来
    local Travel = require("papersprite.core.travel")
    local State = require("papersprite.core.state")
    local function visits()
        local n = 0
        for i = 1, 200 do
            local s = State.fresh(1)
            s.seed = i * 7919
            s.visit_check = 1
            s.seen_visitors = {}
            Travel.settle(s, 1 + 3600 * 72)
            if next(s.seen_visitors) then n = n + 1 end
        end
        return n
    end
    assert(visits() > 100, "home sprite gets visitors without trips")
end

do -- 玩法扩展：委托 / 招待 / 成就 / 读书
    local State = require("papersprite.core.state")
    local Quest = require("papersprite.core.quest")
    local stub = package.loaded["papersprite.core.reading"]
    package.loaded["papersprite.core.reading"] = nil
    local Reading = require("papersprite.core.reading")
    package.loaded["papersprite.core.reading"] = stub
    local Travel = require("papersprite.core.travel")
    local Errand = require("papersprite.core.errand")
    local Disturb = require("papersprite.core.disturb")
    local s = State.fresh(1)
    s.sprite.status = "home"
    s.visitor = { id = "inkbug", until_at = 1e9 }
    Errand.leave(s, "inkbug", 1000)
    assert(#s.errands == 1 and not Errand.done(s, s.errands[1]) and not Errand.claim(s, 1, 1000))
    Errand.leave(s, "inkbug", 1001)
    assert(#s.errands == 1, "one open errand per visitor")
    local function bump(st, err)
        if err.kind == "place" then st.place_trips[err.key] = (err.base or 0) + 1
        elseif err.kind == "tag" then st.stats.tag = st.stats.tag or {} st.stats.tag[err.key] = (err.base or 0) + 1
        elseif err.kind == "weather" then st.stats.weather = st.stats.weather or {} st.stats.weather[err.key] = (err.base or 0) + 1
        elseif err.kind == "book" then st.stats.books = (err.base or 0) + 1
        elseif err.kind == "host" then st.bonds[err.visitor] = (err.base or 0) + 1
        else error("unknown errand kind " .. tostring(err.kind)) end
    end
    bump(s, s.errands[1])
    local before = s.inspiration
    assert(Errand.done(s, s.errands[1]) and Errand.claim(s, 1, 2000))
    -- 领取会顺手判定成就（第一张纸条 +6），灵感增量不只有委托本身
    assert(s.inspiration >= before + Errand.REWARD and s.achieved.errand1 and (s.bonds.inkbug or 0) >= 1
        and not Errand.claim(s, 1, 2000), "claim once")
    s.sprite.status = "away"
    Errand.leave(s, "inkbug", 3000)
    bump(s, s.errands[#s.errands])
    assert(Errand.done(s, s.errands[#s.errands]) and not Errand.claim(s, #s.errands, 4000), "away cannot claim")
    local d = State.fresh(1)
    d.postcards[1] = { place = "ink_lake", at = 1 }
    assert(not Disturb.next(d), "unarmed")
    Disturb.arm(d)
    d.postcards[2] = { place = "ink_lake", at = 2 }
    local note = Disturb.next(d)
    assert(note and note.kind == "card" and note.index == 2)
    Disturb.ack(d, note)
    assert(not Disturb.next(d))
    d.sprite = { status = "away", left_at = 5 }
    note = Disturb.next(d)
    assert(note and note.kind == "away" and note.at == 5, "departure gets an illustrated notice")
    Disturb.ack(d, note)
    assert(not Disturb.next(d), "acknowledged departure is not repeated")
    Disturb.arm(d)
    assert(not Disturb.next(d), "enabling disturbances does not replay an old departure")
    d.sprite = { status = "home" }
    d.sprite.back_at = 9
    note = Disturb.next(d)
    assert(note and note.kind == "home")
    Disturb.ack(d, note)
    d.visitor = { id = "inkbug", until_at = 50 }
    note = Disturb.next(d)
    assert(note and note.kind == "visitor")
    Disturb.ack(d, note)
    d.achieved = { errand1 = 3 }
    note = Disturb.next(d)
    assert(note and note.kind == "ach" and note.id == "errand1")
    local returned = State.fresh(1)
    Disturb.arm(returned)
    returned.sprite = { status = "home", left_at = 5, back_at = 9 }
    assert(Disturb.next(returned).kind == "home", "a completed trip does not replay departure")

    local g = State.fresh(1)
    g.sprite.status = "home"
    g.visitor = { id = "inkbug", pose = "", until_at = 1e9 }
    g.souvenirs.ad_slip = 2
    local ok = Quest.give(g, "ad_slip", 2000)
    assert(ok and g.souvenirs.ad_slip == 1 and Quest.bond(g, "inkbug") >= 1 and g.visitor.fed)
    assert(not Quest.give(g, "ad_slip", 2000), "one gift per visit")

    assert(Reading.tagOf("a detective story") == "night" and Reading.tagOf("plain") == nil)
    assert(not Reading.qualify(1, 9) and Reading.qualify(1, 10) and not Reading.qualify(4, 30) and not Reading.qualify(0, 30))
    local data = {}
    local reading_store = {
        readSetting = function(_, k) return data[k] end,
        saveSetting = function(_, k, v) data[k] = v end,
        flush = function() end,
    }
    Reading._inject(reading_store)
    Reading.record(1000, { title = "雾", keywords = "推理", finished = true, quote = "  灯还亮着  " }, 1, 9)
    assert(data.pages == nil, "short dwell does not count")
    local long = string.rep("字", 50)
    Reading.record(1000, { title = "雾", keywords = "推理", finished = true, quote = long }, 1, 10)
    assert(data.pages == 1 and data.finished[1].quote == Reading.clip(long) and data.finished[1].tag == "night")
    local editions = {}
    Reading._inject({
        readSetting = function(_, k) return editions[k] end,
        saveSetting = function(_, k, v) editions[k] = v end,
        flush = function() end,
    })
    Reading.record(1001, { title = "同名书", finished = true, id = "edition-a", cover = "/covers/a.png" }, 1, 10)
    Reading.record(1002, { title = "同名书", finished = true, id = "edition-a" }, 1, 10)
    Reading.record(1003, { title = "同名书", finished = true, id = "edition-b" }, 1, 10)
    assert(#editions.finished == 2 and editions.finished[1].cover == "/covers/a.png",
        "same-title editions are distinct and duplicate reads retain their cover")
    local edition_wall = State.fresh(1000)
    assert(Reading.collect(edition_wall) == 10 and #edition_wall.bookmarks == 2
        and edition_wall.bookmarks[1].cover == "/covers/a.png", "bookmarks retain cover paths and same-title editions")
    Reading._inject(reading_store)
    local shelf = State.fresh(1000)
    assert(Reading.collect(shelf) == 5)
    assert(shelf.bookmarks[1].line:find("雾", 1, true) and shelf.log[#shelf.log]:find("灯"))
    assert(Reading.collect(shelf) == 0 and #shelf.bookmarks == 1)
    Reading._inject({ readSetting = function() error("reading store unavailable") end })
    local collected = pcall(Reading.collect, State.fresh(1000))
    assert(not collected, "reading storage failures must reach the caller")
    Reading._inject(reading_store)
    local names = {
        "main", "logger", "ui/widget/container/widgetcontainer",
        "papersprite.ui.reader_overlay", "papersprite.core.reading",
    }
    local saved = {}
    for _, name in ipairs(names) do saved[name] = package.loaded[name] end
    local errors, attempts = {}, 0
    package.loaded["logger"] = { err = function(...) errors[#errors + 1] = table.concat({...}, " ") end }
    package.loaded["ui/widget/container/widgetcontainer"] = {
        extend = function(_, class) return class end,
    }
    package.loaded["papersprite.ui.reader_overlay"] = { onPage = function() end }
    package.loaded["papersprite.core.reading"] = {
        record = function(_, _book, step)
            attempts = attempts + 1
            if attempts == 1 then error("reading disk unavailable") end
            assert(step == 2, "failed page transition remains the recording baseline")
        end,
    }
    package.loaded["main"] = nil
    local Plugin = require("main")
    local plugin = { ui = { document = {} }, _last_page = 10, _last_at = os.time() - 20,
        _bookInfo = function() return {} end }
    Plugin.onPageUpdate(plugin, 11)
    assert(plugin._last_page == 10 and #errors == 1, "failed record is logged and page baseline is retained")
    Plugin.onPageUpdate(plugin, 12)
    assert(plugin._last_page == 12 and attempts == 2, "page recording resumes after storage recovers")
    local old_sha2, old_storage, old_open = package.loaded["ffi/sha2"],
        package.loaded["papersprite.core.storage"], io.open
    package.loaded["ffi/sha2"] = { md5 = function(path) return path == "/book.epub" and "book-id" or "other-id" end }
    package.loaded["papersprite.core.storage"] = {
        dir = function() return "/fake/paper-sprite" end,
        deps = { mkdirp = function(path) assert(path == "/fake/paper-sprite/covers") end },
    }
    local Main = Plugin
    local cover_calls, written, freed = 0, nil, 0
    io.open = function(path)
        if path:find("/fake/paper-sprite/covers/", 1, true) then return nil end
        return old_open(path)
    end
    local book = setmetatable({
        ui = {
            document = { file = "/book.epub", getPageCount = function() return 20 end },
            doc_props = { title = "封面书" },
            bookinfo = { getCoverImage = function()
                cover_calls = cover_calls + 1
                return {
                    writeToFile = function(_, path, format)
                        written = path .. ":" .. format
                        return true
                    end,
                    free = function() freed = freed + 1 end,
                }
            end },
        },
    }, { __index = Main })
    local info = Main._bookInfo(book, 19)
    assert(info.id == "book-id" and info.cover == "/fake/paper-sprite/covers/book-id.png"
        and written == info.cover .. ":png" and cover_calls == 1 and freed == 1)
    Main._bookInfo(book, 20)
    assert(cover_calls == 1, "cover is captured once per book")
    io.open = old_open
    package.loaded["ffi/sha2"], package.loaded["papersprite.core.storage"] = old_sha2, old_storage
    for _, name in ipairs(names) do package.loaded[name] = saved[name] end
    local Lock = require("papersprite.core.postcard_lock")
    assert(Lock.latest(nil) == nil)
    local card = Lock.latest({ postcards = {
        { place = "ink_lake", weather = "mist", line = "旧的", at = 1 },
        { place = "ink_lake", weather = "clear", line = "湖面很静", at = 50 },
    } })
    assert(card and card.place == "墨水湖" and card.weather == "晴" and card.line == "湖面很静")
    local function units(sample)
        local n, i = 0, 1
        while i <= #sample do
            local b = sample:byte(i)
            local len = 1
            if b >= 240 then len = 4 elseif b >= 224 then len = 3 elseif b >= 192 then len = 2 end
            i, n = i + len, n + 1
        end
        return n
    end
    assert(Lock.clampLines("一二三", units, 3) == "一二三")
    assert(Lock.clampLines("一二三四", units, 3) == "一二…")
    H.saved = State.fresh(0)
    H.saved.souvenirs.ad_slip = 1
    H.saved.visitor = { id = "inkbug", pose = "", until_at = 1e12 }
    H.saved.bookmarks = { { title = "封面书", at = 1, cover = "/covers/book-id.png" } }
    local gu = Game.new(H.host):show()
    gu:go("achievements")
    local first_achievement = H.view.shelf.cells[1]
    assert(first_achievement.icon == "achievements/trips1.png"
        and first_achievement.meta:find("0 / 1", 1, true)
        and first_achievement.meta:find("灵感 +3", 1, true), "locked achievements show their own art, progress, and reward")
    gu:go("bookwall")
    assert(H.view.shelf.cells[1].file == "/covers/book-id.png", "book wall forwards saved cover paths")
    for _, pg in ipairs({ "quests", "achievements", "bookwall", "guest_here" }) do gu:go(pg) assert(H.view.title, pg) end
    gu:close()
end

do -- 锁屏复用新版明信片，两面完整落在屏内，不写存档。
    local names = { "papersprite.host.moon", "papersprite.ui.postcard", "papersprite.ui.lock_card" }
    local saved = {}
    for _, name in ipairs(names) do saved[name] = package.loaded[name] end
    local data = require("papersprite.core.state").fresh(1)
    package.loaded["papersprite.host.moon"] = { new = function() return {
        loadState = function() return data end, now = function() return 10 end,
        saveState = function() error("lockscreen must not write state") end,
    } end }
    package.loaded["papersprite.ui.postcard"] = { widget = function(pc) return pc end }
    package.loaded["papersprite.ui.lock_card"] = nil
    local backgrounds = require("papersprite.ui.lock_card").backgrounds()
    assert(#backgrounds == 2 and backgrounds[1].id == "postcard", "original lockscreen style remains available")
    local background = backgrounds[2]
    assert(background.id == "postcard_pair", "new style is independently selectable")
    local empty_key = background.cache_key()
    assert(background.blocks({ w = 1080, h = 1440 })[1].text == "等阿页寄第一张回来。")
    data.postcards[1] = { place = "ink_lake", pose = "sit", prop = "none", weather = "clear",
        variant = "a", line = "湖面很静", at = 5 }
    assert(background.cache_key() ~= empty_key)
    for _, rect in ipairs({ { w = 1080, h = 1440 }, { w = 1440, h = 1080 }, { w = 600, h = 800 } }) do
        local blocks = background.blocks(rect)
        assert(#blocks == 2 and blocks[1].widget.side == "front" and blocks[2].widget.side == "back")
        assert(blocks[2].widget.line == "湖面很静" and blocks[2].widget.zip ~= "")
        for _, b in ipairs(blocks) do
            assert(b.x >= 0 and b.y >= 0 and b.x + b.width <= rect.w and b.y + b.height <= rect.h)
        end
        if rect.w > rect.h then
            assert(blocks[2].x >= blocks[1].x + blocks[1].width and blocks[1].y == blocks[2].y)
        else
            assert(blocks[2].y >= blocks[1].y + blocks[1].height and blocks[1].x == blocks[2].x)
        end
    end
    for _, name in ipairs(names) do package.loaded[name] = saved[name] end
end

do -- 提醒使用月读弹窗：插画、翻面、关闭确认都走同一套窗口生命周期。
    local names = {
        "papersprite.ui.reader_overlay", "papersprite.ui.read_prefs", "ui/uimanager",
        "apps/reader/readerui", "ui.themes.widgets.modal", "ui.themes", "ui.themes.widgets.text",
        "ui/widget/verticalgroup", "ui/widget/verticalspan", "ui/widget/container/centercontainer",
        "ui/geometry", "ui/widget/imagewidget", "papersprite.ui.postcard", "papersprite.ui.moon_widgets",
    }
    local saved = {}
    for _, name in ipairs(names) do saved[name] = package.loaded[name] end
    local state = require("papersprite.core.state").fresh(1)
    state.postcards = { { place = "ink_lake", at = 1 } }
    local writes, shown, image, opened = 0
    package.loaded["papersprite.ui.read_prefs"] = {
        disturb = function() return true end,
        host = function() return {
            loadState = function() return state end, now = function() return 10 end,
            saveState = function() writes = writes + 1 end,
        } end,
    }
    package.loaded["ui/uimanager"] = { setDirty = function() end, scheduleIn = function() end }
    package.loaded["apps/reader/readerui"] = { instance = { document = {} } }
    local Modal = {}
    function Modal:new(args)
        args.theme = { space = { md = 8 }, dialog = { bg = "white" } }
        return setmetatable(args, { __index = self })
    end
    function Modal:innerWidth() return 400 end
    function Modal:setDialog(dialog) self.dialog = dialog end
    function Modal:show() shown = self end
    function Modal:dismiss() self.close_callback() end
    package.loaded["ui.themes.widgets.modal"] = Modal
    package.loaded["ui.themes"] = { px = function(n) return n end }
    package.loaded["ui.themes.widgets.text"] = { box = function(_role, text) return { text = text } end }
    local widget = { new = function(_self, args) return args end }
    for _, name in ipairs({ "ui/widget/verticalgroup", "ui/widget/verticalspan",
        "ui/widget/container/centercontainer", "ui/geometry" }) do package.loaded[name] = widget end
    package.loaded["ui/widget/imagewidget"] = { new = function(_self, args) image = args.file return args end }
    package.loaded["papersprite.ui.postcard"] = { widget = function(body) return { side = body.side } end }
    package.loaded["papersprite.ui.moon_widgets"] = { open = function(page)
        assert(writes == 3, "visitor notice is closed before opening the hosting page")
        opened = page
    end }
    package.loaded["papersprite.ui.reader_overlay"] = nil
    local M = require("papersprite.ui.reader_overlay")
    M.syncFlags = function() return state end
    local Disturb = require("papersprite.core.disturb")
    Disturb.arm(state)
    state.sprite = { status = "away", left_at = 2 }
    M.poke()
    assert(shown.modal and shown.dialog.title == "阿页出门了" and image:find("sprite/walk.png", 1, true))
    shown:dismiss()
    assert(writes == 1 and not Disturb.next(state), "modal dismissal acknowledges departure")
    state.sprite = { status = "home", back_at = 3 }
    M.poke()
    assert(image:find("sprite/wave.png", 1, true))
    shown:dismiss()
    state.visitor = { id = "clip_snail", pose = "_2", until_at = 100 }
    M.poke()
    assert(image:find("visitors/clip_snail_2.png", 1, true), "visitor uses its own illustration")
    assert(#shown.dialog.buttons == 2 and shown.dialog.buttons[2].text == "招待客人")
    shown.dialog.buttons[2].callback()
    assert(opened == "guest_here", "hosting reuses the existing souvenir selection page")
    state.postcards[2] = { place = "ink_lake", pose = "sit", prop = "none", weather = "clear", variant = "a", at = 4 }
    M.poke()
    assert(shown.dialog.body.side == "back" and #shown.dialog.buttons == 2)
    shown.dialog.buttons[1].callback()
    assert(shown.dialog.body.side == "front" and writes == 3, "turning a postcard does not close or acknowledge it")
    shown.dialog.buttons[2].callback()
    assert(writes == 4 and not Disturb.next(state), "close button acknowledges postcard once")
    state.visitor = { id = "clip_snail", pose = "", until_at = 200, fed = true }
    M.poke()
    assert(#shown.dialog.buttons == 1, "an already hosted visitor only offers dismissal")
    shown:dismiss()
    state.achieved.trips1 = 20
    M.poke()
    assert(image:find("achievements/trips1.png", 1, true), "achievement notice uses its matching artwork")
    shown:dismiss()
    for _, name in ipairs(names) do package.loaded[name] = saved[name] end
end

do -- 伴读：设置立即重绘，翻页按真实经过时间结束，并重画原来的看书姿势。
    local names = {
        "papersprite.ui.read_prefs", "papersprite.ui.reader_overlay", "ui/uimanager",
        "ui/time", "ui/geometry", "ui/widget/imagewidget", "ffi/blitbuffer", "ffi",
    }
    local saved = {}
    for _, name in ipairs(names) do saved[name] = package.loaded[name] end
    package.loaded["papersprite.ui.read_prefs"] = nil
    package.loaded["papersprite.ui.reader_overlay"] = nil
    local P = require("papersprite.ui.read_prefs")
    local settings = { companion = true }
    P.host = function() return H.host end
    P.get = function(key, default)
        if settings[key] == nil then return default end
        return settings[key]
    end
    P.set = function(key, value) settings[key] = value end
    local clock, pending, dirty = 100, {}, {}
    package.loaded["ui/time"] = { now = function() return clock end, to_s = function(t) return t end }
    package.loaded["ui/geometry"] = { new = function(_self, rect) return rect end }
    package.loaded["ui/uimanager"] = {
        setDirty = function(_self, widget, mode, region)
            dirty[#dirty + 1] = { widget = widget, mode = mode, region = region }
        end,
        scheduleIn = function(_self, _delay, fn) pending[#pending + 1] = fn end,
    }
    local loaded, painted = {}, {}
    local pixel = { a = 0, getAlpha = function() return 255 end }
    pixel.getColor8A = function() return pixel end
    package.loaded["ui/widget/imagewidget"] = { new = function(_self, args)
        loaded[#loaded + 1] = args.file
        return { _bb = { getPixel = function() return pixel end },
            getSize = function() return { w = 1, h = 1 } end }
    end }
    package.loaded["ffi"] = { fill = function() end }
    package.loaded["ffi/blitbuffer"] = {
        TYPE_BB8A = 2,
        Color8A = function(gray, alpha) return { a = gray, alpha = alpha } end,
        new = function()
            return { data = {}, stride = 2, h = 1,
                getWidth = function() return 1 end, getHeight = function() return 1 end,
                setPixel = function(self, _x, _y, c) self.pixel = c end }
        end,
    }
    local M = require("papersprite.ui.reader_overlay")
    M.poke = function() end
    local ui = { document = {}, view = { dimen = { x = 10, y = 20, w = 540, h = 720 } } }
    ui.view.registerViewModule = function(self, name, widget) self[name] = widget widget.view = self end
    M.attach(ui)
    local bb = { pmulalphablitFrom = function(_self, src) painted[#painted + 1] = src.pixel end }
    assert(P.fade() == 20, "default transparency is 20%")
    ui.view.papersprite_companion:paintTo(bb, 0, 0)
    assert(painted[#painted].alpha == 204, "20% transparency leaves 80% opacity")
    P.setFade(0)
    assert(P.fade() == 0 and dirty[#dirty].widget == ui and dirty[#dirty].mode == "ui",
        "setting changes refresh only the companion region")
    assert(dirty[#dirty].region.x == 28 and dirty[#dirty].region.y == 571
        and dirty[#dirty].region.w == 151 and dirty[#dirty].region.h == 151,
        "refresh region matches the companion bounds")
    ui.view.papersprite_companion:paintTo(bb, 0, 0)
    assert(painted[#painted].alpha == 255, "new transparency applies without settling game state")
    M.onPage({ ui = ui })
    assert(dirty[#dirty].widget == ui and dirty[#dirty].mode == "ui",
        "animation redraws only the companion area without partial-refresh promotion")
    assert(#pending == 1, "animation schedules only the next visual state")
    clock = 100.13
    table.remove(pending, 1)()
    ui.view.papersprite_companion:paintTo(bb, 0, 0)
    assert(loaded[#loaded]:find("chair_turn.png", 1, true), "middle frame uses the AI page-turn image")
    clock = 100.5
    table.remove(pending, 1)()
    ui.view.papersprite_companion:paintTo(bb, 0, 0)
    assert(loaded[#loaded]:find("chair_turn_left.png", 1, true), "page crosses the spine and lands on the left")
    clock = 101
    table.remove(pending, 1)()
    assert(M.flags.turn_from == nil and not M.flags.turn_ticking and #pending == 0,
        "animation ends even when CPU time does not advance")
    assert(dirty[#dirty].widget == ui and dirty[#dirty].mode == "ui",
        "ending animation redraws only the companion area")
    ui.view.papersprite_companion:paintTo(bb, 0, 0)
    assert(painted[#painted].alpha == 255)
    P.setCorner("se")
    assert(dirty[#dirty - 1].region.x == 28 and dirty[#dirty - 1].region.y == 571
        and dirty[#dirty].region.x == 381,
        "moving the companion clears its old corner and draws the new one")
    settings.companion_fade = 100
    local count = #painted
    ui.view.papersprite_companion:paintTo(bb, 0, 0)
    assert(#painted == count, "fully transparent companion draws nothing")
    for _, name in ipairs(names) do package.loaded[name] = saved[name] end
end
