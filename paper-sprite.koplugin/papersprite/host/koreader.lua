-- SPDX-License-Identifier: MIT
--[[--
KOReader 宿主：UIManager 显示 / 定时，LuaSettings 存档（settings/papersprite.lua）。
结构沿用 ko-adarkroom 的 host/koreader.lua。
--]]
local Interface = require("papersprite.host.interface")

local Host = {}
Host.__index = Host

local STATE_FILE = "papersprite.lua"

function Host.new(opts)
    return Interface.check(setmetatable({ opts = opts or {} }, Host))
end

function Host:_store()
    if not self.store then
        local DataStorage = require("datastorage")
        local LuaSettings = require("luasettings")
        self.store = LuaSettings:open(self.opts.state_path or (DataStorage:getSettingsDir() .. "/" .. STATE_FILE))
    end
    return self.store
end

function Host:_screenModule()
    local Screen = require("papersprite.ui.screen")
    local skin = self:getSetting("ui_skin", "auto") -- auto：装了月读就用月读主题组件；native：强制原生
    return { open = function(view, on_close) return Screen.open(view, on_close, skin) end }
end

function Host:showScreen(view)
    local UIManager = require("ui/uimanager")
    local old = self.widget
    self.widget = self:_screenModule().open(view, function()
        self.widget = nil
        if view.on_close then view.on_close() end
    end)
    -- 先盖上新界面再关旧的，整屏刷新（不留下层残影，见 ko-adarkroom e38498d）
    UIManager:show(self.widget, "ui")
    if old then UIManager:close(old, "ui") end
end

function Host:closeScreen()
    if self.widget then
        require("ui/uimanager"):close(self.widget, "ui")
        self.widget = nil
    end
end

function Host:now() return os.time() end

function Host:schedule(seconds, fn)
    require("ui/uimanager"):scheduleIn(seconds, fn)
    return fn
end

function Host:unschedule(handle) require("ui/uimanager"):unschedule(handle) end

function Host:loadState() return self:_store():readSetting("state") end

function Host:saveState(state)
    local s = self:_store()
    s:saveSetting("state", state)
    s:flush()
end

function Host:getSetting(key, default)
    local v = self:_store():readSetting("setting_" .. key)
    if v == nil then return default end
    return v
end

function Host:setSetting(key, value)
    local s = self:_store()
    s:saveSetting("setting_" .. key, value)
    s:flush()
end

function Host:notify(text)
    local InfoMessage = require("ui/widget/infomessage")
    require("ui/uimanager"):show(InfoMessage:new{ text = text, timeout = 2 })
end

function Host:assetDir() return Interface.pluginDir() .. "/assets" end

return Host
