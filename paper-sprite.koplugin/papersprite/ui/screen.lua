-- SPDX-License-Identifier: MIT
--[[--
全屏浮层界面。思路同 ko-adarkroom：covers_fullscreen + 整屏刷新，盖住月读首页。
皮肤：月读在时（能 require ui.themes）用月读主题组件——标题栏、卡片框、文字、按钮、翻页条、主题色；
每个组件单独 pcall，某个组件失败只有它退回 KOReader 原生控件。skin = "native" 强制原生。
view = {
  title, scene?（分层画面）, icons?, lines = {string|{text,muted}},
  grid?  = { cols, cells = { {scene, new, caption, callback} } },        明信片墙：缩略图网格
  list?  = { rows = { {scene, new, title, line, date, callback} } },      明信片列表：缩略图 + 文字
  pager? = { page, pages, prev, next },                                   翻页条（n / m）
  buttons = { btn | {btn,...} }, on_close?
}
缩略图走 ui/compose 的合成缓存（墨水屏上不反复解码缩放）。
--]]
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Interface = require("papersprite.host.interface")
local Screen = Device.screen

local S = InputContainer:extend{ covers_fullscreen = true, modal = true }

function S.open(view, on_close, skin)
    return S:new{ view = view, on_close = on_close, skin = skin }
end

local function try(fn, ...)
    local ok, r = pcall(fn, ...)
    if ok and r then return r end
end

--- 可点的包装
local function tap(child, w, h, cb)
    local box = InputContainer:new{ dimen = Geom:new{ x = 0, y = 0, w = w, h = h }, child }
    box.ges_events = { TapPS = { GestureRange:new{ ges = "tap", range = function() return box.dimen end } } }
    function box:onTapPS() if cb then cb() end return true end
    return box
end

