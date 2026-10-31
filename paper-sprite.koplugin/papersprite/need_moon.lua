-- SPDX-License-Identifier: MIT
--[[--
阿页依赖月读：入口统一先过这里。没装月读就弹提示（此时没有月读主题组件，只能用 KOReader 原生 InfoMessage）并返回 false。
--]]
return function()
    if pcall(require, "ui.themes") and pcall(require, "utils.settings") then return true end
    require("ui/uimanager"):show(require("ui/widget/infomessage"):new{ text = require("papersprite.l10n")("阿页的阁楼需要先安装「月读」插件。") })
    return false
end
