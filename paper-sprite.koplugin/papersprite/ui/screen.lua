-- SPDX-License-Identifier: MIT
--[[--
全屏浮层界面。思路同 ko-adarkroom：covers_fullscreen + 整屏刷新，盖住月读首页。
皮肤：月读在时（能 require ui.themes）用月读主题组件——标题栏、卡片框、文字、按钮、翻页条、主题色；
每个组件单独 pcall，某个组件失败只有它退回 KOReader 原生控件。skin = "native" 强制原生。
view = {
  title, scene?（分层画面）, icons?, lines = {string|{text,muted}},
  grid?  = { cols, cells = { {scene, new, caption, callback} } },        明信片墙：缩略图网格
  list?  = { rows = { {scene, new, title, line, date, callback} } },      明信片列表：缩略图 + 文字
  status? = { icon?, title, caption?, meta?, callback? }                  状态卡（图标 + 标题 / 说明 / 小字）
  empty?  = { title, caption? }                                           空状态卡
  switch? = { icon, text, callback }                                      标题栏右侧视图切换；左侧固定是返回（无 back 时关闭）
  lines 里 { text, label = true } 是小节标签（小号灰字）
  tabs?  = { {text, active, callback} },                                  分类页签（一行按钮，当前项加 ✓）
  shelf? = { cols, icon?, cells = { {icon|scene, title|name, meta|price+owned, desc|caption, check?, badge?, dim, callback} } } 卡片网格
  pager? = { page, pages, prev, next },                                   翻页条（n / m）
  buttons = { btn | {btn,...} }, on_close?, back?（有则标题栏右上角按钮 / 返回键回上一级，否则关闭）
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
local logger = require("logger")
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
    --- 标题栏：左 = 返回（主页是关闭），中 = 标题，右 = 视图切换（没有就留空，保持标题居中）
    --- left / right = { icon, text, callback }
    function native.title(w, title, left, right)
        local hh = px(48)
        local function side(sd, sw)
            if not sd then return HorizontalSpan:new{ width = sw } end
            return tap(CenterContainer:new{ dimen = Geom:new{ w = sw, h = hh },
                TextWidget:new{ text = sd.text, face = k.face, fgcolor = k.ink } }, sw, hh, sd.callback)
        end
        local sw = px(72)
        return VerticalGroup:new{ align = "left",
            HorizontalGroup:new{ align = "center", side(left, sw),
                CenterContainer:new{ dimen = Geom:new{ w = w - sw * 2, h = hh }, TextWidget:new{ text = title or "", face = k.face, bold = true, max_width = w - sw * 2 } },
                side(right, sw) },
            require("ui/widget/linewidget"):new{ dimen = Geom:new{ w = w, h = px(1) }, background = k.muted } }
    end
    function native.head(text, w)
        return TextWidget:new{ text = text, face = k.face, bold = true, max_width = w, fgcolor = k.ink }
    end
    function native.frame(child, border)
        return FrameContainer:new{ padding = 0, bordersize = border and px(2) or 0, color = k.ink, background = k.bg, child }
    end
    function native.badge(text)
        return FrameContainer:new{ bordersize = px(1), padding = px(2), margin = 0, background = Blitbuffer.COLOR_WHITE, color = k.ink,
            TextWidget:new{ text = text, face = k.small } }
    end
    --- 原生翻页条：同 KOReader Menu / KeyValuePage 的页脚（« ‹  n / m  › »，无边框图标按钮）
    function native.pager(w, p)
        local Button = require("ui/widget/button")
        local isz = px(32)
        local function chev(icon, enabled, cb)
            return Button:new{ icon = icon, icon_width = isz, icon_height = isz, bordersize = 0, enabled = enabled,
                callback = cb or function() end, show_parent = nil }
        end
        local first = p.first or function() for _ = p.page, 2, -1 do p.prev() end end
        local mid_w = px(140)
        local mid = CenterContainer:new{ dimen = Geom:new{ w = mid_w, h = px(44) }, TextWidget:new{ text = p.page .. " / " .. p.pages, face = k.face } }
        local row = HorizontalGroup:new{ align = "center",
            chev("chevron.first", p.page > 1, p.go and function() p.go(1) end or nil), HorizontalSpan:new{ width = px(16) },
            chev("chevron.left", p.page > 1, p.prev), mid,
            chev("chevron.right", p.page < p.pages, p.next), HorizontalSpan:new{ width = px(16) },
            chev("chevron.last", p.page < p.pages, p.go and function() p.go(p.pages) end or nil) }
        return CenterContainer:new{ dimen = Geom:new{ w = w, h = row:getSize().h }, row }
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
    guarded("title", function(w, title, left, right)
        return require("ui.themes.widgets.titlebar").widget{ width = w, title = title or "",
            left_icon = left and left.icon, left_callback = left and left.callback,
            right_icon = right and right.icon, right_callback = right and right.callback }
    end)
    guarded("head", function(text, w)
        return require("ui.themes.widgets.text").line("title", text, { width = w })
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
    -- 页脚（翻页条 + 按钮）先建好：量出高度，内容区按剩余高度排，页脚贴屏幕底部
    local footer = VerticalGroup:new{ align = "left" }
    if v.pager and v.pager.pages > 1 then
        table.insert(footer, indent(k.pager(inner, v.pager)))
        table.insert(footer, VerticalSpan:new{ width = px(8) })
    end
    for _, b in ipairs(v.buttons or {}) do
        local row = b[1] and b or { b }
        local bg = px(8)
        local bw = math.floor((inner - bg * (#row - 1)) / #row)
        local g = HorizontalGroup:new{}
        for i, btn in ipairs(row) do
            if i > 1 then table.insert(g, HorizontalSpan:new{ width = bg }) end
            table.insert(g, k.button(btn.text, bw, btn.callback))
        end
        table.insert(footer, indent(g))
        table.insert(footer, VerticalSpan:new{ width = px(8) })
    end
    local footer_h = footer:getSize().h
    -- VerticalGroup 会缓存尺寸，量高度前先 resetLayout
    local function bodyH() if body.resetLayout then body:resetLayout() end return body:getSize().h end
    --- 按剩余高度算一页能放几行；和当前每页数量不一样就告诉游戏（下一帧重排），保证不裁切也不留大块空白
    local function fit(spec, cols, before, step, gapn)
        if not spec or not spec.fit or step <= 0 then return end
        local avail = h - before - footer_h - px(6)
        local rows = math.max(1, math.floor((avail + gapn) / step))
        local per = rows * cols
        if per ~= spec.per then UIManager:nextTick(function() spec.fit(per) end) end
    end
    local left = v.back and { icon = "arrow_back", text = "‹ 返回", callback = v.back }
        or { icon = "close", text = "✕", callback = function() self:onClose() end }
    table.insert(body, k.title(w, v.title, left, v.switch))
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
    -- 状态卡：图标 + 标题 / 说明 / 小字
    local function iconW(rel, sz)
        if not rel then return nil end
        return try(function() return require("papersprite.ui.compose").icon(rel, sz) end) or img(rel, sz, sz, true)
    end
    local function cardBox(child)
        local cpad = px(12)
        local cw = inner - px(4) - cpad * 2
        local sz = child:getSize()
        local box = OverlapGroup:new{ dimen = Geom:new{ w = cw, h = sz.h }, child }
        return k.frame(FrameContainer:new{ padding = cpad, bordersize = 0, box }, true)
    end
    if v.status then
        local st = v.status
        local isz = px(st.icon_size or 56)
        local ic = iconW(st.icon, isz)
        local tw = inner - px(28) - (ic and (isz + px(12)) or 0)
        local col = VerticalGroup:new{ align = "left", k.head(st.title or "", tw) }
        if st.caption and st.caption ~= "" then
            table.insert(col, VerticalSpan:new{ width = px(4) })
            table.insert(col, k.text(st.caption, tw))
        end
        if st.meta and st.meta ~= "" then
            table.insert(col, VerticalSpan:new{ width = px(4) })
            table.insert(col, k.line(st.meta, tw, true, true))
        end
        local row = ic and HorizontalGroup:new{ align = "center", ic, HorizontalSpan:new{ width = px(12) }, col } or col
        local card = cardBox(row)
        if st.callback then card = tap(card, card:getSize().w, card:getSize().h, st.callback) end
        table.insert(body, indent(card))
        gap(12)
    end
    local function renderEmpty(e)
        local t = VerticalGroup:new{ align = "center", k.head(e.title or "", inner - px(40)) }
        if e.caption then table.insert(t, VerticalSpan:new{ width = px(6) }) table.insert(t, k.line(e.caption, inner - px(40), true, true)) end
        table.insert(body, indent(cardBox(CenterContainer:new{ dimen = Geom:new{ w = inner - px(28), h = t:getSize().h + px(40) }, t })))
        gap(12)
    end
    local function renderLines(ls)
    for _, l in ipairs(ls or {}) do
        local t = type(l) == "table" and l or { text = l }
        if t.label then
            table.insert(body, indent(k.line(t.text, inner, true, true)))
            gap(4)
        else
            table.insert(body, indent(k.text(t.text, inner, t.muted, t.small)))
            gap(6)
        end
    end
    end
    if v.empty then renderEmpty(v.empty) end
    renderLines(v.lines)
    -- 分类页签
    if v.tabs then
        local tg = px(6)
        local tw = math.floor((inner - tg * (#v.tabs - 1)) / #v.tabs)
        local row = HorizontalGroup:new{}
        for i, t in ipairs(v.tabs) do
            if i > 1 then table.insert(row, HorizontalSpan:new{ width = tg }) end
            table.insert(row, k.button((t.active and "✓ " or "") .. t.text, tw, t.callback))
        end
        table.insert(body, indent(row))
        gap(10)
    end
    -- 小铺货架：物品卡（图标 + 名字 + 价格 / 已有 + 一行效果）
    local function renderShelf(shelf)
        local before = bodyH()
        local cols, g = shelf.cols or 2, px(10)
        local cw = math.floor((inner - g * (cols - 1)) / cols)
        local cpad = px(8)
        local iw = px(shelf.icon or 64)
        local row
        for i, c in ipairs(shelf.cells) do
            if (i - 1) % cols == 0 then
                if row then table.insert(body, indent(row)) gap(10) end
                row = HorizontalGroup:new{ align = "top" }
            else
                table.insert(row, HorizontalSpan:new{ width = g })
            end
            local textw = cw - cpad * 2 - iw - px(8) - px(4)
            local icon = (c.scene and thumb(k, c.scene, iw, iw, c.new)) or iconW(c.icon, iw)
                or require("ui/widget/container/widgetcontainer"):new{ dimen = Geom:new{ w = iw, h = iw } }
            if c.badge then icon = OverlapGroup:new{ dimen = Geom:new{ w = iw, h = iw }, icon, k.badge(c.badge) } end
            local meta = c.meta or ((c.price or "") .. "　" .. (c.owned or ""))
            if shelf.compact then
                -- 紧凑卡：图标居中在上，标题 + 小字两行居中
                local tw = cw - cpad * 2 - px(4)
                local col = VerticalGroup:new{ align = "center", icon, VerticalSpan:new{ width = px(6) },
                    k.line((c.check and "✓ " or "") .. (c.title or ""), tw), VerticalSpan:new{ width = px(2) }, k.line(meta, tw, true, true) }
                local box = CenterContainer:new{ dimen = Geom:new{ w = cw - px(4) - cpad * 2, h = col:getSize().h }, col }
                local cell = k.frame(FrameContainer:new{ padding = cpad, bordersize = 0, box }, true)
                local sz = cell:getSize()
                table.insert(row, tap(cell, sz.w, sz.h, c.callback))
                goto continue
            end
            local info = VerticalGroup:new{ align = "left", k.line((c.check and "✓ " or "") .. (c.title or c.name or ""), textw), VerticalSpan:new{ width = px(4) },
                k.line(meta, textw, true, c.dim) }
            local top = HorizontalGroup:new{ align = "center", icon, HorizontalSpan:new{ width = px(8) }, info }
            local inner_c = VerticalGroup:new{ align = "left", top, VerticalSpan:new{ width = px(6) }, k.line(c.desc or c.caption or "", cw - cpad * 2 - px(4), true, true) }
            local box = OverlapGroup:new{ dimen = Geom:new{ w = cw - px(4) - cpad * 2,
                h = iw + px(6) + k.line("阿", cw, true, true):getSize().h }, inner_c }
            local framed = FrameContainer:new{ padding = cpad, bordersize = 0, box }
            local cell = k.frame(framed, true)
            local sz = cell:getSize()
            table.insert(row, tap(cell, sz.w, sz.h, c.callback))
            shelf._step = shelf._step or (sz.h + px(10))
            ::continue::
        end
        if row then table.insert(body, indent(row)) gap(10) end
        fit(shelf, cols, before, shelf._step or 0, px(10))
    end
    if v.shelf then renderShelf(v.shelf) end
    if v.lines2 then renderLines(v.lines2) end
    if v.shelf2 then renderShelf(v.shelf2) end
    if v.empty2 then renderEmpty(v.empty2) end
    -- 明信片墙：缩略图网格
    if v.grid then
        local cols, g = v.grid.cols or 3, px(12)
        local cw = math.floor((inner - g * (cols - 1)) / cols)
        local ch = math.floor(cw / 2)
        local caph = k.line("阿", cw, true, true):getSize().h
        fit(v.grid, cols, bodyH(), ch + caph + px(4) + px(12), px(12))
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
        -- 行高按屏幕剩余高度定：先按默认缩略图算能放几行；剩下的空白超过半行就多放一行、把缩略图略缩小
        local g12 = px(12)
        local before = bodyH()
        local avail = h - before - footer_h - px(6)
        local colh = k.line("阿", 100):getSize().h + k.line("阿", 100, true, true):getSize().h * 2 + px(4)
        local bd = px(2)
        local th = px(84)
        local rows = math.max(1, math.floor((avail + g12) / (math.max(th + bd, colh) + g12)))
        local left = avail + g12 - rows * (math.max(th + bd, colh) + g12)
        if left > (math.max(th + bd, colh) + g12) * 0.5 then
            local th2 = math.floor((avail + g12) / (rows + 1) - g12 - bd)
            if th2 >= colh - bd and th2 >= px(60) then th, rows = th2, rows + 1 end
        end
        local tw = th * 2
        local textw = inner - tw - px(14)
        for _, r in ipairs(v.list.rows) do
            local col = VerticalGroup:new{ align = "left",
                k.line(r.title or "", textw), VerticalSpan:new{ width = px(2) },
                k.line(r.line or "", textw, true, true), VerticalSpan:new{ width = px(2) },
                k.line(r.date or "", textw, true, true) }
            local rw = HorizontalGroup:new{ align = "center", k.frame(thumb(k, r.scene, tw, th, r.new), false), HorizontalSpan:new{ width = px(14) }, col }
            local rowh = math.max(th + bd, col:getSize().h, rw:getSize().h)
            table.insert(body, indent(tap(rw, inner, rowh, r.callback)))
            gap(12)
        end
        if v.list.fit and rows ~= v.list.per then UIManager:nextTick(function() v.list.fit(rows) end) end
    end
    local filler = h - bodyH() - footer_h
    if filler > 0 then table.insert(body, VerticalSpan:new{ width = filler }) end
    if footer_h > 0 then table.insert(body, footer) end
    body:resetLayout()
    self[1] = FrameContainer:new{ width = w, height = h, padding = 0, bordersize = 0, background = k.bg, body }
    -- 左右滑翻页（同 KOReader 列表）
    if v.pager and v.pager.pages > 1 then
        self.ges_events = self.ges_events or {}
        self.ges_events.SwipePage = { GestureRange:new{ ges = "swipe", range = function() return self.dimen end } }
    end
end

function S:onSwipePage(_, ges)
    local p = self.view.pager
    if not p or not ges then return false end
    local dir = ges.direction
    if dir == "west" and p.page < p.pages then p.next() return true end
    if dir == "east" and p.page > 1 then p.prev() return true end
    return dir == "west" or dir == "east"
end

function S:onClose()
    UIManager:close(self, "ui")
    if self.on_close then self.on_close() end
    return true
end

return S
