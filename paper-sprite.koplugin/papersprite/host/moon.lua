-- SPDX-License-Identifier: MIT
--[[--
月读宿主：存档与 KOReader 宿主共用 <数据目录>/.moon/game/paper-sprite/save.lua（旧的 ext.papersprite.state 首次迁移过去，见 core/storage）；
设置仍放在月读扩展独立表 utils.settings.getSource("ext.papersprite").settings，
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
    return { open = function(view, on_close) return Screen.open(view, on_close, self:getSetting("ui_skin", "auto")) end }
end

function Host:notify(text)
    local ok, Toast = pcall(require, "ui.themes.widgets.toast")
    if ok and Toast and pcall(function() Toast:new{ text = text, timeout = 2 }:show() end) then return end
    return KOHost.notify(self, text)
end

--- 可选 AI：月读已配置 AI（端点 / 密钥 / 模型齐全）时返回适配器，否则 nil。
--- 只用月读现有的 AI 设置与客户端（require("ai")），不引入新的密钥或配置。
function Host:ai()
    if self.opts.no_ai or self:getSetting("ai_story", true) == false then return nil end
    local ok, AI = pcall(require, "ai")
    if not ok or type(AI) ~= "table" or not AI.jsonExtract or not AI.isConfigured then return nil end
    local ok2, configured = pcall(AI.isConfigured)
    if not ok2 or not configured then return nil end
    return {
        json = function(messages, cb)
            return AI.jsonExtract(messages, { temperature = 0.8 }, cb)
        end,
    }
end

-- 存档统一走 KOReader 宿主的文件存档（loadState / saveState 继承自 KOHost）

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
