-- SPDX-License-Identifier: MIT
--[[--
月读首页组件（只读视图，不在组件里玩）：
  attic     阁楼：当前阁楼画面（季节/夜晚、在家/出门、装饰、访客）+ 一行近况；点按打开阁楼
  postcards 明信片：「最近列表」或「迷你墙」两种模式（组件设置里切换）；点某张打开那张，点空白打开明信片墙
  cabinet   纪念物柜：已收集特产图标 + 数量（n/48）；点按打开特产柜
尺寸档位 小 / 中 / 大 在组件设置里选，决定默认高度与行数。
图片走 ui/compose 的合成缓存；每次绘制前比对数据签名，变了才重建。月读主题不可用时回落朴素样式。
--]]
local Data = require("papersprite.ui.widget_data")
local Compose = require("papersprite.ui.compose")

local M = {}

local function host() return require("papersprite.host.moon").new() end

local function setting(key, default)
    local ok, v = pcall(function() return host():getSetting(key, default) end)
    if ok and v ~= nil then return v end
    return default
end
local function setSetting(key, v) pcall(function() host():setSetting(key, v) end) end

function M.size(kind) local v = setting("w_" .. kind .. "_size", "medium") return Data.LIST_ROWS[v] and v or "medium" end
function M.mode() local v = setting("w_postcards_mode", "list") return (v == "grid") and "grid" or "list" end

--- 打开阁楼并跳到某页
function M.open(page, arg)
    local g = require("papersprite.game").new(host()):show()
    if page and page ~= "attic" then
        if page == "wall" then g.wall_page = 1 end
        g:go(page, arg)
    end
    return g
end

local function read()
    local h = host()
    local raw, dbg = nil, false
    pcall(function() raw = h:loadState() end)
    pcall(function() dbg = h:getSetting("debug_fast", false) end)
    local now = os.time()
    return Data.view(raw, now, dbg), now, dbg
end

--- 主题工具；拿不到主题时 T 为 nil
local function theme()
    local ok, T = pcall(function()
        local Theme = require("ui.themes")
        return { Theme = Theme, t = Theme.current(), Box = require("ui.themes.widgets.box"), Text = require("ui.themes.widgets.text") }
    end)
    return ok and T or nil
end

local function px(T, n) if T then return T.Theme.px(n) end return n end

--- 一行文字（主题 / 朴素）
local function line(T, role, text, width, tone)
    if T then
        local color = tone == "muted" and T.t.color.muted or tone == "faint" and T.t.color.faint or nil
        return T.Text.line(role, text, { width = width, color = color })
    end
    local Font = require("ui/font")
    local TextWidget = require("ui/widget/textwidget")
    local size = role == "title" and 20 or role == "caption" and 14 or 17
    return TextWidget:new{ text = text, face = Font:getFace("cfont", size), bold = role == "title", max_width = width }
end

local function lineH(T, role)
    local ok, h = pcall(function() return line(T, role, "阿", 100):getSize().h end)
    return ok and h or 24
end

--- 卡片外框；内容贴左上（Box 默认居中）
local function card(T, w, h, child)
    local Geom = require("ui/geometry")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local pad = T and px(T, T.t.space.md) or 10
    local bd = T and px(T, (T.t.card and T.t.card.border) or 1) or 1
    child = OverlapGroup:new{ dimen = Geom:new{ w = math.max(1, w - pad * 2 - bd * 2), h = math.max(1, h - pad * 2 - bd * 2) }, child }
    if T then
        local ok, b = pcall(function() return T.Box:new{ style = T.t.card, width = w, height = h, padding = px(T, T.t.space.md), child } end)
        if ok then return b end
    end
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Blitbuffer = require("ffi/blitbuffer")
    return FrameContainer:new{ width = w, height = h, bordersize = 1, radius = 4, padding = 10, background = Blitbuffer.COLOR_WHITE, child }
end

local function padOf(T) return T and px(T, T.t.space.md) or 10 end
local function gapOf(T) return T and px(T, T.t.space.sm) or 6 end
local function borderOf(T) return T and px(T, (T.t.card and T.t.card.border) or 1) or 1 end

