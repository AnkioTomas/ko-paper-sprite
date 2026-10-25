-- SPDX-License-Identifier: MIT
--[[--
阁楼游戏控制器：读存档 → 按真实时间结算 →（可选）AI 文案请求 → 生成 view 交给 host 显示。
界面开着时只在「下一件事」到点时安排一次刷新（最长 60 秒一次），关掉即停。
页面：attic 阁楼 / basket 收拾行囊 / shop 小铺 / wall 明信片墙 / card 单张 / cabinet 特产柜
      / scrapbook 地点剪贴簿 / place 地点页 / guestbook 来客簿 / guest 来客页
view.scene = { bg, overlays = { {img, x, y, h} } }：分层画面（x/y 为中心点占比，h 为高度占比）
view.icons = { 资源路径... }：一行小图标
--]]
local T = require("papersprite.l10n")
local State = require("papersprite.core.state")
local Travel = require("papersprite.core.travel")
local Album = require("papersprite.core.album")
local Story = require("papersprite.core.story")
local Festival = require("papersprite.core.festival")
local Items = require("papersprite.data.items")
local Postcards = require("papersprite.data.postcards")

local Game = {}
Game.__index = Game

local SLOT_NAME = { food = T("干粮"), charm = T("护身物"), book = T("随身小书") }
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
    local function fresh(cur)
        if self.closed then return end
        self.state = cur
        if self.page == "attic" then self:render() end
    end
    Story.maybeRequest(self.host, self.state, function(cur) if not self.closed then self.state = cur end end)
    Story.maybeRecap(self.host, self.state, fresh)
    Story.maybeDaily(self.host, self.state, fresh)
    self:save()
    return ev
end

function Game:show()
    self:tick()
    self:render()
    self:_almanac()
    return self
end

--- 界面出来后再取一次今天的节日 / 节气（一天一次，失败静默）；先让界面上屏，网络慢也不挡着
function Game:_almanac()
    if type(self.host.almanac) ~= "function" or not Festival.needsFetch(self.state, self.host:now()) then return end
    self.host:schedule(2, function()
        if self.closed then return end
        local now = self.host:now()
        local cur = State.load(self.host:loadState() or self.state, now)
        if not Festival.refresh(self.host, cur, now, function(daily)
            cur = State.load(self.host:loadState() or cur, now)
            if not Festival.store(cur, daily, now) then cur.almanac_try = now end
            self.host:saveState(cur)
            if self.closed then return end
            self.state = cur
            self:render()
        end) then return end
        self.host:saveState(cur)
    end)
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

local function dailyKey(now)
    return os.date("%Y-%m-%d", now) .. Story.band(os.date("*t", now).hour)
end

