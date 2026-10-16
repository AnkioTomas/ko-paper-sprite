-- SPDX-License-Identifier: MIT
--[[--
全屏浮层界面（KOReader 通用皮肤 / 月读主题皮肤）。思路同 ko-adarkroom：
covers_fullscreen + 整屏刷新，盖住月读首页；顶部一行淡色标题 + ✕，无框无分割线。
view = { title, image?(assets 相对路径), lines, buttons = { btn | {btn,...} } }
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

local function kit(skin)
    local px = function(n) return Screen:scaleBySize(n) end
    local k = {
        px = px, bg = Blitbuffer.COLOR_WHITE, ink = Blitbuffer.COLOR_BLACK,
        muted = Blitbuffer.Color8(0x77), face = Font:getFace("cfont", 19),
        button = function(text, w, cb)
            return require("ui/widget/button"):new{ text = text, width = w, callback = cb,
                bordersize = px(1), radius = px(4), text_font_size = 17 }
        end,
    }
    if skin == "moon" then
        local ok = pcall(function()
            local Theme = require("ui.themes")
            local MButton = require("ui.themes.widgets.button")
            local MText = require("ui.themes.widgets.text")
            local c = Theme.current().color
            k.px = Theme.px
            k.bg, k.ink, k.muted = Blitbuffer.Color8(c.page), Blitbuffer.Color8(c.ink), Blitbuffer.Color8(c.muted)
            k.face = MText.face("body")
            k.button = function(text, w, cb) return MButton:new{ text = text, width = w, callback = cb } end
        end)
        if not ok then return kit(nil) end
    end
    return k
end

function S:init()
    local w, h = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = w, h = h }
    local k = kit(self.skin)
    local px, pad = k.px, k.px(20)
    local inner = w - pad * 2
    local v = self.view
    local body = VerticalGroup:new{ align = "left" }
    -- 标题行
    local xw, hh = px(52), px(44)
    local close = InputContainer:new{ dimen = Geom:new{ x = 0, y = 0, w = xw, h = hh },
        CenterContainer:new{ dimen = Geom:new{ w = xw, h = hh }, TextWidget:new{ text = "✕", face = k.face, fgcolor = k.muted } } }
    close.ges_events = { TapClose = { GestureRange:new{ ges = "tap", range = function() return close.dimen end } } }
    close.onTapClose = function() self:onClose() return true end
    table.insert(body, HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = pad },
        LeftContainer:new{ dimen = Geom:new{ w = inner - xw + pad, h = hh },
            TextWidget:new{ text = v.title or "", face = k.face, fgcolor = k.muted, max_width = inner - xw } }, close })
    -- 插画（占位图，墨水屏 4 级灰）
    if v.image then
        local path = Interface.pluginDir() .. "/assets/" .. v.image
        local ok, img = pcall(function()
            return require("ui/widget/imagewidget"):new{ file = path, width = inner, height = math.floor(inner * 0.5),
                scale_factor = 0, file_do_cache = false }
        end)
        if ok and img then
            table.insert(body, CenterContainer:new{ dimen = Geom:new{ w = w, h = math.floor(inner * 0.5) }, img })
            table.insert(body, VerticalSpan:new{ width = px(12) })
        end
    end
    for _, l in ipairs(v.lines or {}) do
        local t = type(l) == "table" and l or { text = l }
        table.insert(body, HorizontalGroup:new{ HorizontalSpan:new{ width = pad },
            TextBoxWidget:new{ text = t.text, face = k.face, width = inner, fgcolor = t.muted and k.muted or k.ink } })
        table.insert(body, VerticalSpan:new{ width = px(6) })
    end
    table.insert(body, VerticalSpan:new{ width = px(10) })
    for _, b in ipairs(v.buttons or {}) do
        local row = b[1] and b or { b }
        local gap = px(8)
        local bw = math.floor((inner - gap * (#row - 1)) / #row)
        local g = HorizontalGroup:new{ HorizontalSpan:new{ width = pad } }
        for i, btn in ipairs(row) do
            if i > 1 then table.insert(g, HorizontalSpan:new{ width = gap }) end
            table.insert(g, k.button(btn.text, bw, btn.callback))
        end
        table.insert(body, g)
        table.insert(body, VerticalSpan:new{ width = px(8) })
    end
    self[1] = FrameContainer:new{ width = w, height = h, padding = 0, bordersize = 0, background = k.bg, body }
end

function S:onClose()
    UIManager:close(self, "ui")
    if self.on_close then self.on_close() end
    return true
end

return S
