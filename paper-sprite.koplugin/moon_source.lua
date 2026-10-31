-- SPDX-License-Identifier: MIT
--[[--
月读扩展描述：不是书源，只提供首页组件——「阿页」近况卡片、阁楼画面、明信片（最近列表 / 迷你墙）、纪念物柜。
组件都是只读视图，点按全屏打开阁楼对应的页面。尺寸 / 模式在首页编辑态的组件设置里选。
契约见月读 examples/moonsource-demo.koplugin/moon_source.lua（api = 1，id = ext.<name>）。
--]]

local PLUGIN_DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
if not package.path:find(PLUGIN_DIR .. "/?.lua", 1, true) then
    package.path = PLUGIN_DIR .. "/?.lua;" .. package.path
end
local _ = require("papersprite.l10n")

local ID = "ext.papersprite"

-- 首页出现后稍等再查更新，不和首屏渲染抢网络；update.autoCheck 自己保证每进程一次、24h 一次
local function scheduleUpdateCheck()
    require("ui/uimanager"):scheduleIn(5, function() pcall(require("papersprite.update").autoCheck) end)
end

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
        scheduleUpdateCheck()
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

--- 只读图片组件：出错时退回一个打开阁楼的按钮
local function fallback(w, h, text, page)
    local Button = require("ui/widget/button")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Geom = require("ui/geometry")
    return CenterContainer:new{
        dimen = Geom:new{ w = w, h = h },
        Button:new{ text = text, width = math.floor(w * 0.8), callback = function()
            pcall(function() require("papersprite.ui.moon_widgets").open(page) end)
        end },
    }
end

local DEFAULT_H = { attic = 360, postcards = 300, cabinet = 240 }

local function imageWidget(kind, title, icon, builder, page)
    return {
        id = kind,
        title = _(title),
        icon = icon,
        heightRange = function(_ctx, opts)
            local ok, h = pcall(function() return require("papersprite.ui.moon_widgets").heights[kind]((opts and opts.width) or 1000) end)
            return { height = ok and h or DEFAULT_H[kind] }
        end,
        build = function(_ctx, w, h)
            scheduleUpdateCheck()
            local ok, wdg = pcall(function() return require("papersprite.ui.moon_widgets")[builder](w, h) end)
            if ok and wdg then return wdg end
            return fallback(w, h, _(title), page)
        end,
        settings = function(desktop, _id)
            pcall(function() require("papersprite.ui.moon_widgets").settings(kind, desktop) end)
        end,
    }
end

-- 月读设置「游戏」组 → 三级页：自动 / 手动检查更新。
local function settingEntries(desktop)
    local Update = require("papersprite.update")
    local Row = require("ui.themes.widgets.row")
    local title = string.format("%s（%s）", _("阿页的阁楼"), Update.version())
    return { {
        group = "games",
        order = 30,
        id = "main",
        icon = "bookmark",
        title = title,
        page = {
            title = title,
            sections = function()
                return { { title = _("显示"), rows = {
                    function(iw)
                        local K = require("papersprite.ui.komenu")
                        local on = K.enabled()
                        return Row.widget({
                            width = iw, chevron = false, kind = "toggle", icon = "bookmark",
                            title = _("在顶部菜单显示"),
                            subtitle = _("KOReader 顶部菜单里的「阿页」页签"),
                            status = on and _("开") or _("关"), status_on = on,
                            callback = function()
                                K.setEnabled(not on)
                                desktop:updateView()
                            end,
                        })
                    end,
                } }, { title = _("更新"), rows = {
                    function(iw)
                        local on = Update.autoEnabled()
                        return Row.widget({
                            width = iw, chevron = false, kind = "toggle", icon = "update",
                            title = _("自动检查更新"),
                            subtitle = _("每天最多一次，有新版本时提示"),
                            status = on and _("开") or _("关"), status_on = on,
                            callback = function()
                                Update.setAuto(not on)
                                desktop:updateView()
                            end,
                        })
                    end,
                    function(iw)
                        return Row.widget({
                            width = iw, chevron = false, kind = "action", icon = "system_update",
                            title = _("检查更新"),
                            status = Update.version(), status_on = true,
                            callback = function() Update.manualCheck() end,
                        })
                    end,
                } } }
            end,
        },
    } }
end

return {
    api = 1,
    id = ID,
    provides = { source = false,
    -- 顶部下拉快捷面板：月读只开放「动作开关」挂点（title / icon / run），不能放自定义画面，
    -- 所以这里放一个「阿页」开关，点一下全屏打开阁楼（画面在首页「阁楼」组件里看）。
    features = { setting = { entries = settingEntries }, panel = { actions = function()
        return { {
            id = "attic", scope = "desktop", title = _("阿页"), icon = "home",
            run = function() pcall(function() require("papersprite.ui.moon_widgets").open("attic") end) end,
        } }
    end } },
    home_widgets = {
        widget,
        imageWidget("attic", "阿页的阁楼", "home", "atticBuild", "attic"),
        imageWidget("postcards", "阿页的明信片", "image", "postcardsBuild", "wall"),
        imageWidget("cabinet", "纪念物柜", "archive", "cabinetBuild", "cabinet"),
    } },
}