local function fmtDur(sec, debug)
    if debug then return T("%d 秒", sec) end
    if sec >= 3600 then return T("%d 小时", math.floor(sec / 3600)) end
    return T("%d 分钟", math.max(1, math.floor(sec / 60)))
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
Game.FEST_POS = { 0.29, 0.80, 0.16 } -- 节日应景小物摆在左边

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
    local fest = Festival.at(s, now)
    if fest and sp.status ~= "away" then
        scene.overlays[#scene.overlays + 1] = { img = "props/fest_" .. fest.id .. ".png", x = Game.FEST_POS[1], y = Game.FEST_POS[2], h = Game.FEST_POS[3] }
    end
    if s.visitor and sp.status ~= "away" then -- 阿页出门时阁楼是空的，不招待客人
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
    local fest = Festival.at(s, now)
    if sp.status == "home" then
        st.title, st.caption = T("阿页在家"), T("坐在书桌边，油灯亮着。收拾好行囊，它就会出门。")
        local daily = s.daily and s.daily.key == dailyKey(now) and s.daily.text
        if not daily then -- 没有 AI 的纸条：按钟点从本地池里按天稳定地挑一句
            local h = os.date("*t", now).hour
            local pool = require("papersprite.data.notes")[(h >= 5 and h < 9) and "dawn" or (h >= 9 and h < 17) and "day" or (h >= 17 and h < 21) and "dusk" or "night"]
            daily = pool[((tonumber(os.date("%j", now)) or 0) * 31 + math.floor(h / 2)) % #pool + 1]
        end
        st.caption = daily
        if fest then
            local alts = fest.here_alt
            local day = tonumber(os.date("%j", now)) or 0
            st.title = T("阿页在家 · %s", fest.name)
            st.caption = (alts and #alts > 0 and day % (#alts + 1) > 0) and alts[day % (#alts + 1)] or fest.here
        end
    elseif sp.status == "packed" then
        st.title, st.caption = T("快要出门了"), T("藤筐收拾好了，阿页在窗边发呆。")
        if fest then st.title = T("快要出门了 · %s", fest.name) end
    else
        local p = sp.place and Travel.place(sp.place)
        st.title = T("阿页在路上 · 已出门 %s", fmtDur(now - sp.left_at, self.debug))
        st.caption = T("书桌上压着一张纸条：「%s」", s.note or "")
        st.icon = nil
        if p then st.title = st.title end
    end
    local unseen = #s.postcards - (s.wall_seen or 0)
    st.meta = T("灵感 ✦ %d　·　明信片 %d", s.inspiration, #s.postcards) .. (unseen > 0 and T("（新 %d）", unseen) or "")
    local ids = {}
    for id in pairs(s.souvenirs or {}) do if Postcards.souvenirs[id] then ids[#ids + 1] = id end end
    table.sort(ids)
    local last = s.postcards[#s.postcards]
    local _, places_done, places_total = Album.places(s)
    local _, guests_have, guests_total = Album.visitors(s)
    local cells = {
        { icon = "sprite/carry.png", title = T("收拾行囊"), meta = sp.status == "away" and T("阿页在路上") or (sp.status == "packed" and T("已收拾好") or T("还没收拾")),
          caption = T("干粮 · 护身物 · 随身小书"), dim = sp.status == "away",
          callback = function() if sp.status == "away" then self.host:notify(T("阿页还在路上")) else self:go("basket") end end },
        { icon = "items/paper_umbrella.png", title = T("小铺"), meta = T("灵感 ✦ %d", s.inspiration), caption = T("用灵感换行囊里的东西"),
          callback = function() self:go("shop") end },
        { scene = last and Game.cardScene(last), icon = (not last) and "sprite/carry.png" or nil, title = T("明信片墙"),
          meta = T("%d 张", #s.postcards) .. (unseen > 0 and T("　新 %d", unseen) or ""), badge = unseen > 0 and T("新") or nil,
          caption = last and T("最近：%s", (Travel.place(last.place) or {}).name or "") or T("还没有寄回来的"),
          callback = function() self.wall_page = 1 self:go("wall") end },
        { icon = ids[1] and ("souvenirs/" .. ids[1] .. ".png") or "sprite/carry.png", title = T("特产柜"),
          meta = T("%d / %d 种", #ids, Game.souvenirTotal()), caption = T("摆在阁楼 %d / %d", #(s.decor or {}), Game.DECOR_MAX),
          callback = function() self:go("cabinet") end },
        { icon = "items/travel_diary.png", title = T("剪贴簿"), meta = T("%d / %d 页", places_done, places_total),
          caption = T("按地点收齐特产"), callback = function() self.scrap_page = 1 self:go("scrapbook") end },
        { icon = "sprite/peek.png", title = T("来客簿"), meta = T("%d / %d 位", guests_have, guests_total),
          caption = T("来过的小客人"), callback = function() self.guest_page = 1 self:go("guestbook") end },
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
        return { title = T("阿页的阁楼"), scene = scene, status = st, shelf = { cols = 3, icon = 56, compact = true, cells = cells }, pager = pager }
    end
    local v = { title = T("阿页的阁楼"), pager = pager, lines = {} }
    if page == 2 then
        local vis = s.visitor and sp.status ~= "away" and Travel.visitor(s.visitor.id)
        if vis then
            v.status = { icon = "visitors/" .. vis.id .. (s.visitor.pose or "") .. ".png", icon_size = 72, title = T("来客 · %s", vis.name),
                caption = s.visitor.line or vis.here, meta = T("还会待一会儿") }
        else
            v.status = { icon = "sprite/peek.png", title = T("今天没有客人"), caption = T("小客人会在阿页回家后来串门。") }
        end
    end
    local first = page == 2 and 1 or (c2 + (page - 3) * per + 1)
    local cnt = page == 2 and c2 or per
    v.lines[1] = { text = T("最近") .. (#logs > 0 and T("（%d–%d / %d）", math.min(#logs, first), math.min(#logs, first + cnt - 1), #logs) or ""), label = true }
    if #logs == 0 then v.empty = { title = T("还没有什么新鲜事"), caption = T("阿页出门、回家、来客都会记在这里。") } end
    local rows = {}
    for i = first, math.min(#logs, first + cnt - 1) do rows[#rows + 1] = { text = logs[i].text, meta = Game.when(logs[i].at, now) } end
    v.notes = { rows = rows, per = per, lead = lead, fit = function(full, ld)
        self.per_page = self.per_page or {}
        -- 各页最高那张卡不一样，量出来的条数会来回跳（页数 3/5 ↔ 3/7 死循环）；只许往小收，不许回弹
        local cur = self.per_page.attic_log
        if cur and full > cur then full = cur end
        if self.closed or (cur == full and self.per_page.attic_lead == ld) then return end
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
        cells[#cells + 1] = { icon = cur and ("items/" .. cur.id .. ".png") or "props/basket.png", title = SLOT_NAME[sl],
            meta = cur and cur.name or T("（空）"), caption = cur and (Game.itemEffect(cur)) or T("点这里挑一样"), check = sl == slot,
            callback = function() self.basket_slot = sl self.basket_page = 1 self:render() end }
    end
    local st = { icon = "sprite/carry.png", title = T("藤筐 %d / 3", filled),
        caption = s.sprite.status == "packed" and T("收拾好了，阿页过一会儿就出门。") or T("三格都放好，阿页就会出门。"),
        meta = T("带的东西决定它爱去哪儿、走多久") }
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
            meta = n == math.huge and T("常备") or T("有 %d", n), caption = (Game.itemEffect(it)),
            callback = function()
                Travel.put(s, it.id, self.host:now(), self.debug)
                -- 放好后自动跳到下一个空格
                for _, sl in ipairs(Travel.SLOTS) do if not s.basket[sl] then self.basket_slot, self.basket_page = sl, 1 break end end
                self:save()
                self:render()
            end }
    end
    -- 两组卡片：三格 + 可选物品；用 lines 标签分隔
    return { title = T("收拾行囊"), status = st,
        shelf = { cols = 3, icon = 48, compact = true, cells = cells },
        lines2 = { { text = T("放进「%s」", SLOT_NAME[slot]), label = true } },
        shelf2 = { cols = 2, cells = picks, per = per, fit = self:fitter("basket") },
        empty2 = #picks == 0 and { title = T("这一格没有可放的东西"), caption = T("去小铺看看") } or nil,
        pager = { page = page, pages = pages, go = function(n) self.basket_page = n self:render() end, prev = function() self.basket_page = page - 1 self:render() end,
            next = function() self.basket_page = page + 1 self:render() end } }
end

Game.SHOP_COLS, Game.SHOP_ROWS = 2, 3
Game.SHOP_TABS = { { id = "all", name = T("全部") }, { id = "food", name = T("干粮") }, { id = "charm", name = T("护身物") }, { id = "book", name = T("随身小书") } }
local TAG_NAME = { water = T("水边"), forest = T("森林"), market = T("集市"), indoor = T("屋里"), town = T("小镇"), travel = T("车站"), snow = T("雪地"),
    sky = T("天上"), mountain = T("山里"), desert = T("沙丘"), sea = T("海边"), garden = T("花园"), night = T("夜里"), underground = T("地下") }
Game.TAG_NAME = TAG_NAME

--- 纯函数：由数据算出物品的实际效果（tags 让目的地更偏向这些地方；hours_bias 加减旅程小时）
function Game.itemEffect(it)
    local places = {}
    for _, t in ipairs(it.tags or {}) do places[#places + 1] = TAG_NAME[t] or t end
    local h = it.hours_bias or 0
    local short = T("爱去%s", table.concat(places, "·"))
    if h > 0 then short = short .. T(" · 旅程+%d时", h) elseif h < 0 then short = short .. T(" · 旅程%d时", h) end
    local long = { T("放进藤筐后，阿页更常去%s的地方。", table.concat(places, T("、"))) }
    if h > 0 then long[#long + 1] = T("旅程平均长 %d 小时，回家得晚一些。", h)
    elseif h < 0 then long[#long + 1] = T("旅程平均短 %d 小时，早点回家。", -h)
    else long[#long + 1] = T("不影响旅程长短。") end
    long[#long + 1] = it.price == 0 and T("常备物品，不会用完。") or T("出门时带走一个，用掉就没了。")
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
    if s.inspiration < it.price then self.host:notify(T("灵感不够")) return end
    s.inspiration = s.inspiration - it.price
    s.inventory[it.id] = (s.inventory[it.id] or 0) + 1
    self:save()
    self.host:notify(T("买下了%s", it.name))
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
            owned = T("有 %d", s.inventory[it.id] or 0), desc = short, dim = s.inspiration < it.price,
            callback = function() self:go("shop_item", it.id) end }
    end
    local tabs = {}
    for _, t in ipairs(Game.SHOP_TABS) do
        tabs[#tabs + 1] = { text = t.name, active = t.id == tab, callback = function() self.shop_tab, self.shop_page = t.id, 1 self:render() end }
    end
    return { title = T("小铺"), status = { icon = "items/paper_clip.png", icon_size = 48, title = T("图钉小铺"), caption = T("老板是一枚不爱说话的图钉。点一件看看。"),
            meta = T("灵感 ✦ %d", s.inspiration) },
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
    local lines = { { text = T("效果"), label = true } }
    for _, l in ipairs(long) do lines[#lines + 1] = "· " .. l end
    return { title = it.name, status = { icon = "items/" .. it.id .. ".png", icon_size = 96, title = it.name, caption = it.desc or "",
            meta = T("✦ %d　·　已有 %d　·　灵感 ✦ %d", it.price, s.inventory[it.id] or 0, s.inspiration) }, lines = lines,
        buttons = { { text = T("买一个（✦ %d）", it.price), callback = function() self:_buy(it) end } } }
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
    local v = { title = T("明信片墙"), lines = {} }
    if #s.postcards == 0 then v.empty = { title = T("墙上还空着"), caption = T("等阿页寄第一张回来。") } 
    else v.lines[1] = { text = T("%d 张 · 新的在前", #s.postcards) .. ((#s.postcards - seen_before) > 0 and T("　·　新 %d", #s.postcards - seen_before) or ""), label = true } end
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
    v.switch = { icon = mode == "grid" and "view_list" or "grid_view", text = mode == "grid" and T("列表") or T("网格"), callback = function()
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
        status = { title = (p and p.name or c.place) .. " · " .. (Postcards.weather_names[c.weather] or ""), caption = (c.line or "") .. T("　——阿页"),
            meta = os.date("%Y-%m-%d %H:%M", c.at or 0) .. T("　·　第 %d / %d 张", i, n) },
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
    elseif #s.decor >= Game.DECOR_MAX then self.host:notify(T("阁楼摆满了，先收起一样")) return
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
            meta = "×" .. s.souvenirs[id] .. (on and T("　摆在阁楼") or ""), caption = (s.souvenir_notes and s.souvenir_notes[id]) or sv.note,
            callback = function() self:go("souvenir", id) end }
    end
    return { title = T("特产柜"),
        status = { icon = s.decor[1] and ("souvenirs/" .. s.decor[1] .. ".png") or nil, title = T("收集 %d / %d 种", #ids, Game.souvenirTotal()),
            caption = T("阿页带回来的东西都在这里。点一件看看，可以摆到阁楼里。"), meta = T("阁楼里摆了 %d / %d", #s.decor, Game.DECOR_MAX) },
        empty = #ids == 0 and { title = T("柜子还空着"), caption = T("每趟旅行回来，阿页都会带一样特产。") } or nil,
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
            meta = T("收着 ×%d　·　%s", s.souvenirs[id], on and T("摆在阁楼里") or T("收在柜子里")) },
        lines = { { text = T("阁楼右墙的矮架上能摆 %d 样，现在摆了 %d 样。", Game.DECOR_MAX, #s.decor), muted = true, small = true } },
        buttons = { { text = on and T("从阁楼收起") or T("摆到阁楼里"), callback = function() self:_toggleDecor(id) end } } }
end

Game.SCRAP_PER = 6
Game.GUEST_PER = 6

function Game:_scrapbook()
    local s = self.state
    local list, done, total = Album.places(s)
    local per = self:per("scrapbook", Game.SCRAP_PER)
    local pages = math.max(1, math.ceil(#list / per))
    local page = math.max(1, math.min(self.scrap_page or 1, pages))
    self.scrap_page = page
    local cells = {}
    for i = (page - 1) * per + 1, math.min(#list, page * per) do
        local row = list[i]
        local p = row.place
        local meta = row.trips > 0 and T("去过 %d 次 · 特产 %d / %d", row.trips, row.have, row.total) or T("还没去过")
        if row.wished then meta = T("惦记中　·　") .. meta end
        cells[#cells + 1] = {
            icon = "places/" .. p.id .. ".png", title = p.name, check = row.done, dim = row.trips == 0,
            meta = meta, caption = row.cards > 0 and T("明信片 %d 张", row.cards) or T("按地点收齐特产"),
            callback = function() self:go("place", p.id) end,
        }
    end
    return { title = T("地点剪贴簿"),
        status = { icon = "items/travel_diary.png", title = T("收齐 %d / %d 页", done, total),
            caption = T("每一页是一个地点。特产收齐、去过一次，这一页就算收齐。"),
            meta = s.wish_place and T("正惦记：%s", (Travel.place(s.wish_place) or {}).name or s.wish_place) or T("灵感 ✦ %d", s.inspiration) },
        shelf = { cols = 2, cells = cells, per = per, fit = self:fitter("scrapbook") },
        pager = { page = page, pages = pages, go = function(n) self.scrap_page = n self:render() end,
            prev = function() self.scrap_page = page - 1 self:render() end, next = function() self.scrap_page = page + 1 self:render() end } }
end

function Game:_place()
    local s = self.state
    local p = Travel.place(self.arg)
    if not p then self.page = "scrapbook" return self:_scrapbook() end
    local row = Album.place(s, p)
    local lines = { { text = T("特产"), label = true } }
    for _, id in ipairs(p.souvenirs or {}) do
        local have = (s.souvenirs or {})[id] and (s.souvenirs[id] or 0) > 0
        local name = Album.souvenirName(id)
        lines[#lines + 1] = (have and "✓ " or "· ") .. name
    end
    lines[#lines + 1] = { text = T("明信片"), label = true }
    lines[#lines + 1] = row.cards > 0 and T("墙上有 %d 张来自这里。", row.cards) or T("还没有寄回这里的明信片。")
    if row.trips > 0 then lines[#lines + 1] = T("阿页来过 %d 次。", row.trips)
    else lines[#lines + 1] = T("阿页还没来过。用灵感惦记这里，下一趟会直达。") end
    local cost = Album.WISH_COST
    local buttons = {}
    if row.wished then
        buttons[#buttons + 1] = { text = T("取消惦记"), callback = function()
            s.wish_place = nil self:save() self.host:notify(T("不惦记了")) self:render()
        end }
    else
        buttons[#buttons + 1] = { text = T("惦记这里（✦ %d）", cost), callback = function() self:_wish(p.id) end }
    end
    return { title = p.name,
        status = { icon = "places/" .. p.id .. ".png", icon_size = 96, title = p.name,
            caption = row.done and T("这一页收齐了。") or T("特产 %d / %d", row.have, row.total),
            meta = T("灵感 ✦ %d", s.inspiration) },
        lines = lines, buttons = buttons }
end

function Game:_wish(place_id)
    local s = self.state
    local cost = Album.WISH_COST
    if s.sprite.status == "away" then self.host:notify(T("阿页还在路上")) return end
    if s.wish_place == place_id then return end
    if s.inspiration < cost then self.host:notify(T("灵感不够")) return end
    s.inspiration = s.inspiration - cost
    s.wish_place = place_id
    self:save()
    local p = Travel.place(place_id)
    self.host:notify(T("阿页会惦记着去%s", p and p.name or place_id))
    self:render()
end

function Game:_guestbook()
    local s = self.state
    local list, have, total = Album.visitors(s)
    local per = self:per("guestbook", Game.GUEST_PER)
    local pages = math.max(1, math.ceil(#list / per))
    local page = math.max(1, math.min(self.guest_page or 1, pages))
    self.guest_page = page
    local cells = {}
    for i = (page - 1) * per + 1, math.min(#list, page * per) do
        local row = list[i]
        local v = row.visitor
        cells[#cells + 1] = {
            icon = row.seen and ("visitors/" .. v.id .. ".png") or "sprite/peek.png",
            title = row.seen and v.name or T("？？？"),
            check = row.seen, dim = not row.seen,
            meta = row.seen and T("留下 ✦ %d", v.gift) or T("还没来过"),
            caption = row.seen and (Game.when(row.at, self.host:now()) or T("来过")) or T("回家后有时会来串门"),
            callback = function() self:go("guest", v.id) end,
        }
    end
    return { title = T("来客簿"),
        status = { icon = "sprite/peek.png", title = T("见过 %d / %d 位", have, total),
            caption = T("小客人来过一次就会记在这里。稀有的来得少，多等几次。"),
            meta = T("%d / %d", have, total) },
        shelf = { cols = 2, cells = cells, per = per, fit = self:fitter("guestbook") },
        pager = { page = page, pages = pages, go = function(n) self.guest_page = n self:render() end,
            prev = function() self.guest_page = page - 1 self:render() end, next = function() self.guest_page = page + 1 self:render() end } }
end

function Game:_guest()
    local s = self.state
    local v = Travel.visitor(self.arg)
    if not v then self.page = "guestbook" return self:_guestbook() end
    local at = (s.seen_visitors or {})[v.id]
    local seen = at ~= nil
    local lines
    if seen then
        lines = {
            { text = T("来访"), label = true },
            v.arrive or "",
            { text = T("离开"), label = true },
            v.leave or "",
        }
        if at and at > 0 then lines[#lines + 1] = T("第一次来是 %s。", os.date("%Y-%m-%d %H:%M", at)) end
    else
        lines = { T("见过面之后，这里会记下它的样子和留下的灵感。") }
    end
    return { title = seen and v.name or T("？？？"),
        status = { icon = seen and ("visitors/" .. v.id .. ".png") or "sprite/peek.png", icon_size = 120,
            title = seen and v.name or T("还没见过的客人"),
            caption = seen and (v.here or "") or T("小客人会在阿页回家后来串门。"),
            meta = seen and T("初次来访　·　留下 ✦ %d", v.gift) or T("待发现") },
        lines = lines }
end

--- 每页数量：默认值，界面按屏幕剩余高度回报实际能放的数量（fit）后记住
function Game:per(key, default) self.per_page = self.per_page or {} return self.per_page[key] or default end
--- 事件时间：1 分钟内「刚刚」，1 小时内「N 分钟前」，当天内「N 小时前」，更早用明信片同款「MM-DD HH:MM」；没时间返回 nil
function Game.when(at, now)
    if not at or at <= 0 then return nil end
    now = now or os.time()
    local d = now - at
    if d < 0 then return os.date("%m-%d %H:%M", at) end
    if d < 60 then return T("刚刚") end
    if d < 3600 then return T("%d 分钟前", math.floor(d / 60)) end
    if d < 86400 then return T("%d 小时前", math.floor(d / 3600)) end
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

Game.PARENT = {
    basket = "attic", shop = "attic", wall = "attic", cabinet = "attic",
    scrapbook = "attic", guestbook = "attic",
    shop_item = "shop", card = "wall", souvenir = "cabinet",
    place = "scrapbook", guest = "guestbook",
}

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
