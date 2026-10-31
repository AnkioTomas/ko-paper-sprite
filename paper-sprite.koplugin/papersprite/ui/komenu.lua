-- SPDX-License-Identifier: MIT
--[[--
把「阿页的阁楼」做成 KOReader 原生顶部菜单（TouchMenu）里的一个 Tab，文件管理器和阅读中都有。
做法照抄月读快捷面板（book.koplugin/features/panel/native.lua）：
  · 一次性 patch FileManagerMenu / ReaderMenu 的 setUpdateItemTable 和 onShowMenu，往 tab_item_table 插一个带标记的 Tab
    （{ icon, remember = false, _papersprite_attic = true }）；已有就不重复插。
  · 一次性 patch TouchMenu.updateItems：触屏设备上切到带标记的 Tab 时，不画原生条目，改画自绘内容
    （Tab 栏 + 阁楼卡 + 一行快捷按钮 + 原生 footer），按新高度设 dimen 并 setDirty；其它 Tab 原样走原函数。
  · 非触屏设备：Tab 里填原生菜单条目（打开阁楼 / 收拾行囊 / 小铺 / 明信片墙 / 特产柜）。
插入位置：月读的面板 Tab 之后（有的话），否则第一个。点卡片 / 按钮：关菜单，下一帧全屏打开阁楼对应页。
所有自绘都 pcall；结构不符就退回原函数。
--]]
local T = require("papersprite.l10n")

local M = {}
local MARKER = "_papersprite_attic"
local ICON_FALLBACK = "bookmark"

--- Tab 图标：插件自带的 assets/icons/papersprite.tab.svg（折角书签 + 圆点眼睛）。
--- TouchMenu 只收图标名，IconWidget 按「图标目录/名字.svg」找；用足够多的 ../ 退到根再接插件绝对路径，
--- 任何一个图标目录都能解析到它。找不到文件就用 KOReader 自带的 bookmark。
local function tabIcon()
    local ok, icon = pcall(function()
        local lfs = require("libs/libkoreader-lfs")
        local dir = debug.getinfo(1, "S").source:match("^@(.*)/papersprite/ui/[^/]*$")
        if not dir then return nil end
        if dir:sub(1, 1) ~= "/" then dir = lfs.currentdir() .. "/" .. dir end
        local base = dir .. "/assets/icons/papersprite.tab"
        if lfs.attributes(base .. ".svg", "mode") ~= "file" then return nil end
        return ("../"):rep(32) .. base:sub(2)
    end)
    return ok and icon or ICON_FALLBACK
end
local PAGES = { { "attic", T("打开阁楼") }, { "basket", T("收拾行囊") }, { "shop", T("小铺") }, { "wall", T("明信片墙") }, { "cabinet", T("特产柜") } }

function M.open(page)
    if not require("papersprite.need_moon")() then return end
    local g = require("papersprite.game").new(require("papersprite.host.moon").new()):show()
    if page and page ~= "attic" then g:go(page) end
end

local function closeMenu(menu)
    pcall(function() menu:closeMenu() end)
end

