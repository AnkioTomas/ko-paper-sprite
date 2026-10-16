-- SPDX-License-Identifier: MIT
--[[--
分层明信片（原创）：一张 = 地点背景 + 阿页姿势 + 前景小物 + 天气/时刻层 + 一句短句。
  背景  assets/places/<place>.png    1200×600
  姿势  assets/sprite/<pose>.png     透明，320×320
  小物  assets/props/<prop>.png      透明，200×200（"none" 无）
  天气  assets/weather/<weather>.png 透明，1200×600（"clear" 无叠加）
组合数：14 地点 × 8 姿势 × 7 小物 × 6 天气 ≈ 4700 种画面，再乘短句库。
存档里每张明信片记下自己的组合与短句（AI 写的或本地库的），离线可看。
--]]
local Places = require("papersprite.data.places")
local R = require("papersprite.core.rng")

local M = {}

M.poses = { "sit", "read", "wave", "walk", "peek", "sleep", "look_up", "carry" }
M.props = { "none", "lantern", "teacup", "paper_boat", "umbrella", "books", "flower" }
M.weathers = { "clear", "drizzle", "snow", "mist", "dusk", "night" }
M.weather_names = { clear = "晴", drizzle = "小雨", snow = "落纸屑", mist = "起雾", dusk = "黄昏", night = "夜里" }

--- 天气 / 时刻专属的通用短句（任何地点可用）
M.generic = {
    drizzle = { "下了点小雨，我躲在一片大字底下等它停。" },
    snow = { "天上落纸屑了，我接住一片，上面什么也没写。" },
    mist = { "雾太大，我只好跟着自己的书角走。" },
    dusk = { "黄昏的时候，所有的影子都像书签。" },
    night = { "夜里很静，我借着别人的台灯给你写信。" },
    clear = { "今天天气很好，适合被读。" },
}

M.souvenirs = require("papersprite.data.souvenirs")

function M.place(id) for _, p in ipairs(Places) do if p.id == id then return p end end end

--- 一张明信片的身份：图层组合 + 文案 id（地点句 p:<序号> / 天气通用句 g:<序号>）
function M.key(c) return table.concat({ c.place, c.pose, c.prop, c.weather, c.text_id or "?" }, "|") end

--- 某地点的全部候选（视觉组合 × 可用文案）
local function candidates(place_id)
    local p = M.place(place_id)
    local out = {}
    for _, pose in ipairs(M.poses) do
        for _, prop in ipairs(M.props) do
            for _, weather in ipairs(M.weathers) do
                for li, line in ipairs(p.lines) do
                    out[#out + 1] = { place = place_id, pose = pose, prop = prop, weather = weather, line = line, text_id = "p:" .. li }
                end
                for gi, line in ipairs(M.generic[weather] or {}) do
                    out[#out + 1] = { place = place_id, pose = pose, prop = prop, weather = weather, line = line, text_id = "g:" .. gi }
                end
            end
        end
    end
    return out
end
M.candidates = candidates

--- 用存档种子拼一张明信片。返回 seed, card（card.key 为身份）
---@param collected table|nil key -> 最近一次收到的时间
---@param exclude table|nil 本趟已选的 key（同一趟不重复）
--- 规则：只挑没收集过、且本趟没选过的组合；全部收集过才退回「最久没见过」的那张。
function M.compose(seed, place_id, collected, exclude)
    collected, exclude = collected or {}, exclude or {}
    local all = candidates(place_id)
    local fresh = {}
    for _, c in ipairs(all) do
        local k = M.key(c)
        if not collected[k] and not exclude[k] then c.key = k fresh[#fresh + 1] = c end
    end
    local pick
    if #fresh > 0 then
        seed, pick = R.pick(seed, fresh)
    else
        local best, bt
        for _, c in ipairs(all) do
            local k = M.key(c)
            if not exclude[k] then
                local t = collected[k] or 0
                if not bt or t < bt then best, bt = c, t end
            end
        end
        pick = best or all[1]
        pick.key = M.key(pick)
    end
    return seed, pick
end

--- 图层路径（assets 相对）
function M.layers(c)
    local out = { bg = "places/" .. c.place .. ".png", pose = "sprite/" .. c.pose .. ".png" }
    if c.prop and c.prop ~= "none" then out.prop = "props/" .. c.prop .. ".png" end
    if c.weather and c.weather ~= "clear" then out.weather = "weather/" .. c.weather .. ".png" end
    return out
end

return M
