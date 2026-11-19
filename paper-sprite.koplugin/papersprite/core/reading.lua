-- SPDX-License-Identifier: MIT
--[[--
阅读账本：KOReader 翻页事件记次数，打开阁楼时折算成灵感。
账本存 paper-sprite.sqlite3 的 kv 表（见 core/storage），KOReader 与月读两种宿主共用。
规则：离开这一页时停满 MIN_DWELL 秒、页码差 1–3，才记 1 次。每 20 次 = 1 灵感。
阅读联动：账本还记最近在读的那本书的类型（按书名 / 关键词归到地点类型）和读完的书；
折算时类型让阿页下一趟更爱去对应地方（48 小时内有效）。读完的书变成书签，
阁楼日志写一句带书名的告别；有划线时书签带上用户自己的那句（最多 42 字）。
月读已读在打开阁楼或读书墙时按名册指纹对账后同步到墙上（沿用月读完成时间，不发灵感）；
只有合格翻页记下的读完才奖励灵感，避免批量手动已读刷奖。
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

--- book = { title, keywords?, finished?, quote?, id?, cover? }。step / dwell 不合格就什么都不写。
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
            local done = {}
    for _, b in ipairs(s:readSetting("finished") or {}) do done[#done + 1] = b end
            local seen = false
            for _, b in ipairs(done) do
                if (book.id and b.id == book.id) or (not book.id and b.title == book.title) then seen = true end
            end
            if not seen then
                done[#done + 1] = { id = book.id, title = book.title, at = now, tag = tag,
                    quote = M.clip(book.quote), cover = book.cover, aliases = book.aliases }
                s:saveSetting("finished", done)
            end
        end
    end
    s:saveSetting("pages", (s:readSetting("pages") or 0) + 1)
    s:flush()
end

--- 是否需要向月读拉已读。opts.moon 为真才查（打开阁楼 / 进读书墙）；定时 tick 不扫。
--- 先取完整已读名册做指纹对账：指纹没变才跳过明细，避免 COUNT+MAX 在迟到+新书或同水位换集时漏同步。
--- 查询失败或写入失败不前推指纹，下次重试。
local function pullMoon(state)
    local Moon = require("papersprite.core.moon_books")
    local roster = Moon.roster()
    if not roster then return nil, "unavailable" end
    local fp = Moon.fingerprint(roster)
    if type(state.moon_sync_fp) == "string" and state.moon_sync_fp ~= "" and state.moon_sync_fp == fp then
        return {}, { fp = fp }
    end
    local rows = Moon.finished()
    if not rows then return nil, "unavailable" end
    return rows, { fp = fp }
end

--- 把账本里新增的内容折算进存档 state；返回新增灵感。
--- opts.moon：顺带按名册指纹同步月读已读（历史 / 后来在月读里标记的都不发奖）。
function M.collect(state, opts)
    local s = open()
    local Quest = require("papersprite.core.quest")
    local pages = s:readSetting("pages") or 0
    local seen = state.reading_seen or 0
    local gained = math.floor(pages / M.PAGES_PER_POINT) - math.floor(seen / M.PAGES_PER_POINT)
    state.reading_seen = pages
    if pages > seen then Quest.note(state, "pages", nil, pages - seen) end
    if gained > 0 then state.inspiration = state.inspiration + gained end
    local tag, at = s:readSetting("last_tag"), s:readSetting("last_tag_at")
    if tag and at then state.read_tag, state.read_tag_at = tag, at end
    local Shelf = require("papersprite.core.shelf")
    local legacy = state.bookmarks -- 旧版把读完的书放在存档里，搬进书架表
    local done = {}
    for _, b in ipairs(s:readSetting("finished") or {}) do done[#done + 1] = b end
    local sync_moon = opts and opts.moon
    if not legacy and #done == 0 and not sync_moon then return math.max(0, gained) end
    local moon_rows, moon_stats, moon_err
    if sync_moon then
        moon_rows, moon_stats = pullMoon(state)
        if not moon_rows then moon_err = moon_stats or "unavailable" end
        for _idx, b in ipairs(moon_rows or {}) do
            b.tag, b.backfill = M.tagOf(b.title), true
            done[#done + 1] = b
        end
    end
    if not legacy and #done == 0 then
        -- 月读查询失败：指纹不动。成功但对账无新明细（含空名册）：记下当前指纹，下次指纹不变则不再拉明细。
        if sync_moon and not moon_err and moon_stats then
            state.moon_sync_fp = moon_stats.fp
        end
        return math.max(0, gained)
    end
    local rest, failed = {}, false
    local ran = Shelf.batch(function()
        for _idx, b in ipairs(legacy or {}) do
            -- 1.9.1 存下过 title 不是字符串的坏书签；没有阅读时间（1970）的不是在这台设备上读的；
            -- 没有 id 的是旧版月读导入（缺封面 / 摘录），下面重导
            if type(b.title) == "string" and (b.at or 0) > 0 and (b.id or state.moon_imported == 3
                or state.moon_sync_fp) then Shelf.add(b) end
        end
        for _idx, b in ipairs(done) do
            b.line = M.farewell(b.title, b.tag)
            b.quote = M.clip(b.quote)
            local added = Shelf.add(b)
            if added == nil then
                failed = true
                rest[#rest + 1] = b
            elseif added and not b.backfill then
                require("papersprite.core.state").log(state, b.line, b.at)
                state.inspiration = state.inspiration + M.FINISH_REWARD
                gained = gained + M.FINISH_REWARD
                Quest.note(state, "book")
            end
        end
    end)
    if not ran then return math.max(0, gained) end -- 库不可用：什么都不动，下次再收
    state.bookmarks = nil
    if failed or moon_err then
        -- 失败不前推水位，下次再同步；旧字段清掉以免误以为一次导入已完成
        if failed then state.moon_imported = nil end
    elseif sync_moon and moon_stats then
        state.moon_sync_fp = moon_stats.fp
    end
    -- 账本里读完的书只是待收的队列，收进书架就清掉，写不进的留到下次
    if #(s:readSetting("finished") or {}) > 0 then
        local keep = {}
        for _idx, b in ipairs(rest) do if not b.backfill then keep[#keep + 1] = b end end
        s:saveSetting("finished", keep)
        s:flush()
    end
    return math.max(0, gained)
end

return M
