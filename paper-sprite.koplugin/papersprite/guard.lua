-- SPDX-License-Identifier: MIT
--[[--
阿页入口的错误隔离：直接用月读 `ui/guard.lua`（日志 + 可复制的错误页，堆栈里的 .koplugin 归到阿页）。
没装月读时只写日志、吞掉这次调用，保证不带崩阅读器。只包阿页拥有的入口（事件、定时器、绘制、点按回调）。
--]]
local Guard = {}

local function moon()
    local ok, G = pcall(require, "ui.guard")
    if ok and type(G) == "table" and G.call then return G end
end

local function fallback(label, ok, ...)
    if ok then return ... end
    require("logger").err("papersprite", label, (...))
end

function Guard.call(label, fn, ...)
    local G = moon()
    if G then return G.call(label, fn, ...) end
    return fallback(label, xpcall(fn, debug.traceback, ...))
end

local broken = {}
function Guard.paint(label, fn, ...)
    local G = moon()
    if G then return G.paint(label, fn, ...) end
    if broken[label] then return end
    local ok, err = xpcall(fn, debug.traceback, ...)
    if not ok then broken[label] = true require("logger").err("papersprite", label, err) end
end

function Guard.wrap(label, fn)
    return function(...) return Guard.call(label, fn, ...) end
end

return Guard
