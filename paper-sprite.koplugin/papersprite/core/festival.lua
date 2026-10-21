-- SPDX-License-Identifier: MIT
--[[--
节日与时令：公历节日离线可用；农历节日 / 节气来自节日接口（api.ankio.net/myrl，月读首页时钟用的同一个），
一天只取一次，存进 state.almanac。取不到就只剩公历节日，其余照常。
接口只返回当天，所以只能认出「今天」的农历节日。
--]]
local T = require("papersprite.l10n")
local Defs = require("papersprite.data.festivals")

local F = { URL = "https://api.ankio.net/myrl?type=json", RETRY = 3600 }

local TERM_LINES = {
    T("节气换了一页，空气里的颜色也跟着淡了一点。"),
    T("日历上多了一个小圈，我也在这一天里画了个记号。"),
}

local function ymd(t) return os.date("%Y-%m-%d", t) end

--- 把接口 JSON（已解码）整理成 { ymd, lunar, festival, term, holiday }；不合规返回 nil
function F.parse(payload)
    local d = type(payload) == "table" and (type(payload.data) == "table" and payload.data or payload) or nil
    if not d or type(d.date) ~= "table" or type(d.date.ymd) ~= "string" then return nil end
    local al = type(d.almanac) == "table" and d.almanac or {}
    local function s(v) return type(v) == "string" and v ~= "" and v or nil end
    return {
        ymd = d.date.ymd, lunar = s(d.date.lunar), festival = s(al.festival), term = s(al.term),
        holiday = type(d.holiday) == "table" and s(d.holiday.label) or nil,
    }
end

--- 月读 online.myrl 缓存的结构与上面一致，直接复用
function F.store(state, daily, now)
    if type(daily) ~= "table" or type(daily.ymd) ~= "string" then return false end
    state.almanac = { ymd = daily.ymd, lunar = daily.lunar, festival = daily.festival, term = daily.term, holiday = daily.holiday }
    state.almanac_try = now
    return true
end

local function known(a, def)
    if not a then return false end
    local text = (a.festival or "") .. " " .. (a.holiday or "")
    for _, m in ipairs(def.match or {}) do if text:find(m, 1, true) then return true end end
    return def.lunar ~= nil and a.lunar ~= nil and a.lunar:find(def.lunar, 1, true) ~= nil
end

--- t 那天的节日（没有返回 nil）：{ id, name, here, lines, weather }
function F.at(state, t)
    if not t then return nil end
    local d = os.date("*t", t)
    local a = state and state.almanac
    if a and a.ymd ~= ymd(t) then a = nil end
    for _, def in ipairs(Defs) do
        if (def.md and def.md[1] == d.month and def.md[2] == d.day) or known(a, def) then return def end
    end
    if a and a.term then
        local name = a.term
        return { id = "term", name = name, weather = {}, here = T("今天是%s，阿页在窗边多坐了一会儿。", name),
            lines = TERM_LINES }
    end
end

--- 明信片的出片情境：月份、钟点、节日
function F.context(state, t)
    local d = os.date("*t", t)
    return { month = d.month, hour = d.hour, festival = F.at(state, t) }
end

--- 今天还需要取接口吗（一天一次；失败一小时后再试）
function F.needsFetch(state, now)
    local a = state.almanac
    if a and a.ymd == ymd(now) then return false end
    return (state.almanac_try or 0) + F.RETRY <= now
end

--- 取今天的节日数据；host:almanac(cb) 是可选能力。回调里 daily 为 nil 表示失败。
function F.refresh(host, state, now, done)
    if type(host.almanac) ~= "function" or host:getSetting("festival_online", true) == false then return false end
    if not F.needsFetch(state, now) then return false end
    state.almanac_try = now
    host:almanac(function(daily) done(daily) end)
    return true
end

return F
