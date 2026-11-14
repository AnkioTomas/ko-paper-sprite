-- SPDX-License-Identifier: MIT
--[[--
画面显色。插件只入库一套彩色素材，运行时按设备收成三种观感：

  mono        黑白墨水屏，或用户关掉「彩色渲染」：对比度 1.40（支点 128）后
              3 级灰 Bayer 4×4 有序抖动（#000 #AAA #FFF），合成走 BB8。
              这是运行时转换，不改彩色源资产。目的是减少丰富色彩转灰时的
              细碎中灰网点与发灰；浅色纸身 / 雪、细线与墨点应仍可辨。
              不是宣称「最好」的灰阶，对照样例见 art-samples/v5/audit/mono_preview/。
  eink_color  彩色墨水屏（hasColorScreen + hasEinkScreen，如 Kindle Colorsoft、Kobo Kaleido）：
              只做轻微色域适配，颜色仍然一眼能看出来，合成走 RGB32。
  lcd         彩色液晶（Android / 模拟器等）：接近原图，合成走 RGB32，apply 空操作。

判定只用 KOReader 公开 API：Device:hasColorScreen()、Device:hasEinkScreen()、
Device.screen:isColorEnabled()。不要在各处各自猜测型号。
阁楼合成、图标、明信片、伴读插画都走这一套。

apply 优先走 LuaJIT FFI 按 stride 扫描原始缓冲（旋转=0、反色=0 的 BB8 / BBRGB32），
保留 RGB32 的 alpha；其余情况回退到 getPixel/setPixel。
--]]
local M = {
    MONO = "mono",
    EINK_COLOR = "eink_color",
    LCD = "lcd",
}

local forced
local cached

-- 测试可关快路径，强制走 Lua 回退。
M.fast_path = true

--- 测试用：传入 "mono" / "eink_color" / "lcd"；传 nil 恢复自动判定。
function M.setMode(mode)
    forced = mode
    cached = nil
    pcall(function()
        require("papersprite.ui.compose").clear()
    end)
end

function M.reset()
    M.setMode(nil)
end

local function deviceFlag(Device, name)
    if type(Device) ~= "table" or type(Device[name]) ~= "function" then
        return false
    end
    local ok, value = pcall(Device[name], Device)
    return ok and value == true
end

local function colorEnabled(Device, has_color)
    local screen = Device and Device.screen
    if type(screen) == "table" and screen.isColorEnabled then
        local ok, on = pcall(function()
            return screen:isColorEnabled()
        end)
        if ok and type(on) == "boolean" then
            return on
        end
        ok, on = pcall(screen.isColorEnabled)
        if ok and type(on) == "boolean" then
            return on
        end
    end
    return has_color
end

local function detect()
    local ok, Device = pcall(require, "device")
    if not ok or type(Device) ~= "table" then
        return M.MONO
    end
    local has_color = deviceFlag(Device, "hasColorScreen")
    local color_on = colorEnabled(Device, has_color)
    if not has_color or not color_on then
        return M.MONO
    end
    if deviceFlag(Device, "hasEinkScreen") then
        return M.EINK_COLOR
    end
    return M.LCD
end

function M.mode()
    if forced then
        return forced
    end
    if not cached then
        cached = detect()
    end
    return cached
end

function M.isColor()
    return M.mode() ~= M.MONO
end

--- 离屏合成缓冲类型。彩色设备必须用 RGB，不能再强制 TYPE_BB8 把颜色丢掉。
--- 可传入显色模式；默认当前设备模式。分享导出应显式传 "lcd"，不要 setMode。
function M.bufferType(mode)
    local Blitbuffer = require("ffi/blitbuffer")
    if (mode or M.mode()) == M.MONO then
        return Blitbuffer.TYPE_BB8
    end
    return Blitbuffer.TYPE_BBRGB32
end

-- 有序抖动矩阵与历史 4 级灰、process_art.py --gray 对照路径相同；
-- 运行时黑白级数改为 3，避免丰富色彩转灰时铺满 #555 细碎网点。
-- process_art --gray 仍是旧 4 级对照，不会改入库的彩色 PNG。
local LV = { 0x00, 0xAA, 0xFF }
local MONO_CONTRAST = 1.40
local MONO_PIVOT = 128
local B4 = {
    { 0, 8, 2, 10 },
    { 12, 4, 14, 6 },
    { 3, 11, 1, 9 },
    { 15, 7, 13, 5 },
}

function M.bayer(x, y)
    return B4[(y % 4) + 1][(x % 4) + 1]
end

--- 0–255 亮度 → 对比度拉伸后再落到 3 级灰（#000 #AAA #FFF）。
function M.quantizeGray(luma, x, y)
    if luma < 0 then luma = 0 elseif luma > 255 then luma = 255 end
    luma = (luma - MONO_PIVOT) * MONO_CONTRAST + MONO_PIVOT
    if luma < 0 then luma = 0 elseif luma > 255 then luma = 255 end
    local v = luma / 255 * 2
    local base = math.floor(v)
    if base >= 2 then
        return 255
    end
    local step = 0
    if (v - base) * 16 > M.bayer(x, y) + 0.5 then
        step = 1
    end
    return LV[base + step + 1]
end

-- 与 KOReader ColorRGB24:getColor8 相同的亮度公式。
function M.luma(r, g, b)
    return math.floor((4898 * r + 9618 * g + 1869 * b) / 16384)
end

local function clamp8(v)
    if v < 0 then return 0 end
    if v > 255 then return 255 end
    return math.floor(v + 0.5)
end

-- 与原先 einkColor 公式相同，但不在每像素分配闭包。
local EINK_SAT = 0.88
local EINK_MID_LO = 8
local EINK_MID_SPAN = 247 - 8
local EINK_LEVELS = 12

