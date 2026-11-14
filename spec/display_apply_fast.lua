-- SPDX-License-Identifier: MIT
-- LuaJIT-only: FFI scan vs Lua getPixel/setPixel pixel equivalence,
-- alpha, padded stride, and a local microbench. Run with:
--   luajit -e 'package.path=...; dofile("spec/display_apply_fast.lua")'
-- This file does not load the moon runtime or start the emulator.

local ffi = require("ffi")

local function fail(msg)
    io.stderr:write("FAIL: " .. msg .. "\n")
    os.exit(1)
end

local function assert_eq(a, b, msg)
    if a ~= b then
        fail((msg or "assert_eq") .. string.format(" (%s ~= %s)", tostring(a), tostring(b)))
    end
end

-- Minimal package search so require("papersprite.ui.display") works
-- when this file is run from the repo root or via an explicit path.
local function pluginRoot()
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) == "@" then
        src = src:sub(2)
    end
    local dir = src:match("^(.*)/") or "."
    return dir .. "/../paper-sprite.koplugin/?.lua"
end
package.path = pluginRoot() .. ";" .. package.path

package.loaded["ffi/blitbuffer"] = {
    TYPE_BB8 = 1,
    TYPE_BBRGB32 = 5,
    Color8 = function(a)
        return { a = a }
    end,
    ColorRGB32 = function(r, g, b, a)
        return {
            r = r, g = g, b = b, alpha = a,
            getR = function(self) return self.r end,
            getG = function(self) return self.g end,
            getB = function(self) return self.b end,
            getAlpha = function(self) return self.alpha end,
        }
    end,
}

local D = require("papersprite.ui.display")

local function rawRGB32(w, h, stride)
    stride = stride or (w * 4)
    local data = ffi.new("unsigned char[?]", stride * h)
    ffi.fill(data, stride * h, 0)
    local function pix(x, y)
        return data + y * stride + x * 4
    end
    local bb = {
        w = w, h = h, stride = stride, pixel_stride = w, data = data,
        getType = function() return 5 end,
        getRotation = function() return 0 end,
        getInverse = function() return 0 end,
        getPixel = function(_, x, y)
            local p = pix(x, y)
            return {
                getColorRGB32 = function()
                    return package.loaded["ffi/blitbuffer"].ColorRGB32(p[0], p[1], p[2], p[3])
                end,
            }
        end,
        setPixel = function(_, x, y, c)
            local p = pix(x, y)
            p[0], p[1], p[2], p[3] = c.r, c.g, c.b, c.alpha
        end,
    }
    return bb, data, pix
end

local function rawBB8(w, h, stride)
    stride = stride or w
    local data = ffi.new("unsigned char[?]", stride * h)
    ffi.fill(data, stride * h, 0)
    local bb = {
        w = w, h = h, stride = stride, pixel_stride = w, data = data,
        getType = function() return 1 end,
        getRotation = function() return 0 end,
        getInverse = function() return 0 end,
        getPixel = function(_, x, y)
            return { getColor8 = function() return { a = data[y * stride + x] } end }
        end,
        setPixel = function(_, x, y, c)
            data[y * stride + x] = c.a
        end,
    }
    return bb, data
end

local function fillRGB(bb, pix, fn)
    for y = 0, bb.h - 1 do
        for x = 0, bb.w - 1 do
            local r, g, b, a = fn(x, y)
            local p = pix(x, y)
            p[0], p[1], p[2], p[3] = r, g, b, a
        end
        -- mark padding
        for k = bb.w * 4, bb.stride - 1 do
            bb.data[y * bb.stride + k] = 0xEE
        end
    end
end

local function fillGray(bb, fn)
    for y = 0, bb.h - 1 do
        for x = 0, bb.w - 1 do
            bb.data[y * bb.stride + x] = fn(x, y)
        end
        for k = bb.w, bb.stride - 1 do
            bb.data[y * bb.stride + k] = 0xEE
        end
    end
end

local function copyBuf(src, nbytes)
    local dst = ffi.new("unsigned char[?]", nbytes)
    ffi.copy(dst, src, nbytes)
    return dst
end

-- Pattern covering primaries, pastels, near-white paper, near-black ink, and alpha 0/1/128/255.
local function colorFn(x, y)
    local kind = (x + y * 3) % 8
    if kind == 0 then return 255, 0, 0, 255 end
    if kind == 1 then return 40, 200, 40, 128 end
    if kind == 2 then return 20, 40, 220, 1 end
    if kind == 3 then return 245, 236, 220, 255 end -- cream paper
    if kind == 4 then return 250, 250, 250, 255 end -- snow
    if kind == 5 then return 12, 10, 8, 255 end     -- ink
    if kind == 6 then return 200, 180, 60, 0 end    -- fully transparent
    return 90, 110, 130, 200
end

