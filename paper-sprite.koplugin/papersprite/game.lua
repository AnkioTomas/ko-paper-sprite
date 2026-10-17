-- SPDX-License-Identifier: MIT
--[[--
阁楼游戏控制器：读存档 → 按真实时间结算 →（可选）AI 文案请求 → 生成 view 交给 host 显示。
界面开着时只在「下一件事」到点时安排一次刷新（最长 60 秒一次），关掉即停。
页面：attic 阁楼 / basket 收拾行囊 / shop 小铺 / wall 明信片墙 / card 单张 / cabinet 特产柜
view.scene = { bg, overlays = { {img, x, y, h} } }：分层画面（x/y 为中心点占比，h 为高度占比）
view.icons = { 资源路径... }：一行小图标
--]]
local State = require("papersprite.core.state")
local Travel = require("papersprite.core.travel")
local Story = require("papersprite.core.story")
local Items = require("papersprite.data.items")
local Postcards = require("papersprite.data.postcards")

local Game = {}
Game.__index = Game

local SLOT_NAME = { food = "干粮", charm = "护身物", book = "随身小书" }
local unpack = unpack or table.unpack

function Game.new(host)
    -- 同一时刻只留一个阁楼实例（菜单和月读卡片都能打开）
    if Game.current and not Game.current.closed then Game.current:close() end
    local self = setmetatable({ host = host, page = "attic", wall_page = 1 }, Game)
    self.debug = host:getSetting("debug_fast", false)
    self.state = State.load(host:loadState(), host:now())
    Game.current = self
    return self
end

function Game:save() self.host:saveState(self.state) end

function Game:tick()
    -- 以落盘的为准（首页卡片 / AI 回调 / 其他入口可能改过）
    self.state = State.load(self.host:loadState() or self.state, self.host:now())
    local ok, Reading = pcall(require, "papersprite.core.reading")
    if ok then pcall(Reading.collect, self.state) end
    local ev = Travel.settle(self.state, self.host:now(), self.debug)
    self:save()
    Story.maybeRequest(self.host, self.state, function(cur)
        if self.closed then return end
        self.state = cur
    end)
    self:save()
    return ev
end

function Game:show()
    self:tick()
    self:render()
    return self
end

function Game:close()
    self.closed = true
    if self.timer then self.host:unschedule(self.timer) self.timer = nil end
    self.host:closeScreen()
end

function Game:_arm()
    if self.timer then self.host:unschedule(self.timer) self.timer = nil end
    if self.closed then return end
    local at = Travel.nextAt(self.state)
    if not at then return end
    local wait = math.max(1, math.min(60, at - self.host:now()))
    self.timer = function()
        self.timer = nil
        if self.closed then return end
        self:tick()
        self:render()
    end
    self.host:schedule(wait, self.timer)
end

local function fmtDur(sec, debug)
    if debug then return sec .. " 秒" end
    if sec >= 3600 then return math.floor(sec / 3600) .. " 小时" end
    return math.max(1, math.floor(sec / 60)) .. " 分钟"
end

function Game:go(page, arg)
    -- 进明信片墙时记下「上次看到哪」，这一趟翻页 / 切视图 / 看单张回来，「新」角标都还在
    if page == "wall" and self.page ~= "wall" and self.page ~= "card" then self._wall_seen0 = self.state.wall_seen or 0 end
    self.page, self.arg = page, arg
    self:render()
end

local VISITOR_POS = { -- 访客在阁楼图里的位置（中心占比 x, y, 高）；书桌面约 y=.55，地板约 y=.85
    inkbug = { 0.34, 0.51, 0.08 }, clip_snail = { 0.55, 0.88, 0.10 },
    lampfly = { 0.62, 0.30, 0.12 }, stamp_turtle = { 0.62, 0.86, 0.16 },
    eraser_rabbit = { 0.52, 0.85, 0.14 }, pin_hedgehog = { 0.68, 0.88, 0.12 },
    page_fish = { 0.55, 0.22, 0.14 }, ink_octopus = { 0.33, 0.50, 0.10 },
    tape_caterpillar = { 0.58, 0.90, 0.10 }, shaving_bird = { 0.50, 0.18, 0.12 },
    staple_crab = { 0.62, 0.90, 0.10 }, seal_bear = { 0.60, 0.84, 0.20 },
}
--- 阁楼里摆特产的 4 个位置（右墙矮架：架顶两处 + 中层两格）
Game.DECOR_POS = { { 0.83, 0.50, 0.11 }, { 0.93, 0.50, 0.11 }, { 0.85, 0.69, 0.09 }, { 0.94, 0.69, 0.09 } }
Game.DECOR_MAX = #Game.DECOR_POS

