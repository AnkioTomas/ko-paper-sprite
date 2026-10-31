-- SPDX-License-Identifier: MIT
--[[--
全屏浮层界面。思路同 ko-adarkroom：covers_fullscreen + 整屏刷新，盖住月读首页。
组件：月读主题——标题栏、卡片框、文字、按钮、翻页条、底栏、主题色；
阿页依赖月读：入口（papersprite.moon）保证 ui.themes 可用，这里不再有原生兜底。
view = {
  title, scene?（分层画面）, scene_wide?（画面宽贴满内容区，阁楼主页用）, icons?, lines = {string|{text,muted}},
  grid?  = { cols, cells = { {scene, new, caption, callback} } },        明信片墙：缩略图网格
  list?  = { rows = { {scene, new, title, line, date, callback} } },      明信片列表：缩略图 + 文字
  status? = { icon?, title, caption?, meta?, callback? }                  状态卡（图标 + 标题 / 说明 / 小字）
  empty?  = { title, caption? }                                           空状态卡
  switch? = { icon, text, callback }                                      标题栏右侧视图切换；左侧固定是返回（无 back 时关闭）
  notes?  = { rows = { {text, meta?} }, per, fit }                        文字卡列表（按最高一张自适应每页条数）
  lines 里 { text, label = true } 是小节标签（小号灰字）
  tabs?  = { {text, active, callback} },                                  分类页签（一行按钮，当前项加 ✓）
  shelf? = { cols, icon?, cells = { {icon|scene, title|name, meta|price+owned, desc|caption, check?, badge?, dim, callback} } } 卡片网格
  pager? = { page, pages, prev, next },                                   翻页条（n / m）
  tabbar? = { tabs = { {id, text, icon} }, active, on_tab(id) },          底栏（月读 Tabbar，钉在屏幕最底；阁楼主页用）
  buttons = { btn | {btn,...} }, on_close?, back?（有则标题栏右上角按钮 / 返回键回上一级，否则关闭）
}
缩略图走 ui/compose 的合成缓存（墨水屏上不反复解码缩放）。
--]]
--- 去边框去底色：拷一份主题样式，border / bg / shadow 全关（靠留白 / 细分隔线区分；全屏页本身的底色在 S:init 的整屏 FrameContainer 上，那是页面底、不是卡片底色，必须留，否则下层残影透出来）
local function noBorder(style)
    if type(style) ~= "table" then return style end
    local c = {} for kk, vv in pairs(style) do c[kk] = vv end
    c.border, c.bg, c.shadow = 0, nil, 0
    return c
end

local T = require("papersprite.l10n")
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

function S.open(view, on_close)
    return S:new{ view = view, on_close = on_close }
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

--- 组件工具箱：月读主题组件（阿页依赖月读，入口 papersprite.moon 已保证 ui.themes 可用）
local function kit()
    local Theme = require("ui.themes")
    local t = Theme.current()
    local c = t.color
    local k = { px = Theme.px, bg = Blitbuffer.Color8(c.page), ink = Blitbuffer.Color8(c.ink), muted = Blitbuffer.Color8(c.muted),
        small = Font:getFace("cfont", 15) }
    local Text = require("ui.themes.widgets.text")
    function k.button(text, w, cb) return require("ui.themes.widgets.button"):new{ text = text, width = w, callback = cb } end
    -- transparent：不铺文字底色（Text.box 默认拿 bg 铺满自身，卡片底色关了这里再铺一层就露馅）
    function k.text(text, w, muted, small)
        return Text.box(small and "caption" or "body", text, w, { color = muted and c.muted or nil, transparent = true })
    end
    function k.line(text, w, muted, small)
        return Text.line(small and "caption" or "body", text, { width = w, color = muted and c.muted or nil })
    end
    function k.title(w, title, left, right)
        return require("ui.themes.widgets.titlebar").widget{ width = w, title = title or "",
            left_icon = left and left.icon, left_callback = left and left.callback,
            right_icon = right and right.icon, right_callback = right and right.callback }
    end
    function k.head(text, w) return Text.line("title", text, { width = w }) end
    function k.frame(child, border)
        local sz = child:getSize()
        return require("ui.themes.widgets.box"):new{ style = noBorder(border and t.card or t.image), width = sz.w, height = sz.h, child }
    end
    function k.badge(text)
        return FrameContainer:new{ bordersize = 0, padding = Theme.px(2), margin = 0, background = Blitbuffer.COLOR_BLACK,
            TextWidget:new{ text = text, face = k.small, fgcolor = Blitbuffer.COLOR_WHITE } }
    end
    function k.pager(w, p)
        return require("ui.themes.widgets.pager").widget{ width = w, page = p.page, pages = p.pages, on_prev = p.prev, on_next = p.next }
    end
    function k.tabbar(w, tb)
        return require("ui.themes.widgets.tabbar").widget{ width = w, tabs = tb.tabs, active = tb.active, on_tab = tb.on_tab }
    end
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
    return OverlapGroup:new{ dimen = Geom:new{ w = w, h = h }, pic, k.badge(T("新")) }
end

