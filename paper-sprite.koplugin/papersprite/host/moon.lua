-- SPDX-License-Identifier: MIT
--[[--
月读宿主：存档放在月读扩展独立表 utils.settings.getSource("ext.papersprite")，
界面优先用月读主题组件（papersprite.ui.screen 的 moon 皮肤），提示用月读 Toast；
任何月读模块缺失时整体回落 KOReader 宿主。思路同 ko-adarkroom host/moon.lua。
--]]
local KOHost = require("papersprite.host.koreader")
local Interface = require("papersprite.host.interface")

local ID = "ext.papersprite"

local Host = setmetatable({}, { __index = KOHost })
Host.__index = Host
Host.ID = ID

function Host.new(opts)
    return Interface.check(setmetatable({ opts = opts or {} }, Host))
end

local function moonSettings()
    local ok, S = pcall(require, "utils.settings")
    if ok and type(S) == "table" and S.getSource and S.saveSource then return S end
end
local function conf() return moonSettings().getSource(ID) end
local function save() moonSettings().saveSource(ID) end

function Host:_screenModule()
    local Screen = require("papersprite.ui.screen")
    return { open = function(view, on_close) return Screen.open(view, on_close, "moon") end }
end

function Host:notify(text)
    local ok, Toast = pcall(require, "ui.themes.widgets.toast")
    if ok and Toast and pcall(function() Toast:new{ text = text, timeout = 2 }:show() end) then return end
    return KOHost.notify(self, text)
end

function Host:loadState()
    if not moonSettings() then return KOHost.loadState(self) end
    return conf().state
end

function Host:saveState(state)
    if not moonSettings() then return KOHost.saveState(self, state) end
    conf().state = state
    save()
end

function Host:getSetting(key, default)
    if not moonSettings() then return KOHost.getSetting(self, key, default) end
    local v = (conf().settings or {})[key]
    if v == nil then return default end
    return v
end

function Host:setSetting(key, value)
    if not moonSettings() then return KOHost.setSetting(self, key, value) end
    local c = conf()
    c.settings = c.settings or {}
    c.settings[key] = value
    save()
end

return Host
