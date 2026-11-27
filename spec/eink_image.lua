-- SPDX-License-Identifier: MIT
-- 图片区域补刷：tickAfterNext 防整页合并；只用 ui + dither，从不 full；
-- 墙面合并一次；同 key 已在屏不重复刷；导出不刷屏；真实 handleEvent 链路。
package.path = "paper-sprite.koplugin/?.lua;" .. package.path
if unpack == nil then unpack = table.unpack end

local calls, ticks = {}, {}

package.loaded["ui/geometry"] = {
    new = function(_, t)
        t = t or _
        return { x = t.x or 0, y = t.y or 0, w = t.w or 0, h = t.h or 0 }
    end
}

local WidgetContainer = {}
function WidgetContainer:extend(o)
    o = o or {}
    setmetatable(o, { __index = self })
    return o
end
function WidgetContainer:new(o)
    o = o or {}
    setmetatable(o, { __index = self })
    if type(o.init) == "function" then o:init() end
    return o
end
function WidgetContainer:handleEvent(event)
    if self[1] and type(self[1].handleEvent) == "function" then
        return self[1]:handleEvent(event)
    end
    return false
end
function WidgetContainer:getSize()
    if self[1] and type(self[1].getSize) == "function" then
        return self[1]:getSize()
    end
    return { w = 0, h = 0 }
end
package.loaded["ui/widget/container/widgetcontainer"] = WidgetContainer
package.loaded["ui/widget/widget"] = WidgetContainer