local function grayFn(x, y)
    local vals = { 0, 16, 24, 40, 128, 173, 210, 230, 245, 255 }
    return vals[(x + y * 5) % #vals + 1]
end

-- 1) eink_color: FFI vs Lua, padded stride, exact RGB, alpha unchanged, padding intact.
do
    local w, h, stride = 17, 13, 17 * 4 + 10
    local a, da, pix_a = rawRGB32(w, h, stride)
    local b, db, pix_b = rawRGB32(w, h, stride)
    fillRGB(a, pix_a, colorFn)
    fillRGB(b, pix_b, colorFn)
    D.setMode("eink_color")
    D.fast_path = true
    assert(D._fastKind(a) == "rgb32", "fast kind rgb32")
    D.apply(a)
    D.fast_path = false
    D._applyLua(b, "eink_color")
    local mismatch = 0
    local maxdiff = 0
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local pa, pb = pix_a(x, y), pix_b(x, y)
            for c = 0, 2 do
                local dlt = math.abs(pa[c] - pb[c])
                if dlt > maxdiff then maxdiff = dlt end
                if pa[c] ~= pb[c] then mismatch = mismatch + 1 end
            end
            assert_eq(pa[3], pb[3], "alpha ffi vs lua")
            local _, _, _, a0 = colorFn(x, y)
            assert_eq(pa[3], a0, "alpha preserved vs source")
        end
        for k = w * 4, stride - 1 do
            assert_eq(da[y * stride + k], 0xEE, "rgb32 padding")
            assert_eq(db[y * stride + k], 0xEE, "rgb32 padding lua")
        end
    end
    if mismatch ~= 0 then
        fail("eink_color FFI vs Lua mismatches=" .. mismatch .. " maxdiff=" .. maxdiff)
    end
    print(string.format("ok eink_color FFI vs Lua exact, %dx%d stride=%d maxdiff=%d", w, h, stride, maxdiff))
end

-- 2) mono: FFI vs Lua, padded stride.
do
    local w, h, stride = 19, 11, 19 + 7
    local a, da = rawBB8(w, h, stride)
    local b, db = rawBB8(w, h, stride)
    fillGray(a, grayFn)
    fillGray(b, grayFn)
    D.setMode("mono")
    D.fast_path = true
    assert(D._fastKind(a) == "bb8", "fast kind bb8")
    D.apply(a)
    D.fast_path = false
    D._applyLua(b, "mono")
    local mismatch = 0
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            if da[y * stride + x] ~= db[y * stride + x] then
                mismatch = mismatch + 1
            end
            local want = D.quantizeGray(grayFn(x, y), x, y)
            assert_eq(da[y * stride + x], want, "mono ffi equals quantizeGray")
        end
        for k = w, stride - 1 do
            assert_eq(da[y * stride + k], 0xEE, "bb8 padding")
        end
    end
    if mismatch ~= 0 then
        fail("mono FFI vs Lua mismatches=" .. mismatch)
    end
    print(string.format("ok mono FFI vs Lua exact, %dx%d stride=%d", w, h, stride))
end

-- 3) fallback: rotation / inverse / bad stride / unknown type.
do
    D.setMode("eink_color")
    D.fast_path = true
    local bb = rawRGB32(4, 2, 20)
    bb.getRotation = function() return 1 end
    assert(D._fastKind(bb) == nil, "rot fallback")
    bb = rawRGB32(4, 2, 20)
    bb.getInverse = function() return 1 end
    assert(D._fastKind(bb) == nil, "inv fallback")
    bb = rawRGB32(4, 2, 20)
    bb.stride = 4 * 4 - 1
    assert(D._fastKind(bb) == nil, "short stride fallback")
    bb = rawRGB32(4, 2, 20)
    bb.getType = function() return 4 end
    assert(D._fastKind(bb) == nil, "rgb24 fallback")
    print("ok fallback conditions")
end

-- 4) local microbench (offscreen, no display). Not a device measurement.
local function bench(label, w, h, stride, typ, mode, use_fast)
    local bb, data, pix
    if typ == "rgb32" then
        bb, data, pix = rawRGB32(w, h, stride)
        fillRGB(bb, pix, colorFn)
    else
        bb, data = rawBB8(w, h, stride)
        fillGray(bb, grayFn)
    end
    D.setMode(mode)
    D.fast_path = use_fast
    -- warmup
    if use_fast then
        D.apply(bb)
        if typ == "rgb32" then fillRGB(bb, pix, colorFn) else fillGray(bb, grayFn) end
    else
        D._applyLua(bb, mode)
        if typ == "rgb32" then fillRGB(bb, pix, colorFn) else fillGray(bb, grayFn) end
    end
    local t0 = os.clock()
    if use_fast then D.apply(bb) else D._applyLua(bb, mode) end
    local ms = (os.clock() - t0) * 1000
    print(string.format("bench %s %dx%d %s: %.1f ms", label, w, h, use_fast and "fast" or "lua", ms))
    return ms
end

-- ColorSoft attic / postcard sizes from the 207 investigation.
bench("eink attic", 1272, 636, 1272 * 4 + 16, "rgb32", "eink_color", false)
bench("eink attic", 1272, 636, 1272 * 4 + 16, "rgb32", "eink_color", true)
bench("eink postcard", 1232, 748, 1232 * 4 + 16, "rgb32", "eink_color", false)
bench("eink postcard", 1232, 748, 1232 * 4 + 16, "rgb32", "eink_color", true)
bench("mono attic", 1272, 636, 1272 + 16, "bb8", "mono", false)
bench("mono attic", 1272, 636, 1272 + 16, "bb8", "mono", true)

print("ALL OK")
