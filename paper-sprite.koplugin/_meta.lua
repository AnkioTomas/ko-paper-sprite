-- SPDX-License-Identifier: MIT
local PLUGIN_DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
if not package.path:find(PLUGIN_DIR .. "/?.lua", 1, true) then
    package.path = PLUGIN_DIR .. "/?.lua;" .. package.path
end
local _ = require("papersprite.l10n")
return {
    name = "papersprite",
    fullname = _("阿页的阁楼"),
    description = _("住在书页里的小纸灵「阿页」。替它收拾行囊，它会自己出门旅行，寄回明信片。完全离线；也可作为月读扩展，在首页显示阿页的近况。"),
}
