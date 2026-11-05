-- SPDX-License-Identifier: MIT
--[[--
可翻面的明信片。正面是白边里的一幅画。
背面左边是信，右边是地址。邮票是这张画裁下来的 3:4 矩形，边缘是波浪齿孔。红色邮戳只压在左边或左角，不盖住整张。
邮编上下各一排，格数相同。墨水屏不翻转动画。
--]]
local M = {}

local function font(size)
    return require("ui/font"):getFace("cfont", size)
end

local function has(s) return type(s) == "string" and s ~= "" end

local function label(str, size, max_w, color, bold)
    return require("ui/widget/textwidget"):new{
        text = str, face = font(size), max_width = math.max(1, max_w),
        bold = bold or nil, fgcolor = color,
    }
end

local function rule(w, h, color)
    return require("ui/widget/linewidget"):new{
        dimen = require("ui/geometry"):new{ w = math.max(1, w), h = math.max(1, h) },
        background = color,
    }
end

local function utf8chars(s)
    local out, i = {}, 1
    while i <= #s do
        local b = s:byte(i)
        local len = 1
        if b >= 240 then len = 4 elseif b >= 224 then len = 3 elseif b >= 192 then len = 2 end
        if i + len - 1 > #s then len = 1 end
        out[#out + 1] = s:sub(i, i + len - 1)
        i = i + len
    end
    return out
end

local function textWidth(face, text, bold)
    if not text or text == "" then return 0 end
    return require("ui/rendertext"):sizeUtf8Text(0, 1000000, face, text, true, bold).x or 0
end

--- 按宽度折行。放不下的末行收成省略号。
local function wrapLines(text, face, max_w, max_lines, bold)
    max_lines = math.max(1, max_lines or 1)
    max_w = math.max(1, max_w)
    local lines, cur, overflow = {}, "", false
    local function push(s)
        if #lines >= max_lines then overflow = true return false end
        lines[#lines + 1] = s
        return true
    end
    for _, ch in ipairs(utf8chars(text or "")) do
        if ch == "\n" then
            if not push(cur) then break end
            cur = ""
        else
            local trial = cur .. ch
            if cur ~= "" and textWidth(face, trial, bold) > max_w then
                if not push(cur) then break end
                cur = ch
            else
                cur = trial
            end
        end
    end
    if cur ~= "" and not push(cur) then overflow = true end
    if overflow and lines[1] then
        local last = lines[#lines]
        while last ~= "" and textWidth(face, last .. "…", bold) > max_w do
            local cs = utf8chars(last)
            cs[#cs] = nil
            last = table.concat(cs)
        end
        lines[#lines] = last .. "…"
    end
    return lines
end

local ZIP_N = 6

--- 邮编固定六位。缺了就留空格，上下排的格子数仍然一样。
local function zipDigits(code)
    local s = type(code) == "string" and code:gsub("%D", "") or ""
    if s == "" then return string.rep(" ", ZIP_N) end
    if #s < ZIP_N then s = string.rep("0", ZIP_N - #s) .. s end
    return s:sub(1, ZIP_N)
end

local function digitBox(ch, sz, ink)
    local Blitbuffer = require("ffi/blitbuffer")
    local Geom = require("ui/geometry")
    local border = sz >= 22 and 2 or 1
    local inner = math.max(1, sz - border * 2)
    local face = math.max(12, math.min(26, sz - 12))
    local lab = label(ch, face, inner, ink, true)
    return require("ui/widget/container/framecontainer"):new{
        width = sz, height = sz, padding = 0, bordersize = border, margin = 0,
        background = Blitbuffer.COLOR_WHITE, color = Blitbuffer.COLOR_BLACK,
        require("ui/widget/container/centercontainer"):new{ dimen = Geom:new{ w = inner, h = inner }, lab },
    }
end

local function zipMetrics(max_w)
    local gap = 3
    local sz = math.floor((math.max(1, max_w) - (ZIP_N - 1) * gap) / ZIP_N)
    if sz < 16 then gap = 2 end
    sz = math.floor((math.max(1, max_w) - (ZIP_N - 1) * gap) / ZIP_N)
    sz = math.max(8, math.min(48, sz))
    while sz > 6 and ZIP_N * sz + (ZIP_N - 1) * gap > max_w do sz = sz - 1 end
    return sz, gap
end

local function zipRow(code, sz, gap, ink, align_right, width)
    local g = require("ui/widget/horizontalgroup"):new{ align = "center" }
    local Span = require("ui/widget/horizontalspan")
    local digits = zipDigits(code)
    for i = 1, ZIP_N do
        if i > 1 then g[#g + 1] = Span:new{ width = gap } end
        g[#g + 1] = digitBox(digits:sub(i, i), sz, ink)
    end
    if not align_right then return g end
    local h = math.max(1, g:getSize().h)
    return require("ui/widget/container/rightcontainer"):new{
        dimen = require("ui/geometry"):new{ w = width, h = h }, g,
    }
end

--- 信文左对齐，和「致 你」同一条边。
local function letterBlock(rows, width, size, ink, gap)
    local col = require("ui/widget/verticalgroup"):new{ align = "left" }
    local Span = require("ui/widget/verticalspan")
    if #rows == 0 then rows = { " " } end
    for i, text in ipairs(rows) do
        if i > 1 then col[#col + 1] = Span:new{ width = gap } end
        col[#col + 1] = label(text ~= "" and text or " ", size, width, ink)
    end
    return col
end

local function blank(w, h)
    return require("ui/widget/widget"):new{
        dimen = require("ui/geometry"):new{ w = math.max(1, w), h = math.max(1, h) },
    }
end

local function postmarkFile()
    return require("papersprite.host.interface").pluginDir() .. "/assets/postmark.png"
end

--- 黑字画进小位图，再按墨色涂成红色。TextWidget 的颜色在这块屏上落不成红。
local function redInk(text, size, max_w)
    local Blitbuffer = require("ffi/blitbuffer")
    local Geom = require("ui/geometry")
    local lab = label(text, size, max_w, Blitbuffer.COLOR_BLACK, true)
    local tw = math.max(1, lab:getSize().w)
    local th = math.max(1, lab:getSize().h)
    local src = Blitbuffer.new(tw, th, Blitbuffer.TYPE_BB8)
    src:fill(Blitbuffer.COLOR_WHITE)
    lab:paintTo(src, 0, 0)
    local wdg = require("ui/widget/widget"):new{ dimen = Geom:new{ w = tw, h = th } }
    function wdg:paintTo(bb, x, y)
        for yy = 0, th - 1 do
            for xx = 0, tw - 1 do
                local g = src:getPixel(xx, yy).a
                if g < 250 then
                    bb:setPixelBlend(x + xx, y + yy, Blitbuffer.ColorRGB32(0xC8, 0x28, 0x28, 255 - g))
                end
            end
        end
    end
    return wdg
end

--- 邮戳只压左边。沿边的位置每次重画随机，可以落在左上角、左边或左下角。

local function at(x, y, child)
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    return VerticalGroup:new{ align = "left",
        VerticalSpan:new{ width = math.max(0, y) },
        HorizontalGroup:new{ HorizontalSpan:new{ width = math.max(0, x) }, child },
    }
end

--- 邮票：3:4，钉在右上角，不跟着邮戳挪。邮戳中心只在左边，沿边随机，含两个左角。
local function postage(pc, w, h)
    local Blitbuffer = require("ffi/blitbuffer")
    local Geom = require("ui/geometry")
    w, h = math.max(8, math.floor(w)), math.max(8, math.floor(h))
    local sh = math.max(20, math.min(h, math.floor(w * 4 / 3)))
    local sw = math.max(16, math.floor(sh * 3 / 4))
    sh = math.max(20, math.min(h, math.floor(sw * 4 / 3)))
    sw = math.max(16, math.floor(sh * 3 / 4))
    local mark_sz = math.max(16, math.min(math.floor(sh * 0.62), w - 2, h - 2))
    local need = math.floor(mark_sz / 2)
    if w - sw < need then
        sw = math.max(16, w - need)
        sh = math.max(20, math.min(h, math.floor(sw * 4 / 3)))
        sw = math.max(16, math.floor(sh * 3 / 4))
        sh = math.max(20, math.min(h, math.floor(sw * 4 / 3)))
        mark_sz = math.max(16, math.min(math.floor(sh * 0.62), w - 2, h - 2))
        need = math.floor(mark_sz / 2)
    end
    local sx = math.max(0, w - sw)
    local sy = 0
    local where = math.random(3)
    local along = where == 1 and 0 or (where == 3 and 1 or (0.32 + math.random() * 0.36))
    local cx = sx
    local cy = sy + math.floor(along * math.max(1, sh - 1))
    local mx = math.max(0, math.min(w - mark_sz, cx - need))
    local my = math.max(sy, math.min(sy + sh - mark_sz, cy - need))
    my = math.max(0, math.min(h - mark_sz, my))
    local out = Blitbuffer.new(sw, sh, Blitbuffer.TYPE_BB8)
    out:fill(Blitbuffer.COLOR_WHITE)
    local scene = pc and pc.scene
    if scene then
        local src = require("papersprite.ui.compose").scene(scene, 280, 180)
        local amp = 2
        local period = 7
        local freq = (math.pi * 2) / period
        local margin = amp + 1
        local crop_w = math.max(1, math.floor(src.w * 0.42))
        local crop_h = math.max(1, math.floor(src.h * 0.62))
        local crop_x = math.floor(src.w * 0.24)
        local crop_y = math.floor(src.h * 0.08)
        local inner_w = math.max(1, sw - margin * 2)
        local inner_h = math.max(1, sh - margin * 2)
        local function inside(x, y)
            local top = margin + amp * math.sin(x * freq)
            local bot = sh - 1 - margin + amp * math.sin(x * freq + 1.7)
            if y < top or y > bot then return false end
            local left = margin + amp * math.sin(y * freq)
            local right = sw - 1 - margin + amp * math.sin(y * freq + 0.8)
            return x >= left and x <= right
        end
        local dark = Blitbuffer.Color8(0x33)
        for y = 0, sh - 1 do
            for x = 0, sw - 1 do
                if inside(x, y) then
                    if not inside(x - 1, y) or not inside(x + 1, y) or not inside(x, y - 1) or not inside(x, y + 1) then
                        out:setPixel(x, y, dark)
                    else
                        local u = (x - margin) / inner_w
                        local v = (y - margin) / inner_h
                        if u < 0 then u = 0 elseif u > 1 then u = 1 end
                        if v < 0 then v = 0 elseif v > 1 then v = 1 end
                        local px = crop_x + math.floor(u * (crop_w - 1))
                        local py = crop_y + math.floor(v * (crop_h - 1))
                        if px < 0 then px = 0 elseif px >= src.w then px = src.w - 1 end
                        if py < 0 then py = 0 elseif py >= src.h then py = src.h - 1 end
                        out:setPixel(x, y, src:getPixel(px, py))
                    end
                end
            end
        end
    end
    local pic = require("ui/widget/imagewidget"):new{
        image = out, image_disposable = true, width = sw, height = sh,
    }
    local mark = blank(mark_sz, mark_sz)
    pcall(function()
        local wdg = require("ui/widget/imagewidget"):new{
            file = postmarkFile(), width = mark_sz, height = mark_sz,
            alpha = true, scale_factor = 0,
        }
        if wdg then mark = wdg end
    end)
    local layers = { at(sx, sy, pic), at(mx, my, mark) }
    if pc and has(pc.stamp) and mark_sz >= 48 then
        local date = redInk(pc.stamp, math.max(11, math.floor(mark_sz * 0.16)), mark_sz - 6)
        local dw = date:getSize().w
        local dx = math.max(0, mx + math.floor((mark_sz - dw) / 2))
        local dy = math.max(0, my + math.floor(mark_sz * 0.20))
        layers[#layers + 1] = at(dx, dy, date)
    end
    return require("ui/widget/overlapgroup"):new{ dimen = Geom:new{ w = w, h = h }, unpack(layers) }
end

local function photo(scene, w, h)
    local Blitbuffer = require("ffi/blitbuffer")
    local Geom = require("ui/geometry")
    local iw, ih = math.max(1, w - 2), math.max(1, h - 2)
    local pic = blank(iw, ih)
    if scene then
        pcall(function()
            local wdg = require("papersprite.ui.compose").widget(scene, iw, ih)
            if wdg then pic = wdg end
        end)
    end
    return require("ui/widget/container/framecontainer"):new{
        width = w, height = h, padding = 0, bordersize = 1, margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        require("ui/widget/container/centercontainer"):new{ dimen = Geom:new{ w = iw, h = ih }, pic },
    }
end

--- 正面只留画。地名和天气在背面右侧，图上再贴一块就是重复。
local function front(pc, iw, ih)
    return photo(pc.scene, iw, ih)
end

local function back(pc, iw, ih)
    local Blitbuffer = require("ffi/blitbuffer")
    local Geom = require("ui/geometry")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local ink = Blitbuffer.COLOR_BLACK
    local gutter = 14
    local edge = ih >= 180 and 16 or (ih >= 120 and 10 or 6)
    local foot = edge
    -- 右侧要放下六格邮编和邮票，宁可信文折行。左右都留边，别贴着框和中线。
    local right_w = math.max(math.floor(iw * 0.50), 6 * 40 + 5 * 4)
    right_w = math.max(140, math.min(right_w, 320, math.max(120, iw - 150)))
    local left_w = math.max(1, iw - right_w - gutter * 2 - 1)
    local text_w = math.max(1, left_w - edge * 2)
    local right_inner = math.max(1, right_w - edge)
    local sz, zgap = zipMetrics(math.min(text_w, right_inner))
    local zip = pc.zip
    local top = zipRow(zip, sz, zgap, ink)
    local bot = zipRow(zip, sz, zgap, ink, true, right_inner)
    local top_h, bot_h = top:getSize().h, bot:getSize().h
    local sign_lab = label(has(pc.sign) and pc.sign or " ", 18, text_w, ink)
    local sign_h = sign_lab:getSize().h
    local sign = RightContainer:new{ dimen = Geom:new{ w = text_w, h = sign_h }, sign_lab }
    local write_size = 16
    local write_face = font(write_size)
    local line_gap = 6
    local dear = ""
    if has(pc.dear) or has(pc.you) then dear = (pc.dear or "") .. "  " .. (pc.you or "") end
    local dear_lab = has(dear) and label(dear, write_size, text_w, ink) or nil
    local dear_h = dear_lab and (dear_lab:getSize().h + line_gap) or 0
    local mid_h = math.max(1, ih - edge - top_h - 8 - sign_h - foot)
    local line_h = math.max(1, label("字", write_size, text_w, ink):getSize().h)
    local body_h = math.max(1, mid_h - dear_h)
    local slots = math.max(1, math.floor((body_h + line_gap) / (line_h + line_gap)))
    local rows = {}
    for _, ln in ipairs(wrapLines(pc.line or "", write_face, text_w, slots)) do
        rows[#rows + 1] = ln
    end
    local letter = letterBlock(rows, text_w, write_size, ink, line_gap)
    local letter_h = letter:getSize().h
    while #rows > 1 and letter_h > body_h do
        rows[#rows] = nil
        letter = letterBlock(rows, text_w, write_size, ink, line_gap)
        letter_h = letter:getSize().h
    end
    local stack = VerticalGroup:new{ align = "left" }
    if dear_lab then
        stack[#stack + 1] = dear_lab
        stack[#stack + 1] = VerticalSpan:new{ width = line_gap }
    end
    stack[#stack + 1] = letter
    local stack_h = dear_h + letter_h
    local push = math.max(0, math.floor((mid_h - stack_h) / 2))
    local left_col = VerticalGroup:new{ align = "left",
        VerticalSpan:new{ width = edge },
        top,
        VerticalSpan:new{ width = 8 + push },
        stack,
        VerticalSpan:new{ width = math.max(0, mid_h - push - stack_h) },
        sign,
    }
    local left = HorizontalGroup:new{
        HorizontalSpan:new{ width = edge },
        left_col,
        HorizontalSpan:new{ width = edge },
    }
    local stamp_w = math.min(right_inner, math.floor(ih * 0.56), 176)
    local stamp_h = math.floor(stamp_w * 1.16)
    local addr_min = 52
    local room = ih - edge - bot_h - foot - addr_min
    if stamp_h > room then
        stamp_h = math.max(36, room)
        stamp_w = math.max(28, math.floor(stamp_h / 1.16))
    end
    local place_size = ih >= 200 and 24 or (ih >= 140 and 20 or 16)
    local meta_size = math.max(14, place_size - 4)
    local fields = {}
    if has(pc.place) then fields[#fields + 1] = { pc.place, place_size, true } end
    if has(pc.weather) then fields[#fields + 1] = { pc.weather, meta_size, false } end
    if has(pc.date) then fields[#fields + 1] = { pc.date, meta_size, false } end
    local addr_bits = {}
    for i, field in ipairs(fields) do
        if i > 1 then addr_bits[#addr_bits + 1] = VerticalSpan:new{ width = 6 } end
        local lab = label(field[1], field[2], right_inner, ink, field[3])
        addr_bits[#addr_bits + 1] = RightContainer:new{ dimen = Geom:new{ w = right_inner, h = math.max(1, lab:getSize().h) }, lab }
    end
    local addr = #addr_bits > 0 and VerticalGroup:new{ align = "right", unpack(addr_bits) } or blank(1, 1)
    local addr_h = #addr_bits > 0 and addr:getSize().h or 0
    local addr_room = math.max(0, ih - edge - stamp_h - bot_h - foot)
    local addr_push = math.max(4, math.floor((addr_room - addr_h) / 2))
    local right_col = VerticalGroup:new{ align = "right",
        VerticalSpan:new{ width = edge },
        RightContainer:new{ dimen = Geom:new{ w = right_inner, h = stamp_h }, postage(pc, right_inner, stamp_h) },
        VerticalSpan:new{ width = addr_push },
        addr,
        VerticalSpan:new{ width = math.max(0, addr_room - addr_push - addr_h) },
        bot,
    }
    local right = HorizontalGroup:new{ right_col, HorizontalSpan:new{ width = edge } }
    return HorizontalGroup:new{ align = "top",
        left,
        HorizontalSpan:new{ width = gutter },
        rule(1, ih, Blitbuffer.Color8(0x88)),
        HorizontalSpan:new{ width = gutter },
        right,
    }
end

--- pc 来自 cardface.of，另可带 side = "front"|"back"
function M.widget(pc, w, h)
    local Blitbuffer = require("ffi/blitbuffer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    w, h = math.max(1, math.floor(w or 1)), math.max(1, math.floor(h or 1))
    local pad = math.max(8, math.min(12, math.floor(math.min(w, h) * 0.03)))
    local border = 1
    local inset = pad + border
    local iw, ih = math.max(1, w - inset * 2), math.max(1, h - inset * 2)
    local child = pc and pc.side == "back" and back(pc, iw, ih) or front(pc or {}, iw, ih)
    return FrameContainer:new{
        width = w, height = h, padding = pad, bordersize = border, margin = 0, radius = 0,
        background = Blitbuffer.COLOR_WHITE, color = Blitbuffer.COLOR_BLACK, child,
    }
end


--- 正反叠成一张图。月读在就弹局域网下载二维码，否则复制正文。
function M.share(pc, host)
    local T = require("papersprite.l10n")
    local function tell(msg)
        if host and host.notify then host:notify(msg) end
    end
    local ok = pcall(function()
        local Blitbuffer = require("ffi/blitbuffer")
        local w, h, gap, margin = 900, 560, 16, 16
        local function sided(side)
            local o = {}
            for k, val in pairs(pc or {}) do o[k] = val end
            o.side = side
            return o
        end
        local front = M.widget(sided("front"), w, h)
        local back = M.widget(sided("back"), w, h)
        front:getSize()
        back:getSize()
        local bb = Blitbuffer.new(w + margin * 2, h * 2 + gap + margin * 2, Blitbuffer.TYPE_BBRGB32)
        bb:fill(Blitbuffer.COLOR_WHITE)
        front:paintTo(bb, margin, margin)
        back:paintTo(bb, margin, margin + h + gap)
        local lfs = require("libs/libkoreader-lfs")
        local dir = require("datastorage"):getDataDir() .. "/screenshots"
        if not lfs.attributes(dir, "mode") then lfs.mkdir(dir) end
        local path = string.format("%s/aye-postcard-%s.png", dir, tostring(pc and pc.index or os.time()))
        local wrote, werr = bb:writeToFile(path, "png")
        bb:free()
        if not wrote then error(werr or "write") end
        local okm, mod = pcall(require, "features.remote.screenshot")
        if okm and type(mod) == "table" and type(mod.share) == "function" then
            mod.share(path)
            return
        end
        local text = table.concat({
            ((pc.dear or "") .. " " .. (pc.you or "")):gsub("^%s+", ""):gsub("%s+$", ""),
            pc.line or "",
            pc.sign or "",
            pc.place or "",
            pc.zip or "",
            pc.date or "",
        }, "\n")
        pcall(function() require("device").input.setClipboardText(text) end)
        tell(T("已复制明信片，可以粘贴分享"))
    end)
    if not ok then tell(T("明信片没能存下来")) end
end

return M
