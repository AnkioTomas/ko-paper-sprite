-- SPDX-License-Identifier: MIT
--[[--
阿页的明细数据：明信片、近况（事件）、特产、来客等，都在自己的表里（表结构见 core/tables），
不放进内存里的 state。读按需查（分页 / 单键 / 计数），写当场落一行，不整块重写。

  明信片  Vault.cardCount / card(i) 第 i 张（1 = 最早）/ cardsNewest(offset, limit) / eachCard(fn) / cardAdd / cardReplace
  近况    Vault.logAdd(text, at)（只留最近 LOG_MAX 条）/ logList() → texts, ats（旧的在前）/ logLast()
  表字段  Vault.get(field, k) / set(field, k, v)（v = nil 删除）/ incr(field, k, n) / all(field) / size(field)
          field ∈ souvenirs seen_souvenirs seen_visitors collected place_trips achieved bonds texts

后端：默认 sqlite（core/db）；spec 用 Vault.use(be) 换内存实现。be 接口（t 是表名，pk 是主键）：
  count(t) / get(t, pk) / put(t, row) / del(t, pk) / page(t, offset, limit, desc) / scan(t, fn) / tx(fn)
--]]
local Tables = require("papersprite.core.tables")
local Storage = require("papersprite.core.storage")

local M = {}

M.LOG_MAX = 20

local PK = { paper_postcards = "seq", paper_log = "seq" }
local function pkOf(t) return PK[t] or "k" end

local sqlite = {}

function sqlite.count(t)
    return tonumber(require("papersprite.core.db").rowexec("SELECT COUNT(*) FROM " .. t .. ";")) or 0
end

local function rowFrom(t, r)
    local row = {}
    for i, c in ipairs(Tables.COLS[t]) do row[c] = r[i] end
    return row
end

function sqlite.get(t, pk)
    local out
    local cols = Tables.COLS[t]
    require("papersprite.core.db").each("SELECT " .. table.concat(cols, ", ") .. " FROM " .. t .. " WHERE " .. cols[1] .. " = ?;",
        { pk }, function(r) out = rowFrom(t, r) return false end)
    return out
end

