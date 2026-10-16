-- SPDX-License-Identifier: MIT
--- 可存档的确定性随机数（LCG）：同一存档同一时刻结算结果相同，方便测试与重开插件后复现。
local R = {}
function R.next(seed)
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed, seed / 2147483648
end
function R.pick(seed, list)
    local s, f = R.next(seed)
    return s, list[math.floor(f * #list) + 1]
end
return R
