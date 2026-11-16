-- SPDX-License-Identifier: MIT
--[[--
阅读页上的两件东西：
  · 伴读：view module，四个角选一处。在家坐在椅子上看书，翻页时只让手里那页抬一下再放下，出门只留空椅子。
    不占页边。透明度可调，默认 20% 透明，正文从他身上透出来。
  · 打扰：月读主题弹窗，配角色插画；明信片保留正反翻面。
    休眠 / 锁屏时不弹；解锁后再等一会儿（WAKE_GRACE）。
结算只在翻页和定时器里做，不在 paintTo 里做。阁楼开着时不另起一份结算。
--]]
local T = require("papersprite.l10n")
local Prefs = require("papersprite.ui.read_prefs")

local M = { flags = {} }
local popup
local timer_on
local sprites = {}

local function pluginDir()
    return require("papersprite.host.interface").pluginDir()
end

local function sprite(name, h)
    local key = name .. ":" .. h
    if sprites[key] == nil then
        local ok, w = pcall(function()
            return require("ui/widget/imagewidget"):new{
                file = pluginDir() .. "/assets/sprite/" .. name .. ".png",
                height = h, width = h, scale_factor = 0, alpha = true,
            }
        end)
        sprites[key] = ok and w or false
    end
    return sprites[key] or nil
end

local TURN_START = 0.12
local TURN_S = 0.9
local TURN_MID = TURN_S / 2
local TURN_PUT = TURN_S - TURN_START -- 放下那一帧：约 0.78s，回到看书姿势
-- 解锁后再等一会儿才打扰。5 秒对齐月读 utils.wake.GRACE：刚揭开锁屏或输完密码时不要立刻弹窗。
local WAKE_GRACE = 5
local faded = {}
local faded_order = {}
local FADE_CACHE_MAX = 8

local function now()
    local time = require("ui/time")
    return time.to_s(time.now())
end

function M.seat(view, corner, size)
    local dim = view and view.dimen
    local vw = dim and dim.w or 0
    local vh = dim and dim.h or 0
    if vw < 40 or vh < 40 then
        local Screen = require("device").screen
        vw, vh = Screen:getWidth(), Screen:getHeight()
    end
    local sh = math.floor(math.min(vw, vh) * Prefs.SIZE_SCALE[size or Prefs.size()])
    local edge = math.floor(math.min(vw, vh) * 0.035)
    local top = math.max(edge, math.floor(vh * 0.055))
    local sx = (corner == "se" or corner == "ne") and (vw - sh - edge) or edge
    local sy = (corner == "nw" or corner == "ne") and top or (vh - sh - edge)
    return sx, sy, sh, vw, vh
end

local function evictFade(key)
    local ent = faded[key]
    faded[key] = nil
    if type(ent) == "table" and ent.bb and ent.bb.free then pcall(ent.bb.free, ent.bb) end
end

