-- SPDX-License-Identifier: MIT
--[[--
阅读账本：KOReader 翻页事件记次数，打开阁楼时折算成灵感。
账本存 <数据目录>/.moon/game/paper-sprite/reading.lua（见 core/storage），KOReader 与月读两种宿主共用。
规则：离开这一页时停满 MIN_DWELL 秒、页码差 1–3，才记 1 次。每 20 次 = 1 灵感。
阅读联动：账本还记最近在读的那本书的类型（按书名 / 关键词归到地点类型）和读完的书；
折算时类型让阿页下一趟更爱去对应地方（48 小时内有效）。读完的书变成书签，
阁楼日志写一句带书名的告别；有划线时书签带上用户自己的那句（最多 42 字）。
--]]
local M = { PAGES_PER_POINT = 20, FINISH_REWARD = 5, TAG_TTL = 48 * 3600, MIN_DWELL = 10 }

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

local FAREWELL = {
    night = "读完《%s》，阿页把灯又留了一会儿。",
    water = "读完《%s》，阿页把一句诗折进了书角。",
    sky = "读完《%s》，阿页朝窗外看了很久。",
    town = "读完《%s》，阿页把书签夹在了最后一页。",
    travel = "读完《%s》，阿页在地图册上点了一个点。",
    forest = "读完《%s》，阿页把书轻轻合上，像怕惊动里面的人。",
    market = "读完《%s》，阿页在书页边闻了闻。",
    indoor = "读完《%s》，阿页坐着没说话。",
    garden = "读完《%s》，阿页把一页折了个很小的角。",
    mountain = "读完《%s》，阿页伸了个懒腰。",
    underground = "读完《%s》，阿页把灯挪近了一点。",
    sea = "读完《%s》，阿页听了听窗外的风。",
}
local FAREWELL_ANY = "读完《%s》，阿页把书签夹了进去。"

local store
local function open()
    if not store then
        store = require("papersprite.core.storage").open("reading")
    end
    return store
end
function M._inject(s) store = s end

--- 按码点截断。超长加省略号；空串返回 nil。
function M.clip(text, limit)
    if type(text) ~= "string" then return end
    text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end
    limit = limit or 42
    local i, count = 1, 0
    while i <= #text and count < limit do
        local b = text:byte(i)
        local len = 1
        if b >= 240 then len = 4 elseif b >= 224 then len = 3 elseif b >= 192 then len = 2 end
        if i + len - 1 > #text then break end
        i, count = i + len, count + 1
    end
    if i > #text then return text end
    return text:sub(1, i - 1) .. "…"
end

function M.farewell(title, tag)
    return require("papersprite.l10n")(FAREWELL[tag] or FAREWELL_ANY, title)
end

--- 这次翻页算不算数：相邻页，并且在上一页停满 MIN_DWELL 秒。
function M.qualify(step, dwell)
    return type(step) == "number" and step >= 1 and step <= 3
        and type(dwell) == "number" and dwell >= M.MIN_DWELL
end

--- book = { title, keywords?, finished?, quote? }。step / dwell 不合格就什么都不写。
function M.record(now, book, step, dwell)
    if not M.qualify(step, dwell) then return end
    local s = open()
    if book then
        local tag = M.tagOf(book.title, book.keywords)
        if tag then
            s:saveSetting("last_tag", tag)
            s:saveSetting("last_tag_at", now)
        end
        if book.finished and book.title and book.title ~= "" then
            local done = s:readSetting("finished") or {}
            local seen = false
            for _, b in ipairs(done) do if b.title == book.title then seen = true end end
            if not seen then
                done[#done + 1] = { title = book.title, at = now, tag = tag, quote = M.clip(book.quote) }
                s:saveSetting("finished", done)
            end
        end
    end
    s:saveSetting("pages", (s:readSetting("pages") or 0) + 1)
    s:flush()
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
            local line = M.farewell(b.title, b.tag)
            state.bookmarks[#state.bookmarks + 1] = {
                title = b.title, at = b.at, tag = b.tag, line = line, quote = b.quote,
            }
            require("papersprite.core.state").log(state, line, b.at)
            state.inspiration = state.inspiration + M.FINISH_REWARD
            gained = gained + M.FINISH_REWARD
            Quest.note(state, "book")
        end
    end
    return math.max(0, gained)
end

return M
