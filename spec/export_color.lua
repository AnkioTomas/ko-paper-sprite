-- SPDX-License-Identifier: MIT
-- 分享导出：在 mono / eink_color / lcd 下都写出鲜艳真 RGB，不 setMode，不污染屏幕缓存。
package.path = "paper-sprite.koplugin/?.lua;" .. package.path
if unpack == nil then unpack = table.unpack end

local EXPORT_W, EXPORT_H, GAP, MARGIN = 900, 560, 16, 16
local CANVAS_W = EXPORT_W + MARGIN * 2
local CANVAS_H = EXPORT_H * 2 + GAP + MARGIN * 2
local SAMPLE_DIR = "art-samples/v5/audit/t643u"

local TYPE_BB8, TYPE_BBRGB32 = 1, 5
local canvases = {}
local setmode_calls = 0

local function clamp(v)
    if v < 0 then return 0 end
    if v > 255 then return 255 end
    return math.floor(v + 0.5)
end

local function Color8(a)
    return { a = a, r = a, g = a, b = a, alpha = 255 }
end

local function ColorRGB32(r, g, b, a)
    return { r = r, g = g, b = b, alpha = a or 255 }
end

local function newBB(w, h, typ)
    typ = typ or TYPE_BBRGB32
    local bpp = typ == TYPE_BB8 and 1 or 4
    local stride = w * bpp
    local data = {}
    for i = 1, stride * h do data[i] = 255 end
    local bb = { w = w, h = h, stride = stride, _data = data, _typ = typ }
    function bb:getType() return typ end
    function bb:getRotation() return 0 end
    function bb:getInverse() return 0 end
    function bb:getWidth() return w end
    function bb:getHeight() return h end
    local function at(x, y) return y * stride + x * bpp + 1 end
    function bb:getPixel(x, y)
        if typ == TYPE_BB8 then
            local g = data[at(x, y)] or 0
            return {
                a = g,
                getColor8 = function() return { a = g } end,
                getColorRGB32 = function()
                    return {
                        getR = function() return g end,
                        getG = function() return g end,
                        getB = function() return g end,
                        getAlpha = function() return 255 end,
                    }
                end,
            }
        end
        local o = at(x, y)
        local r, g, b, a = data[o], data[o + 1], data[o + 2], data[o + 3]
        return {
            a = r,
            r = r, g = g, b = b, alpha = a,
            getColor8 = function()
                return { a = math.floor((4898 * r + 9618 * g + 1869 * b) / 16384) }
            end,
            getColorRGB32 = function()
                return {
                    getR = function() return r end,
                    getG = function() return g end,
                    getB = function() return b end,
                    getAlpha = function() return a end,
                }
            end,
        }
    end
    local function writePixel(x, y, r, g, b, a)
        if x < 0 or y < 0 or x >= w or y >= h then return end
        if typ == TYPE_BB8 then
            data[at(x, y)] = r
        else
            local o = at(x, y)
            data[o], data[o + 1], data[o + 2], data[o + 3] = r, g, b, a or 255
        end
    end
    function bb:setPixel(x, y, c)
        if type(c) ~= "table" then
            writePixel(x, y, c, c, c, 255)
            return
        end
        if c.r ~= nil then
            writePixel(x, y, c.r, c.g, c.b, c.alpha or 255)
        else
            local g = c.a or 0
            writePixel(x, y, g, g, g, 255)
        end
    end
    function bb:setPixelBlend(x, y, c)
        if x < 0 or y < 0 or x >= w or y >= h then return end
        local sr, sg, sb, sa = c.r, c.g, c.b, c.alpha or 255
        if typ == TYPE_BB8 then
            local luma = math.floor((4898 * sr + 9618 * sg + 1869 * sb) / 16384)
            local a = sa / 255
            local d = data[at(x, y)] or 255
            data[at(x, y)] = clamp(luma * a + d * (1 - a))
            return
        end
        local o = at(x, y)
        local a = sa / 255
        data[o] = clamp(sr * a + data[o] * (1 - a))
        data[o + 1] = clamp(sg * a + data[o + 1] * (1 - a))
        data[o + 2] = clamp(sb * a + data[o + 2] * (1 - a))
        data[o + 3] = 255
    end
    function bb:fill(color)
        for y = 0, h - 1 do
            for x = 0, w - 1 do
                self:setPixel(x, y, color)
            end
        end
    end
    function bb:blitFrom(src, dx, dy, sx, sy, cw, ch)
        for yy = 0, ch - 1 do
            for xx = 0, cw - 1 do
                local p = src:getPixel(sx + xx, sy + yy)
                local c = p:getColorRGB32()
                if typ == TYPE_BB8 then
                    self:setPixel(dx + xx, dy + yy, p:getColor8())
                else
                    self:setPixel(dx + xx, dy + yy, ColorRGB32(c:getR(), c:getG(), c:getB(), c:getAlpha()))
                end
            end
        end
    end
    function bb:rgbAt(x, y)
        local p = self:getPixel(x, y):getColorRGB32()
        return p:getR(), p:getG(), p:getB(), p:getAlpha()
    end
    function bb:writeToFile(path)
        local f = assert(io.open(path, "wb"))
        f:write(string.format("P6\n%d %d\n255\n", w, h))
        for y = 0, h - 1 do
            for x = 0, w - 1 do
                local r, g, b = self:rgbAt(x, y)
                f:write(string.char(r, g, b))
            end
        end
        f:close()
        return true
    end
    function bb:free() end
    if w == CANVAS_W and h == CANVAS_H and typ == TYPE_BBRGB32 then
        canvases[#canvases + 1] = bb
    end
    return bb
end

package.loaded["ffi/blitbuffer"] = {
    TYPE_BB8 = TYPE_BB8,
    TYPE_BBRGB32 = TYPE_BBRGB32,
    COLOR_WHITE = Color8(255),
    COLOR_BLACK = Color8(0),
    Color8 = Color8,
    ColorRGB32 = ColorRGB32,
    new = newBB,
}

local RED = { 220, 40, 30, 255 }
local BLUE = { 20, 40, 220, 128 }

local function fileColor(file)
    if type(file) == "string" and file:find("postmark", 1, true) then
        return 30, 30, 30, 255
    end
    if type(file) == "string" and file:find("export_blue", 1, true) then
        return BLUE[1], BLUE[2], BLUE[3], BLUE[4]
    end
    return RED[1], RED[2], RED[3], RED[4]
end

local function paintColor(bb, x, y, tw, th, r, g, b, a, alpha)
    for yy = 0, th - 1 do
        for xx = 0, tw - 1 do
            local c = ColorRGB32(r, g, b, a)
            if alpha then
                bb:setPixelBlend(x + xx, y + yy, c)
            else
                bb:setPixel(x + xx, y + yy, c)
            end
        end
    end
end

package.loaded["ui/widget/imagewidget"] = {
    new = function(_, opts)
        local o = {}
        for k, v in pairs(opts or {}) do o[k] = v end
        function o:getSize()
            return { w = o.width or (o.image and o.image.w) or 1, h = o.height or (o.image and o.image.h) or 1 }
        end
        function o:paintTo(bb, x, y)
            local tw = o.width or (o.image and o.image.w) or 0
            local th = o.height or (o.image and o.image.h) or 0
            if o.image then
                local sw, sh = o.image.w, o.image.h
                for yy = 0, th - 1 do
                    for xx = 0, tw - 1 do
                        local sx = math.floor(xx * sw / tw)
                        local sy = math.floor(yy * sh / th)
                        local p = o.image:getPixel(sx, sy)
                        local c = p:getColorRGB32()
                        local col = ColorRGB32(c:getR(), c:getG(), c:getB(), c:getAlpha())
                        if o.alpha then
                            bb:setPixelBlend(x + xx, y + yy, col)
                        else
                            bb:setPixel(x + xx, y + yy, col)
                        end
                    end
                end
                return
            end
            if o.file then
                local r, g, b, a = fileColor(o.file)
                paintColor(bb, x, y, tw, th, r, g, b, a, o.alpha)
            end
        end
        function o:free() end
        function o:handleEvent() end
        return o
    end,
}

local function Size(w, h) return { w = w, h = h } end

package.loaded["ui/geometry"] = {
    new = function(_, o) o = o or {} o.x = o.x or 0 o.y = o.y or 0 o.w = o.w or 0 o.h = o.h or 0 return o end,
}

local function walkPaint(node, bb, x, y)
    if type(node) ~= "table" then return end
    if type(node.paintTo) == "function" then
        node:paintTo(bb, x, y)
    end
end

local function makeWidget()
    return {
        new = function(_, opts)
            local o = {}
            if type(opts) == "table" then
                for k, v in pairs(opts) do o[k] = v end
            end
            function o:getSize()
                if o.dimen then return Size(o.dimen.w, o.dimen.h) end
                if o.width and o.height then return Size(o.width, o.height) end
                local w, h, is_h, is_v = 0, 0, o._kind == "h", o._kind == "v"
                for _, child in ipairs(o) do
                    if type(child) == "table" and child.getSize then
                        local s = child:getSize()
                        if is_h then
                            w = w + (s.w or 0)
                            if (s.h or 0) > h then h = s.h end
                        elseif is_v then
                            h = h + (s.h or 0)
                            if (s.w or 0) > w then w = s.w end
                        else
                            if (s.w or 0) > w then w = s.w end
                            if (s.h or 0) > h then h = s.h end
                        end
                    elseif type(child) == "table" and child.width then
                        w = w + (child.width or 0)
                    end
                end
                return Size(math.max(1, w), math.max(1, h))
            end
            function o:paintTo(bb, x, y)
                if o.background and o.width and o.height and bb.fill then
                    for yy = 0, (o.height or 0) - 1 do
                        for xx = 0, (o.width or 0) - 1 do
                            bb:setPixel(x + xx, y + yy, o.background)
                        end
                    end
                end
                local cx, cy = x, y
                if o._kind == "frame" then
                    cx = x + (o.padding or 0)
                    cy = y + (o.padding or 0)
                end
                if o._kind == "center" and o.child then
                    local s = o.child.getSize and o.child:getSize() or Size(0, 0)
                    local dw = (o.dimen and o.dimen.w or s.w)
                    local dh = (o.dimen and o.dimen.h or s.h)
                    walkPaint(o.child, bb, x + math.floor((dw - s.w) / 2), y + math.floor((dh - s.h) / 2))
                    return
                end
                if o._kind == "right" and (o[1] or o.child) then
                    local child = o[1] or o.child
                    local s = child.getSize and child:getSize() or Size(0, 0)
                    local dw = o.dimen and o.dimen.w or s.w
                    walkPaint(child, bb, x + math.max(0, dw - s.w), y)
                    return
                end
                if o._kind == "h" then
                    local acc = 0
                    for _, child in ipairs(o) do
                        if type(child) == "table" then
                            if child._kind == "span" then
                                acc = acc + (child.width or 0)
                            else
                                walkPaint(child, bb, x + acc, y)
                                local s = child.getSize and child:getSize() or Size(0, 0)
                                acc = acc + (s.w or 0)
                            end
                        end
                    end
                    return
                end
                if o._kind == "v" then
                    local acc = 0
                    for _, child in ipairs(o) do
                        if type(child) == "table" then
                            if child._kind == "span" then
                                acc = acc + (child.width or 0)
                            else
                                walkPaint(child, bb, x, y + acc)
                                local s = child.getSize and child:getSize() or Size(0, 0)
                                acc = acc + (s.h or 0)
                            end
                        end
                    end
                    return
                end
                if o.child then walkPaint(o.child, bb, cx, cy) end
                for _, child in ipairs(o) do
                    if type(child) == "table" then walkPaint(child, bb, cx, cy) end
                end
            end
            function o:free() end
            function o:handleEvent() end
            return o
        end,
    }
end

local base = makeWidget()
local function kinded(kind, extra)
    local src = makeWidget()
    return {
        new = function(_, opts)
            opts = opts or {}
            opts._kind = kind
            if extra then for k, v in pairs(extra) do if opts[k] == nil then opts[k] = v end end end
            return src.new(_, opts)
        end,
    }
end

package.loaded["ui/widget/widget"] = kinded("plain")
package.loaded["ui/widget/container/framecontainer"] = kinded("frame")
package.loaded["ui/widget/container/centercontainer"] = kinded("center")
package.loaded["ui/widget/container/rightcontainer"] = kinded("right")
package.loaded["ui/widget/verticalgroup"] = kinded("v")
package.loaded["ui/widget/horizontalgroup"] = kinded("h")
package.loaded["ui/widget/verticalspan"] = kinded("span")
package.loaded["ui/widget/horizontalspan"] = kinded("span")
package.loaded["ui/widget/overlapgroup"] = kinded("overlap")
package.loaded["ui/widget/linewidget"] = kinded("line")
package.loaded["ui/widget/textwidget"] = {
    new = function(_, opts)
        local o = {}
        for k, v in pairs(opts or {}) do o[k] = v end
        local tw = math.max(1, math.min(o.max_width or 40, #(o.text or "") * 8))
        local th = 16
        function o:getSize() return Size(tw, th) end
        function o:paintTo(bb, x, y)
            if not bb.setPixel then return end
            for yy = 0, th - 1 do
                for xx = 0, math.min(tw, 8) - 1 do
                    bb:setPixel(x + xx, y + yy, o.fgcolor or Color8(0))
                end
            end
        end
        return o
    end,
}
package.loaded["ui/font"] = { getFace = function(_, _, size) return { size = size or 16 } end }
package.loaded["ui/rendertext"] = {
    sizeUtf8Text = function(_, _, _, text)
        return { x = math.max(1, #(text or "") * 8) }
    end,
}
package.loaded["libs/libkoreader-lfs"] = {
    attributes = function(path)
        local f = io.open(path, "r")
        if f then f:close() return "directory" end
        local p = io.popen("test -d '" .. path .. "' && echo dir || true")
        local out = p:read("*a") or ""
        p:close()
        if out:find("dir") then return "directory" end
        return nil
    end,
    mkdir = function(path)
        os.execute("mkdir -p '" .. path .. "'")
        return true
    end,
}
package.loaded["datastorage"] = {
    getDataDir = function()
        return SAMPLE_DIR
    end,
}

package.loaded["papersprite.host.interface"] = {
    pluginDir = function() return "/tmp/aye-export-spec-plugin" end,
    check = function() end,
}

local Display = require("papersprite.ui.display")
local Compose = require("papersprite.ui.compose")
local Postcard = require("papersprite.ui.postcard")

local orig_setMode = Display.setMode
function Display.setMode(mode)
    setmode_calls = setmode_calls + 1
    return orig_setMode(mode)
end

local scene = {
    bg = "places/export_red.png",
    overlays = {
        { img = "souvenirs/export_blue.png", h = 1, x = 0.5, y = 0.5, full = true },
    },
}

local function expectedBlend()
    local a = BLUE[4] / 255
    return clamp(BLUE[1] * a + RED[1] * (1 - a)),
        clamp(BLUE[2] * a + RED[2] * (1 - a)),
        clamp(BLUE[3] * a + RED[3] * (1 - a))
end

local function almost(a, b, tol)
    return math.abs(a - b) <= (tol or 1)
end

local function isGray(r, g, b)
    return r == g and g == b
end

local er, eg, eb = expectedBlend()
assert(er ~= eg or eg ~= eb, "fixture itself must be colorful")

local lfs = require("libs/libkoreader-lfs") -- already stubbed
os.execute("mkdir -p " .. SAMPLE_DIR)

local samples = {}

for _, mode in ipairs({ "mono", "eink_color", "lcd" }) do
    Display.setMode(mode)
    Compose.clear()
    setmode_calls = 0
    local before_mode = Display.mode()
    assert(before_mode == mode)

    local screen = Compose.scene(scene, 80, 40, "export-color-test")
    local k_screen = Compose._key("export-color-test", 80, 40)
    local k_lcd = Compose._key("export-color-test", 80, 40, "lcd")
    assert(k_screen:find(":" .. mode, 1, true), "screen cache key includes device mode")
    assert(k_lcd:find(":lcd", 1, true), "explicit lcd key")
    if mode ~= "lcd" then
        assert(k_screen ~= k_lcd, "export lcd key is isolated from screen key")
    end

    local sr, sg, sb = screen:rgbAt(10, 10)
    if mode == "mono" then
        assert(screen:getType() == TYPE_BB8, "screen mono uses BB8")
        assert(isGray(sr, sg, sb), "screen mono pixels are gray")
        local levels = { [0] = true, [0xAA] = true, [0xFF] = true }
        assert(levels[sr], "screen mono stays on 3-level palette")
        assert(not (almost(sr, er) and almost(sg, eg) and almost(sb, eb)), "screen mono is not the vivid blend")
    elseif mode == "eink_color" then
        assert(screen:getType() == TYPE_BBRGB32, "screen eink_color uses RGB32")
        local qr, qg, qb = Display.einkColor(er, eg, eb, 10, 10)
        assert(almost(sr, qr, 2) and almost(sg, qg, 2) and almost(sb, qb, 2), "screen eink_color follows einkColor")
        assert(not (almost(sr, er) and almost(sg, eg) and almost(sb, eb)), "screen eink_color is quantized, not source")
    else
        assert(screen:getType() == TYPE_BBRGB32)
        assert(almost(sr, er) and almost(sg, eg) and almost(sb, eb), "screen lcd keeps source blend")
    end
    local screen_id = tostring(screen)

    canvases = {}
    local pc = {
        index = "color-" .. mode,
        scene = scene,
        stamp = "11.14",
        place = "雪镇",
        line = "hello",
        sign = "阿页",
    }
    local path, err = Postcard.exportImage(pc)
    assert(path, "exportImage writes a file: " .. tostring(err))
    assert(path:find("aye-postcard-color-" .. mode, 1, true), path)
    local f = io.open(path, "rb")
    assert(f, "export file exists: " .. path)
    local header = f:read(16)
    f:close()
    local is_rgb = header and (header:find("P6", 1, true) or header:find("\x89PNG", 1, true) or header:byte(1) == 0x89)
    assert(is_rgb, "export is a real RGB image file")

    assert(Display.mode() == mode, "device mode unchanged after export")
    assert(setmode_calls == 0, "export must not call setMode")

    local canvas = canvases[#canvases]
    assert(canvas, "captured export canvas")
    assert(canvas:getType() == TYPE_BBRGB32, "export target is TYPE_BBRGB32")
    assert(canvas.w == CANVAS_W and canvas.h == CANVAS_H)

    -- 正面画心：页边 16 + 卡片 padding（约 12）+ 相框 1，取偏里一点。
    local fx, fy = MARGIN + 24, MARGIN + 24
    local found
    for yy = fy, fy + 80 do
        for xx = fx, fx + 80 do
            local r, g, b, a = canvas:rgbAt(xx, yy)
            if almost(r, er, 2) and almost(g, eg, 2) and almost(b, eb, 2) and a == 255 then
                found = { x = xx, y = yy, r = r, g = g, b = b }
                break
            end
        end
        if found then break end
    end
    assert(found, "front photo on export is the vivid RGB blend, not device quantization")
    assert(not isGray(found.r, found.g, found.b), "export front is not grayscale")

    -- 背面邮票：下半张里应仍是彩色原资源（含透明合成后的鲜艳色，不是设备量化）。
    local by = MARGIN + EXPORT_H + GAP
    local stamp_found
    for yy = by, CANVAS_H - 1 do
        for xx = 0, CANVAS_W - 1 do
            local r, g, b = canvas:rgbAt(xx, yy)
            if almost(r, er, 8) and almost(g, eg, 8) and almost(b, eb, 8) then
                stamp_found = true
                break
            end
        end
        if stamp_found then break end
    end
    assert(stamp_found, "back postage crop stays vivid color")

    -- 缓存隔离：屏幕那张还在，像素没被 lcd 导出覆盖。
    local screen2 = Compose.scene(scene, 80, 40, "export-color-test")
    assert(tostring(screen2) == screen_id, "screen cache entry reused after export")
    local sr2, sg2, sb2 = screen2:rgbAt(10, 10)
    assert(sr2 == sr and sg2 == sg and sb2 == sb, "screen pixels unchanged after color export")

    samples[#samples + 1] = path
    print(string.format("ok %s export=%s front=(%d,%d,%d) screen=(%d,%d,%d) mode=%s",
        mode, path, found.r, found.g, found.b, sr, sg, sb, Display.mode()))
end

Display.reset()
print("export_color: all modes passed")
for _, p in ipairs(samples) do print("sample", p) end
