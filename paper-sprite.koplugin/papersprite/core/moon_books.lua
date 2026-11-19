-- SPDX-License-Identifier: MIT
--[[--
月读书库里「已读」的书，形状同阅读账本的 finished 项。
打开阁楼或读书墙时先拉已读名册（身份 + 完成时间）做指纹对账：指纹变了才取封面 / 摘录明细。
不用 COUNT+MAX 或时间水位做跳过条件，避免迟到旧书和新书同一轮、或同水位下集合被替换时永久漏同步。
只收录有阅读时间的书，用月读自己的时间，不发灵感。之后的合格翻页读完仍走阅读账本。
--]]
local M = {}

local JOIN = [[
  FROM books b LEFT JOIN pending_progress p
    ON p.source_id = b.source_id AND p.stable_id = b.stable_id
]]
-- 与月读书库已读口径一致：手动已读，或未被强制未读且进度 ≥ 99%。
-- 时间用月读进度 / 云端最近阅读时间，不用同步时刻冒充完成时间。
local AT = "MAX(COALESCE(p.updated_at, 0), b.read_at)"
local QUALIFIED = [[
  b.title <> ''
  AND (b.read_state = 1 OR (b.read_state = 0 AND COALESCE(p.fraction, 0) >= 0.99))
  AND ]] .. AT .. [[ > 0
]]

function M.idOf(source_id, stable_id)
    if type(source_id) ~= "string" or source_id == "" or type(stable_id) ~= "string" or stable_id == "" then
        return
    end
    return "moon:" .. source_id .. ":" .. stable_id
end

--- 书里用户划的第一句（月读 notes 表按章存 JSON 快照）。没有就 nil。
local function firstQuote(DB, source_id, stable_id)
    local ok, json = pcall(require, "json")
    if not ok then return end
    local quote
    DB.each("SELECT payload FROM notes WHERE source_id = ? AND stable_id = ? ORDER BY chapter_idx",
        { source_id, stable_id }, function(row)
        if quote then return end
        local decoded = json.decode(row[1])
        for _idx, item in ipairs(type(decoded) == "table" and decoded.items or {}) do
            if type(item.drawer) == "string" and item.drawer ~= "" and type(item.text) == "string"
                and item.text:find("%S") then
                quote = item.text
                return
            end
        end
    end)
    return quote
end

local function openDB()
    local ok, DB = pcall(require, "utils.db")
    if ok then return DB end
end

local function firstRow(DB, sql, binds)
    local row, qok
    qok = DB.each(sql, binds, function(r)
        row = r
        return false
    end)
    if qok == false then return nil, false end
    return row, true
end

