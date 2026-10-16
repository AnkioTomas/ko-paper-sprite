-- SPDX-License-Identifier: MIT
--[[--
把紧凑阁楼卡插进月读顶部下拉快捷面板（桌面模式）。月读本体只读，这里在运行时包一层：
  features.panel.widget.body 的 Body.updateView 原样执行后，若是桌面面板（无 header）、非编辑态且设置开着，
  在其纵向布局 self[1]（VerticalGroup）最前面插入卡片 + 间距，再按新高度重算 self.dimen。
  月读自己就是这样往同一个 VerticalGroup 里放阅读面板的书名头（header）的。
防护：结构不符（模块缺失 / updateView 不是函数 / self[1] 不是带 getSize 的组）一律不动；所有自绘 pcall；
只 patch 一次（Body._papersprite_attic 标记）；可用 unpatch() 还原。
点卡片：走 body.on_action("ext.papersprite.attic") —— 月读的 Registry.execute 会先关面板再跑动作；
动作不存在时退回直接打开阁楼。
--]]
local M = {}
local ACTION_ID = "ext.papersprite.attic"

local function inject(body)
    if body.header or body.editing then return end
    local W = require("papersprite.ui.moon_widgets")
    if not W.panelEnabled() then return end
    local group = body[1]
    if type(group) ~= "table" or type(group.getSize) ~= "function" then return end
    local cardw = body.width
    if type(cardw) ~= "number" or cardw < 100 then return end
    local card = W.panelCard(cardw, function()
        local ok, done = pcall(function() return body.on_action and body.on_action(ACTION_ID) end)
        -- on_action 返回值不保证；动作未注册时 executeAction 返回 false
        if not ok then pcall(W.open, "attic") end
        if ok and done == false then pcall(W.open, "attic") end
    end)
    local Theme = require("ui.themes")
    local VerticalSpan = require("ui/widget/verticalspan")
    table.insert(group, 1, VerticalSpan:new{ width = Theme.px(10) })
    table.insert(group, 1, card)
    if group.resetLayout then group:resetLayout() end
    local Geom = require("ui/geometry")
    body.dimen = Geom:new{ w = body.width, h = group:getSize().h }
end

function M.install()
    local ok, Body = pcall(require, "features.panel.widget.body")
    if not ok or type(Body) ~= "table" or type(Body.updateView) ~= "function" then return false end
    if Body._papersprite_attic then return true end
    local original = Body.updateView
    Body._papersprite_attic = original
    Body.updateView = function(self, ...)
        local r = original(self, ...)
        local ok2, err = pcall(inject, self)
        if not ok2 then pcall(function() require("logger").warn("papersprite panel inject:", err) end) end
        return r
    end
    return true
end

function M.uninstall()
    local ok, Body = pcall(require, "features.panel.widget.body")
    if ok and type(Body) == "table" and Body._papersprite_attic then
        Body.updateView, Body._papersprite_attic = Body._papersprite_attic, nil
    end
end

return M
