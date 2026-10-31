-- SPDX-License-Identifier: MIT
--[[--
阿页的阁楼 · KOReader 插件入口。
  · 主菜单「工具」里打开阁楼；
  · 阅读时翻页累计到「阅读账本」（papersprite.core.reading），打开阁楼时折算成灵感。
宿主差异由 papersprite.host.* 适配；游戏逻辑在 papersprite/core 与 papersprite/game.lua。
--]]
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local PLUGIN_DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
if not package.path:find(PLUGIN_DIR .. "/?.lua", 1, true) then
    package.path = PLUGIN_DIR .. "/?.lua;" .. package.path
end
local _ = require("papersprite.l10n")

local PaperSprite = WidgetContainer:extend{
    name = "papersprite",
    is_doc_only = false,
}

function PaperSprite:init()
    self.ui.menu:registerToMainMenu(self)
    -- KOReader 原生顶部菜单里的「阿页」Tab（照月读快捷面板的注入方式，见 ui/komenu.lua）
    pcall(function()
        local K = require("papersprite.ui.komenu")
        K.install()
        K.inject(self.ui.menu)
    end)
    self:onDispatcherRegisterActions()
end

-- KOReader 手势动作「阿页的阁楼」：可在「手势」设置里绑到任意手势
function PaperSprite:onDispatcherRegisterActions()
    pcall(function()
        require("dispatcher"):registerAction("papersprite_panel",
            { category = "none", event = "PaperSpritePanel", title = _("阿页的阁楼"), general = true })
    end)
end

function PaperSprite:onPaperSpritePanel()
    self:launch()
    return true
end

function PaperSprite:addToMainMenu(menu_items)
    menu_items.papersprite = {
        text = _("阿页的阁楼"),
        sorting_hint = "tools",
        callback = function() self:launch() end,
    }
end

-- 阅读中每次翻页记一笔（只记次数和时间，不读书的内容）。
-- 只认相邻翻页：改字号 / 旋转 / 重排（页码没变）和进度条跳转（一次跨好几页）都不算。
function PaperSprite:onPageUpdate(pageno)
    if not self.ui or not self.ui.document then return end
    local last = self._last_page
    self._last_page = type(pageno) == "number" and pageno or nil
    if not last or not self._last_page then return end
    local step = math.abs(self._last_page - last)
    if step == 0 or step > 3 then return end
    pcall(function() require("papersprite.core.reading").record(os.time(), self:_bookInfo(pageno)) end)
end

-- 当前书的书名 / 关键词，翻到最后几页算读完（不读正文）
function PaperSprite:_bookInfo(pageno)
    local props = self.ui.doc_props or {}
    local total = self.ui.document:getPageCount()
    return { title = props.display_title or props.title, keywords = (props.keywords or "") .. " " .. (props.description or ""),
        finished = type(total) == "number" and total >= 20 and pageno >= total - 1 }
end

-- 阿页依赖月读：没装月读时只弹提示，不开游戏
function PaperSprite:launch()
    if not require("papersprite.need_moon")() then return end
    require("papersprite.game").new(require("papersprite.host.moon").new()):show()
end

return PaperSprite
