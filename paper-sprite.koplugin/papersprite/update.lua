--[[--
阿页的阁楼自更新：复用月读的 GitHub 更新管线（Release 接口、直连与镜像竞速下载、Job 子进程、进度窗），
只把仓库、包名与换目录逻辑换成自己的。只在月读里可用，模块里的月读依赖都在用到时才 require。

Release 挂两份包：
  paper-sprite.koplugin-VERSION.zip       完整包（首装 / 素材变了）
  paper-sprite.koplugin-VERSION-code.zip  代码包（日常更新，不含 assets/）

本地 assets_rev 与代码包内一致 → 下代码包，安装时把现有 assets/ 挪进新目录；
不一致或没有代码包 → 下完整包。包体唯一信任根是 Release 资产 sha256。
--]]
local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")
local _ = require("papersprite.l10n")

local Update = { _job = nil, _offered = nil }

local ID = "ext.papersprite"
local REPO = "AnkioTomas/ko-paper-sprite"
local API_URL = "https://api.ankio.net/gh/repos/" .. REPO .. "/releases/latest"
local GITHUB = "https://github.com"
local ASSET_PREFIX = "^https://github%.com/" .. REPO:gsub("%-", "%%-") .. "/releases/download/"
local DIR_NAME = "paper-sprite.koplugin"
local CHECK_INTERVAL = 24 * 60 * 60
local MAX_BYTES = 100 * 1024 * 1024
local PROBE_MIRRORS = 5

local PLUGIN_DIR = debug.getinfo(1, "S").source:match("^@(.*)/papersprite/[^/]*$") or "."

function Update.version()
    return require("papersprite.version")
end

local function assetsRev()
    local ok, rev = pcall(require, "papersprite.assets_rev")
    if ok and type(rev) == "string" and rev ~= "" then return rev end
end

local function settings()
    return require("utils.settings").getSource(ID)
end

local function save()
    require("utils.settings").saveSource(ID)
end

function Update.autoEnabled()
    return settings().auto_update_check ~= false
end

function Update.setAuto(on)
    settings().auto_update_check = on and true or false
    save()
end

local function newer(candidate, installed)
    local left = { candidate:match("^(%d+)%.(%d+)%.(%d+)") }
    local right = { installed:match("^(%d+)%.(%d+)%.(%d+)") }
    if #right == 0 then return true end
    for i = 1, 3 do
        local l, r = tonumber(left[i]), tonumber(right[i])
        if l ~= r then return l > r end
    end
    return false
end

---@param asset table GitHub release asset
---@return table|nil
local function packFromAsset(asset)
    local url = asset.browser_download_url
    if type(url) ~= "string" or not url:match(ASSET_PREFIX) then return nil end
    local digest = (asset.digest or ""):match("^sha256:(" .. ("%x"):rep(64) .. ")$")
    if not digest then return nil end
    return {
        url = url,
        size = tonumber(asset.size),
        sha256 = digest:lower(),
    }
end