function sqlite.put(t, row)
    local cols, vals, marks = Tables.COLS[t], {}, {}
    for i, c in ipairs(cols) do vals[i], marks[i] = row[c], "?" end
    assert(require("papersprite.core.db").exec("INSERT OR REPLACE INTO " .. t .. " (" .. table.concat(cols, ", ")
        .. ") VALUES (" .. table.concat(marks, ", ") .. ");", unpack(vals, 1, #cols)), t .. " write failed")
end

function sqlite.del(t, pk)
    assert(require("papersprite.core.db").exec("DELETE FROM " .. t .. " WHERE " .. Tables.COLS[t][1] .. " = ?;", pk), t .. " delete failed")
end

function sqlite.page(t, offset, limit, desc)
    local cols, out = Tables.COLS[t], {}
    assert(require("papersprite.core.db").each("SELECT " .. table.concat(cols, ", ") .. " FROM " .. t .. " ORDER BY " .. cols[1]
        .. (desc and " DESC" or "") .. " LIMIT ? OFFSET ?;", { limit, offset }, function(r) out[#out + 1] = rowFrom(t, r) end), t .. " unavailable")
    return out
end

function sqlite.scan(t, fn)
    local cols = Tables.COLS[t]
    assert(require("papersprite.core.db").each("SELECT " .. table.concat(cols, ", ") .. " FROM " .. t .. " ORDER BY " .. cols[1] .. ";",
        nil, function(r) return fn(rowFrom(t, r)) end), t .. " unavailable")
end

function sqlite.tx(fn)
    assert(require("papersprite.core.db").transaction(function() fn() return true end), "paper-sprite.sqlite3 transaction failed")
end

local be = sqlite
function M.use(x) be = x or sqlite end

-- 明信片 -----------------------------------------------------------------

function M.cardCount() return be.count("paper_postcards") end

function M.card(i)
    local r = be.page("paper_postcards", i - 1, 1, false)[1]
    return r and Tables.cardOf(r, Storage.decode)
end

--- 新的在前；每张带 index（在全部明信片里的位置，1 = 最早）
function M.cardsNewest(offset, limit)
    local total, out = be.count("paper_postcards"), {}
    for k, r in ipairs(be.page("paper_postcards", offset, limit, true)) do
        local c = Tables.cardOf(r, Storage.decode)
        c.index = total - offset - k + 1
        out[k] = c
    end
    return out
end

--- 从早到晚逐张；fn(card, index) 返回 false 提前结束
function M.eachCard(fn)
    local i = 0
    be.scan("paper_postcards", function(r)
        i = i + 1
        return fn(Tables.cardOf(r, Storage.decode), i)
    end)
end

--- 各地点的明信片张数 { place = n }
function M.cardsByPlace()
    local out = {}
    be.scan("paper_postcards", function(r) if r.place then out[r.place] = (out[r.place] or 0) + 1 end end)
    return out
end

function M.cardAdd(card)
    local last = be.page("paper_postcards", 0, 1, true)[1]
    local row = Tables.cardRow(card, Storage.encode)
    row.seq = (last and last.seq or 0) + 1
    be.put("paper_postcards", row)
end

--- 改写第 i 张（序号 i = card(i) 的位置）；本趟 AI 文案迟到时用
function M.cardReplace(i, card)
    local r = be.page("paper_postcards", i - 1, 1, false)[1]
    local row = Tables.cardRow(card, Storage.encode)
    row.seq = r.seq
    be.put("paper_postcards", row)
end

-- 近况 -------------------------------------------------------------------

local function logPut(text, at)
    local last = be.page("paper_log", 0, 1, true)[1]
    be.put("paper_log", { seq = (last and last.seq or 0) + 1, text = text, at = at or os.time() })
    local extra = be.count("paper_log") - M.LOG_MAX
    if extra > 0 then
        for _, r in ipairs(be.page("paper_log", 0, extra, false)) do be.del("paper_log", r.seq) end
    end
end

function M.logAdd(text, at)
    be.tx(function() logPut(text, at) end)
end

--- 旧的在前
function M.logList()
    local texts, ats = {}, {}
    for i, r in ipairs(be.page("paper_log", 0, M.LOG_MAX, false)) do texts[i], ats[i] = r.text, tonumber(r.at) end
    return texts, ats
end

function M.logLast()
    local r = be.page("paper_log", 0, 1, true)[1]
    return r and r.text
end

-- (k, v) 表 --------------------------------------------------------------

local function tname(field)
    assert(Tables.FIELD[field], "unknown vault field " .. tostring(field))
    return "paper_" .. field
end

function M.get(field, k)
    local r = be.get(tname(field), k)
    if r then return Storage.decode(r.v) end
end

function M.set(field, k, v)
    local t = tname(field)
    if v == nil then be.del(t, k) else be.put(t, { k = k, v = Storage.encode(v) }) end
end

function M.incr(field, k, n)
    local v = (M.get(field, k) or 0) + (n or 1)
    M.set(field, k, v)
    return v
end

--- 整张表读成 { k = v }（每次现查，不留在内存里；这些表都以目录 id 为键，只有几十到几百行）
function M.all(field)
    local out = {}
    be.scan(tname(field), function(r) out[r.k] = Storage.decode(r.v) end)
    return out
end

function M.size(field) return be.count(tname(field)) end

-- 旧存档迁移 --------------------------------------------------------------

--- 旧版把这些都放在 state 里。表还是空的才导入（导入后存档里就不再有这些字段，重复导入会翻倍）。
function M.import(s)
    if type(s.postcards) == "table" and M.cardCount() == 0 then
        be.tx(function() for _, c in ipairs(s.postcards) do M.cardAdd(c) end end)
    end
    if type(s.log) == "table" and be.count("paper_log") == 0 then
        be.tx(function()
            for i, text in ipairs(s.log) do logPut(text, (s.log_at or {})[i] or 0) end
        end)
    end
    for field in pairs(Tables.FIELD) do
        if type(s[field]) == "table" and M.size(field) == 0 then
            be.tx(function() for k, v in pairs(s[field]) do M.set(field, k, v) end end)
        end
    end
end

return M
