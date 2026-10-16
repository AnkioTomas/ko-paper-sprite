-- SPDX-License-Identifier: MIT
--[[--
月读首页「阿页」卡片：图标 + 标题 + 近况两行，整张卡点按打开阁楼。
每次绘制前比对摘要，变了就重建（从阁楼返回首页即刷新）。月读主题不可用时回落朴素样式。
近况按真实时间在「只读副本」上结算，不写存档。
--]]
local Card = {}

local function copy(t)
    if type(t) ~= "table" then return t end
    local o = {} for k, v in pairs(t) do o[k] = copy(v) end return o
end

--- 纯函数：由存档 + 当前时间算出卡片文案。
function Card.summary(raw, now, debug_fast)
    local State = require("papersprite.core.state")
    local Travel = require("papersprite.core.travel")
    local s = State.load(copy(raw), now)
    Travel.settle(s, now, debug_fast)
    local out = { title = "阿页" }
    local sp = s.sprite
    if sp.status == "away" then
        local h = math.floor((now - sp.left_at) / 3600)
        out.line1 = h >= 1 and ("出门了，已经走了 " .. h .. " 小时") or "刚出门，纸条还压在桌上"
    elseif sp.status == "packed" then
        out.line1 = "行囊收好了，正望着窗外"
    else
        out.line1 = s.visitor and "在阁楼招待一只墨点虫" or "在阁楼打盹"
    end
    local new = 0
    local seen = (type(raw) == "table" and raw.postcards) and #raw.postcards or 0
    new = #s.postcards - seen
    out.line2 = (new > 0 and ("有 " .. new .. " 张新明信片 · ") or "") .. "灵感 " .. s.inspiration
    return out
end

local function key(s) return s.line1 .. "\31" .. s.line2 end

local function themed(s, w, h)
    local Theme = require("ui.themes")
    local Box = require("ui.themes.widgets.box")
    local Text = require("ui.themes.widgets.text")
    local Icon = require("ui.themes.widgets.icon")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local Geom = require("ui/geometry")
    local t = Theme.current()
    local pad, gap = Theme.px(t.space.md), Theme.px(t.space.md)
    local text_w = math.max(1, w - pad * 2 - Theme.px(40) - Theme.px(24) - gap * 2)
    local col = VerticalGroup:new{ align = "left",
        Text.line("title", s.title, { width = text_w }),
        VerticalSpan:new{ width = Theme.px(t.space.xs) },
        Text.line("body", s.line1, { width = text_w, color = t.color.muted }),
        VerticalSpan:new{ width = Theme.px(t.space.xs) },
        Text.line("caption", s.line2, { width = text_w, color = t.color.faint }),
    }
    return Box:new{ style = t.card, width = w, height = h, padding = pad, HorizontalGroup:new{ align = "center",
        Icon.widget{ name = "bookmark", size = 40 }, HorizontalSpan:new{ width = gap },
        LeftContainer:new{ dimen = Geom:new{ w = text_w, h = col:getSize().h }, col },
        HorizontalSpan:new{ width = gap }, Icon.widget{ name = "chevron_right", size = 24 } } }
end

local function plain(s, w, h)
    local Blitbuffer = require("ffi/blitbuffer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local TextWidget = require("ui/widget/textwidget")
    local Font = require("ui/font")
    local inner = w - 24
    return FrameContainer:new{ width = w, height = h, bordersize = 1, radius = 4, padding = 10, background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{ align = "left",
            TextWidget:new{ text = s.title, face = Font:getFace("tfont", 22), bold = true, max_width = inner },
            TextWidget:new{ text = s.line1, face = Font:getFace("cfont", 18), max_width = inner },
            TextWidget:new{ text = s.line2, face = Font:getFace("cfont", 15), fgcolor = Blitbuffer.COLOR_GRAY_5, max_width = inner } } }
end

local function content(s, w, h)
    local ok, wdg = pcall(themed, s, w, h)
    if ok and wdg then return wdg end
    return plain(s, w, h)
end

function Card.height()
    local ok, h = pcall(function()
        local Theme = require("ui.themes")
        local Text = require("ui.themes.widgets.text")
        local t = Theme.current()
        return Text.line("title", "阿"):getSize().h + Text.line("body", "阿"):getSize().h
            + Text.line("caption", "阿"):getSize().h + Theme.px(t.space.xs) * 2 + Theme.px(t.space.md) * 2 + 2
    end)
    return ok and h or 110
end

function Card.build(w, h, load, open)
    local Geom = require("ui/geometry")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local GestureRange = require("ui/gesturerange")
    local function read()
        local ok, st = pcall(load)
        local dbg = false
        pcall(function() dbg = require("papersprite.host.moon").new():getSetting("debug_fast", false) end)
        local ok2, s = pcall(Card.summary, ok and st or nil, os.time(), dbg)
        return ok2 and s or { title = "阿页", line1 = "在阁楼打盹", line2 = "" }
    end
    local s = read()
    local card = InputContainer:new{ dimen = Geom:new{ x = 0, y = 0, w = w, h = h }, content(s, w, h) }
    card.summary_key = key(s)
    card.ges_events = { TapPaperSpriteCard = { GestureRange:new{ ges = "tap", range = function() return card.dimen end } } }
    function card:onTapPaperSpriteCard() open() return true end
    local paintTo = card.paintTo
    function card:paintTo(bb, x, y)
        local now = read()
        if key(now) ~= self.summary_key then self.summary_key = key(now) self[1] = content(now, w, h) end
        return paintTo(self, bb, x, y)
    end
    return card
end

return Card