--- 可点区域：rects 为相对卡片左上角的 {x,y,w,h,fn}；没命中走 fallback
local function tappable(w, h, content, rects, fallback, refresh, on_swipe)
    local Geom = require("ui/geometry")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local GestureRange = require("ui/gesturerange")
    local box = InputContainer:new{ dimen = Geom:new{ x = 0, y = 0, w = w, h = h }, content }
    box.rects = rects
    box.ges_events = { TapPaperSpriteWidget = { GestureRange:new{ ges = "tap", range = function() return box.dimen end } } }
    if on_swipe then
        box.ges_events.SwipePaperSpriteWidget = { GestureRange:new{ ges = "swipe", range = function() return box.dimen end } }
        function box:onSwipePaperSpriteWidget(_, ges)
            if ges and ges.direction == "south" then on_swipe() return true end
            return false -- 左右滑照旧交给月读翻页
        end
    end
    function box:onTapPaperSpriteWidget(_, ges)
        local x, y = ges.pos.x - self.dimen.x, ges.pos.y - self.dimen.y
        for _, r in ipairs(self.rects or {}) do
            if x >= r[1] and x < r[1] + r[3] and y >= r[2] and y < r[2] + r[4] then r[5]() return true end
        end
        fallback()
        return true
    end
    local paintTo = box.paintTo
    function box:paintTo(bb, x, y)
        if refresh then
            local ok, new = pcall(refresh)
            if ok and new then self[1], self.rects = new.content, new.rects end
        end
        return paintTo(self, bb, x, y)
    end
    return box
end

--- 签名变了才重建：返回 refresh 闭包
local function watcher(build, sig0)
    local cur = sig0
    return function()
        local content, rects, sig = build()
        if sig == cur then return nil end
        cur = sig
        return { content = content, rects = rects }
    end
end

------------------------------------------------------------------ 阁楼
local function atticHeights(T, w)
    local inner = w - padOf(T) * 2 - borderOf(T) * 2
    local text = lineH(T, "body") + lineH(T, "caption") + gapOf(T)
    local size = M.size("attic")
    if size == "small" then return math.floor(inner * 0.22) + padOf(T) * 2 + borderOf(T) * 2, "row" end
    local img = math.floor(inner * (size == "large" and 0.5 or 0.42))
    return img + gapOf(T) + text + padOf(T) * 2 + borderOf(T) * 2, "col"
end

function M.atticBuild(w, h)
    local T = theme()
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local function build()
        local s, now, dbg = read()
        local d = Data.attic(s, now, dbg)
        local sig = Data.sig(d) .. w .. "x" .. h .. M.size("attic")
        local inner_w = w - padOf(T) * 2 - borderOf(T) * 2
        local inner_h = h - padOf(T) * 2 - borderOf(T) * 2
        local _, layout = atticHeights(T, w)
        local body
        if layout == "row" then
            local ih = inner_h
            local iw = math.min(math.floor(inner_w * 0.5), ih * 2)
            local tw = math.max(1, inner_w - iw - gapOf(T))
            body = HorizontalGroup:new{ align = "center", Compose.widget(d.scene, iw, ih),
                HorizontalSpan:new{ width = gapOf(T) },
                VerticalGroup:new{ align = "left", line(T, "body", d.line, tw), VerticalSpan:new{ width = gapOf(T) }, line(T, "caption", d.sub, tw, "faint") } }
        else
            local text = lineH(T, "body") + lineH(T, "caption") + gapOf(T)
            local ih = math.max(1, inner_h - text - gapOf(T))
            body = VerticalGroup:new{ align = "left", Compose.widget(d.scene, inner_w, ih), VerticalSpan:new{ width = gapOf(T) },
                line(T, "body", d.line, inner_w), line(T, "caption", d.sub, inner_w, "faint") }
        end
        return card(T, w, h, body), {}, sig
    end
    local content, rects, sig = build()
    return tappable(w, h, content, rects, function() M.open("attic") end, watcher(build, sig),
        function() pcall(function() require("papersprite.ui.paper_panel").show() end) end)
end

------------------------------------------------------------------ 明信片
local GRID_COLS = 4
M.cards_page = 1

--- 列表一行：地点 · 天气 / 短句 / 日期 三行，缩略图同高（2:1）
local function listRowH(T) return lineH(T, "body") + lineH(T, "caption") * 2 end

