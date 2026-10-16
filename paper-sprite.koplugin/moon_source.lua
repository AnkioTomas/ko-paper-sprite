-- SPDX-License-Identifier: MIT
--[[--
月读扩展描述：不是书源，只在月读首页加一张「阿页」卡片（近况摘要），点按全屏打开阁楼。
契约见月读 examples/moonsource-demo.koplugin/moon_source.lua（api = 1，id = ext.<name>）。
--]]
local _ = require("gettext")

local PLUGIN_DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
if not package.path:find(PLUGIN_DIR .. "/?.lua", 1, true) then
    package.path = PLUGIN_DIR .. "/?.lua;" .. package.path
end

local ID = "ext.papersprite"

local function host() return require("papersprite.host.moon").new() end
local function openGame() require("papersprite.game").new(host()):show() end
local function loadSave() return host():loadState() end

local widget = {
    id = "home", -- 月读补成 ext.papersprite.home
    title = _("阿页"),
    icon = "bookmark",
    heightRange = function()
        local ok, Card = pcall(require, "papersprite.ui.moon_card")
        return { height = ok and Card.height() or 110 }
    end,
    build = function(_ctx, w, h)
        local ok, card = pcall(function() return require("papersprite.ui.moon_card").build(w, h, loadSave, openGame) end)
        if ok and card then return card end
        local Button = require("ui/widget/button")
        local CenterContainer = require("ui/widget/container/centercontainer")
        local Geom = require("ui/geometry")
        return CenterContainer:new{
            dimen = Geom:new{ w = w, h = h },
            Button:new{ text = _("阿页的阁楼"), width = math.floor(w * 0.8), callback = openGame },
        }
    end,
}

return {
    api = 1,
    id = ID,
    provides = { source = false, home_widgets = { widget } },
}
