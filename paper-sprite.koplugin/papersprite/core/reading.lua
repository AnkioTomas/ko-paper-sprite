-- SPDX-License-Identifier: MIT
--[[--
阅读账本：KOReader 翻页事件记次数，打开阁楼时折算成灵感。
账本存 <数据目录>/.moon/game/paper-sprite/reading.lua（见 core/storage），KOReader 与月读两种宿主共用。
规则：每 20 次翻页 = 1 灵感；同一分钟内多次翻页只算 1 次（防连点）。
阅读联动：账本还记最近在读的那本书的类型（按书名 / 关键词归到地点类型）和读完的书；
折算时类型让阿页下一趟更爱去对应地方（48 小时内有效），读完的书变成书签贴上读书墙。
--]]
local M = { PAGES_PER_POINT = 20, FINISH_REWARD = 5, TAG_TTL = 48 * 3600 }

--- 书名 / 关键词 → 地点类型（先匹配到的算）
local GENRES = {
    { "night", { "推理", "悬疑", "侦探", "犯罪", "mystery", "detective", "crime", "thriller" } },
    { "water", { "诗", "散文", "poem", "poetry", "essay" } },
    { "sky", { "科幻", "宇宙", "太空", "science fiction", "sci-fi", "space" } },
    { "town", { "历史", "传记", "history", "biography" } },
    { "travel", { "旅行", "游记", "旅", "travel" } },
    { "forest", { "奇幻", "魔法", "童话", "fantasy", "fairy", "magic" } },
    { "market", { "美食", "烹饪", "菜", "cook", "food" } },
    { "indoor", { "哲学", "心理", "philosoph", "psycholog" } },
    { "garden", { "爱情", "言情", "romance", "love" } },
    { "mountain", { "冒险", "武侠", "adventure" } },
    { "underground", { "恐怖", "惊悚", "horror" } },
    { "sea", { "海", "航", "sea", "ocean" } },
}

function M.tagOf(title, keywords)
    local text = (tostring(title or "") .. " " .. tostring(keywords or "")):lower()
    for _, g in ipairs(GENRES) do
        for _, kw in ipairs(g[2]) do
            if text:find(kw, 1, true) then return g[1] end
        end
    end
end

local store
local function open()
    if not store then
        store = require("papersprite.core.storage").open("reading")
    end
    return store
end
function M._inject(s) store = s end

--- book = { title, keywords?, finished? }（可选）：记下最近在读的类型；finished 记入读完的书
function M.record(now, book)
    local s = open()
    local minute = math.floor(now / 60)
    local dirty = s:readSetting("last_minute") ~= minute
    if book then
        local tag = M.tagOf(book.title, book.keywords)
        if tag then
            if s:readSetting("last_tag") ~= tag then dirty = true end
            s:saveSetting("last_tag", tag)
            s:saveSetting("last_tag_at", now)
        end
        if book.finished and book.title and book.title ~= "" then
            local done = s:readSetting("finished") or {}
            local seen = false
            for _, b in ipairs(done) do if b.title == book.title then seen = true end end
            if not seen then
                done[#done + 1] = { title = book.title, at = now, tag = tag }
                s:saveSetting("finished", done)
                dirty = true
            end
        end
    end
    if s:readSetting("last_minute") ~= minute then
        s:saveSetting("last_minute", minute)
        s:saveSetting("pages", (s:readSetting("pages") or 0) + 1)
    end
    if dirty then s:flush() end
end

--- 把账本里新增的内容折算进存档 state；返回新增灵感。
function M.collect(state)
    local ok, s = pcall(open)
    if not ok then return 0 end
    local Quest = require("papersprite.core.quest")
    local pages = s:readSetting("pages") or 0
    local seen = state.reading_seen or 0
    local gained = math.floor(pages / M.PAGES_PER_POINT) - math.floor(seen / M.PAGES_PER_POINT)
    state.reading_seen = pages
    if pages > seen then Quest.note(state, "pages", nil, pages - seen) end
    if gained > 0 then state.inspiration = state.inspiration + gained end
    local tag, at = s:readSetting("last_tag"), s:readSetting("last_tag_at")
    if tag and at then state.read_tag, state.read_tag_at = tag, at end
    state.bookmarks = state.bookmarks or {}
    for _, b in ipairs(s:readSetting("finished") or {}) do
        local have = false
        for _, x in ipairs(state.bookmarks) do if x.title == b.title then have = true end end
        if not have then
            state.bookmarks[#state.bookmarks + 1] = { title = b.title, at = b.at, tag = b.tag }
            state.inspiration = state.inspiration + M.FINISH_REWARD
            gained = gained + M.FINISH_REWARD
            Quest.note(state, "book")
        end
    end
    return math.max(0, gained)
end

return M
