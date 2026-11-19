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
    if H.view.extra then out[#out + 1] = { text = "extra:" .. (H.view.extra.text or ""), callback = H.view.extra.callback } end
    for _, r in ipairs((H.view.notes and H.view.notes.rows) or {}) do
        if r.callback then out[#out + 1] = { text = r.text, callback = r.callback } end
    end
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

-- 书架表的内存替身（真实实现走月读 SQLite，spec 不碰）
local function fakeShelf()
    local rows = {}
    local impl = {}
    function impl.count() return #rows end
    function impl.page(offset, limit)
        local out = {}
        for i = #rows - offset, math.max(1, #rows - offset - limit + 1), -1 do out[#out + 1] = rows[i] end
        return out
    end
    function impl.pending(limit, skip)
        local out = {}
        for _, r in ipairs(rows) do if not r.thought and not skip[r.key] and #out < limit then out[#out + 1] = r end end
        return out
    end
    function impl.add(b)
        local ids = require("papersprite.core.shelf").idsOf(b)
        for _, r in ipairs(rows) do
            if r.key == b.key or (r.title == b.title and (not r.id or not b.id)) then return false end
            for _, ident in ipairs(ids) do
                if r.key == ident or r.id == ident then return false end
            end
        end
        local r = {}
        for k, v in pairs(b) do r[k] = v end
        rows[#rows + 1] = r
        return true
    end
    function impl.setThought(key, text) for _, r in ipairs(rows) do if r.key == key then r.thought = text end end end
    function impl.batch(fn) fn() return true end
    require("papersprite.core.shelf").use(impl)
    return rows
end

-- 明细表的内存替身（真实实现走 sqlite，spec 不碰）。返回重置函数
local Vault = require("papersprite.core.vault")
local function fakeVault()
    local data = {}
    local be = {}
    local function sorted(t)
        local out = {}
        for _, r in pairs(data[t] or {}) do out[#out + 1] = r end
        local pk = (t == "paper_postcards" or t == "paper_log") and "seq" or "k"
        table.sort(out, function(x, y) return x[pk] < y[pk] end)
        return out
    end
    local function pkOf(t, row) return (t == "paper_postcards" or t == "paper_log") and row.seq or row.k end
    function be.count(t) local n = 0 for _ in pairs(data[t] or {}) do n = n + 1 end return n end
    function be.get(t, pk) return (data[t] or {})[pk] end
    function be.put(t, row)
        data[t] = data[t] or {}
        local r = {} for k, v in pairs(row) do r[k] = v end
        data[t][pkOf(t, row)] = r
    end
    function be.del(t, pk) if data[t] then data[t][pk] = nil end end
    function be.page(t, offset, limit, desc)
        local all, out = sorted(t), {}
        if desc then for i = 1, math.floor(#all / 2) do all[i], all[#all - i + 1] = all[#all - i + 1], all[i] end end
        for i = offset + 1, math.min(#all, offset + limit) do out[#out + 1] = all[i] end
        return out
    end
    function be.scan(t, fn) for _, r in ipairs(sorted(t)) do if fn(r) == false then break end end end
    -- sqlite 不支持嵌套 BEGIN，替身也不许嵌套
    local in_tx = false
    function be.tx(fn)
        assert(not in_tx, "nested transaction")
        in_tx = true
        local ok, err = pcall(fn)
        in_tx = false
        if not ok then error(err, 0) end
    end
    Vault.use(be)
    return function() data = {} end, be
end
local resetVault, vaultBackend = fakeVault()
local function cards()
    local out = {}
    Vault.eachCard(function(c) out[#out + 1] = c end)
    return out
end
local function addCards(list) for _, c in ipairs(list) do Vault.cardAdd(c) end end
local function logs() local t = Vault.logList() return t end

fakeShelf()
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
assert(Vault.cardCount() >= 1, "no postcard")
local sv = 0 for _, c in pairs(Vault.all("souvenirs")) do sv = sv + c end
assert(sv == 1, "souvenir")
local place_id = Vault.card(1).place
assert(Vault.get("place_trips", place_id) == 1, "place_trips on return")
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
resetVault()
local mig = State.load({ version = 1, postcards = { { id = "ink_lake_01", at = 5 }, { id = "gone", at = 6 }, { id = "ink_lake_01", at = 7 } },
    wall_seen = 2, visitor = { until_at = 9 }, sprite = { status = "home" } }, 10)
assert(Vault.cardCount() == 1 and Vault.card(1).place == "ink_lake" and Vault.card(1).line and mig.postcards == nil, "migrate cards")
assert(mig.wall_seen == 1 and mig.visitor.id == "inkbug", "migrate misc")

-- 6. 首页卡片摘要（纯函数）
package.path = package.path -- moon_card 只在 build 时 require KOReader 控件
local Card = require("papersprite.ui.moon_card")
local s = Card.summary(H.saved, H.clock, true); assert(s.line1 and s.line2)

-- 7. 确定性：同存档同时刻结果一致；长期跑 50 趟不出错
local Travel = require("papersprite.core.travel")
resetVault()
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
for _, c in ipairs(cards()) do seenPlace[c.place] = true seenCombo[c.place .. c.pose .. c.prop .. c.weather] = true end
local np, nc = 0, 0 for _ in pairs(seenPlace) do np = np + 1 end for _ in pairs(seenCombo) do nc = nc + 1 end
assert(np >= 8, "place variety " .. np)

-- 8. AI 文案层（桩）：成功 / 不合规 / 报错 / 不回调（超时）都不影响旅行
local Story = require("papersprite.core.story")
local function trip(ai_impl)
    H.saved, H.queue = nil, {}
    resetVault()
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
local ai_cards = 0 for _, c in ipairs(cards()) do if c.ai then ai_cards = ai_cards + 1 assert(c.line:find("AI")) end end
assert(ai_cards >= 1, "ai lines cached into save")
assert(table.concat(logs(), "|"):find("把风叠好"), "narration")
-- 不合规：句子太长 → 整体放弃，用本地句
local bad = { json = function(_, cb) cb({ lines = { string.rep("长", 80) } }) end }
sv = trip(bad); for _, c in ipairs(cards()) do assert(not c.ai, "invalid ai rejected") end
-- 报错
sv = trip({ json = function() error("boom") end }); assert(Vault.cardCount() >= 1)
-- 永不回调（超时）
sv = trip({ json = function() return { cancel = function() end } end }); assert(Vault.cardCount() >= 1)
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
    resetVault()
    H.host.ai = nil
    local g3 = Game.new(H.host):show()
    attic_ops(); click("收拾行囊"); click("燕麦饼干"); click("铅笔头"); click("火柴盒地图册")
    advance(100); advance(400)
    assert(H.saved.sprite.status == "home" and H.saved.recap, "recap kept")
    H.host.ai = function() return only_other end
    g3:tick()
    local cur = H.saved
    assert(not cur.recap, "recap consumed")
    local late = 0 for _, c in ipairs(cards()) do if c.line:find("迟到") then late = late + 1 end end
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
    Vault.set("souvenirs", "shelf_plank", 1)
    local ok, msg = require("papersprite.core.quest").give(cur, "shelf_plank", H.clock)
    assert(ok and msg:find("它眼睛一亮。", 1, true), "reaction shown when hosting: " .. tostring(msg))
    g3:close()
end

-- 9. 明信片去重：200 趟不重复；同一趟不重复；全部收集后退回最久没见过的
local P = require("papersprite.data.postcards")
resetVault()
local st2 = State.fresh(0); st2.inventory = {}
local tt, keys = 0, {}
for i = 1, 200 do
    for _, id in ipairs({ "oat_biscuit", "pencil_stub", "tiny_atlas" }) do assert(Travel.put(st2, id, tt, false)) end
    tt = tt + 40 * 3600; Travel.settle(st2, tt, false)
end
for _, c in ipairs(cards()) do
    assert(c.key, "card has key")
    assert(not keys[c.key], "duplicate postcard " .. c.key)
    keys[c.key] = true
end
print("  200 trips, " .. Vault.cardCount() .. " postcards, all unique")
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
resetVault()
local same = { json = function(msgs, cb)
    local n = select(2, msgs[2].content:gsub("%d%. 天气", ""))
    local lines = {} for i = 1, n do lines[i] = "同一句话，第" .. i .. "张。" end
    cb({ lines = lines })
end }
sv = trip(same)
local first_ai = 0 for _, c in ipairs(cards()) do if c.ai then first_ai = first_ai + 1 end end
local function again()
    H.host.ai = function() return same end
    local g3 = Game.new(H.host):show()
    attic_ops(); click("收拾行囊"); click("燕麦饼干"); click("铅笔头"); click("火柴盒地图册")
    advance(100); advance(400); g3:close()
    return H.saved
end
sv = again()
local ai2 = 0 for _, c in ipairs(cards()) do if c.ai then ai2 = ai2 + 1 end end
local dup1 = 0 for _, c in ipairs(cards()) do if c.line == "同一句话，第1张。" then dup1 = dup1 + 1 end end
assert(first_ai >= 1 and dup1 == 1 and ai2 >= first_ai, "repeated AI lines rejected: " .. dup1)
-- 同一回复里两句相同 → 整体放弃
assert(not Story.validate({ lines = { "一样。", "一样！" } }, 2), "dup within response")
local wk = {} for _, c in ipairs(cards()) do assert(not wk[c.key], "dup in save") wk[c.key] = true end

-- 10. 第 3/4 批：v2 → v4 迁移、背景变体、搭配限制、阁楼季节与装饰、访客姿势、剪贴簿回填
resetVault()
local m3 = State.load({ version = 2, postcards = { { place = "ink_lake", pose = "sit", prop = "none", weather = "clear", text_id = "p:1", key = "ink_lake|sit|none|clear|p:1", trip = 1 } },
    collected = { ["ink_lake|sit|none|clear|p:1"] = 1 }, visitor = { id = "inkbug", until_at = 9 },
    souvenirs = { lake_pebble = 1 } }, 0)
assert(m3.version == State.VERSION and Vault.card(1).variant == "a" and type(m3.decor) == "table" and m3.visitor.pose == "" and type(m3.errands) == "table")
assert(Vault.get("place_trips", "ink_lake") == 1 and Vault.get("seen_visitors", "inkbug") == 9, "v4 album migrate")
assert(P.key(Vault.card(1)) == "ink_lake|sit|none|clear|p:1", "old key stays valid")
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
Vault.set("souvenirs", "lake_pebble", 1) Vault.set("souvenirs", "fog_jar", 2)
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
assert(dp.total == Vault.cardCount() and #dp.cards == math.min(3, dp.total))
for k = 2, #dp.cards do assert(dp.cards[k - 1].index > dp.cards[k].index, "newest first") end
if dp.cards[1] then assert(dp.cards[1].scene.bg:match("^places/") and dp.cards[1].place ~= "") end
vw.wall_seen = Vault.cardCount() - 1
local dp2 = WD.postcards(vw, 3)
assert(dp2.new == 1 and dp2.cards[1].new and (not dp2.cards[2] or not dp2.cards[2].new), "new mark")
resetVault() Vault.set("souvenirs", "fog_jar", 2) Vault.set("souvenirs", "lake_pebble", 1) Vault.set("souvenirs", "gone_item", 3)
local dc = WD.cabinet(vw)
assert(dc.total == Game.souvenirTotal() and dc.have == 2 and dc.items[1].icon:match("^souvenirs/"), "cabinet n/total")
assert(WD.sig(raw) == before, "widget data must not touch the save")
assert(WD.sig({ a = 1, b = { 2 } }) == WD.sig({ b = { 2 }, a = 1 }))
resetVault()
local empty = WD.view(nil, 0, false)
assert(#WD.postcards(empty, 5).cards == 0 and WD.cabinet(empty).have == 0 and WD.attic(empty, 0, false).scene)

-- 12. 明信片墙：一页一张，新的在前
local sw = State.fresh(0)
resetVault()
for k = 1, 30 do Vault.cardAdd({ place = "ink_lake", pose = "sit", prop = "none", weather = "clear", line = "l" .. k, at = k }) end
local i, pg, pgs = Game.cardIndex(30, 1)
assert(i == 30 and pg == 1 and pgs == 30)
i, pg, pgs = Game.cardIndex(30, 99)
assert(pg == 30 and i == 1, "clamped last page")
assert(select(3, Game.cardIndex(0, 1)) == 1)
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
resetVault()
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
resetVault()
for k = 1, 15 do Vault.logAdd("事" .. k, 1000 + k) end
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

-- 预览结算（首页组件）不得把明细写进库
do
    resetVault()
    local before = Vault.cardCount()
    local inside
    Vault.preview(function()
        Vault.cardAdd({ key = "k1", place = "p", at = 1 })
        Vault.logAdd("预览", 1)
        Vault.incr("souvenirs", "s1")
        inside = Vault.cardCount()
    end)
    assert(inside == before + 1 and Vault.cardCount() == before and Vault.logLast() == nil and Vault.get("souvenirs", "s1") == nil)
end

-- 16. 日志时间：新日志记时间；旧存档无时间不显示；格式
do
    local G = Game
    assert(G.when(1000, 1030) == "刚刚" and G.when(1000, 1000 + 180) == "3 分钟前" and G.when(1000, 1000 + 3 * 3600) == "3 小时前")
    assert(G.when(1000, 1000 + 3 * 86400) == os.date("%m-%d %H:%M", 1000) and G.when(0, 5) == nil and G.when(nil, 5) == nil)
    resetVault()
    local old = State.fresh(0); old.log = { "旧1", "旧2" }; old.log_at = nil
    local ls = State.load(old, 0)
    local _, ats = Vault.logList()
    assert(#ats == 2 and ats[1] == 0)
    State.log(ls, "新", 12345); _, ats = Vault.logList(); assert(ats[3] == 12345)
    for k = 1, 30 do State.log(ls, "x" .. k, k) end
    local texts
    texts, ats = Vault.logList()
    assert(#texts == 20 and #ats == 20 and ats[20] == 30 and Vault.logLast() == "x30")
    H.saved = ls
    local g9 = Game.new(H.host):show(); H.view.tabbar.on_tab(3)
    local r1 = H.view.notes.rows[1]; assert(r1.text == "x30" and r1.meta)
    g9:close()
    for k = 1, 3 do Vault.cardAdd({ key = "k" .. k, line = "l" .. k, at = k, trip = k, ai = false }) end
    local newest = Vault.cardsNewest(0, 2)
    assert(newest[1].index == 3 and newest[2].index == 2 and newest[1].trip == 3 and newest[2].key == "k2")
    local fix = Vault.card(2) fix.line = "改" Vault.cardReplace(2, fix)
    assert(Vault.card(2).line == "改" and Vault.cardCount() == 3 and Vault.card(2).index == nil)
    resetVault()
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
    local moon = { postcards = { {}, {}, {} }, trips = 5 }
    local kv = {}
    local tbl = {}
    local backend = {
        load = function(name) local o = {} for k, v in pairs(kv[name] or {}) do o[k] = v end return o end,
        write = function(name, changes)
            kv[name] = kv[name] or {}
            for k, v in pairs(changes) do kv[name][k] = v or nil end
        end }
    St.deps = { backend = backend, dataDir = function() return "/D" end, settingsDir = function() return "/D/settings" end,
        open = fake, exists = function(p) return files[p] ~= nil end, mkdirp = function(p) made[#made + 1] = p end,
        moonState = function() return moon end }
    St._reset()
    fake("/D/settings/papersprite.lua").saveSetting(nil, "state", { postcards = { {} }, trips = 1 })
    fake("/D/settings/papersprite.lua").saveSetting(nil, "setting_ui_skin", "native")
    fake("/D/settings/papersprite_reading.lua").saveSetting(nil, "pages", 42)
    local sv = St.open("save")
    assert(made[1] == "/D/.moon/game/paper-sprite" and kv.save["state.trips"])
    assert(sv:readSetting("state") == moon and sv:readSetting("setting_ui_skin") == "native" and sv:readSetting("migrated_from"))
    assert(files["/D/settings/papersprite.lua"].data.state.trips == 1)   -- 旧文件原样保留
    assert(St.open("reading"):readSetting("pages") == 42)
    -- 已有新存档：不再迁移
    St._reset(); moon = { postcards = { {}, {}, {}, {}, {}, {} }, trips = 9 }
    assert(St.open("save"):readSetting("state").trips == 5)
    -- 编码：cdata 按数字写、不认识的值丢掉，读回来结构不变
    local has_ffi, ffi = pcall(require, "ffi")
    local back = St.decode(St.encode({ n = has_ffi and ffi.new("int64_t", 7) or 7, s = "a\n\"b", l = { 1, 2, { x = true } }, f = print }))
    assert(back.n == 7 and back.s == "a\n\"b" and back.l[3].x == true and back.f == nil)
    -- state 按字段拆行，只写变了的；测试版的整份 state 行下次 flush 拆开
    do
        St._reset(); kv = { save = { state = St.encode({ a = 1, b = { 2 } }) } }
        local sv2 = St.open("save")
        assert(sv2:readSetting("state").a == 1)
        sv2:saveSetting("state", sv2:readSetting("state")) sv2:flush()
        assert(kv.save.state == nil and kv.save["state.a"] and kv.save["state.b"])
        local before = kv.save["state.b"]
        kv.save["state.b"] = "SENTINEL"
        local st2 = sv2:readSetting("state") st2.a = 5 st2.c = 9
        sv2:saveSetting("state", st2) sv2:flush()
        assert(kv.save["state.b"] == "SENTINEL" and St.decode(kv.save["state.a"]) == 5 and kv.save["state.c"], "only changed fields are written")
        st2.c = nil sv2:saveSetting("state", st2) sv2:flush()
        assert(kv.save["state.c"] == nil)
        St._reset()
        assert(St.open("save"):readSetting("state").a == 5)
        kv.save["state.b"] = before
    end
    -- 旧存档里的明信片 / 近况 / 特产等：State.load 搬进表，存档里不再留；旧的按字段行下次 flush 删掉
    do
        St._reset()
        kv = { save = { ["state.postcards"] = St.encode({ { key = "z", at = 1 } }), ["state.y"] = "2",
            ["state.version"] = "5", ["state.souvenirs"] = St.encode({ petal = 2 }) } }
        resetVault()
        local sv4 = St.open("save")
        local loaded = require("papersprite.core.state").load(sv4:readSetting("state"), 0)
        assert(loaded.postcards == nil and loaded.souvenirs == nil and Vault.card(1).key == "z" and Vault.get("souvenirs", "petal") == 2)
        sv4:saveSetting("state", loaded) sv4:flush()
        assert(kv.save["state.postcards"] == nil and kv.save["state.souvenirs"] == nil and kv.save["state.y"])
        -- 表里已有数据就不再导入第二遍
        require("papersprite.core.state").load({ version = 5, postcards = { { key = "z" }, { key = "w" } } }, 0)
        assert(Vault.cardCount() == 1)
        resetVault()
    end
    -- v5 存档里重复的明信片 / 近况：升到 v8 时去重一次，之后不再跑
    do
        resetVault()
        Vault.cardAdd({ key = "a", place = "p", at = 1, line = "x" })
        Vault.cardAdd({ key = "a", place = "p", at = 1, line = "x" })
        Vault.cardAdd({ key = "b", place = "p", at = 2, line = "y" })
        Vault.logAdd("t", 5) Vault.logAdd("t", 5) Vault.logAdd("t", 6)
        local up = require("papersprite.core.state").load({ version = 5, wall_seen = 3 }, 0)
        assert(up.version == 8 and Vault.cardCount() == 2 and Vault.card(2).key == "b" and #Vault.logList() == 2 and up.wall_seen == 2 and up.dedupe_pending == nil)
        Vault.cardAdd({ key = "b", place = "p", at = 2, line = "y" })
        require("papersprite.core.state").load(up, 0)
        assert(Vault.cardCount() == 3, "v8 state is not deduped again")
        -- 同一趟同一时刻寄出的几张不同的卡：只留最后一张，多余卡点亮的图鉴收回
        resetVault()
        for i = 1, 3 do Vault.cardAdd({ key = "k" .. i, place = "p", at = 9, line = "l" .. i, trip = 4 }) Vault.set("collected", "k" .. i, 9) end
        Vault.cardAdd({ key = "other", place = "p", at = 10, line = "o", trip = 5 })
        require("papersprite.core.state").load({ version = 6 }, 0)
        assert(Vault.cardCount() == 2 and Vault.card(1).key == "k3" and Vault.get("collected", "k1") == nil and Vault.get("collected", "k3") == 9)
        assert(Vault.cardSent(4, 9) and not Vault.cardSent(4, 8))
        -- 同一时刻 3 条以上的近况是重复结算，只留最后一条；两条撞时间的不动
        resetVault()
        Vault.logAdd("a1", 7) Vault.logAdd("a2", 7) Vault.logAdd("a3", 7) Vault.logAdd("b1", 8) Vault.logAdd("b2", 8)
        require("papersprite.core.state").load({ version = 7 }, 0)
        local texts = Vault.logList()
        assert(#texts == 3 and texts[1] == "a3" and texts[2] == "b1" and texts[3] == "b2")
        resetVault()
    end
    -- 旧的 save.lua 先补坏书签再导入
    St._reset(); kv = {}; tbl = {}; moon = nil
    files["/D/.moon/game/paper-sprite/save.lua"] = { data = { state = { trips = 8, postcards = {} } } }
    assert(St.open("save"):readSetting("state").trips == 8 and St.decode(kv.save["state.trips"]) == 8)
end

-- 18. 多语言：英文目录下各页没有残留中文（地点 / 物品 / 访客名也走译文），占位符数与中文一致
do
    local L10n = require("papersprite.l10n")
    L10n.load("en")
    -- 数据表在 require 时取译文，换语言后要重新加载（真实环境里语言切换必须重启）
    for k in pairs(package.loaded) do
        if k:find("^papersprite%.") and k ~= "papersprite.l10n" and k ~= "papersprite.core.reading" then package.loaded[k] = nil end
    end
    fakeShelf()
    Vault = require("papersprite.core.vault") Vault.use(vaultBackend)
    local GameEn, StateEn = require("papersprite.game"), require("papersprite.core.state")
    local function cjk(str) return str:find("[\228-\233]") end
    local function clean(where)
        local all = text()
        for _, b in ipairs(btns()) do all = all .. "\n" .. b.text end
        assert(not cjk(all), where .. " 有残留中文: " .. all)
    end
    H.saved = StateEn.fresh(0)
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
    Vault = require("papersprite.core.vault") Vault.use(vaultBackend)
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
    resetVault() Vault.cardAdd({ line = "上一张的句子。" })
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

-- 读书墙：阿页的感悟由 AI 补，失败的本次进入不再试
do
    local Story, State, Shelf = require("papersprite.core.story"), require("papersprite.core.state"), require("papersprite.core.shelf")
    local rows = fakeShelf()
    Shelf.add({ title = "甲", at = 5, quote = "划过的一句" }) Shelf.add({ title = "乙", at = 6 })
    local store, mode = State.fresh(1000), "ok"
    local host
    host = { loadState = function() return store end, saveState = function(_, t) store = t end, now = function() return 1000 end,
        schedule = function() end,
        ai = function() return { json = function(msgs, cb)
            host.last = msgs[2].content
            if mode == "ok" then cb({ thoughts = { "灯下读完，心里很静。", "<b>坏</b>" } }) else cb(nil, "boom") end
        end } end }
    local failed = {}
    assert(Story.maybeThoughts(host, store, nil, failed))
    assert(host.last:find("划过的一句", 1, true))
    assert(rows[1].thought == "灯下读完，心里很静。" and not rows[2].thought and failed["t:乙"])
    assert(not Story.maybeThoughts(host, store, nil, failed), "failed ones wait for the next visit")
    mode = "fail"
    assert(Story.maybeThoughts(host, store, nil, {}) and not rows[2].thought)
    mode = "ok"
    assert(Story.maybeThoughts(host, store, nil, {}) and rows[2].thought, "retries on a new visit")
    fakeShelf()
end

-- 1.9.1 的 cdata 书签把存档写成 `["title"] = ,`：补成 nil 救回，其余数据不丢
do
    local Storage = require("papersprite.core.storage")
    local path = os.tmpname()
    local f = io.open(path, "w")
    f:write('return {\n ["postcards"] = { 1, 2 },\n ["bookmarks"] = { { ["title"] = , ["at"] = 5 } },\n}')
    f:close()
    assert(Storage.repair(path))
    local data = dofile(path)
    assert(#data.postcards == 2 and data.bookmarks[1].title == nil and data.bookmarks[1].at == 5)
    assert(not Storage.repair(path), "a loadable file is left alone")
    os.remove(path)
end

-- 剪贴簿 / 来客簿 / 惦记直达
do
    local Album = require("papersprite.core.album")
    local st = State.fresh(0)
    resetVault()
    Vault.set("place_trips", "ink_lake", 2)
    for _, id in ipairs({ "lake_pebble", "ink_shell", "quill_reed" }) do Vault.set("souvenirs", id, 1) end
    addCards({ { place = "ink_lake", at = 1 }, { place = "ink_lake", at = 2 } })
    Vault.set("seen_visitors", "inkbug", 10)
    local row = Album.place(st, Travel.place("ink_lake"))
    assert(row.done and row.have == 3 and row.cards == 2, "place page complete")
    local _, done, total = Album.places(st)
    assert(done == 1 and total == #require("papersprite.data.places"))
    local guests, have, gtotal = Album.visitors(st)
    assert(have == 1 and gtotal == #require("papersprite.data.visitors") and guests[1].visitor.id == "inkbug")
    -- 惦记：下一趟直达（只推进到出门，别把整趟走完）
    resetVault()
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

print("headless ok: trips=" .. st.trips .. " places=" .. np .. " combos=" .. nc)

do -- 访客：不出门也会来；节日更勤；出门时不来
    local Travel = require("papersprite.core.travel")
    local State = require("papersprite.core.state")
    local function visits()
        local n = 0
        for i = 1, 200 do
            local s = State.fresh(1)
            s.seed = i * 7919
            s.visit_check = 1
            resetVault()
            Travel.settle(s, 1 + 3600 * 72)
            if Vault.size("seen_visitors") > 0 then n = n + 1 end
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
        if err.kind == "place" then Vault.set("place_trips", err.key, (err.base or 0) + 1)
        elseif err.kind == "tag" then st.stats.tag = st.stats.tag or {} st.stats.tag[err.key] = (err.base or 0) + 1
        elseif err.kind == "weather" then st.stats.weather = st.stats.weather or {} st.stats.weather[err.key] = (err.base or 0) + 1
        elseif err.kind == "book" then st.stats.books = (err.base or 0) + 1
        elseif err.kind == "host" then Vault.set("bonds", err.visitor, (err.base or 0) + 1)
        else error("unknown errand kind " .. tostring(err.kind)) end
    end
    bump(s, s.errands[1])
    local before = s.inspiration
    assert(Errand.done(s, s.errands[1]) and Errand.claim(s, 1, 2000))
    -- 领取会顺手判定成就（第一张纸条 +6），灵感增量不只有委托本身
    assert(s.inspiration >= before + Errand.REWARD and Vault.get("achieved", "errand1") and (Vault.get("bonds", "inkbug") or 0) >= 1
        and not Errand.claim(s, 1, 2000), "claim once")
    s.sprite.status = "away"
    Errand.leave(s, "inkbug", 3000)
    bump(s, s.errands[#s.errands])
    assert(Errand.done(s, s.errands[#s.errands]) and not Errand.claim(s, #s.errands, 4000), "away cannot claim")
    local d = State.fresh(1)
    resetVault()
    Vault.cardAdd({ place = "ink_lake", at = 1 })
    assert(not Disturb.next(d), "unarmed")
    Disturb.arm(d)
    Vault.cardAdd({ place = "ink_lake", at = 2 })
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
    Vault.set("achieved", "errand1", 3)
    note = Disturb.next(d)
    assert(note and note.kind == "ach" and note.id == "errand1")
    local returned = State.fresh(1)
    Disturb.arm(returned)
    returned.sprite = { status = "home", left_at = 5, back_at = 9 }
    assert(Disturb.next(returned).kind == "home", "a completed trip does not replay departure")

    local g = State.fresh(1)
    g.sprite.status = "home"
    g.visitor = { id = "inkbug", pose = "", until_at = 1e9 }
    Vault.set("souvenirs", "ad_slip", 2)
    local ok = Quest.give(g, "ad_slip", 2000)
    assert(ok and Vault.get("souvenirs", "ad_slip") == 1 and Quest.bond(g, "inkbug") >= 1 and g.visitor.fed)
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
    local edition_wall, shelf_rows = State.fresh(1000), fakeShelf()
    assert(Reading.collect(edition_wall) == 10 and #shelf_rows == 2
        and shelf_rows[1].cover == "/covers/a.png", "bookmarks retain cover paths and same-title editions")
    assert(#(editions.finished or {}) == 0 and Reading.collect(edition_wall) == 0, "collected books leave the queue")
    local moon_catalog = {
        { "同名书", 6, "local", "b" },
        { "月读已读", 5, "local", "a" },
    }
    local moon_files = {}
    local moon_queries = { stats = 0, finished = 0, failed = false }
    local function stubMoon()
        package.loaded["utils.db"], package.loaded["papersprite.core.moon_books"] = nil, nil
        package.preload["utils.db"] = function()
            return { each = function(sql, binds, fn)
                if moon_queries.failed then return false end
                if sql:find("FROM notes", 1, true) then fn({ "NOTE" }) return true end
                if sql:find("SELECT path FROM", 1, true) then
                    local src, sid = binds and binds[1], binds and binds[2]
                    for _, f in pairs(moon_files) do
                        if f.source_id == src and f.stable_id == sid and f.path
                            and ((sql:find("FROM chapters", 1, true) and f.kind == "chapter")
                                or (sql:find("FROM books", 1, true) and f.kind == "book")) then
                            fn({ f.path })
                        end
                    end
                    for _, r in ipairs(moon_catalog) do
                        if r[3] == src and r[4] == sid and r.path then fn({ r.path }) end
                    end
                    return true
                end
                if sql:find("FROM chapters", 1, true) or (sql:find("FROM books", 1, true) and sql:find("path =", 1, true)) then
                    local hit = moon_files[binds and binds[1]]
                    if hit and hit.kind == "chapter" and sql:find("FROM chapters", 1, true) then
                        if hit.fail then return false end
                        fn({ hit.source_id, hit.stable_id }); return true
                    end
                    if hit and hit.kind == "book" and sql:find("FROM books", 1, true) then
                        fn({ hit.source_id, hit.stable_id }); return true
                    end
                    return true
                end
                if sql:find("SELECT b.read_state", 1, true) then
                    local hit
                    for _, f in pairs(moon_files) do
                        if f.source_id == (binds and binds[1]) and f.stable_id == (binds and binds[2]) then hit = f break end
                    end
                    if hit then fn({ hit.read_state, hit.fraction }) end
                    return true
                end
                if sql:find("SELECT b.source_id", 1, true) then
                    moon_queries.roster = (moon_queries.roster or 0) + 1
                    for _, r in ipairs(moon_catalog) do fn({ r[3], r[4], r[2] }) end
                    return true
                end
                if sql:find("SELECT b.title", 1, true) then
                    moon_queries.finished = moon_queries.finished + 1
                    for _, r in ipairs(moon_catalog) do fn(r) end
                    return true
                end
                error("unexpected moon sql: " .. sql)
            end }
        end
        package.preload["json"] = function()
            return { decode = function() return { items = { { drawer = "" , text = "书签" }, { drawer = "lighten", text = "划过的一句" } } } end }
        end
        package.preload["utils.paths"] = function() return { coverPath = function(id) return "/cache/" .. id .. ".png" end } end
        package.preload["libs/libkoreader-lfs"] = function()
            return { attributes = function(path) return path == "/cache/a.png" and "file" or nil end }
        end
    end
    stubMoon()
    local moon_wall, moon_rows = State.fresh(1000), fakeShelf()
    moon_wall.bookmarks = { { title = 1984, at = 1 }, { id = "old", title = "旧书", at = 3, thought = "旧的感悟" } }
    assert(Reading.collect(moon_wall, { moon = true }) == 0 and #moon_rows == 3 and moon_wall.bookmarks == nil,
        "legacy bookmarks move to the shelf (bad title dropped), moon books backfill without reward")
    assert(type(moon_wall.moon_sync_fp) == "string" and moon_wall.moon_sync_fp ~= "", "successful import stores moon roster fingerprint")
    assert(moon_rows[1].thought == "旧的感悟", "legacy thought kept")
    assert(moon_rows[2].title == "月读已读" and moon_rows[2].cover == "/cache/a.png", "moon cover only when cached")
    assert(moon_rows[2].quote == "划过的一句", "moon first highlight kept as AI context")
    assert(moon_rows[2].id == "moon:local:a" and moon_rows[3].id == "moon:local:b", "moon books use stable source+id")
    local roster_before = moon_queries.roster or 0
    local finished_before = moon_queries.finished
    local fp = moon_wall.moon_sync_fp
    assert(Reading.collect(moon_wall, { moon = true }) == 0 and #moon_rows == 3, "moon books are collected once")
    assert(moon_wall.moon_sync_fp == fp, "unchanged roster keeps the same fingerprint")
    assert((moon_queries.roster or 0) == roster_before + 1 and moon_queries.finished == finished_before,
        "unchanged fingerprint only reruns the lightweight roster, not the detail query")
    assert(Reading.collect(moon_wall) == 0 and (moon_queries.roster or 0) == roster_before + 1,
        "collect without opts.moon does not scan the moon library")

    -- 空首次成功查询只记下 0 水位，后来的已读还能补进墙，且不发奖
    moon_catalog = {}
    moon_queries.stats, moon_queries.finished = 0, 0
    stubMoon()
    local empty_wall, empty_rows = State.fresh(1000), fakeShelf()
    assert(Reading.collect(empty_wall, { moon = true }) == 0 and #empty_rows == 0
        and type(empty_wall.moon_sync_fp) == "string" and empty_wall.moon_sync_fp ~= ""
        and empty_wall.inspiration == 10, "empty first import stores an empty-roster fingerprint, not a permanent skip")
    local empty_fp = empty_wall.moon_sync_fp
    moon_catalog = { { "后来才标已读", 2000, "local", "late" } }
    stubMoon()
    assert(Reading.collect(empty_wall, { moon = true }) == 0 and #empty_rows == 1
        and empty_rows[1].title == "后来才标已读" and empty_rows[1].at == 2000
        and empty_rows[1].backfill == true and empty_wall.inspiration == 10
        and empty_wall.moon_sync_fp ~= empty_fp,
        "books marked read after an empty first import are backfilled without reward")

    -- 旧版 moon_imported=3 的存档也要补漏；同名不同书（都有稳定 id）不合并
    moon_catalog = {
        { "同名经典", 10, "wechat", "id-one" },
        { "同名经典", 11, "local", "id-two" },
    }
    stubMoon()
    local catchup, catchup_rows = State.fresh(1000), fakeShelf()
    catchup.moon_imported = 3
    assert(Reading.collect(catchup, { moon = true }) == 0 and #catchup_rows == 2
        and catchup.inspiration == 10, "legacy one-shot flag still backfills distinct same-title moon books")
    local catchup_ids = {}
    for _, r in ipairs(catchup_rows) do catchup_ids[r.id] = true end
    assert(catchup_ids["moon:wechat:id-one"] and catchup_ids["moon:local:id-two"],
        "same-title moon books with different stable ids stay two wall entries")

    -- 迟到的旧时间已读：条数增加但最大时间不变，必须全量补漏而不是只取新水位
    moon_catalog = { { "先在墙里", 50, "local", "newish" } }
    stubMoon()
    local late_wall, late_rows = State.fresh(1000), fakeShelf()
    assert(Reading.collect(late_wall, { moon = true }) == 0 and #late_rows == 1)
    moon_catalog = {
        { "先在墙里", 50, "local", "newish" },
        { "迟到的旧已读", 20, "local", "older" },
    }
    stubMoon()
    assert(Reading.collect(late_wall, { moon = true }) == 0 and #late_rows == 2
        and late_rows[2].title == "迟到的旧已读" and late_rows[2].at == 20,
        "late older finished books are caught when the roster fingerprint changes")

    -- 手动/跳转/EndOfBook 只要已落入月读已读名册，下次对账就能上墙且不发奖
    moon_catalog = {
        { "先在墙里", 50, "local", "newish" },
        { "迟到的旧已读", 20, "local", "older" },
        { "刚标记已读", 80, "local", "fresh" },
    }
    stubMoon()
    assert(Reading.collect(late_wall, { moon = true }) == 0 and #late_rows == 3
        and late_rows[3].title == "刚标记已读" and late_rows[3].at == 80 and late_wall.inspiration == 10,
        "manual or jump-to-end marks that land in moon are collected on next sync without reward")

    do
    local function testRosterEdges()
    -- 同一轮既有迟到旧书（时间早于旧最大时间）又有刷新最大时间的新书：两者都要进墙
    moon_catalog = { { "水位书", 50, "local", "base" } }
    stubMoon()
    local mix_wall, mix_rows = State.fresh(1000), fakeShelf()
    assert(Reading.collect(mix_wall, { moon = true }) == 0 and #mix_rows == 1)
    moon_catalog = {
        { "水位书", 50, "local", "base" },
        { "同一轮迟到", 10, "local", "lag" },
        { "同一轮新书", 90, "local", "newer" },
    }
    stubMoon()
    assert(Reading.collect(mix_wall, { moon = true }) == 0 and #mix_rows == 3
        and mix_wall.inspiration == 10,
        "late and newer books in the same roster change are both backfilled without reward")
    local mix_titles = {}
    for _, r in ipairs(mix_rows) do mix_titles[r.title] = r.at end
    assert(mix_titles["同一轮迟到"] == 10 and mix_titles["同一轮新书"] == 90,
        "the late book is not dropped just because max at also moved forward")

    -- 条数和最大时间都不变，但已读集合被替换：新身份可见，旧墙上纪念记录不删
    moon_catalog = {
        { "还在的", 20, "local", "keep" },
        { "将被换掉", 50, "local", "gone" },
    }
    stubMoon()
    local swap_wall, swap_rows = State.fresh(1000), fakeShelf()
    assert(Reading.collect(swap_wall, { moon = true }) == 0 and #swap_rows == 2)
    local swap_fp = swap_wall.moon_sync_fp
    moon_catalog = {
        { "还在的", 20, "local", "keep" },
        { "换进来的", 50, "local", "enter" },
    }
    stubMoon()
    assert(Reading.collect(swap_wall, { moon = true }) == 0 and #swap_rows == 3
        and swap_wall.moon_sync_fp ~= swap_fp and swap_wall.inspiration == 10,
        "same count and max at but a replaced identity still arrives; old wall rows are kept")
    local swap_ids = {}
    for _, r in ipairs(swap_rows) do swap_ids[r.id] = r.title end
    assert(swap_ids["moon:local:gone"] == "将被换掉" and swap_ids["moon:local:enter"] == "换进来的")

    end
    testRosterEdges()
    end

    -- 强制未读不在目录里，不会被导入
    moon_catalog = { { "刚标记已读", 80, "local", "fresh" } } -- catalog stub already only lists qualified rows
    stubMoon()
    local force_wall, force_rows = State.fresh(1000), fakeShelf()
    -- 旧无 id 同名行与后来带稳定 id 的月读导入去重，不重复上墙
    force_rows[1] = { key = "t:刚标记已读", title = "刚标记已读", at = 8 }
    assert(Reading.collect(force_wall, { moon = true }) == 0 and #force_rows == 1
        and force_rows[1].key == "t:刚标记已读", "legacy title-only shelf row is not duplicated by later moon id")

    -- 库暂不可用 / 查询失败不前推水位，恢复后可重试
    moon_catalog = { { "恢复后能进墙", 9, "local", "retry" } }
    stubMoon()
    moon_queries.failed = true
    local fail_wall, fail_rows = State.fresh(1000), fakeShelf()
    assert(Reading.collect(fail_wall, { moon = true }) == 0 and #fail_rows == 0
        and fail_wall.moon_sync_fp == nil,
        "a failed moon query does not advance the fingerprint")
    moon_queries.failed = false
    stubMoon()
    assert(Reading.collect(fail_wall, { moon = true }) == 0 and #fail_rows == 1
        and fail_rows[1].title == "恢复后能进墙" and type(fail_wall.moon_sync_fp) == "string",
        "moon sync retries after the library is available again")

    -- 写入失败不前推水位，可重试
    moon_catalog = { { "先失败再写入", 12, "local", "write" } }
    stubMoon()
    local boom, boom_rows = State.fresh(1000), {}
    local boom_impl = {}
    function boom_impl.count() return #boom_rows end
    function boom_impl.page() return boom_rows end
    function boom_impl.pending() return {} end
    function boom_impl.add() return nil end
    function boom_impl.setThought() end
    function boom_impl.batch(fn) fn() return true end
    require("papersprite.core.shelf").use(boom_impl)
    assert(Reading.collect(boom, { moon = true }) == 0 and #boom_rows == 0 and boom.moon_sync_fp == nil,
        "a shelf write failure does not advance the fingerprint")
    fakeShelf() -- restore a working shelf for later tests

    -- 历史补导不发奖；合格翻页读完仍发奖；重复 collect 不再奖
    Reading._inject(reading_store)
    local shelf, rows = State.fresh(1000), fakeShelf()
    shelf.moon_imported = 3
    assert(Reading.collect(shelf) == 5)
    assert(rows[1].line:find("雾", 1, true) and logs()[#logs()]:find("灯"))
    assert(Reading.collect(shelf) == 0 and #rows == 1)
    -- 同一本后来又出现在月读已读里，按稳定 id / 书名去重且不再发奖
    moon_catalog = { { "雾", 1000, "local", "wu" } }
    stubMoon()
    -- 账本那条没有月读 id，同名且一边无 id，应视为同一本
    assert(Reading.collect(shelf, { moon = true }) == 0 and #rows == 1,
        "live finish and later moon backfill of the same title stay one bookmark and are not rewarded twice")

    do
    local function testRewardAndAliases()
    -- 同一轮：先收合格翻页账本并发奖，再补月读已读，不重复奖、不凭手动标记发奖
    local both = {}
    Reading._inject({
        readSetting = function(_, k) return both[k] end,
        saveSetting = function(_, k, v) both[k] = v end,
        flush = function() end,
    })
    Reading.record(70, { title = "同轮读完", finished = true, id = "moon:local:same" }, 1, 10)
    moon_catalog = { { "同轮读完", 70, "local", "same" } }
    stubMoon()
    local both_wall, both_rows = State.fresh(1000), fakeShelf()
    assert(Reading.collect(both_wall, { moon = true }) == 5 and #both_rows == 1
        and both_wall.inspiration == 15,
        "qualified flip is rewarded once even when moon backfill of the same id runs in the same collect")

    moon_catalog = { { "先月读后翻页", 80, "local", "after" } }
    stubMoon()
    local order_wall, order_rows = State.fresh(1000), fakeShelf()
    assert(Reading.collect(order_wall, { moon = true }) == 0 and #order_rows == 1 and order_wall.inspiration == 10)
    local after = {}
    Reading._inject({
        readSetting = function(_, k) return after[k] end,
        saveSetting = function(_, k, v) after[k] = v end,
        flush = function() end,
    })
    Reading.record(90, { title = "先月读后翻页", finished = true, id = "moon:local:after" }, 1, 10)
    assert(Reading.collect(order_wall, { moon = true }) == 0 and #order_rows == 1 and order_wall.inspiration == 10,
        "a later qualified flip of a book already synced from moon is not rewarded again")

    package.loaded["ffi/sha2"] = { md5 = function(path) return "hash:" .. path end }
    local hashed = { "哈希同本", 15, "local", "hashed" }
    hashed.path = "/books/hashed.epub"
    moon_catalog = { hashed }
    moon_files["/books/hashed.epub"] = { kind = "book", source_id = "local", stable_id = "hashed",
        path = "/books/hashed.epub", read_state = 1, fraction = 1 }
    stubMoon()
    local hash_wall, hash_rows = State.fresh(1000), fakeShelf()
    hash_rows[1] = { key = "hash:/books/hashed.epub", id = "hash:/books/hashed.epub", title = "哈希同本", at = 3 }
    assert(Reading.collect(hash_wall, { moon = true }) == 0 and #hash_rows == 1
        and hash_rows[1].id == "hash:/books/hashed.epub" and hash_wall.inspiration == 10,
        "old file-hash wall row maps to moon id via registered path and is not duplicated or rewarded")
    local other = { "仅同名", 16, "local", "other" }
    other.path = "/books/other.epub"
    moon_catalog = { other }
    moon_files["/books/other.epub"] = { kind = "book", source_id = "local", stable_id = "other",
        path = "/books/other.epub", read_state = 1, fraction = 1 }
    stubMoon()
    local title_wall, title_rows = State.fresh(1000), fakeShelf()
    title_rows[1] = { key = "hash:/books/unrelated.epub", id = "hash:/books/unrelated.epub", title = "仅同名", at = 4 }
    assert(Reading.collect(title_wall, { moon = true }) == 0 and #title_rows == 2
        and title_rows[1].id == "hash:/books/unrelated.epub" and title_rows[2].id == "moon:local:other",
        "same title with no path evidence stays two books; the old hash row is kept")

    end
    testRewardAndAliases()
    end

    -- 月读分章：中间章页码 99% 不完读；全书进度 / 已读才完读；短末章也能完读
    local MoonBooks = require("papersprite.core.moon_books")
    moon_files["/chapters/mid.epub"] = { kind = "chapter", source_id = "wechat", stable_id = "serial",
        read_state = 0, fraction = 0.45 }
    moon_files["/chapters/last.epub"] = { kind = "chapter", source_id = "wechat", stable_id = "serial-end",
        read_state = 0, fraction = 0.99 }
    moon_files["/chapters/marked.epub"] = { kind = "chapter", source_id = "wechat", stable_id = "done",
        read_state = 1, fraction = 1 }
    moon_files["/chapters/unread.epub"] = { kind = "chapter", source_id = "wechat", stable_id = "forced",
        read_state = 2, fraction = 1 }
    moon_files["/whole.epub"] = { kind = "book", source_id = "local", stable_id = "epub",
        read_state = 0, fraction = 0.5 }
    stubMoon()
    MoonBooks = require("papersprite.core.moon_books")
    local mid = MoonBooks.forFile("/chapters/mid.epub")
    local last = MoonBooks.forFile("/chapters/last.epub")
    local marked = MoonBooks.forFile("/chapters/marked.epub")
    local forced = MoonBooks.forFile("/chapters/unread.epub")
    local whole = MoonBooks.forFile("/whole.epub")
    local unknown = MoonBooks.forFile("/other.epub")
    assert(mid and mid.id == "moon:wechat:serial" and mid.finished == false, "mid-chapter progress is not whole-book finished")
    assert(last and last.finished == true, "short last chapter still finishes when moon fraction is 99%")
    assert(marked and marked.finished == true, "moon EndOfBook / setRead (read_state=1) is finished")
    assert(forced and forced.finished == false, "forced unread is not finished even at 100%")
    assert(whole and whole.finished == false and unknown == nil, "unfinished whole file and unknown path fall through")
    do
    local function testIdentityMapping()
    package.preload["reader.session.derived_note"] = function()
        return { originOf = function(path) return path == "/derived/copy.epub" and "/chapters/mid.epub" or nil end }
    end
    package.loaded["reader.session.derived_note"] = nil
    package.loaded["papersprite.core.moon_books"] = nil
    MoonBooks = require("papersprite.core.moon_books")
    local derived = MoonBooks.forFile("/derived/copy.epub")
    assert(derived and derived.claimed and derived.id == "moon:wechat:serial" and derived.finished == false,
        "derived edition follows the origin book's whole-book progress")
    moon_files["/outside/book.epub"] = { kind = "book", source_id = "local", stable_id = "/outside/book.epub",
        read_state = 1, fraction = 1 }
    package.preload["utils.settings"] = function()
        return { getSource = function() return { path = "/library" } end }
    end
    package.loaded["utils.settings"], package.loaded["papersprite.core.moon_books"] = nil, nil
    MoonBooks = require("papersprite.core.moon_books")
    assert(MoonBooks.forFile("/outside/book.epub") == nil,
        "legacy local rows outside the scan root are not treated as moon-managed")
    moon_files["/chapters/broken.epub"] = { kind = "chapter", fail = true }
    package.loaded["papersprite.core.moon_books"] = nil
    MoonBooks = require("papersprite.core.moon_books")
    local broken = MoonBooks.forFile("/chapters/broken.epub")
    assert(broken and broken.claimed == true and broken.finished == false and not broken.id,
        "a failed chapter identity lookup stays claimed and unfinished, not a native whole-book finish")
    end
    testIdentityMapping()
    end

    -- 打开阁楼 / 进读书墙会带上月读同步；进其他页或定时 tick 不会全表重扫
    local prev_reading = package.loaded["papersprite.core.reading"]
    local collect_calls = {}
    package.loaded["papersprite.core.reading"] = {
        collect = function(state, opts)
            collect_calls[#collect_calls + 1] = { page = nil, moon = opts and opts.moon or false }
            return 0
        end,
    }
    local saved, saved_view = H.saved, H.view
    resetVault()
    H.saved = State.fresh(0)
    H.saved.visitor = { id = "inkbug", pose = "", until_at = 1e12 }
    local g = require("papersprite.game").new(H.host):show()
    assert(collect_calls[1] and collect_calls[1].moon == true, "opening the attic syncs moon already-read books")
    local after_show = #collect_calls
    g:go("cabinet")
    assert(#collect_calls == after_show, "opening another collection page does not moon-sync")
    g:go("bookwall")
    assert(collect_calls[#collect_calls] and collect_calls[#collect_calls].moon == true,
        "opening the reading wall syncs moon already-read books")
    local after_wall = #collect_calls
    g:tick()
    assert(#collect_calls == after_wall + 1 and collect_calls[#collect_calls].moon == false,
        "attic timer ticks collect the ledger without a moon rescan")
    if g.close then g:close() end
    H.saved, H.view = saved, saved_view
    package.loaded["papersprite.core.reading"] = prev_reading

    Reading._inject({ readSetting = function() error("reading store unavailable") end })
    local collected = pcall(Reading.collect, State.fresh(1000))
    assert(not collected, "reading storage failures must reach the caller")
    Reading._inject(reading_store)
    for _, m in ipairs({ "utils.db", "utils.paths", "libs/libkoreader-lfs", "json", "papersprite.core.moon_books",
        "reader.session.derived_note", "utils.settings" }) do
        package.preload[m], package.loaded[m] = nil, nil
    end
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
    local info = Main._bookInfo(book, 20)
    assert(info.id == "book-id" and info.finished == true and info.cover == "/fake/paper-sprite/covers/book-id.png"
        and written == info.cover .. ":png" and cover_calls == 1 and freed == 1)
    Main._bookInfo(book, 20)
    assert(cover_calls == 1, "cover is captured once per book")
    book.ui.document.getPageCount = function() return 15 end
    local short_native = Main._bookInfo(book, 15)
    assert(short_native.finished == false and short_native.id == "book-id", "native KOReader short books stay unfinished")
    book.ui.document.getPageCount = function() return 20 end
    local mid_native = Main._bookInfo(book, 19)
    assert(mid_native.finished == false, "native 19/20 is not 99%")
    package.loaded["papersprite.core.moon_books"] = {
        forFile = function(path)
            if path == "/book.epub" then
                return { id = "moon:local:epub", finished = false, fraction = 0.4 }
            end
        end,
    }
    book.ui.document.getPageCount = function() return 80 end
    local mid_chapter = Main._bookInfo(book, 80)
    assert(mid_chapter.finished == false and mid_chapter.id == "moon:local:epub",
        "moon-managed mid-chapter 99% of the current document is not a whole-book finish")
    package.loaded["papersprite.core.moon_books"].forFile = function(path)
        if path == "/book.epub" then return { id = "moon:local:epub", finished = true, claimed = true, fraction = 0.99, aliases = { "book-id" } } end
    end
    book.ui.document.getPageCount = function() return 8 end
    local last_chapter = Main._bookInfo(book, 8)
    assert(last_chapter.finished == true and last_chapter.id == "moon:local:epub"
        and last_chapter.aliases and last_chapter.aliases[1] == "book-id",
        "moon-managed short last chapter finishes by whole-book progress, not page count")
    package.loaded["papersprite.core.moon_books"].forFile = function()
        return { claimed = true, finished = false }
    end
    book.ui.document.getPageCount = function() return 80 end
    local failed_map = Main._bookInfo(book, 80)
    assert(failed_map.finished == false and failed_map.id == nil,
        "a claimed moon file whose identity lookup failed does not fall back to native page-ratio finish")
    package.loaded["papersprite.core.moon_books"] = nil
    io.open = old_open
    package.loaded["ffi/sha2"], package.loaded["papersprite.core.storage"] = old_sha2, old_storage
    for _, name in ipairs(names) do package.loaded[name] = saved[name] end
    local Lock = require("papersprite.core.postcard_lock")
    resetVault()
    assert(Lock.latest() == nil)
    addCards({
        { place = "ink_lake", weather = "mist", line = "旧的", at = 1 },
        { place = "ink_lake", weather = "clear", line = "湖面很静", at = 50 },
    })
    local card = Lock.latest()
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
    resetVault() Vault.set("souvenirs", "ad_slip", 1)
    H.saved.visitor = { id = "inkbug", pose = "", until_at = 1e12 }
    require("papersprite.core.shelf").add({ title = "封面书", at = 1, cover = "/covers/book-id.png" })
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
    Vault.cardAdd({ place = "ink_lake", pose = "sit", prop = "none", weather = "clear",
        variant = "a", line = "湖面很静", at = 5 })
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
    resetVault() Vault.cardAdd({ place = "ink_lake", at = 1 })
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
    Vault.cardAdd({ place = "ink_lake", pose = "sit", prop = "none", weather = "clear", variant = "a", at = 4 })
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
    Vault.set("achieved", "trips1", 20)
    M.poke()
    assert(image:find("achievements/trips1.png", 1, true), "achievement notice uses its matching artwork")
    shown:dismiss()
    for _, name in ipairs(names) do package.loaded[name] = saved[name] end
end

do -- 休眠或锁屏时不打扰，解锁后再等 WAKE_GRACE 才弹。
    local names = {
        "papersprite.ui.reader_overlay", "papersprite.ui.read_prefs", "ui/uimanager",
        "ui/time", "apps/reader/readerui", "ui.themes.widgets.modal", "ui.themes",
        "ui.themes.widgets.text", "ui/widget/verticalgroup", "ui/widget/verticalspan",
        "ui/widget/container/centercontainer", "ui/geometry", "ui/widget/imagewidget",
        "papersprite.ui.postcard", "device", "features.passcode", "utils.wake",
    }
    local saved = {}
    for _, name in ipairs(names) do saved[name] = package.loaded[name] end
    local state = require("papersprite.core.state").fresh(1)
    local shown, locked, waiters, clock, pending = nil, false, {}, 100, {}
    local Device = { screen_saver_mode = false }
    package.loaded["device"] = Device
    package.loaded["features.passcode"] = {
        isLocked = function() return locked end,
        afterUnlock = function(key, fn)
            if not locked then return fn() end
            waiters[key] = fn
        end,
    }
    package.loaded["utils.wake"] = { GRACE = 5 }
    package.loaded["papersprite.ui.read_prefs"] = {
        disturb = function() return true end,
        host = function() return {
            loadState = function() return state end, now = function() return 10 end,
            saveState = function() end,
        } end,
    }
    package.loaded["ui/time"] = { now = function() return clock end, to_s = function(t) return t end }
    package.loaded["ui/uimanager"] = {
        setDirty = function() end,
        scheduleIn = function(_self, delay, fn) pending[#pending + 1] = { at = clock + delay, fn = fn } end,
        unschedule = function(_self, fn)
            for i = #pending, 1, -1 do if pending[i].fn == fn then table.remove(pending, i) end end
        end,
    }
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
        "ui/widget/container/centercontainer", "ui/geometry", "ui/widget/imagewidget" }) do
        package.loaded[name] = widget
    end
    package.loaded["papersprite.ui.postcard"] = { widget = function(body) return { side = body.side } end }
    package.loaded["papersprite.ui.reader_overlay"] = nil
    local M = require("papersprite.ui.reader_overlay")
    M.syncFlags = function() return state end
    require("papersprite.core.disturb").arm(state)
    state.sprite = { status = "away", left_at = 2 }
    local function advance(secs)
        local stop = clock + secs
        while true do
            table.sort(pending, function(a, b) return a.at < b.at end)
            local t = pending[1]
            if not t or t.at > stop then break end
            table.remove(pending, 1)
            clock = math.max(clock, t.at)
            t.fn()
        end
        clock = stop
    end

    M.poke()
    assert(shown and shown.dialog.title == "阿页出门了", "already awake still shows immediately")
    shown:dismiss()
    shown = nil
    -- 关掉后 0.2 秒会再 poke；先把这条收掉，后面的用例自己控制时间。
    pending = {}

    Device.screen_saver_mode = true
    state.sprite = { status = "home", left_at = 2, back_at = 3 }
    M.poke()
    assert(shown == nil, "screensaver suppresses the notice")
    assert(#pending == 1 and pending[1].at == clock + 1, "polls until the screensaver is dismissed")

    M.onResume()
    Device.screen_saver_mode = false
    advance(1)
    assert(shown == nil, "unlock starts a grace period instead of showing immediately")
    M.poke()
    assert(shown == nil, "manual poke during grace is also deferred")
    advance(5)
    assert(shown and shown.dialog.title == "阿页回来了", "notice appears after the wake grace")
    shown:dismiss()
    shown = nil
    pending = {}

    Device.screen_saver_mode = true
    locked = true
    state.visitor = { id = "clip_snail", pose = "", until_at = 100 }
    M.onSuspend()
    M.poke()
    assert(shown == nil, "sleep plus passcode still suppresses the notice")
    M.onResume()
    Device.screen_saver_mode = false
    advance(2)
    assert(shown == nil and waiters["papersprite.disturb"], "waits for passcode after the screensaver closes")
    locked = false
    waiters["papersprite.disturb"]()
    assert(shown == nil, "passcode unlock also starts the grace period")
    advance(5)
    assert(shown and shown.dialog.title:find("来做客", 1, true), "notice appears after passcode grace")
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
        -- 图片区域 full 走 tickAfterNext，不进动画自己的 scheduleIn 队列。
        tickAfterNext = function() end,
        nextTick = function() end,
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
    M.syncFlags = function()
        M.flags.away, M.flags.ready, M.flags.shown = false, true, true
        M.flags.corner, M.flags.fade = P.corner(), P.fade()
        return { sprite = { status = "home" } }
    end
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
    clock = 100.78
    table.remove(pending, 1)()
    ui.view.papersprite_companion:paintTo(bb, 0, 0)
    assert(M.last_name == "chair_read", "put-down keyframe returns to the reading pose")
    clock = 100.9
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
    P.setSize("s")
    assert(P.size() == "s" and dirty[#dirty - 1].region.w == 151 and dirty[#dirty].region.w == 86,
        "resizing clears the old footprint and draws the new one")
    P.setSize("l")
    assert(dirty[#dirty].region.w == 151, "large keeps the original size")
    settings.companion_size = "bogus"
    assert(P.size() == "l", "unknown size falls back to large")
    settings.companion_fade = 100
    local count = #painted
    ui.view.papersprite_companion:paintTo(bb, 0, 0)
    assert(#painted == count, "fully transparent companion draws nothing")
    local dirty_n, pending_n = #dirty, #pending
    M.onPage({ ui = ui })
    assert(#dirty == dirty_n and #pending == pending_n,
        "fully transparent companion does not dirty or tick for a page-turn")

    settings.companion_fade = 0
    settings.companion_static = true
    dirty_n, pending_n = #dirty, #pending
    M.flags.turn_from, M.flags.turn_ticking = nil, nil
    M.onPage({ ui = ui })
    assert(#pending == pending_n and M.flags.turn_from == nil,
        "static companion does not start a page-turn animation")
    ui.view.papersprite_companion:paintTo(bb, 0, 0)
    assert(M.last_name == "chair_read", "static companion still sits in the chair")
    for _, name in ipairs(names) do package.loaded[name] = saved[name] end
end

do -- 伴读：打开书或状态变化时马上同步在家/出门，不等下一次定时器。
    local names = {
        "papersprite.ui.read_prefs", "papersprite.ui.reader_overlay", "ui/uimanager",
        "ui/time", "ui/geometry", "ui/widget/imagewidget", "ffi/blitbuffer", "ffi",
        "papersprite.game", "papersprite.core.state", "papersprite.core.travel",
        "papersprite.core.autopilot",
    }
    local saved = {}
    for _, name in ipairs(names) do saved[name] = package.loaded[name] end
    package.loaded["papersprite.ui.read_prefs"] = nil
    package.loaded["papersprite.ui.reader_overlay"] = nil
    local P = require("papersprite.ui.read_prefs")
    local settings = { companion = true }
    local state = require("papersprite.core.state").fresh(1)
    state.sprite = { status = "away", left_at = 1, return_at = 1e12, mail = {}, trip = 1, place = "ink_lake" }
    P.host = function() return {
        loadState = function() return state end, saveState = function() end,
        now = function() return 10 end, getSetting = function(_, _k, d) return d end,
    } end
    P.get = function(key, default)
        if settings[key] == nil then return default end
        return settings[key]
    end
    P.set = function(key, value) settings[key] = value end
    package.loaded["ui/time"] = { now = function() return 10 end, to_s = function(t) return t end }
    package.loaded["ui/geometry"] = { new = function(_self, rect) return rect end }
    local dirty = {}
    package.loaded["ui/uimanager"] = {
        setDirty = function(_self, widget, mode, region)
            dirty[#dirty + 1] = { widget = widget, mode = mode, region = region }
        end,
        scheduleIn = function() end,
    }
    local pixel = { a = 0, getAlpha = function() return 255 end }
    pixel.getColor8A = function() return pixel end
    package.loaded["ui/widget/imagewidget"] = { new = function(_self, args)
        return { _bb = { getPixel = function() return pixel end },
            getSize = function() return { w = 1, h = 1 } end, file = args.file }
    end }
    package.loaded["ffi"] = { fill = function() end }
    package.loaded["ffi/blitbuffer"] = {
        TYPE_BB8A = 2,
        Color8A = function(gray, alpha) return { a = gray, alpha = alpha } end,
        new = function()
            return { data = {}, stride = 2, h = 1,
                getWidth = function() return 1 end, getHeight = function() return 1 end,
                setPixel = function() end }
        end,
    }
    local M = require("papersprite.ui.reader_overlay")
    M.poke = function() end
    local ui = { document = {}, view = { dimen = { x = 10, y = 20, w = 540, h = 720 } } }
    ui.view.registerViewModule = function(self, name, widget) self[name] = widget widget.view = self end
    M.attach(ui)
    assert(M.flags.away == true and M.flags.ready, "opening a book syncs an away sprite immediately")
    local bb = { pmulalphablitFrom = function() end }
    ui.view.papersprite_companion:paintTo(bb, 0, 0)
    assert(M.last_name == "chair_empty", "away companion is an empty chair on first paint")
    state.sprite = { status = "home", back_at = 11 }
    dirty = {}
    M.syncFlags()
    assert(M.flags.away == false and #dirty == 1, "coming home dirties the corner without waiting for a timer")
    ui.view.papersprite_companion:paintTo(bb, 0, 0)
    assert(M.last_name == "chair_read", "home companion sits back down after a status sync")
    for _, name in ipairs(names) do package.loaded[name] = saved[name] end
end

do -- 阁楼盖在阅读页上时不弹打扰。
    local names = {
        "papersprite.ui.reader_overlay", "papersprite.ui.read_prefs", "ui/uimanager",
        "apps/reader/readerui", "ui.themes.widgets.modal", "ui.themes",
        "ui.themes.widgets.text", "ui/widget/verticalgroup", "ui/widget/verticalspan",
        "ui/widget/container/centercontainer", "ui/geometry", "ui/widget/imagewidget",
        "papersprite.ui.postcard", "device",
    }
    local saved = {}
    for _, name in ipairs(names) do saved[name] = package.loaded[name] end
    local state = require("papersprite.core.state").fresh(1)
    local shown
    package.loaded["device"] = { screen_saver_mode = false }
    package.loaded["papersprite.ui.read_prefs"] = {
        disturb = function() return true end,
        host = function() return {
            loadState = function() return state end, now = function() return 10 end,
            saveState = function() end,
        } end,
    }
    package.loaded["ui/uimanager"] = { setDirty = function() end, scheduleIn = function() end, unschedule = function() end }
    package.loaded["apps/reader/readerui"] = { instance = { document = {} } }
    local Modal = {}
    function Modal:new(args)
        args.theme = { space = { md = 8 }, dialog = { bg = "white" } }
        return setmetatable(args, { __index = self })
    end
    function Modal:innerWidth() return 400 end
    function Modal:setDialog(dialog) self.dialog = dialog end
    function Modal:show() shown = self end
    function Modal:dismiss() if self.close_callback then self.close_callback() end end
    package.loaded["ui.themes.widgets.modal"] = Modal
    package.loaded["ui.themes"] = { px = function(n) return n end }
    package.loaded["ui.themes.widgets.text"] = { box = function(_role, text) return { text = text } end }
    local widget = { new = function(_self, args) return args end }
    for _, name in ipairs({ "ui/widget/verticalgroup", "ui/widget/verticalspan",
        "ui/widget/container/centercontainer", "ui/geometry", "ui/widget/imagewidget" }) do
        package.loaded[name] = widget
    end
    package.loaded["papersprite.ui.postcard"] = { widget = function(body) return { side = body.side } end }
    package.loaded["papersprite.ui.reader_overlay"] = nil
    local M = require("papersprite.ui.reader_overlay")
    M.syncFlags = function() return state end
    require("papersprite.core.disturb").arm(state)
    state.sprite = { status = "away", left_at = 2 }
    local Game = require("papersprite.game")
    local prev = Game.current
    Game.current = { closed = false, state = state }
    M.poke()
    assert(shown == nil, "an open attic suppresses the reader notice")
    Game.current.closed = true
    M.poke()
    assert(shown and shown.dialog.title == "阿页出门了", "closing the attic allows the notice again")
    Game.current = prev
    for _, name in ipairs(names) do package.loaded[name] = saved[name] end
end

do -- 托管：有灵感才自己买、自己出门；间隔 1 小时、每天最多 3 次；玩家出行不计次数。
    local Auto = require("papersprite.core.autopilot")
    local State = require("papersprite.core.state")
    local Travel = require("papersprite.core.travel")
    local saved_enabled = Auto.enabled
    Auto.enabled = function() return true end
    local function pack_player(s, t)
        assert(Travel.put(s, "oat_biscuit", t, true))
        assert(Travel.put(s, "pencil_stub", t, true))
        assert(Travel.put(s, "tiny_atlas", t, true))
    end
    local t0 = 1700000000 -- 固定时刻，日期可加一天
    local s = State.fresh(t0)
    s.inspiration = 20
    s.inventory = { oat_biscuit = 0, pencil_stub = 0, tiny_atlas = 0 }
    assert(Auto.maybeBuy(s, t0, true), "buys an affordable shop item")
    assert(s.inspiration < 20 and s.inspiration >= 20 - 12 - 0, "spends a real price and keeps a reserve")
    local bought
    for id, n in pairs(s.inventory) do
        local it = Travel.item(id)
        if it and it.price > 0 and n > 0 then bought = it end
    end
    assert(bought and (s.inventory[bought.id] or 0) >= 1, "purchase lands in inventory")
    assert(s.autopilot.last_buy_at == t0)
    assert(not Auto.maybeBuy(s, t0 + 10, true), "does not buy again inside the 2-hour gap")
    local ink = s.inspiration
    s.inspiration = 2
    assert(not Auto.maybeBuy(s, t0 + 30, true), "does not buy when the reserve would be broken")
    s.inspiration = 0
    assert(not Auto.maybeTravel(s, t0 + 30, true), "does not self-depart with no inspiration")
    s.inspiration = ink
    assert(Auto.maybeTravel(s, t0, true), "packs a trip when funded and at home")
    assert(s.sprite.status == "packed" and s.autopilot.pending, "self-initiated trip uses the existing packed flow")
    Travel.settle(s, s.sprite.depart_at, true)
    assert(s.sprite.status == "away" and s.sprite.autopilot and s.autopilot.trips == 1
        and s.autopilot.pending == nil, "depart records a caretaker trip")
    local return_at = s.sprite.return_at
    Travel.settle(s, return_at, true)
    assert(s.sprite.status == "home" and s.autopilot.last_trip_at == return_at, "return starts the 1-hour gap")
    s.visitor = nil
    assert(not Auto.maybeTravel(s, return_at, true), "does not leave again immediately after returning")
    assert(Auto.maybeTravel(s, return_at + 10, true), "may leave again after one debug hour")
    Travel.settle(s, s.sprite.depart_at, true)
    Travel.settle(s, s.sprite.return_at, true)
    assert(s.autopilot.trips == 2)
    s.visitor = nil
    assert(Auto.maybeTravel(s, s.sprite.back_at + 10, true), "third trip of the day after the gap")
    Travel.settle(s, s.sprite.depart_at, true)
    Travel.settle(s, s.sprite.return_at, true)
    assert(s.autopilot.trips == 3)
    s.visitor = nil
    assert(not Auto.maybeTravel(s, s.sprite.back_at + 10, true), "fourth trip in the same day is refused")
    local next_day = t0 + 24 * 3600
    -- 把上次回家时间拨到新的一天之前，只检验每日上限按日历日重置。
    s.autopilot.last_trip_at = next_day - 20
    s.sprite.back_at = next_day - 20
    s.visitor = nil
    assert(Auto.dayKey(next_day) ~= Auto.dayKey(t0))
    assert(Auto.maybeTravel(s, next_day, true), "a new calendar day resets the trip cap")
    -- 玩家自己出门不计托管次数
    local s2 = State.fresh(t0)
    s2.inspiration = 10
    pack_player(s2, t0)
    Travel.settle(s2, s2.sprite.depart_at, true)
    assert(s2.sprite.status == "away" and not s2.sprite.autopilot)
    assert(not s2.autopilot or s2.autopilot.trips == nil, "player-initiated trips do not consume the daily cap")
    local home_at = s2.sprite.return_at
    Travel.settle(s2, home_at, true)
    assert(s2.sprite.status == "home")
    s2.visitor = nil
    assert(not Auto.maybeTravel(s2, home_at, true), "still waits an hour after a player-initiated return")
    assert(Auto.maybeTravel(s2, home_at + 10, true), "caretaker travel may resume after the hour")
    -- 行囊里已有玩家放的东西时不插手
    local s3 = State.fresh(t0)
    s3.inspiration = 10
    assert(Travel.put(s3, "oat_biscuit", t0, true))
    assert(not Auto.maybeTravel(s3, t0, true), "does not complete a basket the player already started")
    -- 关开关时 Game:tick / settle 写路径也不行动（enabled 已覆盖的反例）
    Auto.enabled = function() return false end
    local s4 = State.fresh(t0)
    s4.inspiration = 20
    Auto.tick(s4, t0, true)
    assert(s4.inspiration == 20 and s4.sprite.status == "home", "disabled caretaker mode changes nothing")
    Auto.enabled = saved_enabled
end


-- 收藏册三视图：明信片 / 列表 / 明信片墙；记住上次选择；分享仍在；列表点进详情。
do
    local State = require("papersprite.core.state")
    local st = State.fresh(0)
    resetVault()
    for k = 1, 12 do
        Vault.cardAdd({ place = "ink_lake", pose = "sit", prop = "none", weather = "clear", line = "line" .. k, at = k })
    end
    H.settings = { debug_fast = true }
    H.saved = st
    local g = Game.new(H.host):show()
    attic_ops(); click("明信片墙")
    assert(g:albumView() == "card", "default album view is single postcard")
    assert(H.view.postcard and H.view.switch and H.view.switch.icon == "share", "card view keeps share")
    assert(H.view.extra and H.view.extra.icon == "photo" and H.view.extra.text == "明信片", "view switch on the title bar")
    local first_index = H.view.postcard.index
    H.view.pager.go(5)
    assert(g.wall_page == 5)
    -- 切到列表：分享还在，选中项落在当前页，列表无整本 scene 合成
    H.view.extra.callback()
    assert(g:albumView() == "list" and H.settings.album_view == "list")
    assert(H.view.notes and H.view.notes.rows and #H.view.notes.rows >= 1, "list uses notes rows")
    assert(H.view.switch and H.view.switch.icon == "share", "list view keeps share")
    assert(H.view.extra and H.view.extra.icon == "view_list")
    assert(not H.view.postcard, "list is not the single-card layout")
    local saw_sel
    for _, r in ipairs(H.view.notes.rows) do
        if r.text:find("✓", 1, true) then saw_sel = true end
        assert(r.callback, "list rows open a card")
        assert(not r.scene, "list does not compose thumbnails")
    end
    assert(saw_sel, "selected card stays marked in the list")
    -- 点列表打开详情，返回仍是列表
    local row = H.view.notes.rows[1]
    row.callback()
    assert(g.page == "card" and H.view.postcard, "list click opens postcard detail")
    assert(H.view.switch and H.view.switch.icon == "share", "detail keeps share")
    assert(not H.view.extra, "detail does not replace share with the view switch")
    back()
    assert(g.page == "wall" and g:albumView() == "list" and H.view.notes)

    -- 切到明信片墙：只给当前页做缩略，分享仍在
    H.view.extra.callback()
    assert(g:albumView() == "wall" and H.settings.album_view == "wall")
    assert(H.view.shelf and H.view.shelf.cols == 3 and #H.view.shelf.cells > 0)
    assert(#H.view.shelf.cells <= (H.view.shelf.per or 9), "grid only composes the visible page")
    assert(H.view.shelf.cells[1].scene, "grid cells are postcard thumbs")
    assert(H.view.switch and H.view.switch.icon == "share", "grid view keeps share")
    local checked = 0
    for _, c in ipairs(H.view.shelf.cells) do if c.check then checked = checked + 1 end end
    assert(checked == 1, "one selected thumb in the grid")
    H.view.shelf.cells[1].callback()
    assert(g.page == "card" and H.view.postcard, "grid click opens detail")
    back()
    assert(g:albumView() == "wall")

    -- 再切回单张，记住设置；新实例读到上次选择
    H.view.extra.callback()
    assert(g:albumView() == "card" and H.view.postcard)
    g:close()
    local g2 = Game.new(H.host):show()
    attic_ops(); click("明信片墙")
    assert(g2:albumView() == "card", "persisted card mode")
    -- 直接改设置后新开是列表
    g2:close()
    H.settings.album_view = "list"
    local g3 = Game.new(H.host):show()
    attic_ops(); click("明信片墙")
    assert(g3:albumView() == "list" and H.view.notes, "new game remembers list setting")
    g3:close()
    H.settings.album_view = nil
end

-- 分享：先落地 PNG 并明确反馈；月读二维码能力保留；失败不可静默。
do
    local Postcard = require("papersprite.ui.postcard")
    local orig_widget = Postcard.widget
    Postcard.widget = function()
        return { getSize = function() return { w = 900, h = 560 } end, paintTo = function() end }
    end
    local names = {
        "ffi/blitbuffer", "libs/libkoreader-lfs", "datastorage",
        "features.remote", "features.remote.screenshot",
        "ui/network/manager", "ui.themes.widgets.qr", "ui/uimanager",
    }
    local saved = {}
    for _, name in ipairs(names) do saved[name] = package.loaded[name] end

    local writes, written_path = {}, nil
    package.loaded["ffi/blitbuffer"] = {
        TYPE_BBRGB32 = 5,
        COLOR_WHITE = 0,
        new = function()
            return {
                fill = function() end,
                free = function() end,
                writeToFile = function(_, path)
                    written_path = path
                    writes[#writes + 1] = path
                    return true
                end,
            }
        end,
    }
    package.loaded["libs/libkoreader-lfs"] = {
        attributes = function() return nil end,
        mkdir = function() return true end,
    }
    package.loaded["datastorage"] = { getDataDir = function() return "/tmp/aye-share-spec" end }

    -- 1) 无月读远程：仍保存并通知路径，不假装只复制正文。
    package.loaded["features.remote"] = nil
    package.loaded["features.remote.screenshot"] = { -- present but we must still notify first; shareUrl missing
        -- no share function: treated as no remote if shareUrl missing and no share()? 
    }
    local notes = {}
    local host = { notify = function(_, m) notes[#notes + 1] = m end }
    local path = Postcard.share({ index = 7, place = "雪镇", line = "hi" }, host)
    assert(path and path:find("aye-postcard-7", 1, true), "export path uses index")
    assert(#notes >= 1 and notes[1]:find("已保存明信片到", 1, true) and notes[1]:find(path, 1, true), "visible save feedback")

    -- 2) 写出失败：可见错误。
    notes = {}
    package.loaded["ffi/blitbuffer"].new = function()
        return { fill = function() end, free = function() end, writeToFile = function() return nil, "disk" end }
    end
    local p2, e2 = Postcard.share({ index = 8 }, host)
    assert(p2 == nil and e2 == "disk")
    assert(#notes == 1 and notes[1]:find("明信片没能存下来", 1, true) and notes[1]:find("disk", 1, true))

    -- 3) 有 shareUrl：保存反馈之后仍走局域网链接并弹出二维码（modal）。
    notes, writes = {}, {}
    package.loaded["ffi/blitbuffer"].new = function()
        return { fill = function() end, free = function() end, writeToFile = function(_, path) writes[#writes+1]=path return true end }
    end
    local remote_calls, qr_shown = 0, 0
    package.loaded["features.remote"] = {
        shareUrl = function(p) remote_calls = remote_calls + 1 return "http://lan.example/file", nil end,
    }
    package.loaded["features.remote.screenshot"] = {
        share = function() error("screenshot.share should not be the only silent path") end,
    }
    package.loaded["ui/network/manager"] = {
        runWhenConnected = function(_, cb) cb() end,
    }
    package.loaded["ui.themes.widgets.qr"] = {
        new = function(_, opts)
            assert(opts.text:find("http://lan.example/file", 1, true))
            qr_shown = qr_shown + 1
            return { modal = true, show = function(self) self.shown = true end }
        end,
    }
    notes = {}
    local p3 = Postcard.share({ index = 9 }, host)
    assert(p3 and #notes >= 1 and notes[1]:find("已保存明信片到", 1, true))
    assert(remote_calls == 1 and qr_shown == 1, "LAN QR still used after save feedback")

    -- 4) shareUrl 失败：必须通知，不能静默。
    package.loaded["features.remote"].shareUrl = function() return nil, "remote down" end
    notes, qr_shown = {}, 0
    Postcard.share({ index = 10 }, host)
    assert(notes[1] and notes[1]:find("已保存明信片到", 1, true), "save feedback remains")
    local saw_fail
    for _, m in ipairs(notes) do if m:find("分享没成功", 1, true) and m:find("remote down", 1, true) then saw_fail = true end end
    assert(saw_fail, "remote failure is visible")
    assert(qr_shown == 0)

    -- 5) 邮戳位置确定，不随调用抖动。
    local a1, b1 = Postcard._stampAnchor({ index = 3, place = "雪镇" })
    local a2, b2 = Postcard._stampAnchor({ index = 3, place = "雪镇" })
    local a3, b3 = Postcard._stampAnchor({ index = 4, place = "雪镇" })
    assert(a1 == a2 and b1 == b2, "stamp anchor is stable")
    assert(a1 ~= a3 or b1 ~= b3, "different cards can differ")

    Postcard.widget = orig_widget
    for _, name in ipairs(names) do package.loaded[name] = saved[name] end
end

do -- 显色：按设备分三种，判定与取色都集中在 ui/display；合成缓存键含模式。
    local names = { "device", "papersprite.ui.display", "papersprite.ui.compose", "ffi/blitbuffer" }
    local saved = {}
    for _, name in ipairs(names) do saved[name] = package.loaded[name] end

    local function loadDisplay()
        package.loaded["papersprite.ui.display"] = nil
        return require("papersprite.ui.display")
    end

    package.loaded["device"] = nil
    local D = loadDisplay()
    assert(D.mode() == "mono" and not D.isColor(), "no device is mono")

    local function install(dev)
        package.loaded["device"] = dev
        D = loadDisplay()
        return D
    end

    D = install({
        hasColorScreen = function() return false end,
        hasEinkScreen = function() return true end,
        screen = { isColorEnabled = function() return true end },
    })
    assert(D.mode() == "mono", "bw eink is mono even if color_rendering is on")

    D = install({
        hasColorScreen = function() return true end,
        hasEinkScreen = function() return true end,
        screen = { isColorEnabled = function() return true end },
    })
    assert(D.mode() == "eink_color", "color eink (Colorsoft / Kaleido) is eink_color")

    D = install({
        hasColorScreen = function() return true end,
        hasEinkScreen = function() return true end,
        screen = { isColorEnabled = function() return false end },
    })
    assert(D.mode() == "mono", "user disabling color rendering forces mono")

    D = install({
        hasColorScreen = function() return true end,
        hasEinkScreen = function() return false end,
        screen = { isColorEnabled = function() return true end },
    })
    assert(D.mode() == "lcd", "color LCD / emulator is lcd")

    package.loaded["ffi/blitbuffer"] = { TYPE_BB8 = 1, TYPE_BBRGB32 = 5 }
    D.setMode("mono")
    assert(D.bufferType() == 1)
    D.setMode("eink_color")
    assert(D.bufferType() == 5)
    D.setMode("lcd")
    assert(D.bufferType() == 5)

    -- 运行时黑白：对比度 1.40 后 3 级灰 {0, 0xAA, 0xFF}，Bayer 矩阵未改。
    -- 彩色源资产与 process_art 默认出图不变；--gray 仍是旧 4 级对照路径。
    local levels = { [0] = true, [0xAA] = true, [0xFF] = true }
    for luma = 0, 255, 17 do
        for y = 0, 3 do
            for x = 0, 3 do
                local g = D.quantizeGray(luma, x, y)
                assert(levels[g], "quantizeGray left the 3-level palette")
                assert(g ~= 0x55, "mono policy no longer uses the muddy #555 rung")
            end
        end
    end
    assert(D.quantizeGray(255, 0, 0) == 255)
    assert(D.quantizeGray(0, 0, 0) == 0)
    -- 浅色纸身 / 雪应落在白；细线 / 墨点应落在黑，不随 Bayer 相位被抹掉或弄脏。
    for _, luma in ipairs({ 230, 240, 245, 250, 255 }) do
        for y = 0, 3 do
            for x = 0, 3 do
                assert(D.quantizeGray(luma, x, y) == 255, "light paper/snow stays white")
            end
        end
    end
    for _, luma in ipairs({ 0, 8, 16, 24 }) do
        for y = 0, 3 do
            for x = 0, 3 do
                assert(D.quantizeGray(luma, x, y) == 0, "ink and thin dark lines stay black")
            end
        end
    end
    -- 对比度后靠近 0xAA/0xFF 边界的中亮灰，Bayer 相位应当仍有变化。
    local mid = {}
    for y = 0, 3 do
        for x = 0, 3 do mid[#mid + 1] = D.quantizeGray(173, x, y) end
    end
    local seen = {}
    for _, g in ipairs(mid) do seen[g] = true end
    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    assert(n >= 2, "ordered dither should vary across the Bayer cell")

    -- apply：LCD 空操作；Lua 回退保持 alpha、不写坏 padding；旋转则走 fallback。
    local Color8 = function(a) return { a = a } end
    local ColorRGB32 = function(r, g, b, a) return { r = r, g = g, b = b, alpha = a, getR = function(self) return self.r end, getG = function(self) return self.g end, getB = function(self) return self.b end, getAlpha = function(self) return self.alpha end } end
    package.loaded["ffi/blitbuffer"] = {
        TYPE_BB8 = 1,
        TYPE_BBRGB32 = 5,
        Color8 = Color8,
        ColorRGB32 = ColorRGB32,
    }

    local function fakeRGB32(w, h, stride, pixels)
        -- pixels[y*w+x+1] = {r,g,b,a}; stride is in bytes, may exceed w*4
        stride = stride or (w * 4)
        local data = {}
        for i = 1, stride * h do data[i] = 0xEE end
        for y = 0, h - 1 do
            for x = 0, w - 1 do
                local px = pixels[y * w + x + 1]
                local o = y * stride + x * 4
                data[o + 1], data[o + 2], data[o + 3], data[o + 4] = px[1], px[2], px[3], px[4]
            end
        end
        local bb = {
            w = w, h = h, stride = stride, pixel_stride = w,
            getType = function() return 5 end,
            getRotation = function() return 0 end,
            getInverse = function() return 0 end,
            getPixel = function(_, x, y)
                local o = y * stride + x * 4
                return { getColorRGB32 = function() return ColorRGB32(data[o + 1], data[o + 2], data[o + 3], data[o + 4]) end }
            end,
            setPixel = function(_, x, y, c)
                local o = y * stride + x * 4
                data[o + 1], data[o + 2], data[o + 3], data[o + 4] = c.r, c.g, c.b, c.alpha
            end,
            _data = data,
        }
        return bb
    end

    local function fakeBB8(w, h, stride, pixels)
        stride = stride or w
        local data = {}
        for i = 1, stride * h do data[i] = 0xEE end
        for y = 0, h - 1 do
            for x = 0, w - 1 do
                data[y * stride + x + 1] = pixels[y * w + x + 1]
            end
        end
        local bb = {
            w = w, h = h, stride = stride, pixel_stride = w,
            getType = function() return 1 end,
            getRotation = function() return 0 end,
            getInverse = function() return 0 end,
            getPixel = function(_, x, y)
                local a = data[y * stride + x + 1]
                return { getColor8 = function() return { a = a } end }
            end,
            setPixel = function(_, x, y, c)
                data[y * stride + x + 1] = c.a
            end,
            _data = data,
        }
        return bb
    end

    -- 无 cdata 的假缓冲不能走 FFI，应自动 fallback。
    D.setMode("lcd")
    local lcd_bb = fakeRGB32(2, 1, 12, { { 10, 20, 30, 40 }, { 50, 60, 70, 80 } })
    D.apply(lcd_bb)
    local d = lcd_bb._data
    assert(d[1] == 10 and d[2] == 20 and d[3] == 30 and d[4] == 40, "LCD apply is a no-op")
    assert(d[5] == 50 and d[8] == 80)
    assert(d[9] == 0xEE and d[12] == 0xEE, "LCD leaves stride padding alone")

    D.setMode("eink_color")
    D.fast_path = false
    local src = {
        { 255, 0, 0, 0 },
        { 40, 200, 40, 1 },
        { 10, 20, 30, 128 },
        { 200, 180, 60, 255 },
    }
    local color_bb = fakeRGB32(2, 2, 12, src) -- stride 12 > 8
    D.apply(color_bb)
    for y = 0, 1 do
        for x = 0, 1 do
            local o = y * 12 + x * 4
            local px = src[y * 2 + x + 1]
            local er, eg, eb = D.einkColor(px[1], px[2], px[3], x, y)
            assert(color_bb._data[o + 1] == er and color_bb._data[o + 2] == eg and color_bb._data[o + 3] == eb,
                "eink_color Lua path matches einkColor")
            assert(color_bb._data[o + 4] == px[4], "eink_color preserves alpha, including 0")
        end
        -- padding bytes 8..11 of each row
        for p = 8, 11 do
            assert(color_bb._data[y * 12 + p + 1] == 0xEE, "eink_color does not write stride padding")
        end
    end

    D.setMode("mono")
    local gray_src = { 0, 24, 173, 230, 245, 128, 40, 255 }
    local gray_bb = fakeBB8(4, 2, 6, gray_src) -- stride 6 > 4
    D.apply(gray_bb)
    for y = 0, 1 do
        for x = 0, 3 do
            local want = D.quantizeGray(gray_src[y * 4 + x + 1], x, y)
            assert(gray_bb._data[y * 6 + x + 1] == want, "mono Lua path matches quantizeGray")
        end
        assert(gray_bb._data[y * 6 + 4 + 1] == 0xEE and gray_bb._data[y * 6 + 5 + 1] == 0xEE,
            "mono does not write stride padding")
    end

    -- 旋转缓冲不得被判为快路径。
    D.fast_path = true
    local rotated = fakeRGB32(2, 1, 8, { { 1, 2, 3, 4 }, { 5, 6, 7, 8 } })
    rotated.getRotation = function() return 1 end
    assert(D._fastKind(rotated) == nil, "rotated buffer falls back")
    local inverted = fakeRGB32(2, 1, 8, { { 1, 2, 3, 4 }, { 5, 6, 7, 8 } })
    inverted.getInverse = function() return 1 end
    assert(D._fastKind(inverted) == nil, "inverted buffer falls back")
    local tight = fakeRGB32(2, 1, 8, { { 1, 2, 3, 4 }, { 5, 6, 7, 8 } })
    tight.stride = 7
    assert(D._fastKind(tight) == nil, "stride shorter than width*bpp is rejected")
    local weird = fakeRGB32(2, 1, 8, { { 1, 2, 3, 4 }, { 5, 6, 7, 8 } })
    weird.getType = function() return 4 end -- TYPE_BBRGB24
    assert(D._fastKind(weird) == nil, "unknown buffer type falls back")
    -- 假缓冲没有 cdata data，快路径条件不成立（无 data 指针）或 applyFast 失败后回退。
    local nodata = fakeRGB32(2, 1, 8, { { 1, 2, 3, 4 }, { 5, 6, 7, 8 } })
    assert(D._fastKind(nodata) == nil, "buffer without raw data pointer is not a fast path")

    D.fast_path = true

    -- 彩色墨水屏只做轻微色域适配：比原色稍收一点，但红色 / 绿色仍须一眼能认出。
    local r, g, b = D.einkColor(255, 0, 0, 0, 0)
    assert(r < 255 and g > 0 and b > 0, "eink_color slightly desaturates a hot red")
    assert(math.abs(r - g) < math.abs(255 - 0), "chroma is reduced a little")
    assert(r > 200 and (r - g) > 80, "eink_color keeps a clearly red hue")
    local r2, g2, b2 = D.einkColor(40, 200, 40, 1, 0)
    local sat1 = math.abs(r - g) + math.abs(g - b)
    local satG = math.abs(r2 - g2) + math.abs(g2 - b2)
    assert(sat1 < 500 and satG < 500, "eink_color stays off the most extreme primaries")
    assert(g2 > 140 and g2 > r2 and g2 > b2, "eink_color keeps a clearly green hue")

    -- 合成缓存键必须带上显色模式，避免灰图 / 彩图串台。
    package.loaded["papersprite.ui.compose"] = nil
    local Compose = require("papersprite.ui.compose")
    D.setMode("mono")
    local k_mono = Compose._key("icon:items/x.png", 64, 64)
    D.setMode("lcd")
    local k_lcd = Compose._key("icon:items/x.png", 64, 64)
    D.setMode("eink_color")
    local k_eink = Compose._key("icon:items/x.png", 64, 64)
    assert(k_mono:find(":mono", 1, true) and k_lcd:find(":lcd", 1, true) and k_eink:find(":eink_color", 1, true))
    assert(k_mono ~= k_lcd and k_lcd ~= k_eink and k_mono ~= k_eink, "cache keys differ by display mode")

    D.reset()
    for _, name in ipairs(names) do package.loaded[name] = saved[name] end
end

do -- db.transaction 嵌套：同一连接不能再 BEGIN，内层必须走 SAVEPOINT（读书墙批量写里会记近况）
    unpack = unpack or table.unpack
    local sqls = {}
    local saved_db, saved_conn = package.loaded["papersprite.core.db"], package.preload["lua-ljsqlite3/init"]
    local Storage = require("papersprite.core.storage")
    local saved_deps = { mkdirp = Storage.deps.mkdirp, dataDir = Storage.deps.dataDir }
    Storage.deps.mkdirp, Storage.deps.dataDir = function() end, function() return "/tmp" end
    package.preload["lua-ljsqlite3/init"] = function()
        return { open = function()
            local conn = {}
            function conn:exec() end
            function conn:prepare(sql)
                return { bind = function() end, close = function() end,
                    step = function() sqls[#sqls + 1] = sql end }
            end
            return conn
        end }
    end
    package.loaded["papersprite.core.db"] = nil
    local DB = require("papersprite.core.db")
    DB.exec("SELECT 1;") -- 先打开连接（含一次性 dedupe 事务），再只看嵌套事务的语句
    sqls = {}
    assert(DB.transaction(function()
        assert(DB.transaction(function() return true end))
        return true
    end))
    assert(table.concat(sqls, "|") == "BEGIN IMMEDIATE;|SAVEPOINT sp1;|RELEASE SAVEPOINT sp1;|COMMIT;", table.concat(sqls, "|"))
    sqls = {}
    assert(DB.transaction(function()
        assert(DB.transaction(function() return nil end) == nil)
        return true
    end))
    assert(table.concat(sqls, "|"):find("ROLLBACK TO SAVEPOINT sp1;|RELEASE SAVEPOINT sp1;", 1, true)
        and sqls[#sqls] == "COMMIT;", "inner failure rolls back only the savepoint")
    package.loaded["papersprite.core.db"], package.preload["lua-ljsqlite3/init"] = saved_db, saved_conn
    Storage.deps.mkdirp, Storage.deps.dataDir = saved_deps.mkdirp, saved_deps.dataDir
end
