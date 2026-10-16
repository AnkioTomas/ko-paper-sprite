-- SPDX-License-Identifier: MIT
--[[--
阿页自己的下拉面板（不碰月读的快捷面板）。照月读面板的样子做：
  从屏幕顶端落下的一块（页面底色 + 下沿分隔线），里面是阁楼卡（画面 + 近况）和一行小按钮；
  面板下方铺月读主题网点遮罩（ui.themes.widgets.mask，拿不到就留空）；
  点遮罩 / 上滑 / 返回键 / 点「收起」关闭；点阁楼卡关面板并全屏打开阁楼。
弹出时整屏 "ui" 刷新（变高 / 关闭时 "full" 清残影），与月读面板的刷新策略一致。
触发：首页「阁楼」组件上向下滑；月读快捷面板里的「阿页」开关；KOReader 手势动作「阿页的下拉面板」。
--]]
local M = {}

local function theme()
    local ok, T = pcall(function() local Theme = require("ui.themes") return { Theme = Theme, t = Theme.current() } end)
    return ok and T or nil
end

function M.show()
    if M.current then return M.current end
    local Device = require("device")
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local LineWidget = require("ui/widget/linewidget")
    local UIManager = require("ui/uimanager")
    local Blitbuffer = require("ffi/blitbuffer")
    local W = require("papersprite.ui.moon_widgets")
    local Screen = Device.screen
    local T = theme()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local pad = T and T.Theme.px(T.t.space.md) or 12

    local panel = InputContainer:new{ dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }, covers_fullscreen = false, modal = true }
    local function close()
        if M.current ~= panel then return end
        M.current = nil
        UIManager:close(panel)
        UIManager:setDirty("all", "full")
    end
    local function open(page)
        close()
        UIManager:nextTick(function() pcall(W.open, page) end)
    end

    local content_w = sw - pad * 2
    local card = W.panelContent(content_w, function() open("attic") end)
    local function button(text, fn, bw)
        if T then
            local ok, b = pcall(function() return require("ui.themes.widgets.button"):new{ text = text, width = bw, callback = fn } end)
            if ok and b then return b end
        end
        return require("ui/widget/button"):new{ text = text, width = bw, callback = fn }
    end
    local gap = T and T.Theme.px(T.t.space.sm) or 6
    local bw = math.floor((content_w - gap * 3) / 4)
    local row = HorizontalGroup:new{
        button("收拾行囊", function() open("pack") end, bw), HorizontalSpan:new{ width = gap },
        button("明信片墙", function() open("wall") end, bw), HorizontalSpan:new{ width = gap },
        button("特产柜", function() open("cabinet") end, bw), HorizontalSpan:new{ width = gap },
        button("收起", close, bw),
    }
    local inner = VerticalGroup:new{ align = "left", card, VerticalSpan:new{ width = gap }, row }
    local sheet
    if T then
        local ok, box = pcall(function()
            return require("ui.themes.widgets.box"):new{ style = { bg = T.t.color.page }, width = sw,
                height = inner:getSize().h + pad * 2, inner }
        end)
        if ok then sheet = box end
    end
    sheet = sheet or FrameContainer:new{ width = sw, bordersize = 0, padding = pad, margin = 0, background = Blitbuffer.COLOR_WHITE, inner }
    local sheet_h = sheet:getSize().h
    local line = LineWidget:new{ dimen = Geom:new{ w = sw, h = T and T.Theme.px(1) or 1 }, background = Blitbuffer.COLOR_DARK_GRAY }
    panel[1] = VerticalGroup:new{ align = "left", sheet, line }
    panel.sheet_h = sheet_h + line:getSize().h

    local paint = panel.paintTo
    function panel:paintTo(bb, x, y)
        local below = sh - self.sheet_h
        if below > 0 then
            pcall(function()
                require("ui.themes.widgets.mask"):new{ dimen = Geom:new{ w = sw, h = below } }:paintTo(bb, x, y + self.sheet_h)
            end)
        end
        return paint(self, bb, x, y)
    end
    local outside = function() return Geom:new{ x = 0, y = panel.sheet_h, w = sw, h = sh - panel.sheet_h } end
    panel.ges_events = {
        TapOutside = { GestureRange:new{ ges = "tap", range = outside } },
        SwipeUp = { GestureRange:new{ ges = "swipe", range = function() return panel.dimen end } },
    }
    function panel:onTapOutside() close() return true end
    function panel:onSwipeUp(_, ges) if ges and ges.direction == "north" then close() end return true end
    if Device:hasKeys() then panel.key_events = { Close = { { "Back" } } } end
    function panel:onClose() close() return true end
    panel.close = close

    M.current = panel
    UIManager:show(panel, "ui")
    return panel
end

function M.close() if M.current then M.current.close() end end

return M
