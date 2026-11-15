-- SPDX-License-Identifier: MIT
--[[--
月读书库里标记为已读的书（books.read_state = 1），形状同阅读账本的 finished 项。
只在第一次打开时导入一遍已有的已读书；之后由阅读时 99% 的判定上墙。
--]]
local M = {}

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

--- 一次性导入用，按月读自己的「读完」口径：手动已读，或没被标未读且进度 ≥ 99%（含已下架 / 隐藏的书）。
--- 旧到新排列；没有阅读时间的（别处同步来的）不算。月读不在返回 nil。
function M.finished()
    local ok, DB = pcall(require, "utils.db")
    if not ok then return end
    local Paths = require("utils.paths")
    local lfs = require("libs/libkoreader-lfs")
    local out = {}
    DB.each([[
        SELECT b.title, MAX(COALESCE(p.updated_at, 0), b.read_at) AS at, b.source_id, b.stable_id
          FROM books b LEFT JOIN pending_progress p
            ON p.source_id = b.source_id AND p.stable_id = b.stable_id
         WHERE b.title <> ''
           AND (b.read_state = 1 OR (b.read_state = 0 AND COALESCE(p.fraction, 0) >= 0.99))
           AND at > 0
         ORDER BY at DESC]], nil, function(row)
        -- 只认月读已缓存到本地的封面，没有就不带（墙上用默认图标）
        local cover = Paths.coverPath(row[4], row[3])
        if lfs.attributes(cover, "mode") ~= "file" then cover = nil end
        table.insert(out, 1, { title = row[1], at = tonumber(row[2]), cover = cover, quote = firstQuote(DB, row[3], row[4]) })
    end)
    return out
end

return M