--- 组件工具箱：先原生，月读可用时逐个替换成主题组件（每个都有原生兜底）
local function kit(skin)
    local px = function(n) return Screen:scaleBySize(n) end
    local k = { moon = false, px = px, bg = Blitbuffer.COLOR_WHITE, ink = Blitbuffer.COLOR_BLACK,
        muted = Blitbuffer.Color8(0x77), face = Font:getFace("cfont", 19), small = Font:getFace("cfont", 15) }
    local native = {}
    function native.button(text, w, cb)
        return require("ui/widget/button"):new{ text = text, width = w, callback = cb, bordersize = px(1), radius = px(4), text_font_size = 17 }
    end
    function native.text(text, w, muted, small)
        return TextBoxWidget:new{ text = text, face = small and k.small or k.face, width = w, fgcolor = muted and k.muted or k.ink }
    end
    function native.line(text, w, muted, small)
        return TextWidget:new{ text = text, face = small and k.small or k.face, max_width = w, fgcolor = muted and k.muted or k.ink }
    end
    function native.title(w, title, on_close)
        local xw, hh = px(52), px(44)
        local close = tap(CenterContainer:new{ dimen = Geom:new{ w = xw, h = hh }, TextWidget:new{ text = "✕", face = k.face, fgcolor = k.muted } }, xw, hh, on_close)
        return HorizontalGroup:new{ align = "center",
            LeftContainer:new{ dimen = Geom:new{ w = w - xw, h = hh }, TextWidget:new{ text = "  " .. (title or ""), face = k.face, fgcolor = k.muted, max_width = w - xw } }, close }
    end
    function native.frame(child, border)
        return FrameContainer:new{ padding = 0, bordersize = border and px(2) or 0, color = k.ink, background = k.bg, child }
    end
    function native.badge(text)
        return FrameContainer:new{ bordersize = px(1), padding = px(2), margin = 0, background = Blitbuffer.COLOR_WHITE, color = k.ink,
            TextWidget:new{ text = text, face = k.small } }
    end
    function native.pager(w, p)
        local bw = math.floor(w / 4)
        local mid = CenterContainer:new{ dimen = Geom:new{ w = w - bw * 2, h = px(44) }, TextWidget:new{ text = p.page .. " / " .. p.pages, face = k.face } }
        return HorizontalGroup:new{ align = "center",
            native.button("‹ 上一页", bw, p.page > 1 and p.prev or function() end), mid,
            native.button("下一页 ›", bw, p.page < p.pages and p.next or function() end) }
    end
    for name, fn in pairs(native) do k[name] = fn end
    if skin == "native" then return k end
    local ok, Theme = pcall(require, "ui.themes")
    if not ok or not Theme then return k end
    local t = try(function() return Theme.current() end)
    if not t then return k end
    k.moon = true
    k.px = function(n) return try(Theme.px, n) or px(n) end
    pcall(function()
        local c = t.color
        k.bg, k.ink, k.muted = Blitbuffer.Color8(c.page), Blitbuffer.Color8(c.ink), Blitbuffer.Color8(c.muted)
    end)
    local function guarded(name, fn)
        k[name] = function(...)
            local ok2, r = pcall(fn, ...)
            if ok2 and r then return r end
            return native[name](...)
        end
    end
    guarded("button", function(text, w, cb) return require("ui.themes.widgets.button"):new{ text = text, width = w, callback = cb } end)
    guarded("text", function(text, w, muted, small)
        return require("ui.themes.widgets.text").box(small and "caption" or "body", text, w, { color = muted and t.color.muted or nil, bg = t.color.page })
    end)
    guarded("line", function(text, w, muted, small)
        return require("ui.themes.widgets.text").line(small and "caption" or "body", text, { width = w, color = muted and t.color.muted or nil })
    end)
    guarded("title", function(w, title, on_close)
        return require("ui.themes.widgets.titlebar").widget{ width = w, title = title or "", right_icon = "close", right_callback = on_close }
    end)
    guarded("frame", function(child, border)
        local Box = require("ui.themes.widgets.box")
        local sz = child:getSize()
        local style = border and t.card or t.image
        local inset = Theme.px((style and style.border) or 0) * 2
        return Box:new{ style = style, width = sz.w + inset, height = sz.h + inset, child }
    end)
    guarded("pager", function(w, p)
        return require("ui.themes.widgets.pager").widget{ width = w, page = p.page, pages = p.pages, on_prev = p.prev, on_next = p.next }
    end)
    return k
end
S.kit = kit

local function img(rel, w, h, alpha)
    return try(function()
        return require("ui/widget/imagewidget"):new{ file = Interface.pluginDir() .. "/assets/" .. rel,
            width = w, height = h, scale_factor = 0, alpha = alpha, file_do_cache = false }
    end)
end

--- 缩略图（缓存）+ 可选「新」角标
local function thumb(k, scene, w, h, new)
    local Compose = require("papersprite.ui.compose")
    local pic = try(Compose.widget, scene, w, h)
    if not pic then return require("ui/widget/container/widgetcontainer"):new{ dimen = Geom:new{ w = w, h = h } } end
    if not new then return pic end
    return OverlapGroup:new{ dimen = Geom:new{ w = w, h = h }, pic, k.badge("新") }
end

