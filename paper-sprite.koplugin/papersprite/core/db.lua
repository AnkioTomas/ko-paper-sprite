-- SPDX-License-Identifier: MIT
--[[--
阿页自己的 SQLite：<数据目录>/.moon/game/paper-sprite/paper-sprite.sqlite3，独立于月读的 book.sqlite3。
  kv(name, k, v)  存档与阅读账本：name = "save" | "reading"，v 是 Lua 字面量文本（见 core/storage 的 encode）
  paper_shelf     读书墙（见 core/shelf）
  paper_postcards / paper_log / paper_souvenirs …  明信片、近况、特产、来客等（见 core/tables）
只有连接、执行原语、事务，参数一律用 ? 绑定。KOReader 自带 lua-ljsqlite3；spec 不碰这里（storage / shelf 都可换后端）。
--]]
local M = {}

local conn

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS kv (name TEXT NOT NULL, k TEXT NOT NULL, v TEXT NOT NULL, PRIMARY KEY (name, k));]],
    [[CREATE TABLE IF NOT EXISTS paper_shelf (
  key TEXT PRIMARY KEY, id TEXT, title TEXT NOT NULL, at INTEGER NOT NULL,
  tag TEXT, line TEXT, quote TEXT, cover TEXT, thought TEXT
);]],
    "CREATE INDEX IF NOT EXISTS paper_shelf_at ON paper_shelf(at);",
}
for _, sql in ipairs(require("papersprite.core.tables").SCHEMA) do SCHEMA[#SCHEMA + 1] = sql end

function M.path() return require("papersprite.core.storage").dir() .. "/paper-sprite.sqlite3" end

--- 打开失败抛错：存档读不出来时必须让问题暴露，而不是当成空档重新开始
local function ensure()
    if conn then return conn end
    local storage = require("papersprite.core.storage")
    storage.deps.mkdirp(storage.dir())
    local c = require("lua-ljsqlite3/init").open(M.path())
    c:exec("PRAGMA journal_mode=WAL;")
    c:exec("PRAGMA busy_timeout=5000;")
    c:exec("PRAGMA synchronous=NORMAL;")
    c:exec("PRAGMA temp_store=MEMORY;")
    for _, sql in ipairs(SCHEMA) do c:exec(sql) end
    conn = c
    M.dedupe()
    return conn
end

--- 1.9.4 以前首页组件在存档副本上结算，会把同一条近况 / 同一张明信片重复写进库；
--- 只清各列完全相同的行（近况 = 文本 + 时间，明信片 = 除序号外全列），保留最早一行，做一次。
--- 特产数量、各地出行次数被多加过，无从还原，不动。
function M.dedupe()
    local marker = "dedupe_dup_rows"
    if M.rowexec("SELECT 1 FROM kv WHERE name = 'meta' AND k = ?;", marker) then return end
    M.transaction(function()
        assert(M.exec("DELETE FROM paper_log WHERE at > 0 AND seq NOT IN (SELECT MIN(seq) FROM paper_log GROUP BY text, at);"))
        assert(M.exec("DELETE FROM paper_postcards WHERE seq NOT IN (SELECT MIN(seq) FROM paper_postcards "
            .. "GROUP BY key, place, pose, prop, weather, variant, line, text_id, at, extra);"))
        assert(M.exec("INSERT OR REPLACE INTO kv (name, k, v) VALUES ('meta', ?, '1');", marker))
        return true
    end)
end

local function bound(sql, ...)
    local stmt = ensure():prepare(sql)
    local n = select("#", ...)
    if n > 0 then stmt:bind(...) end
    return stmt
end

--- 写：失败返回 nil, err
function M.exec(sql, ...)
    local args, n, stmt = { ... }, select("#", ...), nil
    local ok, err = pcall(function()
        stmt = bound(sql, unpack(args, 1, n))
        stmt:step()
    end)
    if stmt then pcall(stmt.close, stmt) end
    if not ok then return nil, err end
    return true
end

--- 取一行的第一列
function M.rowexec(sql, ...)
    local args, n, stmt = { ... }, select("#", ...), nil
    local ok, row = pcall(function()
        stmt = bound(sql, unpack(args, 1, n))
        return stmt:step({}, {})
    end)
    if stmt then pcall(stmt.close, stmt) end
    if ok and row then return row[1] end
end

--- 逐行回调；fn 返回 false 提前结束。库打不开 / 语句出错返回 false
function M.each(sql, binds, fn)
    local stmt
    local ok, err = pcall(function()
        stmt = bound(sql, unpack(binds or {}))
        while true do
            local row = stmt:step({}, {})
            if not row or fn(row) == false then break end
        end
    end)
    if stmt then pcall(stmt.close, stmt) end
    if not ok then require("logger").err("papersprite db", sql, err) end
    return ok
end

local depth = 0

--- 事务控制语句失败时调用方只拿到 nil，原始错误只在这里留一份
local function control(sql)
    local ok, err = M.exec(sql)
    if not ok then require("logger").warn("papersprite db", sql, err) end
    return ok
end

--- fn 返回真才提交；抛错先回滚再抛。嵌套调用用 SAVEPOINT（同一连接不能再 BEGIN）。
function M.transaction(fn)
    local nested = depth > 0
    local name = "sp" .. depth
    if not control(nested and ("SAVEPOINT " .. name .. ";") or "BEGIN IMMEDIATE;") then return nil end
    depth = depth + 1
    local ok, result = pcall(fn)
    depth = depth - 1
    if ok and result and control(nested and ("RELEASE SAVEPOINT " .. name .. ";") or "COMMIT;") then return result end
    if nested then
        M.exec("ROLLBACK TO SAVEPOINT " .. name .. ";")
        M.exec("RELEASE SAVEPOINT " .. name .. ";")
    else
        M.exec("ROLLBACK;")
    end
    if not ok then error(result, 0) end
end

return M
