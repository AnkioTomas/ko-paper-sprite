-- SPDX-License-Identifier: MIT
--[[--
阿页的阁楼 · KOReader 插件入口。
  · 主菜单「工具」里打开阁楼；
  · 阅读时翻页累计到「阅读账本」（papersprite.core.reading），打开阁楼时折算成灵感。
宿主差异由 papersprite.host.* 适配；游戏逻辑在 papersprite/core 与 papersprite/game.lua。
--]]
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local PLUGIN_DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
if not package.path:find(PLUGIN_DIR .. "/?.lua", 1, true) then
    package.path = PLUGIN_DIR .. "/?.lua;" .. package.path
end

local PaperSprite = WidgetContainer:extend{
    name = "papersprite",
    is_doc_only = false,
}

function PaperSprite:init()
    self.ui.menu:registerToMainMenu(self)
end

function PaperSprite:addToMainMenu(menu_items)
    menu_items.papersprite = {
        text = _("阿页的阁楼"),
        sorting_hint = "tools",
        callback = function() self:launch() end,
    }
end

-- 阅读中每次翻页记一笔（只记次数和时间，不读书的内容）
function PaperSprite:onPageUpdate()
    if not self.ui or not self.ui.document then return end
    pcall(function() require("papersprite.core.reading").record(os.time()) end)
end

function PaperSprite:launch()
    local host = require("papersprite.host.koreader").new()
    require("papersprite.game").new(host):show()
end

return PaperSprite
