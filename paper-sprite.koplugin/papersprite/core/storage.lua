-- SPDX-License-Identifier: MIT
--[[--
存档位置：<KOReader 数据目录>/.moon/game/paper-sprite/paper-sprite.sqlite3（阿页自己的库，见 core/db）
  kv 表 name="save"     存档（state，含 AI 写下的文案）+ KOReader 宿主的设置（setting_*）
  kv 表 name="reading"  阅读账本（翻页计数）
读书墙的书在同一个库的 paper_shelf 表（core/shelf）。KOReader 与月读两种宿主共用。缩略图缓存只在内存里（ui/compose），不落盘。

库里还没有某个 name 时，从旧位置迁移（只读取，旧文件留作备份）：
  1.9.x 的 save.lua / reading.lua（先 repair）、更早的 settings/papersprite.lua、settings/papersprite_reading.lua、
  旧月读存档 utils.settings 的 ext.papersprite.state。
两边都有存档时取进度多的那份（明信片数 + 旅行次数）。写进库后才算迁移完成。
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
    backend = nil, -- 默认 sqlite（见 sqliteBackend）；spec 换成内存实现
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

--- 存档值 → Lua 字面量文本。只认纯数据：cdata（int64）按数字写，其它不认识的值丢掉
--- （KOReader 的 dump 会把 cdata 写成 `= ,` 让整份存档读不回来）。
local function encode(v, out)
    local t = type(v)
    if t == "cdata" then v, t = tonumber(v), "number" end
    if t == "string" then out[#out + 1] = string.format("%q", v)
    elseif t == "number" then out[#out + 1] = string.format("%.17g", v)
    elseif t == "boolean" then out[#out + 1] = tostring(v)
    elseif t == "table" then
        out[#out + 1] = "{"
        for k, x in pairs(v) do
            local kt = type(k)
            if (kt == "string" or kt == "number") and type(x) ~= "function" and type(x) ~= "userdata" and type(x) ~= "thread" then
                out[#out + 1] = "[" .. (kt == "string" and string.format("%q", k) or string.format("%.17g", k)) .. "]="
                encode(x, out)
                out[#out + 1] = ","
            end
        end
        out[#out + 1] = "}"
    else out[#out + 1] = "nil" end
end

function M.encode(v)
    local out = {}
    encode(v, out)
    return table.concat(out)
end

function M.decode(text)
    local fn = assert((loadstring or load)("return " .. text, "=kv"))
    if setfenv then setfenv(fn, {}) end
    return fn()
end

local sqliteBackend = {
    load = function(name)
        local DB, rows = require("papersprite.core.db"), {}
        assert(DB.each("SELECT k, v FROM kv WHERE name = ?;", { name }, function(r) rows[r[1]] = r[2] end),
            "paper-sprite.sqlite3 unavailable")
        return rows
    end,
    write = function(name, changes)
        local DB = require("papersprite.core.db")
        assert(DB.transaction(function()
            for k, text in pairs(changes) do
                local ok
                if text == false then ok = DB.exec("DELETE FROM kv WHERE name = ? AND k = ?;", name, k)
                else ok = DB.exec("INSERT OR REPLACE INTO kv (name, k, v) VALUES (?, ?, ?);", name, k, text) end
                if not ok then return false end
            end
            return true
        end), "paper-sprite.sqlite3 write failed")
    end,
}

local function backend() return M.deps.backend or sqliteBackend end

-- 和 LuaSettings 同形：readSetting 返回库里的那张表（调用方就地改），saveSetting 标脏，flush 才落库
local Store = {}
Store.__index = Store

function Store:readSetting(k) return self.data[k] end
function Store:saveSetting(k, v) self.data[k], self.dirty[k] = v, true return self end
function Store:delSetting(k) return self:saveSetting(k, nil) end

-- state 按字段拆行（state.postcards / state.souvenirs / state.log …）：每个领域一行，
-- 只写内容变了的那几行，不再每次点按都重写整份存档。sent 记着每个字段上次落库的文本。
local PREFIX = "state."

function Store:flush()
    local changes = {}
    for k in pairs(self.dirty) do
        local v = self.data[k]
        if k == "state" then
            for field, x in pairs(v or {}) do
                local text = M.encode(x)
                if self.sent[field] ~= text then changes[PREFIX .. field], self.sent[field] = text, text end
            end
            for field in pairs(self.sent) do
                if not (v and v[field] ~= nil) then changes[PREFIX .. field], self.sent[field] = false, nil end
            end
            if self.legacy_state then changes.state, self.legacy_state = false, nil end

        else
            changes[k] = v ~= nil and M.encode(v) or false
        end
    end
    if next(changes) ~= nil then backend().write(self.name, changes) end
    self.dirty = {}
end

--- 1.9.1 把 int64（cdata）写进了书签，KOReader 的序列化会把它写成 `["title"] = ,`，整份存档读不回来
--- （LuaSettings 退到 .old 再退到空表，等于存档清零）。这类文件只坏在那几个值上：补成 nil 后能读就写回去。
function M.repair(path)
    local f = io.open(path, "rb")
    if not f then return false end
    local text = f:read("*a")
    f:close()
    if (loadstring or load)(text, "=save") then return false end
    local fixed, n = text:gsub("%] = ,", "] = nil,")
    if n == 0 or not (loadstring or load)(fixed, "=save") then return false end
    local out = io.open(path, "wb")
    if not out then return false end
    out:write(fixed)
    out:close()
    return true
end

--- 打开（必要时迁移）一个存档；name = "save" | "reading"
function M.open(name)
    if cache[name] then return cache[name] end
    local d = M.deps
    local dir = M.dir()
    d.mkdirp(dir)
    local data, sent, rows = {}, {}, backend().load(name)
    local legacy = rows.state ~= nil -- 测试版整份存的 state：先读它，字段行盖在上面，下次 flush 拆开并删掉
    for k, text in pairs(rows) do
        if k:sub(1, #PREFIX) ~= PREFIX then data[k] = M.decode(text) end
    end
    for k, text in pairs(rows) do
        if k:sub(1, #PREFIX) == PREFIX then
            data.state = data.state or {}
            local field = k:sub(#PREFIX + 1)
            data.state[field] = M.decode(text)
            sent[field] = text
        end
    end
    local store = setmetatable({ name = name, data = data, dirty = {}, sent = sent, legacy_state = legacy }, Store)
    if legacy then store.dirty.state = true end
    if next(data) == nil then
        local from = {}
        local function pull(path)
            for k, v in pairs(d.open(path).data or {}) do store:saveSetting(k, v) end
            from[#from + 1] = path
        end
        local legacy = dir .. "/" .. name .. ".lua"
        if d.exists(legacy) then
            if name == "save" then
                M.repair(legacy)
                M.repair(legacy .. ".old")
            end
            pull(legacy)
        end
        local old_path = d.settingsDir() .. "/" .. (name == "save" and "papersprite.lua" or "papersprite_reading.lua")
        if d.exists(old_path) then
            local old = d.open(old_path)
            for k, v in pairs(old.data or {}) do
                if store:readSetting(k) == nil then store:saveSetting(k, v) end
            end
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
