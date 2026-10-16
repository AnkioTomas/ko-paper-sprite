-- SPDX-License-Identifier: MIT
--[[--
阅读账本：KOReader 翻页事件记次数（不读书的内容），打开阁楼时折算成灵感。
账本存 KOReader settings/papersprite_reading.lua，KOReader 与月读两种宿主共用。
骨架规则（原创，待第 3 批细化）：每 20 次翻页 = 1 灵感；同一分钟内多次翻页只算 1 次（防连点）。
--]]
local M = { PAGES_PER_POINT = 20 }

local store
local function open()
    if not store then
        local DataStorage = require("datastorage")
        store = require("luasettings"):open(DataStorage:getSettingsDir() .. "/papersprite_reading.lua")
    end
    return store
end
function M._inject(s) store = s end

function M.record(now)
    local s = open()
    local minute = math.floor(now / 60)
    if s:readSetting("last_minute") == minute then return end
    s:saveSetting("last_minute", minute)
    s:saveSetting("pages", (s:readSetting("pages") or 0) + 1)
    s:flush()
end

--- 把账本里新增的翻页折算进存档 state；返回新增灵感。
function M.collect(state)
    local ok, s = pcall(open)
    if not ok then return 0 end
    local pages = s:readSetting("pages") or 0
    local gained = math.floor(pages / M.PAGES_PER_POINT) - math.floor((state.reading_seen or 0) / M.PAGES_PER_POINT)
    state.reading_seen = pages
    if gained > 0 then state.inspiration = state.inspiration + gained end
    return math.max(0, gained)
end

return M
