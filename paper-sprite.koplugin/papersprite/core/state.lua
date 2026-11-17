-- SPDX-License-Identifier: MIT
--[[-- 存档结构与版本迁移。存档只含纯数据表（LuaSettings 可序列化）。 --]]
local State = {}

State.VERSION = 8

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
        wall_seen = 0,                    -- 上次看明信片墙时的张数（首页卡片据此显示「新明信片」）
        decor = {},                       -- 摆在阁楼里的特产 id（最多 4 个，按位置顺序）
        visitor = nil,                    -- 来访小客人：{ id, pose, until_at }
        wish_place = nil,                 -- 灵感惦记的下一趟目的地
        -- 以下为成长系统（core/quest.lua），旧档缺字段时由 load 补默认
        stats = {},                       -- trips / cards / visits / gifts / books / pages / events + weather / tag 分项
        quests = {},                      -- { day, week, list = { {id, kind, key, target, p, reward, weekly, claimed} } }
        errands = {},                     -- 访客留下的纸条 { visitor, kind, key, say, base, at, claimed? }
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
    -- v4 → v5：每日委托作废，换成访客纸条。旧清单不迁移。
    [4] = function(s)
        s.errands = s.errands or {}
        s.quests = s.quests or {}
        s.quests.list = {}
    end,
    -- v5 → v6：明信片 / 近况有过重复行。导入完成后去重一次（见 load），版本号推进后不再跑。
    [5] = function(s) s.dedupe_pending = true end,
    -- v6 → v7：重复结算寄出过「同一趟同一时刻」的几十张卡，v6 的判重认不出，再清一次
    [6] = function(s) s.dedupe_pending = true end,
    -- v7 → v8：重复结算还刷出了几条同一时刻的出门 / 寄到近况，再清一次
    [7] = function(s) s.dedupe_pending = true end,
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
    -- 明信片 / 近况 / 特产 / 来客等明细在 core/vault 的表里；旧存档里的搬过去，存档里不再留
    local Vault = require("papersprite.core.vault")
    Vault.import(s)
    s.postcards, s.log, s.log_at = nil, nil, nil
    if s.dedupe_pending then
        Vault.dedupe(s)
        s.dedupe_pending = nil
    end
    for field in pairs(require("papersprite.core.tables").FIELD) do s[field] = nil end
    -- 缺字段补默认
    for k, v in pairs(State.fresh(now)) do if s[k] == nil then s[k] = v end end
    return s
end

function State.log(_s, text, at)
    require("papersprite.core.vault").logAdd(text, at)
end

return State