--- 名册指纹：按稳定身份排序后的 id 与完成时间。有 sha2 时收成短哈希，没有则保留可比较的原文。
function M.fingerprint(roster)
    local items = {}
    for _idx, r in ipairs(roster or {}) do
        items[#items + 1] = { id = tostring(r.id or ""), at = tonumber(r.at) or 0 }
    end
    table.sort(items, function(a, b)
        if a.id == b.id then return a.at < b.at end
        return a.id < b.id
    end)
    local parts = {}
    for i, r in ipairs(items) do parts[i] = r.id .. "\t" .. tostring(r.at) end
    local s = table.concat(parts, "\n")
    local ok, sha = pcall(require, "ffi/sha2")
    if ok and sha and sha.md5 then return sha.md5(s) end
    return string.format("r%d:%s", #items, s)
end

--- 轻量已读名册（身份 + 完成时间，不含封面 / 摘录）。失败返回 nil。
function M.roster()
    local DB = openDB()
    if not DB then return end
    local out = {}
    local qok = DB.each(
        "SELECT b.source_id, b.stable_id, " .. AT .. " AS at" .. JOIN .. " WHERE " .. QUALIFIED, nil, function(row)
            local id = M.idOf(row[1], row[2])
            if id then out[#out + 1] = { id = id, at = tonumber(row[3]) or 0, source_id = row[1], stable_id = row[2] } end
        end)
    if qok == false then return end
    return out
end

local function hashPath(path)
    if type(path) ~= "string" or path == "" then return end
    local ok, sha = pcall(require, "ffi/sha2")
    if ok and sha and sha.md5 then return sha.md5(path) end
end

--- 一本书在月读里登记过的文件路径对应的旧墙哈希（整书 path + 分章 path）。用来和旧的文件哈希书签对上，不凭书名合并。
function M.pathAliases(source_id, stable_id, DB)
    DB = DB or openDB()
    if not DB then return {} end
    local aliases, seen = {}, {}
    local function addPath(path)
        local hashed = hashPath(path)
        if hashed and not seen[hashed] then
            seen[hashed] = true
            aliases[#aliases + 1] = hashed
        end
    end
    local function eachPath(sql)
        return DB.each(sql, { source_id, stable_id }, function(row) addPath(row[1]) end)
    end
    if eachPath("SELECT path FROM books WHERE source_id = ? AND stable_id = ? AND path IS NOT NULL AND path <> '';") == false then
        return nil
    end
    if eachPath("SELECT path FROM chapters WHERE source_id = ? AND stable_id = ? AND path IS NOT NULL AND path <> '';") == false then
        return nil
    end
    return aliases
end

--- 导入用明细。失败返回 nil；成功但没有行返回空表。始终按完整已读集合取，不去按时间截断。
--- 封面 / 摘录 / 路径别名在名册查完后再取，避免在同一连接上嵌套 DB.each。
function M.finished()
    local DB = openDB()
    if not DB then return end
    local Paths = require("utils.paths")
    local lfs = require("libs/libkoreader-lfs")
    local raw = {}
    local qok = DB.each([[
        SELECT b.title, ]] .. AT .. [[ AS at, b.source_id, b.stable_id
        ]] .. JOIN .. [[
         WHERE ]] .. QUALIFIED .. [[
         ORDER BY at ASC]], nil, function(row)
        raw[#raw + 1] = row
    end)
    if qok == false then return end
    table.sort(raw, function(a, b) return (tonumber(a[2]) or 0) < (tonumber(b[2]) or 0) end)
    local out = {}
    for _idx, row in ipairs(raw) do
        local cover = Paths.coverPath(row[4], row[3])
        if lfs.attributes(cover, "mode") ~= "file" then cover = nil end
        local aliases = M.pathAliases(row[3], row[4], DB)
        if not aliases then return end
        out[#out + 1] = {
            title = row[1], at = tonumber(row[2]), id = M.idOf(row[3], row[4]),
            cover = cover, quote = firstQuote(DB, row[3], row[4]),
            aliases = aliases, source_id = row[3], stable_id = row[4],
        }
    end
    return out
end

--- 与月读 Store.identityFor 对齐：章节文件 → 整书 path；库外遗留 local（path 等于 stable_id 且不在扫盘根下）不算月读认领；衍生版跟原书走。
local function rejectLegacyLocal(source_id, stable_id, path)
    if source_id ~= "local" or path ~= stable_id then return false end
    local ok, settings = pcall(require, "utils.settings")
    if not ok or not settings or type(settings.getSource) ~= "function" then return true end
    local src = settings.getSource("local")
    local root = src and src.path
    if type(root) ~= "string" or root == "" then return true end
    local ok_text, text = pcall(require, "utils.text")
    if ok_text and text then
        if type(text.rtrimSlashes) == "function" then root = text.rtrimSlashes(root) end
        if type(text.rtrim) == "function" then root = text.rtrim(root) end
    else
        root = root:gsub("/+$", "")
    end
    return root == "" or path:sub(1, #root + 1) ~= root .. "/"
end

local function originOf(path)
    local ok, derived = pcall(require, "reader.session.derived_note")
    if not ok or not derived or type(derived.originOf) ~= "function" then return end
    local ook, origin = pcall(derived.originOf, path)
    if ook then return origin end
end

local function lookupStore(path)
    local ok, Store = pcall(require, "book.store")
    if not ok or not Store or type(Store.identityFor) ~= "function" then return end
    local iok, identity = pcall(Store.identityFor, path)
    if iok and identity and identity.source_id and identity.stable_id then return identity end
end

local function lookupSql(path, seen)
    seen[path] = true
    local DB = openDB()
    if not DB then return nil, "no-db" end
    local ch, ch_ok = firstRow(DB, "SELECT source_id, stable_id FROM chapters WHERE path = ? LIMIT 1;", { path })
    if ch_ok == false then return nil, "error" end
    if ch then return { source_id = ch[1], stable_id = ch[2], chapter = true } end
    local book, book_ok = firstRow(DB,
        "SELECT source_id, stable_id FROM books WHERE path = ? ORDER BY deleted ASC, inserted_at DESC, stable_id ASC LIMIT 1;",
        { path })
    if book_ok == false then return nil, "error" end
    if book then
        if rejectLegacyLocal(book[1], book[2], path) then return nil, "outside" end
        return { source_id = book[1], stable_id = book[2] }
    end
    local origin = originOf(path)
    if type(origin) == "string" and origin ~= "" and not seen[origin] then
        local ident, err = lookupSql(origin, seen)
        if ident then ident.derived = true end
        return ident, err
    end
    if originOf(path) then return nil, "error" end
    return nil, "none"
end

--- 当前打开的文件在月读书库里的全书身份和完读状态。
--- 不是月读认领的书返回 nil（调用方可回退到整书页码口径）。
--- 已认领但读进度失败、或身份查询出错：返回 claimed=true, finished=false，不要按当前文档页数误判。
function M.forFile(path)
    if type(path) ~= "string" or path == "" then return end
    local identity = lookupStore(path)
    local err
    if not identity then
        identity, err = lookupSql(path, {})
    end
    if err == "no-db" then return end
    if err == "error" then return { claimed = true, finished = false } end
    if not identity then return end
    local id = M.idOf(identity.source_id, identity.stable_id)
    if not id then return { claimed = true, finished = false } end
    local aliases = {}
    local file_hash = hashPath(path)
    if file_hash then aliases[1] = file_hash end
    local DB = openDB()
    if not DB then return { id = id, finished = false, claimed = true, aliases = aliases } end
    local more = M.pathAliases(identity.source_id, identity.stable_id, DB)
    if not more then return { id = id, finished = false, claimed = true, aliases = aliases } end
    local seen = {}
    for _idx, a in ipairs(aliases) do seen[a] = true end
    for _idx, a in ipairs(more) do
        if not seen[a] then
            seen[a] = true
            aliases[#aliases + 1] = a
        end
    end
    local row, ok = firstRow(DB, [[
        SELECT b.read_state, COALESCE(p.fraction, 0)
        ]] .. JOIN .. [[
         WHERE b.source_id = ? AND b.stable_id = ? LIMIT 1;]], { identity.source_id, identity.stable_id })
    if ok == false or not row then
        return { id = id, finished = false, claimed = true, aliases = aliases }
    end
    local read_state, fraction = tonumber(row[1]) or 0, tonumber(row[2]) or 0
    -- 强制未读（2）即使进度到 99% 也不算完读；1 或（0 且 ≥99%）与书库已读口径一致。
    local finished = read_state == 1 or (read_state == 0 and fraction >= 0.99)
    return {
        id = id, finished = finished, claimed = true, aliases = aliases,
        read_state = read_state, fraction = fraction,
    }
end

return M
