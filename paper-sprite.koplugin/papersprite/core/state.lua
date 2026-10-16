-- SPDX-License-Identifier: MIT
--[[-- 存档结构与版本迁移。存档只含纯数据表（LuaSettings 可序列化）。 --]]
local State = {}

State.VERSION = 1

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
        souvenirs = {},                   -- id -> count
        log = {},                         -- 阁楼里的近况（新的在后，最多 20 条）
        visitor = nil,                    -- 墨点虫：{ until_at }
    }
end

local MIGRATIONS = {
    -- [1] = function(s) ... -> 升级到 2
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
    return s
end

function State.log(s, text)
    s.log[#s.log + 1] = text
    while #s.log > 20 do table.remove(s.log, 1) end
end

return State
