-- SPDX-License-Identifier: MIT
--[[-- 存档结构与版本迁移。存档只含纯数据表（LuaSettings 可序列化）。 --]]
local State = {}

State.VERSION = 4

function State.fresh(now)
    return {
        version = State.VERSION,
        created = now,
        inspiration = 10,                 -- 灵感（开局送一点）
        reading_seen = 0,                 -- 已折算过的阅读账本序号
        inventory = { oat_biscuit = 2, pencil_stub = 1, tiny_atlas = 1 },
        basket = {},                      -- slot -> item id
        sprite = { status = "home" },     -- home | packed | away
        seed = (now or 0) % 2147483647 + 1,
        postcards = {},                   -- { {id, at} }，新的在后
        wall_seen = 0,                    -- 上次看明信片墙时的张数（首页卡片据此显示「新明信片」）
        collected = {},                   -- 明信片身份 key -> 最近收到时间（去重用）
        texts = {},                       -- 收到过的文案（归一化）-> true（AI 句去重用）
        decor = {},                       -- 摆在阁楼里的特产 id（最多 4 个，按位置顺序）
        souvenirs = {},                   -- id -> count
        log = {},                         -- 阁楼里的近况（新的在后，最多 20 条）
        log_at = {},                      -- 与 log 一一对应的发生时间（0 = 旧存档没有时间）
        visitor = nil,                    -- 来访小客人：{ id, pose, until_at }
        seen_visitors = {},               -- 来客簿：id -> 初次来访时间
        place_trips = {},                 -- 剪贴簿：地点 id -> 回家次数
        wish_place = nil,                 -- 灵感惦记的下一趟目的地
        -- 以下为成长系统（core/quest.lua），旧档缺字段时由 load 补默认
        stats = {},                       -- trips / cards / visits / gifts / books / pages / events + weather / tag 分项
        quests = {},                      -- { day, week, list = { {id, kind, key, target, p, reward, weekly, claimed} } }
        achieved = {},                    -- 成就 id -> 达成时间
        bonds = {},                       -- 访客 id -> 交情
        bookmarks = {},                   -- 读完的书 { title, at, tag }
        seen_souvenirs = {},              -- 收到过的特产 id（送人后仍算收集过）
        level = 1,
    }
end

local MIGRATIONS = {
    -- v1 → v2：明信片从固定 id 改为分层组合 {place, pose, prop, weather, line, at}；访客带 id
    [1] = function(s)
        local OLD = { -- v1 内置的 6 张
            ink_lake_01 = { "ink_lake", "sit", "lantern", "mist" }, ink_lake_02 = { "ink_lake", "wave", "none", "clear" },
            fog_market_01 = { "fog_market", "peek", "teacup", "mist" }, fog_market_02 = { "fog_market", "sit", "none", "drizzle" },
            fold_peak_01 = { "fold_peak", "wave", "none", "clear" }, fold_peak_02 = { "fold_peak", "sit", "lantern", "drizzle" },
        }
        local Places = require("papersprite.data.places")
        local function firstLine(id) for _, p in ipairs(Places) do if p.id == id then return p.lines[1] end end end
        local out = {}
        for _, pc in ipairs(s.postcards or {}) do
            local o = OLD[pc.id]
            if o then out[#out + 1] = { place = o[1], pose = o[2], prop = o[3], weather = o[4], line = firstLine(o[1]), at = pc.at } end
        end
        s.postcards = out
        -- 建立去重表；v1 里重复收到的同一张只留一张
        s.collected, s.texts = {}, {}
        local P = require("papersprite.data.postcards")
        local uniq = {}
        for _, c in ipairs(out) do
            c.text_id = "p:1"
            c.key = P.key(c)
            if not s.collected[c.key] then
                s.collected[c.key] = c.at or 0
                s.texts[require("papersprite.core.travel").norm(c.line)] = true
                uniq[#uniq + 1] = c
            end
        end
        s.postcards = uniq
        s.wall_seen = math.min(s.wall_seen or 0, #s.postcards)
        if s.visitor and not s.visitor.id then s.visitor.id = "inkbug" end
        if s.sprite and s.sprite.status == "away" then
            -- 旅途中的旧格式邮件丢弃，提前回家
            s.sprite = { status = "home", back_at = s.sprite.left_at }
            s.basket = {}
        end
    end,
    -- v2 → v3：背景有了 a/b 两种（旧明信片都是 a，key 不变）；新增阁楼装饰 decor；访客带姿势
    [2] = function(s)
        for _, c in ipairs(s.postcards or {}) do c.variant = c.variant or "a" end
        s.decor = s.decor or {}
        if s.visitor then s.visitor.pose = s.visitor.pose or "" end
    end,
    -- v3 → v4：地点剪贴簿 / 来客簿；从旧明信片与特产回填出行次数
    [3] = function(s)
        s.seen_visitors = s.seen_visitors or {}
        if s.visitor and s.visitor.id and not s.seen_visitors[s.visitor.id] then
            s.seen_visitors[s.visitor.id] = s.visitor.until_at or 0
        end
        s.place_trips = s.place_trips or {}
        require("papersprite.core.album").rebuildTrips(s)
    end,
}

function State.load(raw, now)
    if type(raw) ~= "table" or type(raw.version) ~= "number" then return State.fresh(now) end
    local s = raw
    while s.version < State.VERSION do
        local m = MIGRATIONS[s.version]
        if not m then return State.fresh(now) end
        m(s)
        s.version = s.version + 1
    end
    -- 缺字段补默认
    for k, v in pairs(State.fresh(now)) do if s[k] == nil then s[k] = v end end
    -- 旧存档的日志没有时间：前面补 0 对齐（显示时不写时间）
    while #s.log_at < #s.log do table.insert(s.log_at, 1, 0) end
    while #s.log_at > #s.log do table.remove(s.log_at, 1) end
    return s
end

function State.log(s, text, at)
    s.log_at = s.log_at or {}
    while #s.log_at < #s.log do table.insert(s.log_at, 1, 0) end
    s.log[#s.log + 1] = text
    s.log_at[#s.log] = at or os.time()
    while #s.log > 20 do table.remove(s.log, 1) table.remove(s.log_at, 1) end
end

return State