--- 按时刻和季节挑阁楼背景：夜里（21 点后、6 点前）用 night，否则按月份四季
function Game.atticBg(t, away)
    local d = os.date("*t", t)
    local v
    if d.hour >= 21 or d.hour < 6 then v = "night"
    elseif d.month >= 3 and d.month <= 5 then v = "spring"
    elseif d.month >= 6 and d.month <= 8 then v = "summer"
    elseif d.month >= 9 and d.month <= 11 then v = "autumn"
    else v = "winter" end
    return "attic/attic_" .. v .. (away and "_empty" or "") .. ".png"
end

--- 纯函数：阁楼画面（季节/夜晚背景、在家/出门、装饰、访客）。首页组件也用它。
function Game.atticScene(s, now)
    local sp = s.sprite
    local scene = { bg = Game.atticBg(now, sp.status == "away"), overlays = {} }
    for i, id in ipairs(s.decor or {}) do
        local pos = Game.DECOR_POS[i]
        if pos and Postcards.souvenirs[id] then
            scene.overlays[#scene.overlays + 1] = { img = "souvenirs/" .. id .. ".png", x = pos[1], y = pos[2], h = pos[3] }
        end
    end
    if s.visitor then
        local v = Travel.visitor(s.visitor.id)
        if v then
            local pos = VISITOR_POS[v.id] or { 0.5, 0.6, 0.12 }
            scene.overlays[#scene.overlays + 1] = { img = "visitors/" .. v.id .. (s.visitor.pose or "") .. ".png", x = pos[1], y = pos[2], h = pos[3] }
        end
    end
    return scene
end

function Game:_attic()
    local s, now = self.state, self.host:now()
    local sp = s.sprite
    local scene = Game.atticScene(s, now)
    local st = { icon = "sprite/carry.png" }
    if sp.status == "home" then
        st.title, st.caption = "阿页在家", "坐在书桌边，油灯亮着。收拾好行囊，它就会出门。"
    elseif sp.status == "packed" then
        st.title, st.caption = "快要出门了", "藤筐收拾好了，阿页在窗边发呆。"
    else
        local p = sp.place and Travel.place(sp.place)
        st.title = "阿页在路上 · 已出门 " .. fmtDur(now - sp.left_at, self.debug)
        st.caption = "书桌上压着一张纸条：「" .. (s.note or "") .. "」"
        st.icon = nil
        if p then st.title = st.title end
    end
    local unseen = #s.postcards - (s.wall_seen or 0)
    st.meta = "灵感 ✦ " .. s.inspiration .. "　·　明信片 " .. #s.postcards .. (unseen > 0 and ("（新 " .. unseen .. "）") or "")
    local ids = {}
    for id in pairs(s.souvenirs or {}) do if Postcards.souvenirs[id] then ids[#ids + 1] = id end end
    table.sort(ids)
    local last = s.postcards[#s.postcards]
    local cells = {
        { icon = "sprite/carry.png", title = "收拾行囊", meta = sp.status == "away" and "阿页在路上" or (sp.status == "packed" and "已收拾好" or "还没收拾"),
          caption = "干粮 · 护身物 · 随身小书", dim = sp.status == "away",
          callback = function() if sp.status == "away" then self.host:notify("阿页还在路上") else self:go("basket") end end },
        { icon = "items/paper_umbrella.png", title = "小铺", meta = "灵感 ✦ " .. s.inspiration, caption = "用灵感换行囊里的东西",
          callback = function() self:go("shop") end },
        { scene = last and Game.cardScene(last), icon = (not last) and "sprite/carry.png" or nil, title = "明信片墙",
          meta = #s.postcards .. " 张" .. (unseen > 0 and ("　新 " .. unseen) or ""), badge = unseen > 0 and "新" or nil,
          caption = last and ("最近：" .. ((Travel.place(last.place) or {}).name or "")) or "还没有寄回来的",
          callback = function() self.wall_page = 1 self:go("wall") end },
        { icon = ids[1] and ("souvenirs/" .. ids[1] .. ".png") or "sprite/carry.png", title = "特产柜",
          meta = #ids .. " / " .. Game.souvenirTotal() .. " 种", caption = "摆在阁楼 " .. #(s.decor or {}) .. " / " .. Game.DECOR_MAX,
          callback = function() self:go("cabinet") end },
    }
    -- 第 1 页：画面 + 状态 + 入口；第 2 页起：来客 + 最近（每页条数按高度自适应）
    local per = self:per("attic_log", 6)
    local logs = {}
    local log_at = s.log_at or {}
    for i = #s.log, 1, -1 do logs[#logs + 1] = { text = s.log[i], at = log_at[i] } end
    local lead = self:per("attic_lead", 2)
    local c2 = math.max(1, per - lead)   -- 第 2 页有来客卡，少放几条
    local log_pages = 1 + math.ceil(math.max(0, #logs - c2) / per)
    local pages = 1 + log_pages
    local page = math.max(1, math.min(self.attic_page or 1, pages))
    self.attic_page = page
    local pager = { page = page, pages = pages, go = function(n) self.attic_page = n self:render() end,
        prev = function() self.attic_page = page - 1 self:render() end, next = function() self.attic_page = page + 1 self:render() end }
    if page == 1 then
        return { title = "阿页的阁楼", scene = scene, status = st, shelf = { cols = 4, icon = 48, compact = true, cells = cells }, pager = pager }
    end
    local v = { title = "阿页的阁楼", pager = pager, lines = {} }
    if page == 2 then
        local vis = s.visitor and Travel.visitor(s.visitor.id)
        if vis then
            v.status = { icon = "visitors/" .. vis.id .. (s.visitor.pose or "") .. ".png", icon_size = 72, title = "来客 · " .. vis.name,
                caption = s.visitor.line or vis.here, meta = "还会待一会儿" }
        else
            v.status = { icon = "sprite/carry.png", title = "今天没有客人", caption = "小客人会在阿页回家后来串门。" }
        end
    end
    local first = page == 2 and 1 or (c2 + (page - 3) * per + 1)
    local cnt = page == 2 and c2 or per
    v.lines[1] = { text = "最近" .. (#logs > 0 and ("（" .. math.min(#logs, first) .. "–" .. math.min(#logs, first + cnt - 1) .. " / " .. #logs .. "）") or ""), label = true }
    if #logs == 0 then v.empty = { title = "还没有什么新鲜事", caption = "阿页出门、回家、来客都会记在这里。" } end
    local rows = {}
    for i = first, math.min(#logs, first + cnt - 1) do rows[#rows + 1] = { text = logs[i].text, meta = Game.when(logs[i].at, now) } end
    v.notes = { rows = rows, per = per, lead = lead, fit = function(full, ld)
        self.per_page = self.per_page or {}
        if self.closed or (self.per_page.attic_log == full and self.per_page.attic_lead == ld) then return end
        self.per_page.attic_log, self.per_page.attic_lead = full, ld
        self:render()
    end }
    return v
end

function Game.souvenirTotal()
    local n = 0
    for _ in pairs(Postcards.souvenirs) do n = n + 1 end
    return n
end

function Game:_basket()
    local s = self.state
    local slot = self.basket_slot or "food"
    local filled = 0
    local cells = {}
    for _, sl in ipairs(Travel.SLOTS) do
        local cur = s.basket[sl] and Travel.item(s.basket[sl])
        if cur then filled = filled + 1 end
        cells[#cells + 1] = { icon = cur and ("items/" .. cur.id .. ".png") or "sprite/carry.png", title = SLOT_NAME[sl],
            meta = cur and cur.name or "（空）", caption = cur and (Game.itemEffect(cur)) or "点这里挑一样", check = sl == slot,
            callback = function() self.basket_slot = sl self.basket_page = 1 self:render() end }
    end
    local st = { icon = "sprite/carry.png", title = "藤筐 " .. filled .. " / 3",
        caption = s.sprite.status == "packed" and "收拾好了，阿页过一会儿就出门。" or "三格都放好，阿页就会出门。",
        meta = "带的东西决定它爱去哪儿、走多久" }
    -- 当前格可放的物品（有存货的 + 常备）
    local list = {}
    for _, it in ipairs(Items) do
        if it.slot == slot and Travel.count(s, it.id) > 0 then list[#list + 1] = it end
    end
    local per = self:per("basket", 6)
    local pages = math.max(1, math.ceil(#list / per))
    local page = math.max(1, math.min(self.basket_page or 1, pages))
    self.basket_page = page
    local picks = {}
    for i = (page - 1) * per + 1, math.min(#list, page * per) do
        local it = list[i]
        local n = Travel.count(s, it.id)
        picks[#picks + 1] = { icon = "items/" .. it.id .. ".png", title = it.name, check = s.basket[slot] == it.id,
            meta = n == math.huge and "常备" or ("有 " .. n), caption = (Game.itemEffect(it)),
            callback = function()
                Travel.put(s, it.id, self.host:now(), self.debug)
                -- 放好后自动跳到下一个空格
                for _, sl in ipairs(Travel.SLOTS) do if not s.basket[sl] then self.basket_slot, self.basket_page = sl, 1 break end end
                self:save()
                self:render()
            end }
    end
    -- 两组卡片：三格 + 可选物品；用 lines 标签分隔
    return { title = "收拾行囊", status = st,
        shelf = { cols = 3, icon = 48, compact = true, cells = cells },
        lines2 = { { text = "放进「" .. SLOT_NAME[slot] .. "」", label = true } },
        shelf2 = { cols = 2, cells = picks, per = per, fit = self:fitter("basket") },
        empty2 = #picks == 0 and { title = "这一格没有可放的东西", caption = "去小铺看看" } or nil,
        pager = { page = page, pages = pages, go = function(n) self.basket_page = n self:render() end, prev = function() self.basket_page = page - 1 self:render() end,
            next = function() self.basket_page = page + 1 self:render() end } }
end

Game.SHOP_COLS, Game.SHOP_ROWS = 2, 3
Game.SHOP_TABS = { { id = "all", name = "全部" }, { id = "food", name = "干粮" }, { id = "charm", name = "护身物" }, { id = "book", name = "随身小书" } }
local TAG_NAME = { water = "水边", forest = "森林", market = "集市", indoor = "屋里", town = "小镇", travel = "车站", snow = "雪地",
    sky = "天上", mountain = "山里", desert = "沙丘", sea = "海边", garden = "花园", night = "夜里", underground = "地下" }
Game.TAG_NAME = TAG_NAME

--- 纯函数：由数据算出物品的实际效果（tags 让目的地更偏向这些地方；hours_bias 加减旅程小时）
function Game.itemEffect(it)
    local places = {}
    for _, t in ipairs(it.tags or {}) do places[#places + 1] = TAG_NAME[t] or t end
    local h = it.hours_bias or 0
    local short = "爱去" .. table.concat(places, "·")
    if h > 0 then short = short .. " · 旅程+" .. h .. "时" elseif h < 0 then short = short .. " · 旅程" .. h .. "时" end
    local long = { "放进藤筐后，阿页更常去" .. table.concat(places, "、") .. "的地方。" }
    if h > 0 then long[#long + 1] = "旅程平均长 " .. h .. " 小时，回家得晚一些。"
    elseif h < 0 then long[#long + 1] = "旅程平均短 " .. (-h) .. " 小时，早点回家。"
    else long[#long + 1] = "不影响旅程长短。" end
    long[#long + 1] = it.price == 0 and "常备物品，不会用完。" or "出门时带走一个，用掉就没了。"
    return short, long
end

--- 纯函数：小铺某一页（只列可买的；tab = all|food|charm|book）
function Game.shopPage(tab, page, per_override)
    local list = {}
    for _, it in ipairs(Items) do
        if it.price > 0 and (tab == nil or tab == "all" or it.slot == tab) then list[#list + 1] = it end
    end
    local per = per_override or Game.SHOP_COLS * Game.SHOP_ROWS
    local pages = math.max(1, math.ceil(#list / per))
    page = math.max(1, math.min(page or 1, pages))
    local out = {}
    for i = (page - 1) * per + 1, math.min(#list, page * per) do out[#out + 1] = list[i] end
    return out, page, pages, #list
end

function Game:_buy(it)
    local s = self.state
    if s.inspiration < it.price then self.host:notify("灵感不够") return end
    s.inspiration = s.inspiration - it.price
    s.inventory[it.id] = (s.inventory[it.id] or 0) + 1
    self:save()
    self.host:notify("买下了" .. it.name)
    self:render()
end

function Game:_shop()
    local s = self.state
    local tab = self.shop_tab or "all"
    local sper = self:per("shop", Game.SHOP_COLS * Game.SHOP_ROWS)
    local items, page, pages = Game.shopPage(tab, self.shop_page, sper)
    self.shop_page = page
    local cells = {}
    for _, it in ipairs(items) do
        local short = Game.itemEffect(it)
        cells[#cells + 1] = { icon = "items/" .. it.id .. ".png", name = it.name, price = "✦ " .. it.price,
            owned = "有 " .. (s.inventory[it.id] or 0), desc = short, dim = s.inspiration < it.price,
            callback = function() self:go("shop_item", it.id) end }
    end
    local tabs = {}
    for _, t in ipairs(Game.SHOP_TABS) do
        tabs[#tabs + 1] = { text = t.name, active = t.id == tab, callback = function() self.shop_tab, self.shop_page = t.id, 1 self:render() end }
    end
    return { title = "小铺", status = { icon = "items/paper_clip.png", icon_size = 48, title = "图钉小铺", caption = "老板是一枚不爱说话的图钉。点一件看看。",
            meta = "灵感 ✦ " .. s.inspiration },
        tabs = tabs, shelf = { cols = Game.SHOP_COLS, cells = cells, per = sper, fit = self:fitter("shop") },
        pager = { page = page, pages = pages, go = function(n) self.shop_page = n self:render() end,
            prev = function() self.shop_page = page - 1 self:render() end, next = function() self.shop_page = page + 1 self:render() end },
        buttons = {} }
end

function Game:_shop_item()
    local s = self.state
    local it = Travel.item(self.arg)
    if not it then self.page = "shop" return self:_shop() end
    local _, long = Game.itemEffect(it)
    local lines = { { text = "效果", label = true } }
    for _, l in ipairs(long) do lines[#lines + 1] = "· " .. l end
    return { title = it.name, status = { icon = "items/" .. it.id .. ".png", icon_size = 96, title = it.name, caption = it.desc or "",
            meta = "✦ " .. it.price .. "　·　已有 " .. (s.inventory[it.id] or 0) .. "　·　灵感 ✦ " .. s.inspiration }, lines = lines,
        buttons = { { text = "买一个（✦ " .. it.price .. "）", callback = function() self:_buy(it) end } } }
end

Game.WALL_GRID = { cols = 3, rows = 4 }
Game.WALL_LIST = 4

--- 纯函数：明信片墙的一页。mode = grid（缩略图网格）| list（缩略图 + 文字），新的在前
function Game.wallPage(s, mode, page, per)
    per = per or (mode == "list" and Game.WALL_LIST or Game.WALL_GRID.cols * Game.WALL_GRID.rows)
    local total = #s.postcards
    local pages = math.max(1, math.ceil(total / per))
    page = math.max(1, math.min(page or 1, pages))
    local first = total - (page - 1) * per
    local out = {}
    for i = first, math.max(1, first - per + 1), -1 do out[#out + 1] = i end
    return out, page, pages
end

function Game:_wall()
    local s = self.state
    local seen_before = self._wall_seen0 or s.wall_seen or 0
    if s.wall_seen ~= #s.postcards then s.wall_seen = #s.postcards self:save() end
    local mode = self.host:getSetting("wall_mode", "grid") == "list" and "list" or "grid"
    local wkey = "wall_" .. mode
    local wper = self:per(wkey, mode == "list" and Game.WALL_LIST or Game.WALL_GRID.cols * Game.WALL_GRID.rows)
    local idx, page, pages = Game.wallPage(s, mode, self.wall_page, wper)
    self.wall_page = page
    local v = { title = "明信片墙", lines = {} }
    if #s.postcards == 0 then v.empty = { title = "墙上还空着", caption = "等阿页寄第一张回来。" } 
    else v.lines[1] = { text = #s.postcards .. " 张 · 新的在前" .. ((#s.postcards - seen_before) > 0 and ("　·　新 " .. (#s.postcards - seen_before)) or ""), label = true } end
    local function cardInfo(i)
        local c = s.postcards[i]
        local p = Travel.place(c.place)
        return c, (p and p.name or c.place), (Postcards.weather_names[c.weather] or "")
    end
    if mode == "grid" then
        v.grid = { cols = Game.WALL_GRID.cols, cells = {}, per = wper, fit = self:fitter(wkey) }
        for _, i in ipairs(idx) do
            local c, name = cardInfo(i)
            v.grid.cells[#v.grid.cells + 1] = { scene = Game.cardScene(c), new = i > seen_before, caption = name,
                callback = function() self:go("card", i) end }
        end
    else
        v.list = { rows = {}, per = wper, fit = self:fitter(wkey) }
        for _, i in ipairs(idx) do
            local c, name, wn = cardInfo(i)
            v.list.rows[#v.list.rows + 1] = { scene = Game.cardScene(c), new = i > seen_before, title = name .. " · " .. wn,
                line = c.line or "", date = os.date("%m-%d %H:%M", c.at or 0), callback = function() self:go("card", i) end }
        end
    end
    v.pager = { page = page, pages = pages,
        prev = function() self.wall_page = page - 1 self:render() end,
        next = function() self.wall_page = page + 1 self:render() end,
        go = function(n) self.wall_page = n self:render() end }
    v.switch = { icon = mode == "grid" and "view_list" or "grid_view", text = mode == "grid" and "列表" or "网格", callback = function()
        self.host:setSetting("wall_mode", mode == "grid" and "list" or "grid") self.wall_page = 1 self:render() end }
    return v
end

--- 明信片的分层画面
function Game.cardScene(c)
    local L = Postcards.layers(c)
    local ov = { { img = L.pose, x = 0.42, y = 0.70, h = 0.50 } }
    if L.prop then ov[#ov + 1] = { img = L.prop, x = 0.62, y = 0.80, h = 0.28 } end
    if L.weather then ov[#ov + 1] = { img = L.weather, x = 0.5, y = 0.5, h = 1.0, full = true } end
    return { bg = L.bg, overlays = ov, frame = true }
end

function Game:_card()
    local s = self.state
    local i = self.arg
    local c = s.postcards[i]
    if not c then self.page = "wall" return self:_wall() end
    local p = Travel.place(c.place)
    local n = #s.postcards
    -- 墙上新的在前：「上一张」= 更新的那张
    return {
        title = (p and p.name or c.place),
        scene = Game.cardScene(c),
        status = { title = (p and p.name or c.place) .. " · " .. (Postcards.weather_names[c.weather] or ""), caption = (c.line or "") .. "　——阿页",
            meta = os.date("%Y-%m-%d %H:%M", c.at or 0) .. "　·　第 " .. i .. " / " .. n .. " 张" },
        pager = { page = n - i + 1, pages = n, prev = function() self.arg = i + 1 self:render() end, next = function() self.arg = i - 1 self:render() end,
            go = function(pg) self.arg = n - pg + 1 self:render() end },
    }
end

local function indexOf(t, x) for i, y in ipairs(t) do if y == x then return i end end end

Game.CAB_PER = 6

function Game:_toggleDecor(id)
    local s = self.state
    local i = indexOf(s.decor, id)
    if i then table.remove(s.decor, i)
    elseif #s.decor >= Game.DECOR_MAX then self.host:notify("阁楼摆满了，先收起一样") return
    else s.decor[#s.decor + 1] = id end
    self:save()
    self:render()
end

function Game:_cabinet()
    local s = self.state
    s.decor = s.decor or {}
    local ids = {}
    for id in pairs(s.souvenirs) do if Postcards.souvenirs[id] then ids[#ids + 1] = id end end
    table.sort(ids, function(a, b) return Postcards.souvenirs[a].name < Postcards.souvenirs[b].name end)
    local cper = self:per("cabinet", Game.CAB_PER)
    local pages = math.max(1, math.ceil(#ids / cper))
    local page = math.max(1, math.min(self.cab_page or 1, pages))
    self.cab_page = page
    local cells = {}
    for k = (page - 1) * cper + 1, math.min(#ids, page * cper) do
        local id = ids[k]
        local sv = Postcards.souvenirs[id]
        local on = indexOf(s.decor, id)
        cells[#cells + 1] = { icon = "souvenirs/" .. id .. ".png", title = sv.name, check = on ~= nil,
            meta = "×" .. s.souvenirs[id] .. (on and "　摆在阁楼" or ""), caption = (s.souvenir_notes and s.souvenir_notes[id]) or sv.note,
            callback = function() self:go("souvenir", id) end }
    end
    return { title = "特产柜",
        status = { icon = s.decor[1] and ("souvenirs/" .. s.decor[1] .. ".png") or nil, title = "收集 " .. #ids .. " / " .. Game.souvenirTotal() .. " 种",
            caption = "阿页带回来的东西都在这里。点一件看看，可以摆到阁楼里。", meta = "阁楼里摆了 " .. #s.decor .. " / " .. Game.DECOR_MAX },
        empty = #ids == 0 and { title = "柜子还空着", caption = "每趟旅行回来，阿页都会带一样特产。" } or nil,
        shelf = { cols = 2, cells = cells, per = cper, fit = self:fitter("cabinet") },
        pager = { page = page, pages = pages, go = function(n) self.cab_page = n self:render() end, prev = function() self.cab_page = page - 1 self:render() end,
            next = function() self.cab_page = page + 1 self:render() end } }
end

function Game:_souvenir()
    local s = self.state
    s.decor = s.decor or {}
    local id = self.arg
    local sv = Postcards.souvenirs[id]
    if not sv or not s.souvenirs[id] then self.page = "cabinet" return self:_cabinet() end
    local on = indexOf(s.decor, id)
    return { title = sv.name,
        status = { icon = "souvenirs/" .. id .. ".png", icon_size = 120, title = sv.name, caption = (s.souvenir_notes and s.souvenir_notes[id]) or sv.note,
            meta = "收着 ×" .. s.souvenirs[id] .. "　·　" .. (on and "摆在阁楼里" or "收在柜子里") },
        lines = { { text = "阁楼右墙的矮架上能摆 " .. Game.DECOR_MAX .. " 样，现在摆了 " .. #s.decor .. " 样。", muted = true, small = true } },
        buttons = { { text = on and "从阁楼收起" or "摆到阁楼里", callback = function() self:_toggleDecor(id) end } } }
end

--- 每页数量：默认值，界面按屏幕剩余高度回报实际能放的数量（fit）后记住
function Game:per(key, default) self.per_page = self.per_page or {} return self.per_page[key] or default end
--- 事件时间：1 分钟内「刚刚」，1 小时内「N 分钟前」，当天内「N 小时前」，更早用明信片同款「MM-DD HH:MM」；没时间返回 nil
function Game.when(at, now)
    if not at or at <= 0 then return nil end
    now = now or os.time()
    local d = now - at
    if d < 0 then return os.date("%m-%d %H:%M", at) end
    if d < 60 then return "刚刚" end
    if d < 3600 then return math.floor(d / 60) .. " 分钟前" end
    if d < 86400 then return math.floor(d / 3600) .. " 小时前" end
    return os.date("%m-%d %H:%M", at)
end

function Game:fitter(key, cur)
    return function(n)
        self.per_page = self.per_page or {}
        if self.per_page[key] == n or self.closed then return end
        self.per_page[key] = n
        self:render()
    end
end

Game.PARENT = { basket = "attic", shop = "attic", wall = "attic", cabinet = "attic", shop_item = "shop", card = "wall", souvenir = "cabinet" }

function Game:view()
    if self.page == "basket" and self.state.sprite.status == "away" then self.page, self.attic_page = "attic", 1 end
    local v = self["_" .. self.page](self)
    -- 子页面不再放「回阁楼」按钮：标题栏右上角的按钮就是返回上一级（阁楼页才是关闭）
    local parent = Game.PARENT[self.page]
    if parent then v.back = function() self:go(parent) end end
    v.on_close = function() self.closed = true if self.timer then self.host:unschedule(self.timer) self.timer = nil end end
    return v
end

function Game:render()
    if self.closed then return end
    self.host:showScreen(self:view())
    self:_arm()
end

return Game
