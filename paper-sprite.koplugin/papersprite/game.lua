-- SPDX-License-Identifier: MIT
--[[--
阁楼游戏控制器：读存档 → 按真实时间结算 → 生成 view 交给 host 显示。
界面开着时只在「下一件事」到点时安排一次刷新（最长 60 秒一次），关掉即停。
页面：attic 阁楼 / basket 收拾行囊 / wall 明信片墙 / card 单张明信片
--]]
local State = require("papersprite.core.state")
local Travel = require("papersprite.core.travel")
local Items = require("papersprite.data.items")
local Postcards = require("papersprite.data.postcards")

local Game = {}
Game.__index = Game

local SLOT_NAME = { food = "干粮", charm = "护身物", book = "随身小书" }

function Game.new(host)
    -- 同一时刻只留一个阁楼实例：菜单和月读卡片都能打开，旧实例若还开着就先关掉，
    -- 否则两个实例各拿一份存档副本，后保存的会覆盖先保存的（模拟器里实测）
    if Game.current and not Game.current.closed then Game.current:close() end
    local self = setmetatable({ host = host, page = "attic" }, Game)
    self.debug = host:getSetting("debug_fast", false)
    self.state = State.load(host:loadState(), host:now())
    Game.current = self
    return self
end

function Game:save() self.host:saveState(self.state) end

function Game:tick()
    -- 每次结算前重读存档：以落盘的为准（首页卡片 / 其他入口可能改过）
    self.state = State.load(self.host:loadState() or self.state, self.host:now())
    local ok, Reading = pcall(require, "papersprite.core.reading")
    if ok then pcall(Reading.collect, self.state) end
    local ev = Travel.settle(self.state, self.host:now(), self.debug)
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

function Game:_attic()
    local s, now = self.state, self.host:now()
    local sp = s.sprite
    local lines = {}
    if sp.status == "home" then
        lines[1] = "阿页坐在书桌边，油灯亮着。"
    elseif sp.status == "packed" then
        lines[1] = "藤筐收拾好了。阿页在窗边发呆，看样子快要出门了。"
    else
        lines[1] = "阁楼空着。书桌上压着一张纸条：「" .. (s.note or "") .. "」"
        lines[2] = { text = "已经出门 " .. fmtDur(now - sp.left_at, self.debug), muted = true }
    end
    if s.visitor then lines[#lines + 1] = "一只墨点虫趴在油灯旁，晃着小触角。" end
    local unseen = #s.postcards - (s.wall_seen or 0)
    lines[#lines + 1] = { text = "灵感 " .. s.inspiration .. " · 明信片 " .. #s.postcards
        .. (unseen > 0 and ("（新 " .. unseen .. "）") or ""), muted = true }
    for i = #s.log, math.max(1, #s.log - 4), -1 do lines[#lines + 1] = { text = s.log[i], muted = true } end
    local b = {}
    if sp.status ~= "away" then
        b[#b + 1] = { text = "收拾行囊", callback = function() self:go("basket") end }
    end
    b[#b + 1] = { text = "明信片墙（" .. #s.postcards .. "）", callback = function() self:go("wall") end }
    return { title = "阿页的阁楼", image = sp.status == "away" and "attic/attic_empty.png" or "attic/attic.png", lines = lines, buttons = b }
end

function Game:_basket()
    local s = self.state
    local lines = { "往藤筐里放三样东西：干粮、护身物、随身小书。" }
    local b = {}
    for _, slot in ipairs(Travel.SLOTS) do
        local cur = s.basket[slot] and Travel.item(s.basket[slot]).name or "（空）"
        lines[#lines + 1] = SLOT_NAME[slot] .. "：" .. cur
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
        if #row > 0 then b[#b + 1] = row end
    end
    b[#b + 1] = { text = "回阁楼", callback = function() self:go("attic") end }
    return { title = "收拾行囊", lines = lines, buttons = b }
end

function Game:_wall()
    local s = self.state
    local lines, b = {}, {}
    if s.wall_seen ~= #s.postcards then s.wall_seen = #s.postcards self:save() end
    if #s.postcards == 0 then lines[1] = "墙上还空着，等阿页寄第一张回来。" end
    for i = #s.postcards, 1, -1 do
        local c = Postcards.get(s.postcards[i].id)
        if c then
            local p = Travel.place(c.place)
            b[#b + 1] = { text = (p and p.name or c.place) .. " · " .. os.date("%m-%d %H:%M", s.postcards[i].at),
                callback = function() self:go("card", c.id) end }
        end
    end
    b[#b + 1] = { text = "回阁楼", callback = function() self:go("attic") end }
    return { title = "明信片墙", lines = lines, buttons = b }
end

function Game:_card()
    local c = Postcards.get(self.arg)
    local p = Travel.place(c.place)
    return {
        title = p.name,
        image = "places/" .. p.bg,
        layers = { "places/" .. p.bg, "sprite/" .. c.pose .. ".png",
            c.prop ~= "none" and ("props/" .. c.prop .. ".png") or nil, "weather/" .. c.weather .. ".png" },
        lines = { c.line, { text = "——阿页", muted = true } },
        buttons = { { text = "回明信片墙", callback = function() self:go("wall") end } },
    }
end

function Game:view()
    -- 停在行囊页时阿页出门了：行囊已带走，回阁楼看纸条
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