local function rememberFade(key, value)
    if faded[key] == nil then
        faded_order[#faded_order + 1] = key
        while #faded_order > FADE_CACHE_MAX do
            evictFade(table.remove(faded_order, 1))
        end
    end
    faded[key] = value
end

local function fadedBB(name, h)
    local opacity = math.floor((100 - Prefs.fade()) * 255 / 100)
    if opacity <= 0 then return nil end
    local Display = require("papersprite.ui.display")
    local key = name .. ":" .. h .. ":" .. opacity .. ":" .. Display.mode()
    if faded[key] ~= nil then return faded[key] or nil end
    local img = sprite(name, h)
    if not img then rememberFade(key, false) return nil end
    local size = img:getSize()
    local src = img._bb
    if not src or size.w < 1 or size.h < 1 then rememberFade(key, false) return nil end
    local BB = require("ffi/blitbuffer")
    local ffi = require("ffi")
    local color = Display.isColor()
    local bb = BB.new(size.w, size.h, color and BB.TYPE_BBRGB32 or BB.TYPE_BB8A)
    ffi.fill(bb.data, bb.stride * bb.h, 0)
    -- RGB32 blit 进 BB8A 会把 alpha 整块丢掉，人就消失。按像素取色，不走 blit。
    local ox, oy = img._offset_x or 0, img._offset_y or 0
    local straight = img._is_straight_alpha == true
    local mode = Display.mode()
    for py = 0, size.h - 1 do
        for px = 0, size.w - 1 do
            local pix = src:getPixel(ox + px, oy + py)
            if color then
                local c = pix:getColorRGB32()
                local a = c:getAlpha()
                if a > 0 then
                    local r, g, b = c:getR(), c:getG(), c:getB()
                    if mode == Display.EINK_COLOR then
                        r, g, b = Display.einkColor(r, g, b, px, py)
                    end
                    if opacity < 255 then
                        if not straight then
                            r = math.floor(r * opacity / 255)
                            g = math.floor(g * opacity / 255)
                            b = math.floor(b * opacity / 255)
                        end
                        a = math.floor(a * opacity / 255)
                    end
                    bb:setPixel(px, py, BB.ColorRGB32(r, g, b, a))
                end
            else
                local g8 = pix:getColor8A()
                local a = g8:getAlpha()
                if a > 0 then
                    local g = Display.quantizeGray(g8.a, px, py)
                    if opacity < 255 then
                        if not straight then g = math.floor(g * opacity / 255) end
                        a = math.floor(a * opacity / 255)
                    end
                    bb:setPixel(px, py, BB.Color8A(g, a))
                end
            end
        end
    end
    rememberFade(key, { bb = bb, straight = straight })
    return faded[key]
end

local function paintSprite(bb, name, sx, sy, sh)
    local src = fadedBB(name, sh)
    if not src then return end
    local w, h = src.bb:getWidth(), src.bb:getHeight()
    if src.straight then
        bb:alphablitFrom(src.bb, sx, sy, 0, 0, w, h)
    else
        bb:pmulalphablitFrom(src.bb, sx, sy, 0, 0, w, h)
    end
end

local companion = {}

function companion:paintTo(bb, x, y)
    if not Prefs.companion() then return end
    local f = M.flags
    local sx, sy, sh = M.seat(self.view, Prefs.corner())
    local name = "chair_read"
    if f.away then
        name = "chair_empty"
    elseif f.turn_from then
        local elapsed = now() - f.turn_from
        if elapsed >= TURN_S then
            f.turn_from = nil
        elseif elapsed >= TURN_START and elapsed < TURN_S - TURN_START then
            name = elapsed < TURN_S / 2 and "chair_turn" or "chair_turn_left"
        end
    end
    M.last_name = name
    paintSprite(bb, name, x + sx, y + sy, sh)
end

-- 排版让不开一个角。以前加的整条页边撤掉：拆掉类上的钩子，文档页边还回用户的值。还一次就停。
function M.applyAvoid()
    local TS = package.loaded["apps/reader/modules/readertypeset"]
    local orig = TS and TS._aye_orig_margins
    if TS and orig then
        TS.onSetPageMargins = orig
        TS._aye_orig_margins = nil
    end
    local ui = M.ui
    if not (ui and ui.document) then
        local ok, ReaderUI = pcall(require, "apps/reader/readerui")
        ui = ok and ReaderUI and ReaderUI.instance
        if ui and ui.document then M.ui = ui end
    end
    local typeset = ui and ui.typeset
    if not typeset or not typeset.unscaled_margins or not ui.document or not ui.document.getPageMargins then return end
    local ok, cur = pcall(function() return ui.document:getPageMargins() end)
    if not ok or type(cur) ~= "table" or not cur.left then return end
    local Screen = require("device").screen
    local base = typeset.unscaled_margins
    local want_l = Screen:scaleBySize(base[1])
    local want_r = Screen:scaleBySize(base[3])
    if cur.left == want_l and cur.right == want_r then return end
    local fn = orig or typeset.onSetPageMargins
    pcall(fn, typeset, base)
end

local function loadState()
    local Game = require("papersprite.game")
    if Game.current and not Game.current.closed then return Game.current.state, false end
    local h = Prefs.host()
    local s = require("papersprite.core.state").load(h:loadState(), h:now())
    local now, fast = h:now(), h:getSetting("debug_fast", false)
    require("papersprite.core.travel").settle(s, now, fast)
    require("papersprite.core.autopilot").tick(s, now, fast)
    h:saveState(s)
    return s, true
end

local function dirtyCompanion(corner, size)
    local ui = M.ui
    local view = ui and ui.view
    if not view then return end
    local sx, sy, sh = M.seat(view, corner, size)
    local dim = view.dimen or {}
    local Geom = require("ui/geometry")
    require("ui/uimanager"):setDirty(ui, "ui", Geom:new{
        x = (dim.x or 0) + sx, y = (dim.y or 0) + sy, w = sh, h = sh,
    })
end

-- 伴读图区域单独 full，且必须晚于本拍可能存在的阅读页刷新，避免和整页合并。
-- 动画过程中仍只用上面的 "ui"。
local function fullCompanion(corner, size)
    local ui = M.ui
    local view = ui and ui.view
    if not view then return end
    local sx, sy, sh = M.seat(view, corner, size)
    local dim = view.dimen or {}
    require("papersprite.ui.eink_image").schedule({
        x = (dim.x or 0) + sx, y = (dim.y or 0) + sy, w = sh, h = sh,
    }, { reason = "quality" })
end

function M.syncFlags()
    local f = M.flags
    local was_away = f.away
    f.shown = Prefs.companion()
    f.corner = Prefs.corner()
    f.fade = Prefs.fade()
    f.size = Prefs.size()
    local ok, s = pcall(loadState)
    if ok and s then f.away = s.sprite and s.sprite.status == "away" end
    f.ready = true
    if f.shown and was_away ~= f.away then
        dirtyCompanion(f.corner)
        fullCompanion(f.corner)
    end
    return ok and s or nil
end

function M.refreshCompanion()
    local f = M.flags
    local shown, corner, fade, size = Prefs.companion(), Prefs.corner(), Prefs.fade(), Prefs.size()
    if f.shown and f.corner then dirtyCompanion(f.corner, f.size) end
    if shown and (not f.shown or corner ~= f.corner or size ~= f.size) then dirtyCompanion(corner, size) end
    if shown then fullCompanion(corner) end
    f.shown, f.corner, f.fade, f.size = shown, corner, fade, size
end

local function noteBody(s, note)
    if note.kind == "card" then
        local c = require("papersprite.core.vault").card(note.index)
        if not c then return end
        local face = require("papersprite.ui.cardface").of(c)
        face.side = "front"
        return face
    end
    if note.kind == "away" then
        return { title = T("阿页出门了"), caption = T("出去走走，别担心。"), image = "sprite/walk.png" }
    end
    if note.kind == "home" then
        return { title = T("阿页回来了"), caption = T("到家了。"), image = "sprite/wave.png" }
    end
    if note.kind == "visitor" then
        local v = s.visitor and require("papersprite.core.travel").visitor(s.visitor.id)
        local say
        for _, e in ipairs(s.errands or {}) do
            if not e.claimed and s.visitor and e.visitor == s.visitor.id then say = e.say break end
        end
        return { title = v and T("%s来做客了", v.name) or T("来做客了"), caption = say or (v and v.here) or "",
            image = v and ("visitors/" .. v.id .. (s.visitor.pose or "") .. ".png") or "sprite/wave.png" }
    end
    if note.kind == "ach" then
        local Achievements = require("papersprite.data.achievements")
        for _, a in ipairs(Achievements) do
            if a.id == note.id then
                return { title = T("成就达成"), caption = a.voice or a.desc or a.name,
                    image = "achievements/" .. a.id .. ".png" }
            end
        end
    end
end

local function showNotice(s, note)
    local UIManager = require("ui/uimanager")
    local Modal = require("ui.themes.widgets.modal")
    local Theme = require("ui.themes")
    local Text = require("ui.themes.widgets.text")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Geom = require("ui/geometry")
    local body = noteBody(s, note)
    if not body then return end
    local box = Modal:new{ name = "papersprite_notice", modal = true }
    box.note, box.side, box.body = note, note.kind == "card" and "back" or "front", body
    function box:rebuild()
        local w = self:innerWidth()
        local content
        local buttons = {}
        if self.note.kind == "card" then
            self.body.side = self.side
            content = require("papersprite.ui.postcard").widget(self.body, w, math.floor(w * 0.64))
            buttons[#buttons + 1] = { text = T("翻面"), callback = function()
                self.side = self.side == "back" and "front" or "back"
                self:rebuild()
                UIManager:setDirty(self, "ui")
            end }
        else
            local art = math.min(math.floor(w * 0.5), Theme.px(160))
            content = VerticalGroup:new{ align = "center",
                CenterContainer:new{ dimen = Geom:new{ w = w, h = art },
                    require("ui/widget/imagewidget"):new{
                        file = pluginDir() .. "/assets/" .. self.body.image,
                        width = art, height = art, scale_factor = 0, alpha = true,
                    } },
                VerticalSpan:new{ width = Theme.px(self.theme.space.md) },
                Text.box("body", self.body.caption, w, { align = "center", bg = self.theme.dialog.bg }),
            }
        end
        local can_host = self.note.kind == "visitor" and s.visitor and not s.visitor.fed
        buttons[#buttons + 1] = { text = T("收起"), variant = not can_host and "primary" or "normal",
            callback = function() self:dismiss() end }
        if can_host then
            buttons[#buttons + 1] = { text = T("招待客人"), variant = "primary", callback = function()
                self:dismiss()
                require("papersprite.ui.moon_widgets").open("guest_here")
            end }
        end
        self:setDialog{ title = self.note.kind ~= "card" and self.body.title or nil, body = content, buttons = buttons }
    end
    box.close_callback = function()
        if popup == box then popup = nil end
        pcall(function()
            local h = Prefs.host()
            local st = require("papersprite.core.state").load(h:loadState(), h:now())
            require("papersprite.core.disturb").ack(st, note)
            h:saveState(st)
        end)
        UIManager:scheduleIn(0.2, function() pcall(M.poke) end)
    end
    box:rebuild()
    popup = box
    box:show()
end

local function readerOpen()
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    return ok and ReaderUI and ReaderUI.instance and ReaderUI.instance.document
end

-- 阁楼盖在阅读页上时不弹打扰。Game.current 是本项目判断阁楼开着的方式。
local function atticOpen()
    local ok, Game = pcall(require, "papersprite.game")
    return ok and Game and Game.current and not Game.current.closed
end

-- 透明度 100% 时完全看不见，静态伴读也不播动画：都不该为翻页去刷新角落。
local function companionAnimates()
    return Prefs.companion() and not Prefs.static() and Prefs.fade() < 100 and not M.flags.away
end

local asleep = false
local quiet_until = 0
local wake_wait

local function wakeGrace()
    local ok, Wake = pcall(require, "utils.wake")
    local n = ok and type(Wake) == "table" and tonumber(Wake.GRACE)
    return n or WAKE_GRACE
end

local function screensaverOn()
    local ok, Device = pcall(require, "device")
    return ok and Device and Device.screen_saver_mode == true
end

local function passcode()
    local ok, P = pcall(require, "features.passcode")
    if ok and type(P) == "table" then return P end
end

local function deviceInactive()
    if screensaverOn() then return true end
    local P = passcode()
    return P and P.isLocked and P.isLocked() == true
end

local function unscheduleWake()
    if not wake_wait then return end
    pcall(function() require("ui/uimanager"):unschedule(wake_wait) end)
    wake_wait = nil
end

local function armQuiet()
    local grace = wakeGrace()
    quiet_until = now() + grace
    unscheduleWake()
    wake_wait = function()
        wake_wait = nil
        pcall(M.poke)
    end
    pcall(function() require("ui/uimanager"):scheduleIn(grace, wake_wait) end)
end

-- 等屏保关掉、密码解开后再起宽限期；点按退出或延时关屏时 Resume 来得更早。
local function watchUnlock()
    unscheduleWake()
    local function check()
        wake_wait = nil
        if deviceInactive() then
            local P = passcode()
            if P and P.isLocked and P.isLocked() and P.afterUnlock then
                P.afterUnlock("papersprite.disturb", check)
            end
            if screensaverOn() or not (P and P.isLocked and P.isLocked()) then
                wake_wait = check
                pcall(function() require("ui/uimanager"):scheduleIn(1, check) end)
            end
            return
        end
        asleep = false
        armQuiet()
    end
    check()
end

function M.poke()
    -- 打扰只叠在阅读页上。桌面、阁楼开着都不弹。休眠或锁屏时也不弹。
    if not readerOpen() or atticOpen() then return end
    if deviceInactive() then
        asleep = true
        watchUnlock()
        return
    end
    if asleep then
        asleep = false
        armQuiet()
        return
    end
    if quiet_until > 0 and now() < quiet_until then return end
    local s = M.syncFlags()
    if not Prefs.disturb() or popup or not s then return end
    local note = require("papersprite.core.disturb").next(s)
    if not note then return end
    pcall(showNotice, s, note)
end

function M.onSuspend()
    asleep = true
    quiet_until = 0
    unscheduleWake()
end

function M.onResume()
    asleep = true
    watchUnlock()
end

function M.onPage(plugin)
    if plugin and plugin.ui then M.ui = plugin.ui end
    -- 先同步在家/出门，避免沿用上次 poke 留下的 flags.away（未同步时是 nil，会被当成在家）。
    M.syncFlags()
    local f = M.flags
    -- 翻页不看 flags.shown：那是上次 poke 的快照，开关和透明度已经每帧直接读设置。
    if companionAnimates() then
        f.turn_from = now()
        if not f.turn_ticking then
            f.turn_ticking = true
            local function tick()
                if not companionAnimates() then
                    M.flags.turn_from = nil
                    M.flags.turn_ticking = nil
                    return
                end
                local UIManager = require("ui/uimanager")
                local elapsed = M.flags.turn_from and now() - M.flags.turn_from
                if not elapsed or elapsed >= TURN_S then
                    M.flags.turn_from = nil
                    M.flags.turn_ticking = nil
                    dirtyCompanion(Prefs.corner())
                    fullCompanion(Prefs.corner())
                    return
                end
                dirtyCompanion(Prefs.corner())
                local next_at = elapsed < TURN_START and TURN_START
                    or elapsed < TURN_MID and TURN_MID
                    or elapsed < TURN_PUT and TURN_PUT
                    or TURN_S
                UIManager:scheduleIn(next_at - elapsed, tick)
            end
            tick()
        end
    end
    M.poke()
end

function M.attach(ui)
    M.ui = ui
    local view = ui and ui.view
    if not view or not view.registerViewModule or not ui.document then return end
    if view.view_modules then view.view_modules.papersprite_companion = nil end
    view:registerViewModule("papersprite_companion", companion)
    pcall(M.syncFlags)
end

function M.install(plugin)
    M.attach(plugin.ui)
    pcall(M.applyAvoid)
    if timer_on then return end
    timer_on = true
    local function loop()
        if not timer_on then return end
        pcall(M.poke)
        pcall(function() require("ui/uimanager"):scheduleIn(45, loop) end)
    end
    pcall(function() require("ui/uimanager"):scheduleIn(2, loop) end)
end

return M
