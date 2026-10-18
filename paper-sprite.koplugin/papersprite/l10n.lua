--[[--
多语言：源字符串是简体中文，按 KOReader 当前语言（设置 → 语言）加载 l10n/<lang>.lua。
  T("得分 %d", n)  先翻译再 string.format；没有译文就用原文。
zh_CN / zh 不加载目录；zh_TW / zh_HK 用 zh_TW；其它语言先找同名，再找基础语言，最后回落 en。
语言切换后 KOReader 会要求重启，所以只在第一次使用时加载一次。
--]]
local M = {}

local catalog

local function currentLang()
    local ok, GetText = pcall(require, "gettext")
    local lang = ok and type(GetText) == "table" and GetText.current_lang or "zh_CN"
    return (tostring(lang):gsub("%.[Uu][Tt][Ff]%-?8$", ""))
end

--- 按语言码给出待尝试的目录名
function M.candidates(lang)
    if lang == "" or lang == "C" or lang:match("^en") then return { "en" } end
    if lang:match("^zh_TW") or lang:match("^zh_HK") then return { "zh_TW" } end
    if lang:match("^zh") then return {} end
    local out = { lang }
    local base = lang:match("^([^_]+)")
    if base and base ~= lang then out[#out + 1] = base end
    out[#out + 1] = "en"
    return out
end

function M.load(lang)
    catalog = {}
    for _, name in ipairs(M.candidates(lang or currentLang())) do
        local ok, t = pcall(require, "papersprite.l10n." .. name)
        if ok and type(t) == "table" then catalog = t break end
    end
    return catalog
end

function M.translate(msg, ...)
    if not catalog then M.load() end
    local s = catalog[msg] or msg
    if select("#", ...) > 0 then return s:format(...) end
    return s
end

return setmetatable(M, { __call = function(_, ...) return M.translate(...) end })
