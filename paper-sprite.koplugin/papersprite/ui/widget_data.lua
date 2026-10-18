-- SPDX-License-Identifier: MIT
--[[--
月读首页组件的显示数据（纯函数，无 KOReader 依赖，headless 可测）。
都在存档的「只读副本」上按当前时间结算，不写存档；组件只读，不在里面玩。
--]]
local T = require("papersprite.l10n")

local M = {}

local function copy(t)
    if type(t) ~= "table" then return t end
    local o = {} for k, v in pairs(t) do o[k] = copy(v) end return o
end

--- 读副本并结算到 now
function M.view(raw, now, debug_fast)
    local State = require("papersprite.core.state")
    local Travel = require("papersprite.core.travel")
    local s = State.load(copy(raw), now)
    pcall(Travel.settle, s, now, debug_fast)
    return s
end

--- 签名：表内容相同 → 同一串（组件据此判断要不要重建）
function M.sig(v)
    local out = {}
    local function enc(x)
        if type(x) ~= "table" then out[#out + 1] = tostring(x) return end
        local ks = {} for k in pairs(x) do ks[#ks + 1] = k end
        table.sort(ks, function(a, b) return tostring(a) < tostring(b) end)
        out[#out + 1] = "{"
        for _, k in ipairs(ks) do out[#out + 1] = tostring(k) .. "=" enc(x[k]) end
        out[#out + 1] = "}"
    end
    enc(v)
    return table.concat(out, "\31")
end

--- 阁楼组件：画面 + 一行近况
function M.attic(s, now, debug_fast)
    local Game = require("papersprite.game")
    local Travel = require("papersprite.core.travel")
    local sp = s.sprite
    local line
    if sp.status == "away" then
        local h = math.floor((now - (sp.left_at or now)) / Travel.timing(debug_fast).hour)
        line = h >= 1 and T("阿页出门了，走了 %d 小时", h) or T("阿页刚出门，纸条压在桌上")
    elseif sp.status == "packed" then
        line = T("行囊收好了，阿页正望着窗外")
    else
        local v = s.visitor and Travel.visitor(s.visitor.id)
        line = v and T("阿页在招待%s", v.name) or T("阿页坐在书桌边")
    end
    local new = #s.postcards - (s.wall_seen or 0)
    local sub = (new > 0 and T("新明信片 %d · ", new) or "") .. T("灵感 %d", s.inspiration)
    return { scene = Game.atticScene(s, now), line = line, sub = sub }
end

--- 明信片组件：最近的 n 张，新的在前；index 是在存档里的序号（点开用）
function M.postcards(s, n, page)
    local Travel = require("papersprite.core.travel")
    local P = require("papersprite.data.postcards")
    local Game = require("papersprite.game")
    local out, seen = {}, s.wall_seen or 0
    n = math.max(1, n)
    local pages = math.max(1, math.ceil(#s.postcards / n))
    page = math.max(1, math.min(page or 1, pages))
    local first = #s.postcards - (page - 1) * n
    for i = first, math.max(1, first - n + 1), -1 do
        local c = s.postcards[i]
        local p = Travel.place(c.place)
        out[#out + 1] = { index = i, scene = Game.cardScene(c), place = p and p.name or c.place,
            weather = P.weather_names[c.weather] or "", line = c.line or "", new = i > seen,
            date = os.date("%m-%d %H:%M", c.at or 0) }
    end
    return { cards = out, total = #s.postcards, new = math.max(0, #s.postcards - seen), page = page, pages = pages }
end

--- 纪念物柜组件：已收集的特产图标（按名字排序）+ n/总数
function M.cabinet(s)
    local P = require("papersprite.data.postcards")
    local total = 0
    for _ in pairs(P.souvenirs) do total = total + 1 end
    local items = {}
    for id, n in pairs(s.souvenirs or {}) do
        local sv = P.souvenirs[id]
        if sv and n > 0 then items[#items + 1] = { id = id, name = sv.name, count = n, icon = "souvenirs/" .. id .. ".png" } end
    end
    table.sort(items, function(a, b) return a.name < b.name end)
    return { items = items, have = #items, total = total }
end

--- 尺寸档位与行列（组件设置里可选 small / medium / large）
M.SIZES = { "small", "medium", "large" }
M.SIZE_NAMES = { small = T("小"), medium = T("中"), large = T("大") }
M.LIST_ROWS = { small = 2, medium = 3, large = 5 }
M.GRID_ROWS = { small = 1, medium = 2, large = 3 }
M.CAB_ROWS = { small = 1, medium = 2, large = 4 }

return M
