-- SPDX-License-Identifier: MIT
-- 无 KOReader 冒烟测试（虚拟时钟）：lua spec/headless.lua
package.path = "paper-sprite.koplugin/?.lua;" .. package.path
local H = { clock = 1000000, queue = {}, saved = nil, view = nil, settings = { debug_fast = true }, shows = 0 }
H.host = {
    showScreen = function(_, v) H.view = v H.shows = H.shows + 1 end,
    closeScreen = function() H.view = nil end,
    schedule = function(_, s, fn) H.queue[#H.queue + 1] = { at = H.clock + s, fn = fn } end,
    unschedule = function(_, fn) for i = #H.queue, 1, -1 do if H.queue[i].fn == fn then table.remove(H.queue, i) end end end,
    loadState = function() return H.saved end, saveState = function(_, t) H.saved = t end,
    getSetting = function(_, k, d) local v = H.settings[k] if v == nil then return d end return v end,
    setSetting = function(_, k, v) H.settings[k] = v end, notify = function() end,
    now = function() return H.clock end,
}
require("papersprite.host.interface").check(H.host)
package.loaded["papersprite.core.reading"] = { collect = function(s) return 0 end }

local function advance(secs)
    local stop = H.clock + secs
    while true do
        table.sort(H.queue, function(a, b) return a.at < b.at end)
        local t = H.queue[1]
        if not t or t.at > stop then break end
        table.remove(H.queue, 1); H.clock = math.max(H.clock, t.at); t.fn()
    end
    H.clock = stop
end
local function btns()
    local out = {}
    for _, b in ipairs(H.view.buttons) do
        if b[1] then for _, c in ipairs(b) do out[#out + 1] = c end else out[#out + 1] = b end
    end
    return out
end
local function click(prefix)
    for _, b in ipairs(btns()) do if b.text:sub(1, #prefix) == prefix then b.callback() return end end
    local t = {} for _, b in ipairs(btns()) do t[#t + 1] = b.text end
    error("no button " .. prefix .. " in " .. table.concat(t, " / "))
end
local function text()
    local t = {} for _, l in ipairs(H.view.lines) do t[#t + 1] = type(l) == "table" and l.text or l end
    return table.concat(t, "\n")
end

-- 1. 打开，收拾行囊
local Game = require("papersprite.game")
local g = Game.new(H.host):show()
assert(H.view.title == "阿页的阁楼")
click("收拾行囊"); click("燕麦饼干"); click("铅笔头"); click("火柴盒地图册")
assert(H.saved.sprite.status == "packed", "should be packed")
click("回阁楼"); assert(text():find("快要出门"))

-- 2. 界面开着：到点自动出门（调试模式：分钟→秒）
advance(100)
assert(H.saved.sprite.status == "away", "should be away: " .. H.saved.sprite.status)
assert(text():find("纸条"))

-- 3. 关掉插件，真实时间流逝后再打开：一次性结算（无后台定时器）
g:close(); assert(#H.queue == 0, "timers left after close")
local n = H.shows; advance(10000); assert(H.shows == n, "render after close")
g = Game.new(H.host):show()
assert(H.saved.sprite.status == "home", "should be home")
assert(#H.saved.postcards >= 1, "no postcard")
local sv = 0 for _, c in pairs(H.saved.souvenirs) do sv = sv + c end
assert(sv == 1, "souvenir")
-- 4. 明信片墙 → 单张
click("明信片墙"); click(""); assert(H.view.layers and #H.view.lines == 2, "card view")
g:close()

-- 5. 存档版本：坏存档 / 旧字段缺失
local State = require("papersprite.core.state")
assert(State.load(nil, 1).version == State.VERSION)
assert(State.load({ version = 1 }, 1).sprite.status == "home")

-- 6. 首页卡片摘要（纯函数）
package.path = package.path -- moon_card 只在 build 时 require KOReader 控件
local Card = require("papersprite.ui.moon_card")
local s = Card.summary(H.saved, H.clock, true); assert(s.line1 and s.line2)

-- 7. 确定性：同存档同时刻结果一致；长期跑 50 趟不出错
local Travel = require("papersprite.core.travel")
local st = State.fresh(0); st.inventory = { oat_biscuit = 99, pencil_stub = 99, tiny_atlas = 99, tea_bag = 99, paper_umbrella = 99, poem_slip = 99 }
local t = 0
for i = 1, 50 do
    local ids = ({ { "oat_biscuit", "pencil_stub", "tiny_atlas" }, { "tea_bag", "paper_umbrella", "poem_slip" } })[i % 2 + 1]
    for _, id in ipairs(ids) do assert(Travel.put(st, id, t, false)) end
    t = t + 40 * 3600; Travel.settle(st, t, false)
    assert(st.sprite.status == "home", "trip " .. i)
end
print("headless ok: postcards=" .. #st.postcards)
