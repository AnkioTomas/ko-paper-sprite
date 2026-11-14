-- SPDX-License-Identifier: MIT
-- 图片区域刷新：tickAfterNext 防整页合并；进页/首次 full；换图 ui；
-- 每 N 次换图批次才 full；墙面合并一次；重复 paint 不计；导出不刷屏；
-- 真实 WidgetContainer handleEvent 链路。
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

assert_eq(Eink.FULL_EVERY, 5, "conservative N")

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

-- 1) schedule 推迟；同一拍两块区域只 flush 一次，外接矩形，首次/quality 为 full
Eink._reset()
installUI()
Eink.schedule({ x = 10, y = 20, w = 498, h = 249 })
Eink.schedule({ x = 10, y = 300, w = 100, h = 50 })
assert_eq(#calls, 0, "must not setDirty in the same beat as schedule")
assert_eq(#ticks, 1, "one tickAfterNext for batched schedules")
assert_eq(#Eink._pending(), 2, "both regions pending")
flush()
assert_eq(#calls, 1, "one union dirty, not one full per widget")
assert_eq(calls[1].mode, "full", "bare schedule is quality full (companion / first)")
assert_eq(calls[1].widget, nil, "nil widget, do not dirty whole window")
assert_eq(calls[1].dither, true)
assert_eq(calls[1].x, 10)
assert_eq(calls[1].y, 20)
assert_eq(calls[1].w, 498)
assert_eq(calls[1].h, 330) -- 300+50-20
assert_eq(#Eink._pending(), 0)

-- 2) wrap 首次 paint 为进页 full；重复 paint 不登记
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
assert_eq(calls[1].mode, "full", "first appearance flashes once")
wdg:paintTo(nil, 5, 7)
assert_eq(#ticks, 1, "still no extra schedule after flush")

-- 3) mark 换图：前 FULL_EVERY-1 次 ui，第 N 次 full；计数按批次
Eink._reset()
installUI()
local evs = {}
local c2 = child(80, 40, evs)
local w2 = Eink.wrap(c2, { key = "scene:b" })
w2:handleEvent({ name = "OnShow" })
w2:paintTo(nil, 1, 2)
flush()
assert_eq(calls[1].mode, "full", "OnShow first paint is quality full")
assert_eq(Eink._changes(), 0, "quality reset counter")

for i = 1, Eink.FULL_EVERY - 1 do
    w2:mark()
    w2:paintTo(nil, 1, 2)
    flush()
    assert_eq(calls[#calls].mode, "ui", "change " .. i .. " stays ui")
    assert_eq(calls[#calls].dither, true, "ui still requests dither")
    assert_eq(Eink._changes(), i)
end
w2:mark()
w2:paintTo(nil, 1, 2)
flush()
assert_eq(calls[#calls].mode, "full", "Nth change batch is regional full")
assert_eq(Eink._changes(), 0, "counter resets after full")
-- 再一次换图又从 ui 计
w2:mark()
w2:paintTo(nil, 1, 2)
flush()
assert_eq(calls[#calls].mode, "ui")
assert_eq(Eink._changes(), 1)

-- 4) 九宫格墙：同一拍 9 个新图，只有一次 full，不是九次
Eink._reset()
installUI()
local wall = {}
for i = 1, 9 do
    wall[i] = Eink.wrap(child(40, 30), { key = "wall:" .. i })
    wall[i]:paintTo(nil, 10 + (i - 1) * 50, 20)
end
assert_eq(#ticks, 1, "wall shares one tickAfterNext")
assert_eq(#Eink._pending(), 9)
flush()
assert_eq(#calls, 1, "wall must not fire nine fulls")
assert_eq(calls[1].mode, "full")
assert_eq(calls[1].x, 10)
assert_eq(calls[1].y, 20)
assert_eq(calls[1].w, 10 + 8 * 50 + 40 - 10)
assert_eq(calls[1].h, 30)
-- 同样九张再 paint：不计换图，不刷新
local n_ticks, n_calls = #ticks, #calls
for i = 1, 9 do
    wall[i]:paintTo(nil, 10 + (i - 1) * 50, 20)
end
assert_eq(#ticks, n_ticks, "same images on a wall do not reschedule")
assert_eq(#calls, n_calls)

-- 5) 墙面上只换一张：一批只计 1，走 ui（若未到 N）
Eink._reset()
installUI()
local cards = {}
for i = 1, 9 do
    cards[i] = Eink.wrap(child(40, 30), { key = "card:" .. i })
    cards[i]:paintTo(nil, i * 50, 0)
end
flush()
assert_eq(calls[1].mode, "full")
cards[3]:mark()
cards[3]:paintTo(nil, 150, 0)
-- 其他未 mark 的再 paint 不应入队
for i = 1, 9 do
    if i ~= 3 then cards[i]:paintTo(nil, i * 50, 0) end
end
assert_eq(#Eink._pending(), 1, "only the changed card is pending")
flush()
assert_eq(#calls, 2)
assert_eq(calls[2].mode, "ui")
assert_eq(Eink._changes(), 1)

-- 6) 进页 enterPage：即便图已在屏，也做一次高质量 full
Eink.enterPage()
for i = 1, 9 do
    cards[i]._need_refresh = true
    cards[i]:paintTo(nil, i * 50, 0)
end
flush()
assert_eq(calls[#calls].mode, "full", "enter page quality even if keys known")
assert_eq(#calls, 3, "enter page still one dirty")
assert_eq(Eink._changes(), 0)

-- 7) 离开页面：scheduleLast close 一次 full
local before = #calls
Eink.leavePage()
Eink.scheduleLast("close")
flush()
assert_eq(#calls, before + 1)
assert_eq(calls[#calls].mode, "full", "leave page quality refresh")

-- 8) 无效 geom 忽略
Eink._reset()
installUI()
Eink.schedule({ x = 0, y = 0, w = 0, h = 10 })
assert_eq(#Eink._pending(), 0)
assert_eq(#ticks, 0)

-- 9) wrap(nil)；handleEvent 传播，OnPreventStandby 不抛，不误触发 full 计数
assert_eq(Eink.wrap(nil), nil)
Eink._reset()
installUI()
local evs9 = {}
local w9 = Eink.wrap(child(80, 40, evs9), { key = "evt" })
assert(type(w9.handleEvent) == "function", "wrapper has handleEvent")
local parent = { w9 }
for _, widget in ipairs(parent) do
    widget:handleEvent({ name = "OnShow" })
end
assert_eq(evs9[1], "OnShow", "wrapper forwards handleEvent to ImageWidget child")
local ok_call = pcall(function() w9:handleEvent({ name = "OnPreventStandby" }) end)
assert(ok_call, "handleEvent must not throw")
assert_eq(evs9[2], "OnPreventStandby")
w9:handleEvent({ name = "OnAllowStandby" })
assert_eq(evs9[3], "OnAllowStandby")
-- OnShow 只打质量标记，本身不 setDirty
assert_eq(#calls, 0)
w9:paintTo(nil, 0, 0)
flush()
assert_eq(calls[1].mode, "full")

-- 10) 离屏导出（wrap=false / 不 wrap）绝不能请求屏幕刷新
Eink._reset()
installUI()
-- 直接 paint 未 wrap 的控件
local raw = child(100, 80)
raw:paintTo(nil, 0, 0)
assert_eq(#ticks, 0)
assert_eq(#calls, 0, "unwrapped offscreen paint must not setDirty")
-- armed=false 的 wrap 首次也不刷
local held = Eink.wrap(child(20, 20), { key = "export", armed = false })
held:paintTo(nil, 3, 4)
assert_eq(#calls, 0)
assert_eq(#ticks, 0, "armed=false export wrap does not refresh the live screen")

-- 11) 伴读 schedule quality：动画结束后一次 full，不是按帧累加
Eink._reset()
installUI()
-- 模拟动画只用外部 ui，不走 schedule；结束时 quality
Eink.schedule({ x = 8, y = 8, w = 64, h = 64 }, { reason = "quality" })
flush()
assert_eq(calls[1].mode, "full")
assert_eq(Eink._changes(), 0)

-- 12) 纯 change 达不到 N 时不会 full；确认不用 flashpartial
Eink._reset()
installUI()
local ch = Eink.wrap(child(10, 10), { key = "chg" })
ch:paintTo(nil, 0, 0)
flush() -- first show full
for i = 1, 3 do
    ch:mark()
    ch:paintTo(nil, 0, 0)
    flush()
    assert_eq(calls[#calls].mode, "ui")
    assert(calls[#calls].mode ~= "flashpartial")
    assert(calls[#calls].mode ~= "flashui")
end

print("ok eink_image schedule / wrap / cadence / wall / lifecycle")
