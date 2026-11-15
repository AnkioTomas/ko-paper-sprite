-- SPDX-License-Identifier: MIT
--[[--
阿页的表结构（core/db 建表）与行 ↔ 内存对象的映射。数据不放进 state，由 core/vault 按需查询、逐行写：
  paper_postcards  明信片，按收到顺序一行一张（seq）
  paper_log        阁楼近况（事件），一行一条，带发生时间
  paper_souvenirs / paper_seen_souvenirs / paper_seen_visitors / paper_collected / paper_place_trips /
  paper_achieved / paper_bonds / paper_texts   各一张 (k, v) 表（id → 值，v 是 storage.encode 的文本）
--]]
local M = {}

local CARD_COLS = { "key", "place", "pose", "prop", "weather", "variant", "line", "text_id", "at" }
local MAPS = { "souvenirs", "seen_souvenirs", "seen_visitors", "collected", "place_trips", "achieved", "bonds", "texts" }

M.FIELD = {}
for _, f in ipairs(MAPS) do M.FIELD[f] = true end

--- 建表语句（core/db 用）
M.SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS paper_postcards (
  seq INTEGER PRIMARY KEY, key TEXT, place TEXT, pose TEXT, prop TEXT, weather TEXT, variant TEXT,
  line TEXT, text_id TEXT, at INTEGER, extra TEXT
);]],
    "CREATE INDEX IF NOT EXISTS paper_postcards_key ON paper_postcards(key);",
    "CREATE TABLE IF NOT EXISTS paper_log (seq INTEGER PRIMARY KEY, text TEXT NOT NULL, at INTEGER NOT NULL);",
}
for _, f in ipairs(MAPS) do
    M.SCHEMA[#M.SCHEMA + 1] = "CREATE TABLE IF NOT EXISTS paper_" .. f .. " (k TEXT PRIMARY KEY, v TEXT NOT NULL);"
end

--- 各表的列（第一列是主键）；后端按它拼 SQL
M.COLS = {
    paper_postcards = { "seq", "key", "place", "pose", "prop", "weather", "variant", "line", "text_id", "at", "extra" },
    paper_log = { "seq", "text", "at" },
}
for _, f in ipairs(MAPS) do M.COLS["paper_" .. f] = { "k", "v" } end

function M.cardRow(c, enc)
    local row, extra = {}, {}
    local known = { index = true } -- index 是 Vault 查询时临时附上的位置
    for _, col in ipairs(CARD_COLS) do known[col] = true row[col] = c[col] end
    for k, v in pairs(c) do if not known[k] then extra[k] = v end end
    row.extra = next(extra) ~= nil and enc(extra) or nil
    return row
end

function M.cardOf(row, dec)
    local c = row.extra and dec(row.extra) or {}
    for _, col in ipairs(CARD_COLS) do if row[col] ~= nil then c[col] = row[col] end end
    c.at = tonumber(c.at)
    return c
end

return M
