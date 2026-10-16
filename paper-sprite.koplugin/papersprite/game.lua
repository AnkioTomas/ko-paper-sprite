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
    local lines = {}
    local scene = Game.atticScene(s, now)
    if sp.status == "home" then
        lines[1] = "阿页坐在书桌边，油灯亮着。"
    elseif sp.status == "packed" then
        lines[1] = "藤筐收拾好了。阿页在窗边发呆，看样子快要出门了。"
    else
        lines[1] = "阁楼空着。书桌上压着一张纸条：「" .. (s.note or "") .. "」——阿页"
        lines[2] = { text = "已经出门 " .. fmtDur(now - sp.left_at, self.debug), muted = true }
    end
    if s.visitor then
        local v = Travel.visitor(s.visitor.id)
        if v then
            lines[#lines + 1] = s.visitor.line or v.here
        end
    end
    local unseen = #s.postcards - (s.wall_seen or 0)
    lines[#lines + 1] = { text = "灵感 " .. s.inspiration .. " · 明信片 " .. #s.postcards
        .. (unseen > 0 and ("（新 " .. unseen .. "）") or ""), muted = true }
    for i = #s.log, math.max(1, #s.log - 3), -1 do lines[#lines + 1] = { text = s.log[i], muted = true } end
    local b = {}
    if sp.status ~= "away" then
        b[#b + 1] = { { text = "收拾行囊", callback = function() self:go("basket") end },
                      { text = "小铺", callback = function() self:go("shop") end } }
    else
        b[#b + 1] = { text = "小铺", callback = function() self:go("shop") end }
    end
    b[#b + 1] = { { text = "明信片墙（" .. #s.postcards .. "）", callback = function() self.wall_page = 1 self:go("wall") end },
                  { text = "特产柜", callback = function() self:go("cabinet") end } }
    return { title = "阿页的阁楼", scene = scene, lines = lines, buttons = b }
end

function Game:_basket()
    local s = self.state
    local lines = { "往藤筐里放三样东西：干粮、护身物、随身小书。" }
    local icons = {}
    local b = {}
    for _, slot in ipairs(Travel.SLOTS) do
        local cur = s.basket[slot] and Travel.item(s.basket[slot])
        lines[#lines + 1] = SLOT_NAME[slot] .. "：" .. (cur and cur.name or "（空）")
        if cur then icons[#icons + 1] = "items/" .. cur.id .. ".png" end
        local row = {}
        for _, it in ipairs(Items) do
            local n = Travel.count(s, it.id)
            if it.slot == slot and n > 0 then
                row[#row + 1] = { text = it.name .. (n == math.huge and "" or ("×" .. n)), callback = function()
                    Travel.put(s, it.id, self.host:now(), self.debug)
                    self:save()
                    self:render()
                end }
            end
        end
        -- 一行最多 3 个
        for i = 1, #row, 3 do b[#b + 1] = { row[i], row[i + 1], row[i + 2] } end
    end
    b[#b + 1] = { text = "回阁楼", callback = function() self:go("attic") end }
    return { title = "收拾行囊", icons = { "sprite/carry.png", unpack(icons) }, lines = lines, buttons = b }
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
function Game.shopPage(tab, page)
    local list = {}
    for _, it in ipairs(Items) do
        if it.price > 0 and (tab == nil or tab == "all" or it.slot == tab) then list[#list + 1] = it end
    end
    local per = Game.SHOP_COLS * Game.SHOP_ROWS
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
    local items, page, pages = Game.shopPage(tab, self.shop_page)
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
    return { title = "小铺", lines = { "图钉老板把货摆在一格一格的架子上。点一件看看。", { text = "灵感 ✦ " .. s.inspiration, muted = true } },
        tabs = tabs, shelf = { cols = Game.SHOP_COLS, cells = cells },
        pager = { page = page, pages = pages,
            prev = function() self.shop_page = page - 1 self:render() end, next = function() self.shop_page = page + 1 self:render() end },
        buttons = { { text = "回阁楼", callback = function() self:go("attic") end } } }
end

function Game:_shop_item()
    local s = self.state
    local it = Travel.item(self.arg)
    if not it then self.page = "shop" return self:_shop() end
    local _, long = Game.itemEffect(it)
    local lines = { it.desc or "", { text = "价格 ✦ " .. it.price .. "　·　已有 " .. (s.inventory[it.id] or 0) .. "　·　灵感 ✦ " .. s.inspiration, muted = true } }
    for _, l in ipairs(long) do lines[#lines + 1] = "· " .. l end
    return { title = it.name, icons = { "items/" .. it.id .. ".png" }, lines = lines,
        buttons = { { { text = "买一个（✦ " .. it.price .. "）", callback = function() self:_buy(it) end },
                      { text = "回小铺", callback = function() self:go("shop") end } } } }
end

Game.WALL_GRID = { cols = 3, rows = 4 }
Game.WALL_LIST = 4

--- 纯函数：明信片墙的一页。mode = grid（缩略图网格）| list（缩略图 + 文字），新的在前
function Game.wallPage(s, mode, page)
    local per = mode == "list" and Game.WALL_LIST or Game.WALL_GRID.cols * Game.WALL_GRID.rows
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
    local idx, page, pages = Game.wallPage(s, mode, self.wall_page)
    self.wall_page = page
    local v = { title = "明信片墙 · " .. #s.postcards .. " 张", lines = {} }
    if #s.postcards == 0 then v.lines[1] = "墙上还空着，等阿页寄第一张回来。" end
    local function cardInfo(i)
        local c = s.postcards[i]
        local p = Travel.place(c.place)
        return c, (p and p.name or c.place), (Postcards.weather_names[c.weather] or "")
    end
    if mode == "grid" then
        v.grid = { cols = Game.WALL_GRID.cols, cells = {} }
        for _, i in ipairs(idx) do
            local c, name = cardInfo(i)
            v.grid.cells[#v.grid.cells + 1] = { scene = Game.cardScene(c), new = i > seen_before, caption = name,
                callback = function() self:go("card", i) end }
        end
    else
        v.list = { rows = {} }
        for _, i in ipairs(idx) do
            local c, name, wn = cardInfo(i)
            v.list.rows[#v.list.rows + 1] = { scene = Game.cardScene(c), new = i > seen_before, title = name .. " · " .. wn,
                line = c.line or "", date = os.date("%m-%d %H:%M", c.at or 0), callback = function() self:go("card", i) end }
        end
    end
    v.pager = { page = page, pages = pages,
        prev = function() self.wall_page = page - 1 self:render() end,
        next = function() self.wall_page = page + 1 self:render() end }
    v.buttons = { {
        { text = mode == "grid" and "列表视图" or "网格视图", callback = function()
            self.host:setSetting("wall_mode", mode == "grid" and "list" or "grid") self.wall_page = 1 self:render() end },
        { text = "回阁楼", callback = function() self:go("attic") end } } }
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
    local c = self.state.postcards[self.arg]
    if not c then self.page = "wall" return self:_wall() end
    local p = Travel.place(c.place)
    return {
        title = p.name .. " · " .. (Postcards.weather_names[c.weather] or ""),
        scene = Game.cardScene(c),
        lines = { c.line or "", { text = "——阿页", muted = true } },
        buttons = { { text = "回明信片墙", callback = function() self:go("wall") end } },
    }
end

local function indexOf(t, x) for i, y in ipairs(t) do if y == x then return i end end end

function Game:_cabinet()
    local s = self.state
    s.decor = s.decor or {}
    local ids = {}
    for id in pairs(s.souvenirs) do if Postcards.souvenirs[id] then ids[#ids + 1] = id end end
    table.sort(ids, function(a, b) return Postcards.souvenirs[a].name < Postcards.souvenirs[b].name end)
    local lines, b, icons = {}, {}, {}
    lines[1] = { text = "阿页带回来的东西，都摆在这里。点一下可以摆到阁楼里（最多 " .. Game.DECOR_MAX .. " 样）。", muted = true }
    if #ids == 0 then lines[2] = "柜子还空着。" end
    for _, id in ipairs(ids) do
        local sv = Postcards.souvenirs[id]
        local note = (s.souvenir_notes and s.souvenir_notes[id]) or sv.note
        lines[#lines + 1] = sv.name .. " ×" .. s.souvenirs[id] .. "　" .. note
    end
    for _, id in ipairs(s.decor) do icons[#icons + 1] = "souvenirs/" .. id .. ".png" end
    local row = {}
    for _, id in ipairs(ids) do
        local on = indexOf(s.decor, id)
        row[#row + 1] = { text = (on and "✓ " or "") .. Postcards.souvenirs[id].name, callback = function()
            local i = indexOf(s.decor, id)
            if i then table.remove(s.decor, i)
            elseif #s.decor >= Game.DECOR_MAX then self.host:notify("阁楼摆满了，先收起一样") return
            else s.decor[#s.decor + 1] = id end
            self:save()
            self:render()
        end }
        if #row == 3 then b[#b + 1] = row row = {} end
    end
    if #row > 0 then b[#b + 1] = row end
    b[#b + 1] = { text = "回阁楼", callback = function() self:go("attic") end }
    return { title = "特产柜", icons = #icons > 0 and icons or nil, lines = lines, buttons = b }
end

function Game:view()
    if self.page == "basket" and self.state.sprite.status == "away" then self.page = "attic" end
    local v = self["_" .. self.page](self)
    v.on_close = function() self.closed = true if self.timer then self.host:unschedule(self.timer) self.timer = nil end end
    return v
end

function Game:render()
    if self.closed then return end
    self.host:showScreen(self:view())
    self:_arm()
end

return Game