function S:init()
    local w, h = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = w, h = h }
    local k = kit(self.skin)
    self.kit_moon = k.moon
    local px, pad = k.px, k.px(20)
    local inner = w - pad * 2
    local v = self.view
    local body = VerticalGroup:new{ align = "left" }
    local function indent(wdg) return HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, wdg } end
    local function gap(n) table.insert(body, VerticalSpan:new{ width = px(n) }) end
    -- 标题栏
    table.insert(body, k.title(w, v.title, function() self:onClose() end))
    gap(8)
    -- 分层画面：缓存合成成一张位图
    local scene = v.scene or (v.image and { bg = v.image, overlays = {} })
    if scene then
        local SW = inner
        local SH = math.floor(SW / 2)
        local pic = try(function() return require("papersprite.ui.compose").widget(scene, SW, SH) end)
        if not pic then
            local grp = OverlapGroup:new{ dimen = Geom:new{ w = SW, h = SH } }
            local bg = img(scene.bg, SW, SH, false)
            if bg then table.insert(grp, bg) end
            pic = grp
        end
        table.insert(body, CenterContainer:new{ dimen = Geom:new{ w = w, h = SH + px(6) }, k.frame(pic, scene.frame) })
        gap(12)
    end
    if v.icons and #v.icons > 0 then
        local isz = px(56)
        local row = HorizontalGroup:new{ align = "center" }
        for i, rel in ipairs(v.icons) do
            if i > 1 then table.insert(row, HorizontalSpan:new{ width = px(10) }) end
            local sz = i == 1 and isz * 2 or isz
            local wdg = try(function() return require("papersprite.ui.compose").icon(rel, sz) end) or img(rel, sz, sz, true)
            if wdg then table.insert(row, wdg) end
        end
        table.insert(body, indent(row))
        gap(8)
    end
    for _, l in ipairs(v.lines or {}) do
        local t = type(l) == "table" and l or { text = l }
        table.insert(body, indent(k.text(t.text, inner, t.muted)))
        gap(6)
    end
    -- 明信片墙：缩略图网格
    if v.grid then
        local cols, g = v.grid.cols or 3, px(12)
        local cw = math.floor((inner - g * (cols - 1)) / cols)
        local ch = math.floor(cw / 2)
        local caph = k.line("阿", cw, true, true):getSize().h
        local row
        for i, c in ipairs(v.grid.cells) do
            if (i - 1) % cols == 0 then
                if row then table.insert(body, indent(row)) gap(12) end
                row = HorizontalGroup:new{ align = "top" }
            else
                table.insert(row, HorizontalSpan:new{ width = g })
            end
            local cell = VerticalGroup:new{ align = "left", k.frame(thumb(k, c.scene, cw, ch, c.new), false), VerticalSpan:new{ width = px(4) },
                k.line(c.caption or "", cw, true, true) }
            table.insert(row, tap(cell, cw, ch + caph + px(4), c.callback))
        end
        if row then table.insert(body, indent(row)) gap(12) end
    end
    -- 明信片列表：左缩略图 + 地点 / 短句 / 日期
    if v.list then
        local th = px(84)
        local tw = th * 2
        local textw = inner - tw - px(14)
        for _, r in ipairs(v.list.rows) do
            local col = VerticalGroup:new{ align = "left",
                k.line(r.title or "", textw), VerticalSpan:new{ width = px(2) },
                k.line(r.line or "", textw, true, true), VerticalSpan:new{ width = px(2) },
                k.line(r.date or "", textw, true, true) }
            local rowh = math.max(th, col:getSize().h)
            local rw = HorizontalGroup:new{ align = "center", k.frame(thumb(k, r.scene, tw, th, r.new), false), HorizontalSpan:new{ width = px(14) }, col }
            table.insert(body, indent(tap(rw, inner, rowh, r.callback)))
            gap(12)
        end
    end
    if v.pager and v.pager.pages > 1 then
        table.insert(body, indent(k.pager(inner, v.pager)))
        gap(10)
    end
    gap(4)
    for _, b in ipairs(v.buttons or {}) do
        local row = b[1] and b or { b }
        local bg = px(8)
        local bw = math.floor((inner - bg * (#row - 1)) / #row)
        local g = HorizontalGroup:new{}
        for i, btn in ipairs(row) do
            if i > 1 then table.insert(g, HorizontalSpan:new{ width = bg }) end
            table.insert(g, k.button(btn.text, bw, btn.callback))
        end
        table.insert(body, indent(g))
        gap(8)
    end
    self[1] = FrameContainer:new{ width = w, height = h, padding = 0, bordersize = 0, background = k.bg, body }
end

function S:onClose()
    UIManager:close(self, "ui")
    if self.on_close then self.on_close() end
    return true
end

return S
