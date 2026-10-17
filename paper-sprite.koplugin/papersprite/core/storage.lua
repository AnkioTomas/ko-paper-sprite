-- SPDX-License-Identifier: MIT
--[[--
存档位置：<KOReader 数据目录>/.moon/game/paper-sprite/
  save.lua      存档（state，含 AI 写下的文案）+ KOReader 宿主的设置（setting_*）
  reading.lua   阅读账本（翻页计数）
KOReader 与月读两种宿主共用同一份存档。缩略图缓存只在内存里（ui/compose），不落盘。

第一次打开新位置时从旧位置迁移（只复制，不删旧文件，旧的留作备份）：
  旧 KOReader 存档 settings/papersprite.lua、旧阅读账本 settings/papersprite_reading.lua、
  旧月读存档 utils.settings 的 ext.papersprite.state。
两边都有存档时取进度多的那份（明信片数 + 旅行次数）。新文件写好并 flush 后才算迁移完成。
--]]
local M = {}

-- 可注入（测试用）
M.deps = {
    dataDir = function() return require("datastorage"):getDataDir() end,
    settingsDir = function() return require("datastorage"):getSettingsDir() end,
    open = function(path) return require("luasettings"):open(path) end,
    exists = function(path) local f = io.open(path, "rb") if f then f:close() return true end return false end,
    mkdirp = function(path)
        local ok, util = pcall(require, "util")
        if ok and util and util.makePath then util.makePath(path) return end
        local lfs = require("libs/libkoreader-lfs")
        local cur = ""
        for part in path:gmatch("[^/]+") do
            cur = cur .. "/" .. part
            if not lfs.attributes(cur, "mode") then lfs.mkdir(cur) end
        end
    end,
    moonState = function()
        local ok, S = pcall(require, "utils.settings")
        if ok and type(S) == "table" and S.getSource then
            local c = S.getSource("ext.papersprite")
            return c and c.state
        end
    end,
}

function M.dir() return M.deps.dataDir() .. "/.moon/game/paper-sprite" end

local function score(st)
    if type(st) ~= "table" then return -1 end
    return #(st.postcards or {}) + (st.trips or 0)
end

local cache = {}

--- 打开（必要时迁移）一个存档文件；name = "save" | "reading"
function M.open(name)
    if cache[name] then return cache[name] end
    local d = M.deps
    local dir = M.dir()
    d.mkdirp(dir)
    local path = dir .. "/" .. name .. ".lua"
    local fresh = not d.exists(path)
    local store = d.open(path)
    if fresh then
        local old_name = name == "save" and "papersprite.lua" or "papersprite_reading.lua"
        local old_path = d.settingsDir() .. "/" .. old_name
        local from = {}
        if d.exists(old_path) then
            local old = d.open(old_path)
            for k, v in pairs(old.data or {}) do store:saveSetting(k, v) end
            from[#from + 1] = old_path
        end
        if name == "save" then
            local ms = d.moonState()
            if ms and score(ms) > score(store:readSetting("state")) then
                store:saveSetting("state", ms)
                from[#from + 1] = "moon:ext.papersprite.state"
            end
        end
        if #from > 0 then store:saveSetting("migrated_from", table.concat(from, ", ")) end
        store:flush()
    end
    cache[name] = store
    return store
end

function M._reset() cache = {} end

return M