--- 标题行右侧的翻页条（月读 Pager，失败退回文字）
local function pagerWidget(T, width, page, pages, prev, next)
    if T then
        local ok, p = pcall(function()
            return require("ui.themes.widgets.pager").widget{ width = width, page = page, pages = pages, on_prev = prev, on_next = next }
        end)
        if ok and p then return p, true end
    end
    return line(T, "body", "‹  " .. page .. " / " .. pages .. "  ›", width, "muted"), false
end

local function headH(T)
    local ok, h = pcall(function() return pagerWidget(T, 300, 1, 2, function() end, function() end):getSize().h end)
    return math.max(lineH(T, "title"), ok and h or 0)
end

local function cardsHeights(T, w)
    local inner = w - padOf(T) * 2 - borderOf(T) * 2
    local size = M.size("postcards")
    local head = headH(T) + gapOf(T)
    if M.mode() == "grid" then
        local cw = math.floor((inner - gapOf(T) * (GRID_COLS - 1)) / GRID_COLS)
        local rows = Data.GRID_ROWS[size]
        return head + rows * math.floor(cw / 2) + (rows - 1) * gapOf(T) + padOf(T) * 2 + borderOf(T) * 2
    end
    local rows = Data.LIST_ROWS[size]
    local rh = listRowH(T)
    return head + rows * rh + (rows - 1) * gapOf(T) + padOf(T) * 2 + borderOf(T) * 2
end

