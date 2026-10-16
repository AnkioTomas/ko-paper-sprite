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
local WALL_PAGE = 8
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

function Game:go(page, arg) self.page, self.arg = page, arg self:render() end

local VISITOR_POS = { -- 访客在阁楼图里的位置（中心占比）
    inkbug = { 0.47, 0.50, 0.14 }, clip_snail = { 0.30, 0.42, 0.12 },
    lampfly = { 0.55, 0.30, 0.12 }, stamp_turtle = { 0.30, 0.78, 0.24 },
}

function Game:_attic()
    local s, now = self.state, self.host:now()
    local sp = s.sprite
    local lines = {}
    local scene = { bg = sp.status == "away" and "attic/attic_empty.png" or "attic/attic.png", overlays = {} }
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
            local pos = VISITOR_POS[v.id] or { 0.5, 0.6, 0.12 }
            scene.overlays[#scene.overlays + 1] = { img = "visitors/" .. v.id .. ".png", x = pos[1], y = pos[2], h = pos[3] }
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

function Game:_shop()
    local s = self.state
    local lines = { "小铺老板是一枚不爱说话的图钉。用灵感换东西。", { text = "灵感 " .. s.inspiration, muted = true } }
    local b, row = {}, {}
    for _, it in ipairs(Items) do
        if it.price > 0 then
            row[#row + 1] = { text = it.name .. " " .. it.price .. "（有 " .. (s.inventory[it.id] or 0) .. "）",
                callback = function()
                    if s.inspiration < it.price then self.host:notify("灵感不够") return end
                    s.inspiration = s.inspiration - it.price
                    s.inventory[it.id] = (s.inventory[it.id] or 0) + 1
                    self:save()
                    self:render()
                end }
            if #row == 2 then b[#b + 1] = row row = {} end
        end
    end
    if #row > 0 then b[#b + 1] = row end
    b[#b + 1] = { text = "回阁楼", callback = function() self:go("attic") end }
    return { title = "小铺", lines = lines, buttons = b }
end

function Game:_wall()
    local s = self.state
    local lines, b = {}, {}
    if s.wall_seen ~= #s.postcards then s.wall_seen = #s.postcards self:save() end
    if #s.postcards == 0 then lines[1] = "墙上还空着，等阿页寄第一张回来。" end
    local pages = math.max(1, math.ceil(#s.postcards / WALL_PAGE))
    self.wall_page = math.max(1, math.min(self.wall_page, pages))
    local first = #s.postcards - (self.wall_page - 1) * WALL_PAGE
    for i = first, math.max(1, first - WALL_PAGE + 1), -1 do
        local c = s.postcards[i]
        local p = Travel.place(c.place)
        b[#b + 1] = { text = (p and p.name or c.place) .. " · " .. (Postcards.weather_names[c.weather] or "")
            .. " · " .. os.date("%m-%d %H:%M", c.at or 0), callback = function() self:go("card", i) end }
    end
    if pages > 1 then
        b[#b + 1] = {
            { text = "上一页", callback = function() self.wall_page = self.wall_page - 1 self:render() end },
            { text = self.wall_page .. " / " .. pages, callback = function() end },
            { text = "下一页", callback = function() self.wall_page = self.wall_page + 1 self:render() end },
        }
    end
    b[#b + 1] = { text = "回阁楼", callback = function() self:go("attic") end }
    return { title = "明信片墙", lines = lines, buttons = b }
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

function Game:_cabinet()
    local s = self.state
    local lines = {}
    for id, n in pairs(s.souvenirs) do
        local sv = Postcards.souvenirs[id]
        if sv then
            local note = (s.souvenir_notes and s.souvenir_notes[id]) or sv.note
            lines[#lines + 1] = sv.name .. " ×" .. n .. "　" .. note
        end
    end
    table.sort(lines)
    if #lines == 0 then lines[1] = "柜子还空着。" end
    table.insert(lines, 1, { text = "阿页带回来的东西，都摆在这里。", muted = true })
    return { title = "特产柜", lines = lines, buttons = { { text = "回阁楼", callback = function() self:go("attic") end } } }
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
