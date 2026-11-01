-- SPDX-License-Identifier: MIT
--[[--
月读锁屏背景：最近一张明信片铺满竖屏。

画面按整屏合成（2:1 素材居中裁切）。地点、短句、署名、日期压在画面底部，不另铺壁纸，也不套白卡。
没有明信片时底是白的，只留一句等待和署名。主体仍由用户另选，叠在这张背景上面。
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

--- 月读锁屏传入整屏矩形。返回铺底的块，主体另外画。
---@param rect table
function M.blocks(rect)
    local Render = require("features.lockscreen.render")
    local Lock = require("papersprite.core.postcard_lock")
    local Blitbuffer = require("ffi/blitbuffer")
    local view = Lock.latest(loadState())
    local w, h = rect.w, rect.h
    local pad = math.max(12, math.floor(w * 0.035))
    local gap = math.max(10, math.floor(pad * 0.5))
    local text_w = w - pad * 2
    local muted = Blitbuffer.COLOR_GRAY_3

    local title = ""
    if view then
        title = view.place or ""
        if view.weather ~= "" then
            title = title ~= "" and (title .. " · " .. view.weather) or view.weather
        end
    end
    local line = view and view.line or T("等阿页寄第一张回来。")
    if line ~= "" then
        line = Lock.clampLines(line, function(sample)
            return Render.measureText(sample, text_w, 26)
        end, 3)
    end
    local sign = T("　——阿页")
    local date = view and (view.at or 0) > 0 and os.date("%Y-%m-%d", view.at) or nil

    local title_h = title ~= "" and Render.measureText(title, text_w, 18) or 0
    local line_h = line ~= "" and Render.measureText(line, text_w, 26) or 0
    local sign_h = Render.measureText(sign, text_w, 16)
    local date_h = date and Render.measureText(date, text_w, 14) or 0
    local text_h = (title_h > 0 and title_h + gap or 0)
        + (line_h > 0 and line_h + gap or 0)
        + sign_h
        + (date and 4 + date_h or 0)
    local band = math.min(h, pad + text_h + pad)

    local blocks = {}
    if view then
        local ok, widget = pcall(function()
            local Game = require("papersprite.game")
            return require("papersprite.ui.compose").widget(Game.cardScene(view.card), w, h)
        end)
        if ok and widget then
            blocks[#blocks + 1] = { kind = "widget", widget = widget, x = 0, y = 0, width = w, height = h }
        end
        blocks[#blocks + 1] = {
            kind = "panel", x = 0, y = h - band, width = w, height = band, lighten = 0.72,
        }
    end

    local x, y = pad, h - band + pad
    if title ~= "" then
        blocks[#blocks + 1] = textBlock(title, x, y, text_w, 18, muted)
        y = y + title_h + gap
    end
    if line ~= "" then
        blocks[#blocks + 1] = textBlock(line, x, y, text_w, 26, Blitbuffer.COLOR_BLACK)
        y = y + line_h + gap
    end
    blocks[#blocks + 1] = textBlock(sign, x, y, text_w, 16, muted, "right")
    if date then
        blocks[#blocks + 1] = textBlock(date, x, y + sign_h + 4, text_w, 14, muted, "right")
    end
    return blocks
end

return {
    backgrounds = function()
        return { {
            id = "postcard",
            label = T("阿页的明信片"),
            cache_key = M.cacheKey,
            blocks = M.blocks,
        } }
    end,
}