local function installUI()
    calls, ticks = {}, {}
    package.loaded["ui/uimanager"] = {
        setDirty = function(_, widget, mode, region, dither)
            calls[#calls + 1] = {
                widget = widget,
                mode = mode,
                x = region and region.x, y = region and region.y,
                w = region and region.w, h = region and region.h,
                dither = dither,
                region = region,
            }
        end,
        tickAfterNext = function(_, fn) ticks[#ticks + 1] = fn end,
        nextTick = function(_, fn) ticks[#ticks + 1] = fn end,
    }
end

installUI()
package.loaded["papersprite.ui.eink_image"] = nil
local Eink = require("papersprite.ui.eink_image")

local function assert_eq(a, b, msg)
    if a ~= b then error((msg or "assert_eq") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end


local function flush()
    assert(#ticks >= 1, "expected a deferred tick")
    local fn = ticks[#ticks]
    fn()
end

local function child(w, h, evs)
    evs = evs or {}
    return {
        getSize = function() return { w = w or 80, h = h or 40 } end,
        paints = 0,
        paintTo = function(self) self.paints = self.paints + 1 end,
        handleEvent = function(_, ev)
            evs[#evs + 1] = ev and ev.name
            return true
        end,
    }
end

local function noFull()
    for i, c in ipairs(calls) do
        assert(c.mode == "ui" and c.dither == true, "call " .. i .. " must be dithered ui, got " .. tostring(c.mode))
    end
end

-- 1) schedule 推迟；同一拍两块区域只 flush 一次，外接矩形
Eink._reset()
installUI()
Eink.schedule({ x = 10, y = 20, w = 498, h = 249 })
Eink.schedule({ x = 10, y = 300, w = 100, h = 50 })
assert_eq(#calls, 0, "must not setDirty in the same beat as schedule")
assert_eq(#ticks, 1, "one tickAfterNext for batched schedules")
assert_eq(#Eink._pending(), 2, "both regions pending")
flush()
assert_eq(#calls, 1, "one union dirty")
assert_eq(calls[1].widget, nil, "nil widget, do not dirty whole window")
assert_eq(calls[1].x, 10)
assert_eq(calls[1].y, 20)
assert_eq(calls[1].w, 498)
assert_eq(calls[1].h, 330) -- 300+50-20
assert_eq(#Eink._pending(), 0)
noFull()

-- 2) wrap 首次 paint 登记；重复 paint 不登记
Eink._reset()
installUI()
local c = child(80, 40)
local wdg = Eink.wrap(c, { key = "scene:a" })
wdg:paintTo(nil, 5, 7)
assert_eq(c.paints, 1)
assert_eq(wdg.dimen.x, 0, "dimen must not bake screen x")
assert_eq(wdg.dimen.w, 80)
assert_eq(#ticks, 1)
assert_eq(#calls, 0, "still deferred")
wdg:paintTo(nil, 5, 7)
assert_eq(#ticks, 1, "repeat paintTo is not a change")
flush()
assert_eq(#calls, 1)
assert_eq(calls[1].x, 5)
assert_eq(calls[1].y, 7)
assert_eq(calls[1].w, 80)
wdg:paintTo(nil, 5, 7)
assert_eq(#ticks, 1, "still no extra schedule after flush")
noFull()

-- 3) 连续换图：每次都是 ui，不会每隔几次 full
Eink._reset()
installUI()
local w2 = Eink.wrap(child(80, 40), { key = "scene:b" })
w2:paintTo(nil, 1, 2)
flush()
for _ = 1, 12 do
    w2:mark()
    w2:paintTo(nil, 1, 2)
    flush()
end
assert_eq(#calls, 13)
noFull()

-- 4) 九宫格墙：同一拍 9 个新图只刷一次；再 paint 不刷
Eink._reset()
installUI()
local wall = {}
for i = 1, 9 do
    wall[i] = Eink.wrap(child(40, 30), { key = "wall:" .. i })
    wall[i]:paintTo(nil, 10 + (i - 1) * 50, 20)
end
assert_eq(#ticks, 1, "wall shares one tickAfterNext")
flush()
assert_eq(#calls, 1, "wall refreshes once")
assert_eq(calls[1].w, 8 * 50 + 40)
assert_eq(calls[1].h, 30)
local n_ticks = #ticks
for i = 1, 9 do wall[i]:paintTo(nil, 10 + (i - 1) * 50, 20) end
assert_eq(#ticks, n_ticks, "same images on a wall do not reschedule")
-- 只换一张：只有它入队
wall[3]:mark()
for i = 1, 9 do wall[i]:paintTo(nil, 10 + (i - 1) * 50, 20) end
assert_eq(#Eink._pending(), 1, "only the changed card is pending")
flush()
noFull()

-- 5) 组件重建、同一 key 已在屏：不再刷；forget（阁楼关掉）后再出现要刷
Eink._reset()
installUI()
local first = Eink.wrap(child(10, 10), { key = "rebuilt" })
first:paintTo(nil, 0, 0)
flush()
local n = #calls
Eink.wrap(child(10, 10), { key = "rebuilt" }):paintTo(nil, 0, 0)
assert_eq(#Eink._pending(), 0, "rebuilt wrapper with an on-screen key must not refresh")
Eink.forget()
Eink.wrap(child(10, 10), { key = "rebuilt" }):paintTo(nil, 0, 0)
flush()
assert_eq(#calls, n + 1, "after forget the image refreshes again")
noFull()

-- 6) 无效 geom 忽略；wrap(nil)
Eink._reset()
installUI()
Eink.schedule({ x = 0, y = 0, w = 0, h = 10 })
assert_eq(#Eink._pending(), 0)
assert_eq(#ticks, 0)
assert_eq(Eink.wrap(nil), nil)

-- 7) handleEvent 传播，不抛，本身不 setDirty
local evs = {}
local w7 = Eink.wrap(child(80, 40, evs), { key = "evt" })
w7:handleEvent({ name = "OnShow" })
assert(pcall(function() w7:handleEvent({ name = "OnPreventStandby" }) end), "handleEvent must not throw")
assert_eq(evs[1], "OnShow", "wrapper forwards handleEvent to ImageWidget child")
assert_eq(evs[2], "OnPreventStandby")
assert_eq(#calls, 0)

-- 8) 离屏导出（不 wrap / armed=false）绝不能请求屏幕刷新
Eink._reset()
installUI()
child(100, 80):paintTo(nil, 0, 0)
Eink.wrap(child(20, 20), { key = "export", armed = false }):paintTo(nil, 3, 4)
assert_eq(#calls, 0)
assert_eq(#ticks, 0, "export never refreshes the live screen")

print("ok eink_image ui-only / wall / rebuild / export")
