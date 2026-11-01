-- SPDX-License-Identifier: MIT
--[[--
月读锁屏主体：最近一张明信片。

竖屏壁纸上放一张白卡，不铺满。上半是 2:1 画面，下面是地点、短句、署名和日期。
没有明信片时同一张卡只留一句等待和署名。位置跟九宫格走，宽度保持宽卡。
--]]
local T = require("papersprite.l10n")

local M = {}

local function loadState()
    local host = require("papersprite.host.moon").new()
    return require("papersprite.core.state").load(host:loadState(), host:now())
end

function M.cacheKey()
    local view = require("papersprite.core.postcard_lock").latest(loadState())
    return view and view.key or "0"
end

local function textBlock(text, x, y, width, size, color, align)
    return {
        text = text, x = x, y = y, width = width, size = size,
        box = false, color = color, align = align,
    }
end

--- 月读锁屏传入位置和宽窄。返回 render 能画的块。
function M.blocks(position, wide)
    local Layout = require("features.lockscreen.layout")
    local Render = require("features.lockscreen.render")
    local Lock = require("papersprite.core.postcard_lock")
    local Blitbuffer = require("ffi/blitbuffer")
    local _sw, sh = Layout.portraitSize()
    local view = Lock.latest(loadState())
    local probe = Layout.panel({ position = position, wide = wide, height = math.floor(sh * 0.4) })
    local inner_w = probe.text_w
    local gap = math.max(10, math.floor(probe.pad * 0.5))
    local muted = Blitbuffer.COLOR_GRAY_3
    local img_h = view and math.floor(inner_w / 2) or 0

    local title = view and view.place or ""
    if view and view.weather ~= "" then
        title = title ~= "" and (title .. " · " .. view.weather) or view.weather
    end
    local line = view and view.line or T("等阿页寄第一张回来。")
    if line ~= "" then
        line = Lock.clampLines(line, function(sample)
            return Render.measureText(sample, inner_w, 26)
        end, 3)
    end
    local sign = T("　——阿页")
    local date = view and (view.at or 0) > 0 and os.date("%Y-%m-%d", view.at) or nil

    local title_h = title ~= "" and Render.measureText(title, inner_w, 18) or 0
    local line_h = line ~= "" and Render.measureText(line, inner_w, 26) or 0
    local sign_h = Render.measureText(sign, inner_w, 16)
    local date_h = date and Render.measureText(date, inner_w, 14) or 0
    local text_h = (title_h > 0 and title_h + gap or 0)
        + (line_h > 0 and line_h + gap or 0)
        + sign_h
        + (date and 4 + date_h or 0)
    local content_h = probe.pad + (img_h > 0 and img_h + gap or 0) + text_h + probe.pad
    local rect = Layout.panel({ position = position, wide = wide, height = content_h })
    if img_h > 0 and rect.h < content_h then
        img_h = math.max(math.floor(inner_w / 4), img_h - (content_h - rect.h))
    end

    local x, y = rect.text_x, rect.y + rect.pad
    local blocks = {
        {
            kind = "panel", x = rect.x, y = rect.y, width = rect.w, height = rect.h,
            radius = rect.radius, shadow = 2, color = Blitbuffer.COLOR_WHITE,
        },
    }
    if view and img_h > 0 then
        local ok, widget = pcall(function()
            local Game = require("papersprite.game")
            return require("papersprite.ui.compose").widget(Game.cardScene(view.card), inner_w, img_h)
        end)
        if ok and widget then
            blocks[#blocks + 1] = { kind = "widget", widget = widget, x = x, y = y, width = inner_w, height = img_h }
            y = y + img_h + gap
        end
    end
    if title ~= "" then
        blocks[#blocks + 1] = textBlock(title, x, y, inner_w, 18, muted)
        y = y + title_h + gap
    end
    if line ~= "" then
        blocks[#blocks + 1] = textBlock(line, x, y, inner_w, 26, Blitbuffer.COLOR_BLACK)
        y = y + line_h + gap
    end
    blocks[#blocks + 1] = textBlock(sign, x, y, inner_w, 16, muted, "right")
    if date then
        blocks[#blocks + 1] = textBlock(date, x, y + sign_h + 4, inner_w, 14, muted, "right")
    end
    return blocks
end

return {
    components = function()
        return { {
            id = "postcard",
            label = T("阿页的明信片"),
            layout = "free",
            supports_narrow = false,
            supports_position = true,
            cache_key = M.cacheKey,
            blocks = M.blocks,
        } }
    end,
}
