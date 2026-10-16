-- SPDX-License-Identifier: MIT
--[[--
把分层画面（背景 + 叠加层）合成到一张离屏位图，按目标尺寸「铺满裁切」，并缓存。
首页组件每次重绘都要显示同一张阁楼 / 明信片缩略图，墨水屏上反复解码缩放 PNG 很慢，
所以合成结果按「画面签名 + 尺寸」缓存在内存里（最多 CAP 张，最久未用的先释放）。
--]]
local M = { CAP = 24 }
local cache, order = {}, {}

local function touch(k)
    for i, x in ipairs(order) do if x == k then table.remove(order, i) break end end
    order[#order + 1] = k
end

local function evict()
    while #order > M.CAP do
        local k = table.remove(order, 1)
        local bb = cache[k]
        cache[k] = nil
        if bb then pcall(function() bb:free() end) end
    end
end

local function paintScene(scene, W0, H0)
    local Blitbuffer = require("ffi/blitbuffer")
    local ImageWidget = require("ui/widget/imagewidget")
    local dir = require("papersprite.host.interface").pluginDir() .. "/assets/"
    local full = Blitbuffer.new(W0, H0, Blitbuffer.TYPE_BB8)
    full:fill(Blitbuffer.COLOR_WHITE)
    local function put(rel, x, y, w, h, alpha)
        local ok, wdg = pcall(function()
            return ImageWidget:new{ file = dir .. rel, width = w, height = h, scale_factor = 0, alpha = alpha, file_do_cache = false }
        end)
        if ok and wdg then
            pcall(function() wdg:paintTo(full, x, y) end)
            pcall(function() wdg:free() end)
        end
    end
    put(scene.bg, 0, 0, W0, H0, scene.icon == true)
    for _, o in ipairs(scene.overlays or {}) do
        local ow, oh
        if o.full then ow, oh = W0, H0 else oh = math.max(1, math.floor(H0 * o.h)) ow = oh end
        put(o.img, math.floor(W0 * o.x - ow / 2), math.floor(H0 * o.y - oh / 2), ow, oh, true)
    end
    return full
end

--- 画面 → W×H 位图（素材是 2:1，按短边铺满后居中裁切）。返回的位图归缓存所有，调用方不要 free。
function M.scene(scene, W, H, sig)
    W, H = math.max(1, math.floor(W)), math.max(1, math.floor(H))
    local k = (sig or require("papersprite.ui.widget_data").sig(scene)) .. "@" .. W .. "x" .. H
    if cache[k] then touch(k) return cache[k] end
    local W0, H0 = W, H
    if not scene.icon then W0 = math.max(W, H * 2) H0 = math.floor(W0 / 2) end
    local full = paintScene(scene, W0, H0)
    local out = full
    if W0 ~= W or H0 ~= H then
        local Blitbuffer = require("ffi/blitbuffer")
        out = Blitbuffer.new(W, H, Blitbuffer.TYPE_BB8)
        out:blitFrom(full, 0, 0, math.floor((W0 - W) / 2), math.floor((H0 - H) / 2), W, H)
        full:free()
    end
    cache[k] = out
    touch(k)
    evict()
    return out
end

--- 显示用控件：缓存位图包一层 ImageWidget（不交出所有权）
function M.widget(scene, W, H, sig)
    local bb = M.scene(scene, W, H, sig)
    return require("ui/widget/imagewidget"):new{ image = bb, image_disposable = false, width = W, height = H }
end

--- 单张素材（图标）缩放后缓存
function M.icon(rel, size)
    return M.widget({ bg = rel, overlays = {}, icon = true }, size, size, "icon:" .. rel)
end

function M.clear()
    for k, bb in pairs(cache) do pcall(function() bb:free() end) cache[k] = nil end
    order = {}
end

return M
