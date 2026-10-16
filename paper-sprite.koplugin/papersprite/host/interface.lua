-- SPDX-License-Identifier: MIT
--[[--
宿主抽象（与 ko-adarkroom 同一套思路）。游戏只经 host 访问外部世界：
  host:showScreen(view)   view = { title, image?, lines = {string|{text,muted}}, buttons = {按钮|{按钮...}}, on_close? }；再次调用即刷新
  host:closeScreen()
  host:schedule(seconds, fn) -> 句柄 / host:unschedule(handle)   —— 只用于界面开着时的刷新，旅行结算不依赖定时器
  host:loadState() -> table|nil / host:saveState(table)
  host:getSetting(key, default) / host:setSetting(key, value)
  host:notify(text)
  host:now() -> 秒（真实时间 os.time；测试注入虚拟时钟）
  host:assetDir() -> 插件 assets 目录
--]]
local Interface = {}

Interface.METHODS = {
    "showScreen", "closeScreen", "schedule", "unschedule",
    "loadState", "saveState", "getSetting", "setSetting", "notify", "now",
}

function Interface.check(host)
    for _, m in ipairs(Interface.METHODS) do
        if type(host[m]) ~= "function" then error("papersprite host missing method: " .. m) end
    end
    return host
end

local SRC = debug.getinfo(1, "S").source:match("^@(.*)/papersprite/host/[^/]*$")
function Interface.pluginDir() return SRC or "." end

return Interface