local function populate(tab)
    if require("device"):isTouchDevice() then return end
    for i = #tab, 1, -1 do table.remove(tab, i) end
    for _, p in ipairs(PAGES) do
        local page = p[1]
        tab[#tab + 1] = { text = p[2], callback = function() M.open(page) end }
    end
end

local function newTab()
    local tab = { icon = tabIcon(), remember = false, [MARKER] = true }
    tab.callback = function() populate(tab) end
    populate(tab)
    return tab
end

--- 设置「在顶部菜单显示」，默认开
function M.enabled()
    return require("papersprite.host.moon").new():getSetting("komenu", true) ~= false
end

function M.setEnabled(on)
    require("papersprite.host.moon").new():setSetting("komenu", on)
end

function M.inject(menu)
    local tabs = menu and menu.tab_item_table
    if type(tabs) ~= "table" then return end
    if not M.enabled() then
        for i = #tabs, 1, -1 do if tabs[i][MARKER] then table.remove(tabs, i) end end
        return
    end
    for _, t in ipairs(tabs) do if t[MARKER] then return end end
    local at = 1
    for i, t in ipairs(tabs) do if t._book_quick_panel or t._book_reader_panel then at = i + 1 end end
    table.insert(tabs, at, newTab())
end

--- 自绘内容：阁楼卡 + 快捷按钮
local function build(menu)
    local W = require("papersprite.ui.moon_widgets")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local UIManager = require("ui/uimanager")
    local okT, Theme = pcall(require, "ui.themes")
    local px = function(n) return okT and Theme.px(n) or n end
    local pad = px(12)
    local width = menu.item_width or menu.width
    local cw = width - pad * 2
    local function go(page)
        closeMenu(menu)
        UIManager:nextTick(function() pcall(M.open, page) end)
    end
    local card = W.panelContent(cw, function() go("attic") end)
    local gap = px(6)
    local n = #PAGES - 1
    local bw = math.floor((cw - gap * (n - 1)) / n)
    local row = HorizontalGroup:new{}
    for i = 2, #PAGES do
        local page = PAGES[i][1]
        if i > 2 then table.insert(row, HorizontalSpan:new{ width = gap }) end
        local b
        if okT then
            local ok, x = pcall(function() return require("ui.themes.widgets.button"):new{ text = PAGES[i][2], width = bw, callback = function() go(page) end } end)
            if ok then b = x end
        end
        b = b or require("ui/widget/button"):new{ text = PAGES[i][2], width = bw, callback = function() go(page) end }
        table.insert(row, b)
    end
    return FrameContainer:new{ bordersize = 0, padding = pad, padding_top = px(4),
        VerticalGroup:new{ align = "left", card, VerticalSpan:new{ width = px(8) }, row } }
end

--- 照月读 renderPanelContent：清空条目组，放 Tab 栏 + 自绘内容 + footer，重算尺寸并刷新
--- 同月读 syncBarSeparator：临时把 switchMenuTab 置空再调当前 Tab 图标的回调，让 Tab 栏的选中框落到本 Tab
local function syncBar(menu)
    local k = menu.cur_tab
    local ib = menu.bar and menu.bar.icon_widgets and k and menu.bar.icon_widgets[k]
    if not ib or not ib.callback then return end
    local sw = menu.switchMenuTab
    menu.switchMenuTab = function() end
    pcall(ib.callback)
    menu.switchMenuTab = sw
end

local function render(menu)
    local UIManager = require("ui/uimanager")
    syncBar(menu)
    local VerticalSpan = require("ui/widget/verticalspan")
    menu.page, menu.page_num = 1, 1
    menu.item_group:clear()
    menu.layout = {}
    table.insert(menu.item_group, menu.bar)
    table.insert(menu.layout, menu.bar.icon_widgets)
    table.insert(menu.item_group, VerticalSpan:new{ width = 8 })
    table.insert(menu.item_group, build(menu))
    table.insert(menu.item_group, menu.footer_top_margin)
    table.insert(menu.item_group, menu.footer)
    menu.page_info_text:setText("")
    menu.page_info_left_chev:showHide(false)
    menu.page_info_right_chev:showHide(false)
    local old = menu.dimen:copy()
    menu.dimen.w = menu.width
    menu.dimen.h = menu.item_group:getSize().h + menu.bordersize * 2 + menu.padding
    UIManager:setDirty((menu.is_fresh or menu.dimen.h >= old.h) and menu.show_parent or "all", function()
        local refresh = menu.is_fresh and "flashui" or "ui"
        menu.is_fresh = false
        return refresh, old:combine(menu.dimen)
    end)
end

local function patchTouchMenu()
    local TouchMenu = require("ui/widget/touchmenu")
    if TouchMenu._papersprite_patched then return end
    TouchMenu._papersprite_patched = true
    local original = TouchMenu.updateItems
    TouchMenu.updateItems = function(self, ...)
        if self.item_table and self.item_table[MARKER] and require("device"):isTouchDevice() then
            local ok, err = pcall(render, self)
            if ok then return end
            pcall(function() require("logger").warn("papersprite komenu:", err) end)
        end
        return original(self, ...)
    end
end

local function patchMenu(path)
    local ok, Menu = pcall(require, path)
    if not ok or type(Menu) ~= "table" or Menu._papersprite_patched then return end
    Menu._papersprite_patched = true
    if type(Menu.setUpdateItemTable) == "function" then
        local o = Menu.setUpdateItemTable
        Menu.setUpdateItemTable = function(self, ...)
            local r = o(self, ...)
            pcall(M.inject, self)
            return r
        end
    end
    if type(Menu.onShowMenu) == "function" then
        local o = Menu.onShowMenu
        Menu.onShowMenu = function(self, ...)
            pcall(M.inject, self)
            return o(self, ...)
        end
    end
end

function M.install()
    pcall(patchTouchMenu)
    pcall(patchMenu, "apps/filemanager/filemanagermenu")
    pcall(patchMenu, "apps/reader/modules/readermenu")
end

M.MARKER = MARKER
return M
