-- SPDX-License-Identifier: MIT
--- 可存档的确定性随机数（Park–Miller 乘同余）：同一存档同一时刻结算结果相同，方便测试与重开插件后复现。
--- 乘积 < 2^47，Lua 5.1 / LuaJIT 的 double 能精确表示；旧的 LCG 乘积超过 2^53，实测约 1.6 万步就进入循环。
local R = {}
local M, A = 2147483647, 48271
function R.next(seed)
    seed = math.floor(tonumber(seed) or 1) % M
    if seed == 0 then seed = 1 end
    seed = (seed * A) % M
    return seed, seed / M
end
function R.pick(seed, list)
    local s, f = R.next(seed)
    return s, list[math.floor(f * #list) + 1]
end
return R