function M.postcardsBuild(w, h)
    local T = theme()
    local Geom = require("ui/geometry")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local WidgetContainer = require("ui/widget/container/widgetcontainer")
    local function build()
        local s = read()
        local size, mode = M.size("postcards"), M.mode()
        local pad, gap, bd = padOf(T), gapOf(T), borderOf(T)
        local inner = w - pad * 2 - bd * 2
        local hh = headH(T)
        local avail = h - pad * 2 - bd * 2 - hh - gap
        local rh = listRowH(T)
        local cw = math.floor((inner - gap * (GRID_COLS - 1)) / GRID_COLS)
        local ch = math.floor(cw / 2)
        local unit = mode == "grid" and ch or rh
        local rows = math.max(1, math.min(mode == "grid" and Data.GRID_ROWS[size] or Data.LIST_ROWS[size],
            math.floor((avail + gap + math.floor(pad * 0.6)) / (unit + gap))))
        local n = mode == "grid" and GRID_COLS * rows or rows
        local d = Data.postcards(s, n, M.cards_page)
        M.cards_page = d.page
        local sig = Data.sig({ d.total, d.new, d.page, size, mode, w, h, (function()
            local ks = {} for _, c in ipairs(d.cards) do ks[#ks + 1] = c.index .. (c.new and "n" or "") end return ks end)() })
        local head = (d.total == 0) and "明信片 · 墙上还空着" or ("明信片 " .. d.total .. (d.new > 0 and (" · 新 " .. d.new) or ""))
        local rects = {}
        local headRow
        if d.pages > 1 then
            local UIManager = require("ui/uimanager")
            local pw = math.floor(inner * 0.45)
            local function turn(dp) return function()
                M.cards_page = math.max(1, math.min(d.pages, d.page + dp))
                UIManager:setDirty("all", "ui")
            end end
            local pager, own = pagerWidget(T, pw, d.page, d.pages, turn(-1), turn(1))
            headRow = require("ui/widget/horizontalgroup"):new{ align = "center", line(T, "title", head, inner - pw), pager }
            if not own then -- 文字兜底：自己按左右半边分翻页（月读 Pager 的按钮自带回调，不能再算一次）
                rects[#rects + 1] = { pad + bd + inner - pw, pad + bd, math.floor(pw / 2), hh, turn(-1) }
                rects[#rects + 1] = { pad + bd + inner - math.floor(pw / 2), pad + bd, math.floor(pw / 2), hh, turn(1) }
            else -- 标题行其余位置点了不跳页
                rects[#rects + 1] = { pad + bd + inner - pw, pad + bd, pw, hh, function() end }
            end
        else
            headRow = line(T, "title", head, inner)
        end
        local col = VerticalGroup:new{ align = "left", require("ui/widget/container/leftcontainer"):new{ dimen = Geom:new{ w = inner, h = hh }, headRow }, VerticalSpan:new{ width = gap } }
        local y0 = pad + bd + hh + gap
        local function open(i) return function() M.open("card", i) end end
        if mode == "grid" then
            for r = 1, rows do
                local row = HorizontalGroup:new{ align = "top" }
                for c = 1, GRID_COLS do
                    local k = (r - 1) * GRID_COLS + c
                    local pc = d.cards[k]
                    if c > 1 then row[#row + 1] = HorizontalSpan:new{ width = gap } end
                    if pc then
                        local cell = Compose.widget(pc.scene, cw, ch)
                        if pc.new then
                            local OverlapGroup = require("ui/widget/overlapgroup")
                            local FrameContainer = require("ui/widget/container/framecontainer")
                            local Blitbuffer = require("ffi/blitbuffer")
                            cell = OverlapGroup:new{ dimen = Geom:new{ w = cw, h = ch }, cell,
                                FrameContainer:new{ bordersize = 1, padding = 2, margin = 0, background = Blitbuffer.COLOR_WHITE,
                                    line(T, "caption", "新", cw) } }
                        end
                        row[#row + 1] = cell
                        rects[#rects + 1] = { pad + bd + (c - 1) * (cw + gap), y0 + (r - 1) * (ch + gap), cw, ch, open(pc.index) }
                    else
                        row[#row + 1] = WidgetContainer:new{ dimen = Geom:new{ w = cw, h = ch } }
                    end
                end
                if r > 1 then col[#col + 1] = VerticalSpan:new{ width = gap } end
                col[#col + 1] = row
            end
        else
            local tw2 = rh * 2
            local tw = math.max(1, inner - tw2 - gap)
            for k = 1, rows do
                local pc = d.cards[k]
                if k > 1 then col[#col + 1] = VerticalSpan:new{ width = gap } end
                if pc then
                    col[#col + 1] = HorizontalGroup:new{ align = "center", Compose.widget(pc.scene, tw2, rh), HorizontalSpan:new{ width = gap },
                        VerticalGroup:new{ align = "left",
                            line(T, "body", (pc.new and "新 · " or "") .. pc.place .. " · " .. pc.weather, tw),
                            line(T, "caption", pc.line, tw, "muted"),
                            line(T, "caption", pc.date, tw, "faint") } }
                    rects[#rects + 1] = { pad + bd, y0 + (k - 1) * (rh + gap), inner, rh, open(pc.index) }
                else
                    col[#col + 1] = WidgetContainer:new{ dimen = Geom:new{ w = inner, h = rh } }
                end
            end
        end
        return card(T, w, h, col), rects, sig
    end
    local content, rects, sig = build()
    return tappable(w, h, content, rects, function() M.open("wall") end, watcher(build, sig))
end

------------------------------------------------------------------ 纪念物柜
local function cabMetrics(T, w)
    local inner = w - padOf(T) * 2 - borderOf(T) * 2
    local cell = px(T, 64)
    local cols = math.max(3, math.floor((inner + gapOf(T)) / (cell + gapOf(T))))
    cell = math.floor((inner - gapOf(T) * (cols - 1)) / cols)
    local cap = lineH(T, "caption")
    return inner, cols, cell, cap
end

local function cabHeights(T, w)
    local _, _, cell, cap = cabMetrics(T, w)
    local rows = Data.CAB_ROWS[M.size("cabinet")]
    return lineH(T, "title") + gapOf(T) + rows * (cell + cap) + (rows - 1) * gapOf(T) + padOf(T) * 2 + borderOf(T) * 2
end

function M.cabinetBuild(w, h)
    local T = theme()
    local Geom = require("ui/geometry")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local WidgetContainer = require("ui/widget/container/widgetcontainer")
    local function build()
        local s = read()
        local d = Data.cabinet(s)
        local size = M.size("cabinet")
        local inner, cols, cell, cap = cabMetrics(T, w)
        local avail = h - padOf(T) * 2 - borderOf(T) * 2 - lineH(T, "title") - gapOf(T)
        local rows = math.max(1, math.min(Data.CAB_ROWS[size], math.floor((avail + gapOf(T) + math.floor(padOf(T) * 0.6)) / (cell + cap + gapOf(T)))))
        -- 被压缩到一行都放不下时，缩小格子
        if cell + cap > avail + padOf(T) * 0.6 then
            cell = math.max(16, math.floor(avail + padOf(T) * 0.6 - cap))
            cols = math.max(3, math.floor((inner + gapOf(T)) / (cell + gapOf(T))))
        end
        local sig = Data.sig({ d, size, w, h })
        local col = VerticalGroup:new{ align = "left", line(T, "title", "纪念物柜 " .. d.have .. "/" .. d.total, inner), VerticalSpan:new{ width = gapOf(T) } }
        if d.have == 0 then col[#col + 1] = line(T, "caption", "还没有纪念物。阿页旅行回来会带一件。", inner, "muted") end
        local show = rows * cols
        local more = d.have > show
        for r = 1, rows do
            if (r - 1) * cols >= math.min(d.have, show) then break end
            local row = HorizontalGroup:new{ align = "top" }
            for c = 1, cols do
                local k = (r - 1) * cols + c
                local it = d.items[k]
                if c > 1 then row[#row + 1] = HorizontalSpan:new{ width = gapOf(T) } end
                if it then
                    local label = (more and k == show) and ("+" .. (d.have - show + 1)) or ("×" .. it.count)
                    row[#row + 1] = VerticalGroup:new{ align = "center",
                        Compose.icon(it.icon, math.max(1, cell - px(T, 8))),
                        CenterContainer:new{ dimen = Geom:new{ w = cell, h = cap }, line(T, "caption", label, cell, "faint") } }
                else
                    row[#row + 1] = WidgetContainer:new{ dimen = Geom:new{ w = cell, h = cell + cap } }
                end
            end
            if r > 1 then col[#col + 1] = VerticalSpan:new{ width = gapOf(T) } end
            col[#col + 1] = row
        end
        return card(T, w, h, col), {}, sig
    end
    local content, rects, sig = build()
    return tappable(w, h, content, rects, function() M.open("cabinet") end, watcher(build, sig))
end

------------------------------------------------------------------ 设置
--- 编辑态设置：尺寸档位（明信片另有显示模式）
function M.settings(kind, desktop)
    local function refresh() pcall(function() desktop:onEvent("home_refresh") end) end
    local cur = M.size(kind)
    local items = { { buttons = {} } }
    for _, sz in ipairs(Data.SIZES) do
        table.insert(items[1].buttons, { text = (cur == sz and "✓ " or "") .. Data.SIZE_NAMES[sz],
            callback = function() setSetting("w_" .. kind .. "_size", sz) refresh() end })
    end
    if kind == "postcards" then
        local m = M.mode()
        items[2] = { buttons = {
            { text = (m == "list" and "✓ " or "") .. "最近列表", callback = function() setSetting("w_postcards_mode", "list") refresh() end },
            { text = (m == "grid" and "✓ " or "") .. "迷你墙", callback = function() setSetting("w_postcards_mode", "grid") refresh() end },
        } }
    end
    local title = ({ attic = "阁楼", postcards = "明信片", cabinet = "纪念物柜" })[kind]
    require("ui.themes.widgets.sheet"):new{ title = title, items = items }:show()
end

------------------------------------------------------------------ 阿页的下拉面板内容
--- 自己的下拉面板（ui/paper_panel）里的内容：通栏阁楼画面 + 近况一行 + 灵感小字；整块点按 on_tap
function M.panelContent(w, on_tap)
    local T = theme()
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local s, now, dbg = read()
    local d = Data.attic(s, now, dbg)
    local pad, gap, bd = padOf(T), gapOf(T), borderOf(T)
    local inner_w = w - pad * 2 - bd * 2
    local ih = math.floor(inner_w * 0.42)
    local h = ih + gap + lineH(T, "body") + lineH(T, "caption") + pad * 2 + bd * 2
    local body = VerticalGroup:new{ align = "left", Compose.widget(d.scene, inner_w, ih), VerticalSpan:new{ width = gap },
        line(T, "body", d.line, inner_w), line(T, "caption", d.sub, inner_w, "faint") }
    return tappable(w, h, card(T, w, h, body), {}, on_tap)
end

M.heights = { attic = function(w) return (atticHeights(theme(), w)) end, postcards = function(w) return cardsHeights(theme(), w) end,
    cabinet = function(w) return cabHeights(theme(), w) end }

return M