local function readAssetsRevFile(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local body = file:read("*a")
    file:close()
    return body and body:match('return%s*["\']([^"\']+)["\']')
end

local function hasPlaceAssets(root)
    local places = root .. "/assets/places"
    if lfs.attributes(places, "mode") ~= "directory" then return false end
    for name in lfs.dir(places) do
        if name ~= "." and name ~= ".." then return true end
    end
    return false
end

local function parseRelease(body)
    local ok, release = pcall(require("json").decode, body)
    if not ok or type(release) ~= "table" or release.draft or release.prerelease then
        return nil, "invalid release response"
    end
    local tag = release.tag_name
    local version = type(tag) == "string" and tag:match("^v?(%d+%.%d+%.%d+[%w%.%+%-]*)$")
    if not version then return nil, "invalid release version" end

    local full_name = DIR_NAME .. "-" .. version .. ".zip"
    local code_name = DIR_NAME .. "-" .. version .. "-code.zip"
    local full, code
    for _i, asset in ipairs(release.assets or {}) do
        if asset.name == full_name then full = packFromAsset(asset) end
        if asset.name == code_name then code = packFromAsset(asset) end
    end
    if not full then return nil, "release has no plugin archive" end

    -- 有本地素材修订号且 Release 挂了代码包 → 先尝试代码包；装不上再回落完整包。
    local pack = full
    local kind = "full"
    if code and assetsRev() then
        pack = code
        kind = "code"
    end

    return {
        version = version,
        kind = kind,
        url = pack.url,
        size = pack.size,
        sha256 = pack.sha256,
        full = full,
        code = code,
        notes = type(release.body) == "string" and release.body:gsub("^%s+", ""):gsub("%s+$", "") or nil,
        available = newer(version, Update.version()),
    }
end

function Update.check(cb)
    if Update._job then return cb(nil, "busy") end
    Update._job = require("http.request").get(API_URL, {
        timeout = require("http.timeout").net(1),
        headers = { Accept = "application/vnd.github+json", ["X-GitHub-Api-Version"] = "2022-11-28" },
    }, function(body, err)
        Update._job = nil
        if err then return cb(nil, err) end
        local release, parse_err = parseRelease(body)
        if not release then return cb(nil, parse_err) end
        settings().update_last_checked_at = os.time()
        save()
        cb(release)
    end)
end

local function removeTree(path)
    local attr = lfs.symlinkattributes(path)
    if not attr then return true end
    if attr.mode ~= "directory" then return os.remove(path) end
    for name in lfs.dir(path) do
        if name ~= "." and name ~= ".." then
            local ok, err = removeTree(path .. "/" .. name)
            if not ok then return nil, err end
        end
    end
    return lfs.rmdir(path)
end

local function fileSha256(path)
    local file, err = io.open(path, "rb")
    if not file then return nil, err end
    local hash = require("ffi/sha2").sha256()
    for chunk in function() return file:read(256 * 1024) end do hash(chunk) end
    file:close()
    return hash()
end

local function extract(archive, staging)
    if not lfs.mkdir(staging) then return nil, "cannot create update staging directory" end
    local reader = require("ffi/archiver").Reader:new()
    if not reader:open(archive) then return nil, reader.err or "cannot open update archive" end
    local ok = true
    for entry in reader:iterate() do
        ok = reader:extractToPath(entry.path, staging .. "/" .. entry.path)
        if not ok then break end
    end
    local err = reader.err
    reader:close()
    if not ok or err then return nil, err or "archive extraction failed" end
    return true
end

--- 完整包：整目录换位。代码包：校验 assets_rev 后把现有 assets/ 挪进新树再换位。
local function installArchive(archive, sha256, kind)
    local digest, err = fileSha256(archive)
    if not digest then return nil, err end
    if digest ~= sha256 then return nil, "update checksum mismatch" end
    local parent = PLUGIN_DIR:match("^(.*)/[^/]+$")
    local staging = parent .. "/.paper-sprite.koplugin-update"
    local backup = parent .. "/.paper-sprite.koplugin-backup"
    local ok
    ok, err = removeTree(staging)
    if ok then ok, err = extract(archive, staging) end
    local staged = staging .. "/" .. DIR_NAME
    if ok and lfs.attributes(staged .. "/main.lua", "mode") ~= "file" then
        ok, err = nil, "not a paper-sprite plugin archive"
    end

    if ok and kind == "code" then
        local remote_rev = readAssetsRevFile(staged .. "/papersprite/assets_rev.lua")
        local local_rev = assetsRev()
        if not remote_rev or not local_rev or remote_rev ~= local_rev then
            ok, err = nil, "assets revision mismatch"
        elseif hasPlaceAssets(staged) then
            ok, err = nil, "code archive must not include assets"
        elseif not hasPlaceAssets(PLUGIN_DIR) then
            ok, err = nil, "assets revision mismatch"
        else
            ok, err = os.rename(PLUGIN_DIR .. "/assets", staged .. "/assets")
        end
        if not ok then
            removeTree(staging)
            return nil, err
        end
    elseif ok and kind == "full" then
        if not hasPlaceAssets(staged) then
            ok, err = nil, "not a paper-sprite plugin archive"
        end
    end

    if ok then ok, err = removeTree(backup) end
    if ok then ok, err = os.rename(PLUGIN_DIR, backup) end
    if not ok then
        -- 代码包已把 assets 挪到 staging：失败时搬回去，避免留下无图的安装。
        if kind == "code" and lfs.attributes(staged .. "/assets", "mode") == "directory"
            and lfs.attributes(PLUGIN_DIR, "mode") == "directory"
            and not lfs.attributes(PLUGIN_DIR .. "/assets") then
            os.rename(staged .. "/assets", PLUGIN_DIR .. "/assets")
        end
        removeTree(staging)
        return nil, err
    end
    ok, err = os.rename(staged, PLUGIN_DIR)
    if not ok then
        local restored, restore_err = os.rename(backup, PLUGIN_DIR)
        if restored and kind == "code" and lfs.attributes(staging .. "/" .. DIR_NAME .. "/assets", "mode") == "directory"
            and not lfs.attributes(PLUGIN_DIR .. "/assets") then
            os.rename(staging .. "/" .. DIR_NAME .. "/assets", PLUGIN_DIR .. "/assets")
        end
        removeTree(staging)
        if not restored then return nil, "install failed and rollback failed: " .. tostring(restore_err) end
        return nil, err
    end
    removeTree(staging)
    removeTree(backup)
    return true
end

-- 直连与随机几个镜像并发探测，最先回 200 且长度对得上的胜出；全部失败回落直连。
-- 月读 0.8 起镜像调度并进 http.github（http.mirror 已删）；0.7.x 只有 http.mirror。
local function pickDownloadUrl(release, cb)
    local has_github, Github = pcall(require, "http.github")
    if has_github and type(Github) == "table" and Github.pickRelease then return Github.pickRelease(release, cb) end
    local Request = require("http.request")
    local path = release.url:sub(#GITHUB + 1)
    local pool = { unpack(require("http.mirror").RELEASE_PROXIES) }
    local prefixes = { GITHUB }
    for i = 1, math.min(PROBE_MIRRORS, #pool) do
        local j = math.random(i, #pool)
        pool[i], pool[j] = pool[j], pool[i]
        prefixes[#prefixes + 1] = pool[i]
    end
    local jobs, pending, settled = {}, #prefixes, false
    local function cancelAll()
        settled = true
        for _i, job in ipairs(jobs) do job:cancel() end
    end
    local function settle(url)
        if settled then return end
        cancelAll()
        cb(url)
    end
    local guard = require("ui.guard")
    for i, prefix in ipairs(prefixes) do
        jobs[i] = Request.stream({
            url = prefix .. path, timeout = require("http.timeout").net(1 / 3), allow_redirects = true,
        }, {
            on_headers = function(code, headers)
                if code ~= 200 then return end
                local length = tonumber((headers:get("Content-Length", true)))
                if length and release.size and length ~= release.size then return end
                local mime = headers:get("Content-Type", true)
                if mime and mime:lower():find("text/html", 1, true) then return end
                UIManager:nextTick(guard.wrap("papersprite update settle", function() settle(prefix .. path) end))
            end,
            on_done = function()
                pending = pending - 1
                if pending == 0 then
                    UIManager:nextTick(guard.wrap("papersprite update settle", function() settle(release.url) end))
                end
            end,
        })
    end
    return { cancel = cancelAll }
end

local function installFrom(url, release, done, on_progress, on_installing)
    local function fail(err)
        if release.kind == "code" and release.full
            and tostring(err):find("assets revision mismatch", 1, true) then
            -- 素材修订号对不上：改下完整包，不再回落直连重试同一代码包。
            local full = {
                version = release.version,
                kind = "full",
                url = release.full.url,
                size = release.full.size,
                sha256 = release.full.sha256,
                full = release.full,
                notes = release.notes,
            }
            return installFrom(full.url, full, done, on_progress, on_installing)
        end
        if url == release.url then return done(false, err) end
        installFrom(release.url, release, done, on_progress, on_installing)
    end
    local Paths = require("utils.paths")
    Paths.ensureDir(Paths.root())
    local archive = Paths.root() .. "/papersprite-update.zip"
    os.remove(archive)
    Update._job = require("http.request").download({
        url = url, timeout = require("http.timeout").net(10), allow_redirects = true,
        max_bytes = MAX_BYTES,
        on_progress = on_progress and function(bytes) on_progress(bytes, release.size) end,
    }, archive, function(ok, err)
        if not ok then return fail(err) end
        if on_installing then on_installing() end
        Update._job = require("workers.job").run(function()
            local installed, install_err = installArchive(archive, release.sha256, release.kind)
            if not installed then error(install_err, 0) end
        end, {
            name = "papersprite.update", kind = "heavy", timeout = 120,
            on_done = function()
                os.remove(archive)
                done(true)
            end,
            on_failed = function(install_err)
                os.remove(archive)
                local text = tostring(install_err)
                if text:find("update checksum mismatch", 1, true)
                    or text:find("assets revision mismatch", 1, true) then
                    fail(install_err)
                else
                    done(false, install_err)
                end
            end,
        })
    end)
end

function Update.cancel()
    if Update._job then Update._job:cancel() end
    Update._job = nil
end

local function errorText(err)
    local text = tostring(err)
    local known = {
        { "^busy$", _("正在检查或安装更新，请稍候") },
        { "^invalid release", _("更新信息无效，请稍后再试") },
        { "^release has no", _("新版本缺少插件包，请稍后再试") },
        { "update checksum mismatch", _("更新包校验失败，请稍后再试") },
        { "download too large", _("更新包过大，已中止下载") },
    }
    for _i, entry in ipairs(known) do
        if text:find(entry[1]) then return entry[2] end
    end
    return text:match("[^\n]*")
end

local function toast(text, timeout)
    require("ui.themes.widgets.toast"):new{ text = text, timeout = timeout }:show()
end

-- 装好立即重启：新文件已就位，旧模块还在内存里，继续跑会新旧混用。
local function startInstall(release)
    local ProgressDialog = require("ui.themes.widgets.progress_dialog")
    local dialog = ProgressDialog:new{ title = _("正在下载阿页更新…"), dismissable = false, on_cancel = Update.cancel }
    dialog:show()
    local function done(ok, err)
        Update._job = nil
        if ok then
            dialog:set(_("更新完成，正在重启 KOReader…"), 100)
            UIManager:nextTick(function()
                UIManager:broadcastEvent(require("ui/event"):new("Restart"))
            end)
            return
        end
        dialog:close()
        toast(_("阿页更新失败：%s", errorText(err)), 5)
    end
    if Update._job then return done(false, "busy") end
    Update._job = pickDownloadUrl(release, function(url)
        installFrom(url, release, done, function(bytes, size)
            if size and size > 0 then dialog:bytes(bytes, size) end
        end, function()
            dialog:close()
            dialog = ProgressDialog:new{ title = _("正在安装阿页更新…"), dismissable = false }
            dialog:show()
        end)
    end)
end

local function promptInstall(release)
    if Update._offered == release.version then return end
    Update._offered = release.version
    local header
    if release.kind == "code" then
        header = _("发现阿页的阁楼 %s（当前 %s）。下载代码更新并保留现有素材？", release.version, Update.version())
    else
        header = _("发现阿页的阁楼 %s（当前 %s）。下载并完整替换插件目录？", release.version, Update.version())
    end
    local dialog
    dialog = require("ui.themes.widgets.text_viewer"):new{
        title = _("更新日志"),
        text = release.notes and release.notes ~= "" and (header .. "\n\n" .. release.notes) or header,
        buttons = {
            { text = _("稍后"), callback = function() dialog:close() end },
            { text = _("下载并安装"), variant = "primary", callback = function()
                dialog:close()
                startInstall(release)
            end },
        },
    }
    dialog:show()
end

function Update.manualCheck()
    local loading = require("ui.themes.widgets.progress_dialog"):new{
        title = _("检查更新"), text = _("正在检查阿页更新…"), dismissable = false,
    }
    loading:show()
    Update.check(function(release, err)
        loading:close()
        if err then
            toast(_("检查更新失败：%s", errorText(err)), 4)
        elseif release.available then
            Update._offered = nil
            promptInstall(release)
        else
            toast(_("已是最新版本（%s）", Update.version()), 3)
        end
    end)
end

local autoChecked = false

-- 每个进程最多尝试一次，且距上次成功检查满 24 小时、已联网才发请求；只提示，不静默安装。
function Update.autoCheck()
    if autoChecked or not Update.autoEnabled() then return end
    autoChecked = true
    if os.time() - (settings().update_last_checked_at or 0) < CHECK_INTERVAL then return end
    if not require("ui/network/manager"):isConnected() then return end
    Update.check(function(release)
        if release and release.available then promptInstall(release) end
    end)
end

return Update
