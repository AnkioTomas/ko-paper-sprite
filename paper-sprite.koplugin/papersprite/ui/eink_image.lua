-- SPDX-License-Identifier: MIT
--[[--
墨水屏上阿页图片的区域补刷，和月读一致：只用不闪的 "ui"，并请求硬件抖动（dither，ColorSoft 等设备有用）。
不主动 "full"：进页、关闭、连续换图都不闪黑，残影交给 KOReader 自己的全刷设置。

  * 推迟到 tickAfterNext，不和本拍整页 setDirty("ui") 合并。
  * 同一拍里多张图（收藏墙）只刷一次外接矩形。
  * 同一图片（同 key）已在屏上：重复 paintTo、控件重建都不再登记。
  * 离屏导出不要 wrap（或 armed=false），不会刷到正在看的屏幕。
--]]

local M = {}

local pending = {}
local scheduled = false
local on_screen = {}

local function geomCopy(g)
    if not g then return nil end
    local x = g.x or 0
    local y = g.y or 0
    local w = g.w or g.width or 0
    local h = g.h or g.height or 0
    if w < 1 or h < 1 then return nil end
    return { x = x, y = y, w = w, h = h }
end

local function unionOf(list)
    local x1, y1, x2, y2
    for _, item in ipairs(list) do
        local g = item.geom
        local r, b = g.x + g.w, g.y + g.h
        if not x1 then
            x1, y1, x2, y2 = g.x, g.y, r, b
        else
            if g.x < x1 then x1 = g.x end
            if g.y < y1 then y1 = g.y end
            if r > x2 then x2 = r end
            if b > y2 then y2 = b end
        end
    end
    return { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
end

--- 测试用：清空队列和在屏记录。
function M._reset()
    pending = {}
    scheduled = false
    on_screen = {}
end

function M._pending()
    return pending
end

--- 阁楼关掉：屏上已不是这些图，下次打开要重新补刷。
function M.forget()
    on_screen = {}
end

local function flush()
    scheduled = false
    local list = pending
    pending = {}
    if #list == 0 then return end
    for _, item in ipairs(list) do
        if item.key then on_screen[item.key] = true end
    end
    local region = unionOf(list)
    local ok, UIManager = pcall(require, "ui/uimanager")
    if not ok or type(UIManager) ~= "table" or type(UIManager.setDirty) ~= "function" then return end
    local Geom = require("ui/geometry")
    -- widget 传 nil：只排队刷新，不再把整层标 dirty（画面已经画过）。
    UIManager:setDirty(nil, "ui", Geom:new{ x = region.x, y = region.y, w = region.w, h = region.h }, true)
end

local function armTick()
    if scheduled then return end
    scheduled = true
    local ok, UIManager = pcall(require, "ui/uimanager")
    if not ok or type(UIManager) ~= "table" then
        scheduled = false
        return
    end
    -- tickAfterNext：避免 scheduleIn(0) 在本拍 _checkTasks 里先于 _repaint 跑，和整页 ui 合并。
    if type(UIManager.tickAfterNext) == "function" then
        UIManager:tickAfterNext(flush)
    elseif type(UIManager.nextTick) == "function" then
        UIManager:nextTick(function() UIManager:nextTick(flush) end)
    elseif type(UIManager.scheduleIn) == "function" then
        UIManager:scheduleIn(0, function() UIManager:scheduleIn(0, flush) end)
    else
        scheduled = false
    end
end

--- 登记一块图片区域。opts.key：图片内容标识，用来认出「同一张已在屏上」。
function M.schedule(geom, opts)
    local g = geomCopy(geom)
    if not g then return end
    pending[#pending + 1] = { geom = g, key = opts and opts.key }
    armTick()
end

--- 让已有图片控件在下次 paintTo 时登记刷新区域。
-- 必须是真正的 WidgetContainer：桌面/UIManager 会 broadcastEvent，
-- WidgetContainer:propagateEvent 对 ipairs 子控件调用 :handleEvent。
-- 普通表没有 handleEvent，onShow 就会报 attempt to call method handleEvent (a nil value)。
function M.wrap(child, opts)
    if not child then return child end
    opts = opts or {}
    local WidgetContainer = require("ui/widget/container/widgetcontainer")
    local Geom = require("ui/geometry")
    local Wrapper = WidgetContainer:extend{
        _papersprite_eink = true,
        _content_key = opts.key,
    }
    function Wrapper:init()
        if self._need_refresh == nil then self._need_refresh = true end
    end
    function Wrapper:mark()
        self._need_refresh = true
        self._content_changed = true
    end
    function Wrapper:handleEvent(event)
        if self[1] and type(self[1].handleEvent) == "function" then
            return self[1]:handleEvent(event)
        end
        return false
    end
    function Wrapper:paintTo(bb, x, y)
        local size
        if self[1] and type(self[1].getSize) == "function" then
            size = self[1]:getSize()
        else
            size = { w = 0, h = 0 }
        end
        local w, h = size.w or 0, size.h or 0
        -- 不要把屏幕坐标写进 self.dimen.x/y，否则 WidgetContainer 默认 paintTo 会再加一次偏移。
        if not self.dimen then
            self.dimen = Geom:new{ x = 0, y = 0, w = w, h = h }
        else
            self.dimen.w, self.dimen.h = w, h
        end
        if self[1] and type(self[1].paintTo) == "function" then
            self[1]:paintTo(bb, x, y)
        end
        if not self._need_refresh then return end
        self._need_refresh = false
        local key, changed = self._content_key, self._content_changed
        self._content_changed = false
        if key and on_screen[key] and not changed then return end
        M.schedule({ x = x, y = y, w = w, h = h }, { key = key })
    end
    local wdg = Wrapper:new{ child }
    if opts.armed == false then wdg._need_refresh = false end
    return wdg
end

return M
