-- SPDX-License-Identifier: MIT
--[[--
读书墙：读完的书，存在阿页自己的 SQLite（core/db，paper_shelf 表）里。
书会越积越多（几万本也要翻得动），所以不放进整份重写的存档，按页查、按条写。
key = 书的 id（阅读时记下的），没有 id（从月读书库导入）的用 "t:" + 书名；
同书名且任一边没有 id 算同一本（导入的书之后又读完，不重复）。
thought = 阿页的感悟，NULL 表示还没写（由 core/story 的 maybeThoughts 补）。
spec 用 Shelf.use(impl) 换成内存实现。
--]]
local M = {}

local function keyOf(b) return b.id or ("t:" .. b.title) end

local function db() return require("papersprite.core.db") end

local function row(r)
    return { id = r[1], title = r[2], at = tonumber(r[3]), tag = r[4], line = r[5], quote = r[6], cover = r[7],
        thought = r[8], key = r[9] }
end
local COLS = "id, title, at, tag, line, quote, cover, thought, key"

local sqlite = {}

function sqlite.count()
    return tonumber((db().rowexec("SELECT COUNT(*) FROM paper_shelf;"))) or 0
end

--- 新的在前，offset 从 0 起
function sqlite.page(offset, limit)
    local out = {}
    db().each("SELECT " .. COLS .. " FROM paper_shelf ORDER BY at DESC, rowid DESC LIMIT ? OFFSET ?;",
        { limit, offset }, function(r) out[#out + 1] = row(r) end)
    return out
end

--- 还没有感悟的，旧的先
function sqlite.pending(limit, skip)
    local out = {}
    db().each("SELECT " .. COLS .. " FROM paper_shelf WHERE thought IS NULL ORDER BY at, rowid;", nil, function(r)
        local b = row(r)
        if not skip[b.key] then out[#out + 1] = b end
        return #out < limit
    end)
    return out
end

--- 已有同一本返回 false，写库失败返回 nil
function sqlite.add(b)
    local DB = db()
    local key = keyOf(b)
    local has = DB.rowexec([[SELECT 1 FROM paper_shelf WHERE key = ? OR (title = ? AND (id IS NULL OR ? = 1)) LIMIT 1;]],
        key, b.title, b.id == nil and 1 or 0)
    if has then return false end
    return DB.exec([[INSERT INTO paper_shelf (key, id, title, at, tag, line, quote, cover, thought) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);]],
        key, b.id, b.title, b.at, b.tag, b.line, b.quote, b.cover, b.thought) and true or nil
end

function sqlite.setThought(key, text)
    db().exec("UPDATE paper_shelf SET thought = ? WHERE key = ? AND thought IS NULL;", text, key)
end

--- 只在一个事务里批量写（导入几千本时不一本一次提交）
function sqlite.batch(fn)
    return db().transaction(function() fn() return true end)
end

local impl = sqlite
function M.use(x) impl = x or sqlite end

function M.count() return impl.count() end
function M.page(offset, limit) return impl.page(offset, limit) end
function M.pending(limit, skip) return impl.pending(limit, skip or {}) end
function M.add(b) b.key = keyOf(b) return impl.add(b) end
function M.setThought(key, text) impl.setThought(key, text) end
function M.batch(fn) return impl.batch(fn) end
M.keyOf = keyOf

return M
