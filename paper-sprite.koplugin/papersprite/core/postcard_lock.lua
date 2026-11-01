-- SPDX-License-Identifier: MIT
--[[--
锁屏用的最近一张明信片。只读存档，新的在 postcards 末尾。
没有明信片时返回 nil。短句超过给定行数时在这里截断。
--]]
local M = {}

local function codes(text)
    local out, i = {}, 1
    while i <= #text do
        local b = text:byte(i)
        local len = 1
        if b >= 240 then len = 4 elseif b >= 224 then len = 3 elseif b >= 192 then len = 2 end
        if i + len - 1 > #text then break end
        out[#out + 1] = text:sub(i, i + len - 1)
        i = i + len
    end
    return out
end

--- 最近一张明信片。card 留给画面合成，别改它。
---@param state table|nil
---@return table|nil
function M.latest(state)
    local cards = type(state) == "table" and state.postcards
    if type(cards) ~= "table" or #cards == 0 then return end
    local card = cards[#cards]
    if type(card) ~= "table" then return end
    local place = require("papersprite.core.travel").place(card.place)
    local names = require("papersprite.data.postcards").weather_names
    local weather = names[card.weather] or ""
    local line = type(card.line) == "string" and card.line or ""
    return {
        place = place and place.name or tostring(card.place or ""),
        weather = weather,
        line = line,
        at = card.at or 0,
        card = card,
        key = table.concat({
            tostring(#cards), tostring(card.at or 0), line, tostring(card.place or ""), tostring(card.weather or ""),
        }, "\0"),
    }
end

--- 短句超过 max_lines 行就截断加省略号。measure(text) 返回这段字的高度。
---@param text string
---@param measure fun(text: string): number
---@param max_lines number
---@return string
function M.clampLines(text, measure, max_lines)
    if text == "" then return text end
    local one = measure("页")
    if one <= 0 then return text end
    local max_h = one * max_lines
    if measure(text) <= max_h then return text end
    local chars = codes(text)
    local low, high, fitted = 0, #chars, "…"
    while low <= high do
        local mid = math.floor((low + high) / 2)
        local candidate = table.concat(chars, "", 1, mid) .. "…"
        if measure(candidate) <= max_h then
            fitted, low = candidate, mid + 1
        else
            high = mid - 1
        end
    end
    return fitted
end

return M
