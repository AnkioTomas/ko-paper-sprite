-- SPDX-License-Identifier: MIT
--[[--
把分层画面（背景 + 叠加层）合成到一张离屏位图，按目标尺寸「铺满裁切」，并缓存。
首页组件每次重绘都要显示同一张阁楼 / 明信片缩略图，墨水屏上反复解码缩放 PNG 很慢，
所以合成结果按「画面签名 + 尺寸 + 显色模式」缓存在内存里（最多 CAP 张，最久未用的先释放）。
素材是彩色 PNG；黑白墨水屏在合成后收成 3 级灰，彩色墨水屏只做轻微色域适配（仍明显是彩色），液晶接近原图。
见 papersprite.ui.display。
--]]
local Display = require("papersprite.ui.display")

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

--- 按 W0×H0 排版、居中裁出 W×H：只分配 W×H，图层带负偏移画进去（blitFrom 会裁掉越界部分）。
--- 竖屏整屏时 W0 可达 W 的 2.7 倍，不能先画整幅再裁。
local function paintScene(scene, W, H, W0, H0, mode)
    local Blitbuffer = require("ffi/blitbuffer")
    local ImageWidget = require("ui/widget/imagewidget")
    local dir = require("papersprite.host.interface").pluginDir() .. "/assets/"
    local out = Blitbuffer.new(W, H, Display.bufferType(mode))
    out:fill(Blitbuffer.COLOR_WHITE)
    local ox, oy = -math.floor((W0 - W) / 2), -math.floor((H0 - H) / 2)
    local function put(rel, x, y, w, h, alpha)
        local ok, wdg = pcall(function()
            return ImageWidget:new{ file = dir .. rel, width = w, height = h, scale_factor = 0, alpha = alpha, file_do_cache = false }
        end)
        if ok and wdg then
            pcall(function() wdg:paintTo(out, x + ox, y + oy) end)
            pcall(function() wdg:free() end)
        end
    end
    put(scene.bg, 0, 0, W0, H0, scene.icon == true)
    for _, o in ipairs(scene.overlays or {}) do
        local ow, oh
        if o.full then ow, oh = W0, H0 else oh = math.max(1, math.floor(H0 * o.h)) ow = oh end
        put(o.img, math.floor(W0 * o.x - ow / 2), math.floor(H0 * o.y - oh / 2), ow, oh, true)
    end
    return out
end

local function cacheKey(sig, W, H, mode)
    return (sig or "") .. "@" .. W .. "x" .. H .. ":" .. (mode or Display.mode())
end

--- 画面 → W×H 位图（素材是 2:1，按短边铺满后居中裁切）。返回的位图归缓存所有，调用方不要 free。
function M.scene(scene, W, H, sig, mode)
    W, H = math.max(1, math.floor(W)), math.max(1, math.floor(H))
    mode = mode or Display.mode()
    local k = cacheKey(sig or require("papersprite.ui.widget_data").sig(scene), W, H, mode)
    if cache[k] then
        touch(k)
        require("papersprite.ui.timing").record("compose_hit", 0, k)
        return cache[k]
    end
    local Timing = require("papersprite.ui.timing")
    local t0 = Timing.now()
    local W0, H0 = W, H
    if not scene.icon then W0 = math.max(W, H * 2) H0 = math.floor(W0 / 2) end
    local out = paintScene(scene, W, H, W0, H0, mode)
    Display.apply(out, mode)
    Timing.record("compose_miss", Timing.now() - t0, k)
    cache[k] = out
    touch(k)
    evict()
    return out
end

--- 显示用控件：缓存位图包一层 ImageWidget（不交出所有权）
function M.widget(scene, W, H, sig, opts)
    local mode, do_wrap
    if type(opts) == "table" then
        mode = opts.mode
        do_wrap = opts.wrap
    elseif type(opts) == "string" then
        mode = opts
    end
    local bb = M.scene(scene, W, H, sig, mode)
    local wdg = require("ui/widget/imagewidget"):new{ image = bb, image_disposable = false, width = W, height = H }
    -- 图标小、对比高，不必每次全刷；阁楼/明信片等画面要区域刷新。
    -- 分享离屏导出必须 wrap=false，避免 paintTo 把刷新请求打到正在看的屏幕上。
    if do_wrap == nil then
        do_wrap = not (scene and scene.icon)
    end
    if do_wrap then
        local key = cacheKey(sig or require("papersprite.ui.widget_data").sig(scene), W, H, mode)
        wdg = require("papersprite.ui.eink_image").wrap(wdg, { key = key })
    end
    return wdg
end

--- 单张素材（图标）缩放后缓存
function M.icon(rel, size)
    return M.widget({ bg = rel, overlays = {}, icon = true }, size, size, "icon:" .. rel)
end

function M.clear()
    for k, bb in pairs(cache) do pcall(function() bb:free() end) cache[k] = nil end
    order = {}
end

-- 测试用：当前缓存键（含显色模式）。
function M._key(sig, W, H, mode)
    return cacheKey(sig, W, H, mode)
end

return M
