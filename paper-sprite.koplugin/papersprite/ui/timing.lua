-- SPDX-License-Identifier: MIT
--[[--
轻量计时。把「从点击到出画」拆成 view / compose / showScreen 等段，
写入 papersprite.ui.timing.last，并在有 logger 时打 papersprite.time。
不能把 Display.apply 的单段耗时当成完整 UI 响应。
--]]
local M = { last = {} }

function M.now()
    local ok, util = pcall(require, "ffi/util")
    if ok and util and util.gettime then
        local s, us = util.gettime()
        return s * 1000 + us / 1000
    end
    return os.clock() * 1000
end

function M.record(name, ms, extra)
    M.last[name] = { ms = ms, extra = extra, at = os.time() }
    pcall(function()
        require("logger").info("papersprite.time", name, string.format("%.1fms", ms), extra or "")
    end)
end

function M.span(name, extra, fn)
    if type(extra) == "function" then
        fn, extra = extra, nil
    end
    local t0 = M.now()
    local a, b, c, d = fn()
    M.record(name, M.now() - t0, extra)
    return a, b, c, d
end

return M
