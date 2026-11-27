-- SPDX-License-Identifier: MIT
--[[--
阿页的阁楼 · KOReader 插件入口。
  · 主菜单「工具」里打开阁楼；
  · 阅读时翻页累计到「阅读账本」（papersprite.core.reading），打开阁楼时折算成灵感。
宿主差异由 papersprite.host.* 适配；游戏逻辑在 papersprite/core 与 papersprite/game.lua。
--]]
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local PLUGIN_DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
if not package.path:find(PLUGIN_DIR .. "/?.lua", 1, true) then
    package.path = PLUGIN_DIR .. "/?.lua;" .. package.path
end
local _ = require("papersprite.l10n")
local Guard = require("papersprite.guard")

local PaperSprite = WidgetContainer:extend{
    name = "papersprite",
    is_doc_only = false,
}

function PaperSprite:init()
    self.ui.menu:registerToMainMenu(self)
    -- KOReader 原生顶部菜单里的「阿页」Tab（照月读快捷面板的注入方式，见 ui/komenu.lua）
    Guard.call("papersprite menu", function()
        local K = require("papersprite.ui.komenu")
        K.install()
        K.inject(self.ui.menu)
    end)
    self:onDispatcherRegisterActions()
    if self.ui and self.ui.document then
        Guard.call("papersprite install", function() require("papersprite.ui.reader_overlay").install(self) end)
    end
end

-- KOReader 手势动作「阿页的阁楼」：可在「手势」设置里绑到任意手势
function PaperSprite:onDispatcherRegisterActions()
    pcall(function()
        require("dispatcher"):registerAction("papersprite_panel",
            { category = "none", event = "PaperSpritePanel", title = _("阿页的阁楼"), general = true })
    end)
end

function PaperSprite:onPaperSpritePanel()
    Guard.call("papersprite panel", self.launch, self)
    return true
end

function PaperSprite:addToMainMenu(menu_items)
    menu_items.papersprite = {
        text = _("阿页的阁楼"),
        sorting_hint = "tools",
        callback = function() Guard.call("papersprite launch", self.launch, self) end,
    }
end

-- 离开这一页时才结算：停满 MIN_DWELL 秒，且只认相邻翻页。不读正文。
-- 改字号 / 旋转 / 重排（页码没变）和进度条跳转（一次跨好几页）都不算。
local function pageUpdate(self, pageno)
    if not self.ui or not self.ui.document then return end
    require("papersprite.ui.reader_overlay").onPage(self)
    local now = os.time()
    local last, since = self._last_page, self._last_at
    if type(pageno) ~= "number" then
        self._last_page, self._last_at = nil, nil
        return
    end
    local Reading = require("papersprite.core.reading")
    if last and since and Reading.qualify(math.abs(pageno - last), now - since) then
        Reading.record(now, self:_bookInfo(pageno), math.abs(pageno - last), now - since)
    end
    self._last_page, self._last_at = pageno, now
end

function PaperSprite:onPageUpdate(pageno)
    return Guard.call("papersprite onPageUpdate", pageUpdate, self, pageno)
end

-- 休眠不打扰；解锁后再由阅读页 overlay 延迟一会儿才弹。
-- 阁楼若开着：休眠停计时且不重绘；唤醒后按当前时钟补算，不把定时刷新当成用户活动。
function PaperSprite:onSuspend()
    Guard.call("papersprite onSuspend", function()
        require("papersprite.ui.reader_overlay").onSuspend()
        local Game = require("papersprite.game")
        if Game.current then Game.current:onSuspend() end
    end)
end

function PaperSprite:onResume()
    Guard.call("papersprite onResume", function()
        require("papersprite.ui.reader_overlay").onResume()
        local Game = require("papersprite.game")
        if Game.current then Game.current:onResume() end
    end)
end

--- 这本书里用户自己划的第一句。没有划线就是 nil。
function PaperSprite:_quote()
    local items = self.ui.annotation and self.ui.annotation.annotations
    if type(items) ~= "table" then return end
    for _idx, item in ipairs(items) do
        if type(item) == "table" and type(item.drawer) == "string" and item.drawer ~= ""
            and type(item.text) == "string" and item.text:find("%S") then
            return item.text
        end
    end
end

-- 当前书的书名 / 关键词。月读认领的书用全书已读/进度，避免分章文档按页误判；
-- 其余（原生 KOReader 整书）仍是总页数 ≥ 20 且读到 99%。读完时带上划线。
function PaperSprite:_bookInfo(pageno)
    local props = self.ui.doc_props or {}
    local total = self.ui.document:getPageCount()
    local file = self.ui.document.file
    local moon
    if type(file) == "string" and file ~= "" then
        local ok, info = pcall(function()
            return require("papersprite.core.moon_books").forFile(file)
        end)
        if ok then moon = info end
    end
    -- 已认领（含身份查询失败）绝不回退到当前文档页数，以免分章中间页被当成整本读完并发奖。
    local claimed = moon and (moon.claimed == true or moon.id)
    local finished
    if claimed then
        finished = moon.finished == true
    else
        finished = type(total) == "number" and total >= 20 and pageno >= total * 0.99
    end
    local id, cover, aliases
    if type(file) == "string" and file ~= "" then
        local file_hash = require("ffi/sha2").md5(file)
        id = (moon and moon.id) or (not claimed and file_hash) or nil
        aliases = moon and moon.aliases
        if id and file_hash and file_hash ~= id then
            aliases = { file_hash }
            for _idx, a in ipairs((moon and moon.aliases) or {}) do
                if a ~= file_hash then aliases[#aliases + 1] = a end
            end
        end
        if finished then
            if self._cover_file ~= file then
                self._cover_file, self._cover_path = file, nil
                local path = require("papersprite.core.storage").dir() .. "/covers/" .. id .. ".png"
                local f = io.open(path, "rb")
                if f then
                    f:close()
                    self._cover_path = path
                else
                    local ok, err = pcall(function()
                        local Storage = require("papersprite.core.storage")
                        Storage.deps.mkdirp(Storage.dir() .. "/covers")
                        local image = self.ui.bookinfo:getCoverImage(self.ui.document)
                        if image then
                            local wrote_ok, wrote, write_err = pcall(image.writeToFile, image, path, "png")
                            image:free()
                            if not wrote_ok then error(wrote) end
                            if not wrote then error(write_err or "cover write failed") end
                            self._cover_path = path
                        end
                    end)
                    if not ok then logger.err("papersprite cover save:", err) end
                end
            end
            cover = self._cover_path
        end
    end
    return { title = props.display_title or props.title, keywords = (props.keywords or "") .. " " .. (props.description or ""),
        id = id, cover = cover, aliases = aliases, finished = finished, quote = finished and self:_quote() or nil }
end

-- 阿页依赖月读：没装月读时只弹提示，不开游戏
function PaperSprite:launch()
    if not require("papersprite.need_moon")() then return end
    require("papersprite.game").new(require("papersprite.host.moon").new()):show()
end

return PaperSprite
