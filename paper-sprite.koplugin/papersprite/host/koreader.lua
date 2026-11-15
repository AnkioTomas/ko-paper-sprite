-- SPDX-License-Identifier: MIT
--[[--
KOReader 宿主：UIManager 显示 / 定时，存档（<数据目录>/.moon/game/paper-sprite/paper-sprite.sqlite3，见 core/storage）。
结构沿用 ko-adarkroom 的 host/koreader.lua。
--]]
local Interface = require("papersprite.host.interface")

local Host = {}
Host.__index = Host

function Host.new(opts)
    return Interface.check(setmetatable({ opts = opts or {} }, Host))
end

function Host:_store()
    if not self.store then
        if self.opts.state_path then
            self.store = require("luasettings"):open(self.opts.state_path)
        else
            self.store = require("papersprite.core.storage").open("save")
        end
    end
    return self.store
end

function Host:_screenModule()
    local Screen = require("papersprite.ui.screen")
    return { open = function(view, on_close) return Screen.open(view, on_close) end }
end

function Host:showScreen(view)
    local Timing = require("papersprite.ui.timing")
    local t0 = Timing.now()
    local UIManager = require("ui/uimanager")
    local old = self.widget
    self.widget = self:_screenModule().open(view, function()
        self.widget = nil
        if view.on_close then view.on_close() end
    end)
    local built = Timing.now() - t0
    -- 先盖上新界面再关旧的，避免先露出下层。新界面已经 setDirty("ui")；
    -- close 再传 "ui" 会再排一次整屏刷新，墨水屏上往往比颜色转换更慢。
    -- 进页：图片区域稍后合并成一次 full，清残影；不要每个缩略图各自闪。
    pcall(function() require("papersprite.ui.eink_image").enterPage() end)
    UIManager:show(self.widget, "ui")
    if old then
        old._replaced = true
        UIManager:close(old)
    end
    Timing.record("showScreen", Timing.now() - t0, string.format("build=%.1fms", built))
end

function Host:closeScreen()
    if self.widget then
        pcall(function()
            local E = require("papersprite.ui.eink_image")
            E.leavePage()
            E.scheduleLast("close")
        end)
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

--- 取今天的节日数据（core/festival.parse 的结果）。没联网 / 超时 / 解析失败都回调 nil；一天只会调一次。
function Host:almanac(cb)
    local daily
    local Timing = require("papersprite.ui.timing")
    local t0 = Timing.now()
    pcall(function()
        local NetworkMgr = require("ui/network/manager")
        if NetworkMgr.isConnected and not NetworkMgr:isConnected() then return end
        -- 注意：这里的 http.request 是同步的，会占住 UI 线程；调用方应在界面上屏后再调度。
        local http, ltn12 = require("socket.http"), require("ltn12")
        local socket, socketutil = require("socket"), require("socketutil")
        local body = {}
        socketutil:set_timeout(4, 8)
        local code = socket.skip(1, http.request{ url = require("papersprite.core.festival").URL, sink = ltn12.sink.table(body) })
        socketutil:reset_timeout()
        if code ~= 200 then return end
        local ok, payload = pcall(require("json").decode, table.concat(body))
        if ok then daily = require("papersprite.core.festival").parse(payload) end
    end)
    Timing.record("almanac_http", Timing.now() - t0, daily and "ok" or "empty")
    cb(daily)
end

function Host:assetDir() return Interface.pluginDir() .. "/assets" end

return Host
