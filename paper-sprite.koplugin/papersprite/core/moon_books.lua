-- SPDX-License-Identifier: MIT
--[[--
月读书库里标记为已读的书（books.read_state = 1），形状同阅读账本的 finished 项。
月读不在（utils.db 加载不了）就是空表，翻页账本照旧管读完。
--]]
local M = {}

function M.finished()
    local ok, DB = pcall(require, "utils.db")
    if not ok then return {} end
    local rows = DB.query([[
        SELECT title, read_at FROM books
         WHERE read_state = 1 AND deleted = 0 AND hidden = 0 AND title <> ''
         ORDER BY read_at]])
    local out = {}
    for _, r in ipairs(rows or {}) do
        out[#out + 1] = { title = r.title or r[1], at = tonumber(r.read_at or r[2]) or 0 }
    end
    return out
end

return M