local function einkQuant(c, bayer)
    local v = c / 255 * EINK_LEVELS
    local base = math.floor(v)
    if base >= EINK_LEVELS then
        return 255
    end
    if (v - base) * 16 > bayer then
        base = base + 1
    end
    return clamp8(base * 255 / EINK_LEVELS)
end

--- 彩色墨水屏：轻微降低一点饱和并做浅量化，适应滤色膜，但必须仍明显是彩色。
function M.einkColor(r, g, b, x, y)
    local yv = 0.299 * r + 0.587 * g + 0.114 * b
    -- 0.88：色相还在，只比液晶稍收一点，不要再压成淡彩。
    r = yv + (r - yv) * EINK_SAT
    g = yv + (g - yv) * EINK_SAT
    b = yv + (b - yv) * EINK_SAT
    -- 只避开两端极端值，避免滤色膜上发糊；范围仍接近原图。
    r = EINK_MID_LO + r * EINK_MID_SPAN / 255
    g = EINK_MID_LO + g * EINK_MID_SPAN / 255
    b = EINK_MID_LO + b * EINK_MID_SPAN / 255
    local bayer = M.bayer(x, y) + 0.5
    return einkQuant(r, bayer), einkQuant(g, bayer), einkQuant(b, bayer)
end

local function sizeOf(bb)
    local w = bb.w or (bb.getWidth and bb:getWidth())
    local h = bb.h or (bb.getHeight and bb:getHeight())
    return w or 0, h or 0
end

local TYPE_BB8 = 1
local TYPE_BBRGB32 = 5

local function typeConstants()
    local ok, BB = pcall(require, "ffi/blitbuffer")
    if ok and type(BB) == "table" then
        return BB.TYPE_BB8 or TYPE_BB8, BB.TYPE_BBRGB32 or TYPE_BBRGB32
    end
    return TYPE_BB8, TYPE_BBRGB32
end

--- 仅在未旋转、未反色、已知像素格式且 stride 合法时走原始缓冲扫描。
function M._fastKind(bb)
    if not M.fast_path or not bb or bb.data == nil then
        return nil
    end
    if type(bb.getRotation) == "function" then
        local ok, rot = pcall(bb.getRotation, bb)
        if not ok or rot ~= 0 then
            return nil
        end
    else
        return nil
    end
    if type(bb.getInverse) == "function" then
        local ok, inv = pcall(bb.getInverse, bb)
        if not ok or inv ~= 0 then
            return nil
        end
    else
        return nil
    end
    if type(bb.getType) ~= "function" then
        return nil
    end
    local ok, typ = pcall(bb.getType, bb)
    if not ok then
        return nil
    end
    local w = tonumber(bb.w)
    local h = tonumber(bb.h)
    local stride = tonumber(bb.stride)
    if not w or not h or not stride or w < 1 or h < 1 then
        return nil
    end
    local t8, t32 = typeConstants()
    if typ == t32 then
        if stride < w * 4 then
            return nil
        end
        return "rgb32", w, h, stride
    end
    if typ == t8 then
        if stride < w then
            return nil
        end
        return "bb8", w, h, stride
    end
    return nil
end

local function applyFast(bb, mode, kind, w, h, stride)
    local ok_ffi, ffi = pcall(require, "ffi")
    if not ok_ffi or not ffi or not ffi.cast then
        return false
    end
    local ok, ptr = pcall(ffi.cast, "unsigned char*", bb.data)
    if not ok or ptr == nil then
        return false
    end
    local einkColor, quantizeGray = M.einkColor, M.quantizeGray
    if kind == "rgb32" then
        if mode ~= M.EINK_COLOR then
            return false
        end
        for y = 0, h - 1 do
            local row = ptr + y * stride
            for x = 0, w - 1 do
                local p = row + x * 4
                local r, g, b = einkColor(p[0], p[1], p[2], x, y)
                p[0], p[1], p[2] = r, g, b
                -- p[3] alpha 保持不变
            end
        end
        return true
    end
    if kind == "bb8" then
        if mode ~= M.MONO then
            return false
        end
        for y = 0, h - 1 do
            local row = ptr + y * stride
            for x = 0, w - 1 do
                row[x] = quantizeGray(row[x], x, y)
            end
        end
        return true
    end
    return false
end

--- Lua 回退：getPixel / setPixel，尊重旋转与逻辑坐标。
function M._applyLua(bb, mode)
    local Blitbuffer = require("ffi/blitbuffer")
    local w, h = sizeOf(bb)
    if w < 1 or h < 1 then
        return bb
    end
    if mode == M.MONO then
        for y = 0, h - 1 do
            for x = 0, w - 1 do
                local g = bb:getPixel(x, y):getColor8().a
                bb:setPixel(x, y, Blitbuffer.Color8(M.quantizeGray(g, x, y)))
            end
        end
        return bb
    end
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local c = bb:getPixel(x, y):getColorRGB32()
            local r, g, b = M.einkColor(c:getR(), c:getG(), c:getB(), x, y)
            bb:setPixel(x, y, Blitbuffer.ColorRGB32(r, g, b, c:getAlpha()))
        end
    end
    return bb
end

--- 按模式原地改写位图。LCD 是空操作。
--- 第二参可指定模式（分享导出用 "lcd"）；省略则用当前设备模式。不会改全局 mode。
function M.apply(bb, mode)
    if not bb then
        return bb
    end
    mode = mode or M.mode()
    if mode == M.LCD then
        return bb
    end
    local kind, w, h, stride = M._fastKind(bb)
    if kind then
        local ok, used = pcall(applyFast, bb, mode, kind, w, h, stride)
        if ok and used then
            return bb
        end
    end
    return M._applyLua(bb, mode)
end

return M