function S:init()
    local w, h = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = w, h = h }
    local k = kit()
    local px, pad = k.px, k.px(20)
    local inner = w - pad * 2
    local v = self.view
    local body = VerticalGroup:new{ align = "left" }
    local function indent(wdg) return HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, wdg } end
    local function gap(n) table.insert(body, VerticalSpan:new{ width = px(n) }) end
    -- 标题栏
    -- 页脚（翻页条 + 按钮）先建好：量出高度，内容区按剩余高度排，页脚贴屏幕底部
    local footer = VerticalGroup:new{ align = "left" }
    if v.pager and v.pager.pages > 1 and not v.pager.hide then
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
    if v.tabbar then table.insert(footer, k.tabbar(w, v.tabbar)) end
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
    local left = v.back and { icon = "arrow_back", text = T("‹ 返回"), callback = v.back }
        or { icon = "close", text = "✕", callback = function() self:onClose() end }
    table.insert(body, k.title(w, v.title, left, v.switch))
    gap(8)
    -- 分层画面：缓存合成成一张位图
    -- scene_wide：贴满屏宽（阁楼主页），高度默认 2:1；放不下只缩高度
    local scene = v.scene or (v.image and { bg = v.image, overlays = {} })
    if scene then
        local SW, SH
        if v.scene_wide then
            SW = w
            SH = self._scene_h or math.floor(SW / 2)
        else
            SH = self._scene_h or math.floor(inner / 2)
            SW = SH * 2
        end
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
    -- 细分隔线：列表卡之间用，代替描边
    local function hair()
        return require("ui/widget/linewidget"):new{ dimen = Geom:new{ w = inner, h = math.max(1, px(1)) }, background = Blitbuffer.Color8(0xCC) }
    end
    local function cardBox(child)
        local cpad = px(12)
        local cw = inner - px(4) - cpad * 2
        local sz = child:getSize()
        local box = OverlapGroup:new{ dimen = Geom:new{ w = cw, h = sz.h }, child }
        return k.frame(FrameContainer:new{ padding = cpad, bordersize = 0, box }, true)
    end
    local status_h0 = bodyH()
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
        table.insert(body, indent(hair()))
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
    local status_h = bodyH() - status_h0
    if v.empty then renderEmpty(v.empty) end
    renderLines(v.lines)
    -- 文字卡列表（阁楼「动态」）：每条一张卡；按最高那张算一页能放几条
    if v.notes then
        local before = bodyH()
        local tallest = 0
        for _, r in ipairs(v.notes.rows) do
            local col = VerticalGroup:new{ align = "left", k.text(r.text, inner - px(28)) }
            if r.meta then table.insert(col, VerticalSpan:new{ width = px(2) }) table.insert(col, k.line(r.meta, inner - px(28), true, true)) end
            local c = cardBox(col)
            tallest = math.max(tallest, c:getSize().h + px(1) + px(8))
            table.insert(body, indent(c))
            table.insert(body, indent(hair()))
            gap(8)
        end
        if v.notes.fit and tallest > 0 then
            local full = math.max(1, math.floor((h - before - footer_h - px(6) + px(8)) / tallest))
            if full ~= v.notes.per then UIManager:nextTick(function() v.notes.fit(full) end) end
        end
    end
    -- 分类页签
    if v.tabs then
        local tg = px(6)
        local tw = math.floor((inner - tg * (#v.tabs - 1)) / #v.tabs)
        local row = HorizontalGroup:new{}
        for i, t in ipairs(v.tabs) do
            if i > 1 then table.insert(row, HorizontalSpan:new{ width = tg }) end
            -- 无边框页签：文字 + 选中项下面一条粗线
            local th = px(40)
            local lab = CenterContainer:new{ dimen = Geom:new{ w = tw, h = th }, k.line((t.active and "✓ " or "") .. t.text, tw, not t.active) }
            local col = VerticalGroup:new{ lab, require("ui/widget/linewidget"):new{ dimen = Geom:new{ w = tw, h = t.active and px(3) or px(1) },
                background = t.active and Blitbuffer.COLOR_BLACK or Blitbuffer.Color8(0xCC) } }
            table.insert(row, tap(col, tw, th + px(3), t.callback))
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
        -- 按剩余高度定图标大小：余下的空白够大半行时，把图标缩一点多放一行（不小于 44）
        if shelf.fit and not shelf.compact then
            local lh = k.line("阿", cw, true, true):getSize().h
            local extra = px(6) + lh + cpad * 2 + px(10)
            local avail = h - before - footer_h - px(6) + px(10)
            local rows = math.max(1, math.floor(avail / (iw + extra)))
            if avail - rows * (iw + extra) > (iw + extra) * 0.35 then
                local iw2 = math.floor(avail / (rows + 1)) - extra
                if iw2 >= px(44) then iw = iw2 end
            end
        end
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
            else
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
            end
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
    -- 还是放不下：缩小顶部画面再排一次（只缩一次）；宽屏模式只缩高度，宽度仍贴满
    local over = bodyH() + footer_h - h
    if over > 0 and scene and not self._scene_h then
        self._scene_h = math.max(px(80), math.floor(inner / 2) - over - px(4))
        return self:init()
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
