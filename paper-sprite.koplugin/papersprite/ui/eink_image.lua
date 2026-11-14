-- SPDX-License-Identifier: MIT
--[[--
墨水屏上阿页的图片需要区域刷新，但不能每次都 full（会先黑一下），
也不能和整页 setDirty("ui") 排在同一拍（UIManager 按相交/共边合并，
可能把整页升成 full）。

策略（N = M.FULL_EVERY = 5）：
  * 进入 / 离开带图片的页面，或一批图片第一次出现：合并成一块区域，
    做一次 dither 的 "full"（会闪一次，清残影）。
  * 普通换图：区域 "ui" + dither（207 有硬件抖动；97 可能被忽略），不闪黑。
  * 自上次 full 起，累计 5 次「换图刷新」（按批次计，不是每个控件一次）
    再做一次区域 full，然后计数清零。
  * 同一图片重复 paintTo、纯按钮/文字：不登记，不计数。
  * 同一拍里多张图（收藏墙）只 flush 一次，用外接矩形，绝不会九次 full。
  * 不用未经上机验证的 flashpartial。
  * 仍用 tickAfterNext，避免和整页 ui 合并。
  * 离屏导出不要 wrap，也就不会 setDirty 屏幕。

不改阅读页全局翻页刷新；伴读动画帧仍走调用方的 "ui"，
动画结束后用 schedule(..., "quality") 清一次。
--]]

local M = {}

-- 换图批次达到这个数才区域 full。偏保守：既少闪黑，又不会拖太久才清残影。
M.FULL_EVERY = 5

local pending = {}
local scheduled = false
local changes = 0
local quality_pending = false
local on_screen = {}
local last_union = nil
local last_flush = nil

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
    if not list or #list == 0 then return nil end
    local x1, y1, x2, y2
    for _, item in ipairs(list) do
        local g = item.geom or item
        local x, y = g.x, g.y
        local r, b = x + g.w, y + g.h
        if not x1 then
            x1, y1, x2, y2 = x, y, r, b
        else
            if x < x1 then x1 = x end
            if y < y1 then y1 = y end
            if r > x2 then x2 = r end
            if b > y2 then y2 = b end
        end
    end
    return { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
end

--- 测试用：清空队列、计数和在屏记录。
function M._reset()
    pending = {}
    scheduled = false
    changes = 0
    quality_pending = false
    on_screen = {}
    last_union = nil
    last_flush = nil
end

function M._pending()
    return pending
end

function M._changes()
    return changes
end

function M._lastFlush()
    return last_flush
end

function M.enterPage()
    quality_pending = true
end

function M.leavePage()
    quality_pending = true
end

--- 用户离开带图片的界面时，把上一批图片区域再登记一次高质量刷新。
function M.scheduleLast(reason)
    if last_union then
        M.schedule(last_union, { reason = reason or "close" })
    end
end

local function flush()
    scheduled = false
    local list = pending
    pending = {}
    if #list == 0 then
        return list
    end
    local has_quality = quality_pending
    local has_close, has_show, has_change = false, false, false
    for _, item in ipairs(list) do
        local r = item.reason
        if r == "show" or r == "close" or r == "quality" then
            has_quality = true
        end
        if r == "close" then has_close = true end
        if r == "show" then has_show = true end
        if r == "change" then has_change = true end
    end
    quality_pending = false

    local mode
    if has_quality then
        mode = "full"
        changes = 0
    else
        -- 同一拍里无论几张换图，只计 1 次，避免墙面九连 full。
        changes = changes + 1
        if changes >= M.FULL_EVERY then
            mode = "full"
            changes = 0
        else
            mode = "ui"
        end
    end

    local region = unionOf(list)
    last_union = region
    last_flush = { mode = mode, region = region, count = #list, changes = changes }

    if has_close and not has_show and not has_change then
        on_screen = {}
    else
        for _, item in ipairs(list) do
            if item.key then
                on_screen[item.key] = true
            end
        end
    end

    local ok, UIManager = pcall(require, "ui/uimanager")
    if not ok or type(UIManager) ~= "table" or type(UIManager.setDirty) ~= "function" then
        return list
    end
    local Geom = require("ui/geometry")
    local box = Geom:new{ x = region.x, y = region.y, w = region.w, h = region.h }
    -- widget 传 nil：只排队刷新，不再把整层标 dirty（画面已经画过）。
    -- dither=true：照片走硬件抖动（若设备支持，如 ColorSoft）。
    UIManager:setDirty(nil, mode, box, true)
    return list
end

local function armTick()
    if scheduled then return end
    scheduled = true
    local ok, UIManager = pcall(require, "ui/uimanager")
    if not ok or type(UIManager) ~= "table" then
        scheduled = false
        return
    end
    -- tickAfterNext：避免 scheduleIn(0) 在本拍 _checkTasks 里先于 _repaint 跑，
    -- 和整页 ui 撞车合并成全屏 full。
    local later = function()
        flush()
    end
    if type(UIManager.tickAfterNext) == "function" then
        UIManager:tickAfterNext(later)
    elseif type(UIManager.nextTick) == "function" then
        UIManager:nextTick(function()
            if type(UIManager.nextTick) == "function" then
                UIManager:nextTick(later)
            else
                later()
            end
        end)
    elseif type(UIManager.scheduleIn) == "function" then
        UIManager:scheduleIn(0, function()
            UIManager:scheduleIn(0, later)
        end)
    else
        scheduled = false
    end
end

--- 登记一块图片区域。opts.reason: "show" | "close" | "quality" | "change"
--- 省略 reason 时按 "quality"（伴读动画结束、需要清一次残影）。
function M.schedule(geom, opts)
    local g = geomCopy(geom)
    if not g then return end
    opts = opts or {}
    pending[#pending + 1] = {
        geom = g,
        reason = opts.reason or "quality",
        key = opts.key,
    }
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
        _papersprite_eink_full = true,
        _content_key = opts.key,
    }
    function Wrapper:init()
        if self._need_refresh == nil then
            self._need_refresh = true
        end
        if self._appeared == nil then
            self._appeared = false
        end
    end
    function Wrapper:mark()
        self._need_refresh = true
        self._content_changed = true
    end
    function Wrapper:handleEvent(event)
        local name = event and event.name
        if name == "OnShow" then
            M.enterPage()
        end
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
        local geom = { x = x, y = y, w = w, h = h }
        self._last_geom = geom
        if not self._need_refresh then
            return
        end
        local key = self._content_key
        local reason
        if quality_pending or not self._appeared then
            reason = "show"
        elseif self._content_changed then
            reason = "change"
        elseif key and on_screen[key] then
            -- 同一图片已经在屏上，重复 paint 不计换图。
            self._need_refresh = false
            return
        else
            reason = "change"
        end
        self._need_refresh = false
        self._content_changed = false
        self._appeared = true
        M.schedule(geom, { reason = reason, key = key })
    end
    local wdg = Wrapper:new{ child }
    if opts.key then
        wdg._content_key = opts.key
    end
    if opts.armed == false then
        wdg._need_refresh = false
        wdg._appeared = true
    end
    return wdg
end

return M
