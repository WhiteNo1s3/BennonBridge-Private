-- Pure duplicate-bridge scoring. No LOVE dependencies, so it can be unit-tested
-- with plain Lua.  Denominations: 1=C 2=D 3=H 4=S 5=NT (matches constants.lua).
local M = {}

-- Standard 16-board vulnerability cycle: "none", "NS", "EW", "both".
local VUL = { "none", "NS", "EW", "both", "NS", "EW", "both", "none",
              "EW", "both", "none", "NS", "both", "none", "NS", "EW" }

function M.vulnerability(board)
    return VUL[((board - 1) % 16) + 1]
end

function M.isVulnerable(board, side)
    local v = M.vulnerability(board)
    return v == "both" or v == side
end

-- level 1-7, denom 1-5, tricks = tricks taken by declarer (0-13),
-- doubled: 0 none, 1 doubled, 2 redoubled. Returns declarer-side score
-- (negative when defeated).
function M.score(level, denom, doubled, vul, tricks)
    doubled = doubled or 0
    local mult = (doubled == 2) and 4 or (doubled == 1) and 2 or 1
    local need = level + 6
    if tricks >= need then
        local perTrick = (denom <= 2) and 20 or 30
        local trickScore = level * perTrick + ((denom == 5) and 10 or 0)
        trickScore = trickScore * mult
        local s = trickScore
        s = s + ((trickScore >= 100) and (vul and 500 or 300) or 50)
        if level == 6 then s = s + (vul and 750 or 500) end
        if level == 7 then s = s + (vul and 1500 or 1000) end
        if doubled == 1 then s = s + 50 elseif doubled == 2 then s = s + 100 end
        local over = tricks - need
        if doubled == 0 then
            s = s + over * perTrick
        else
            s = s + over * (vul and 200 or 100) * (doubled == 2 and 2 or 1)
        end
        return s
    end
    local down = need - tricks
    if doubled == 0 then
        return -down * (vul and 100 or 50)
    end
    local pen
    if vul then
        pen = 200 + (down - 1) * 300
    else
        pen = 100
        if down >= 2 then pen = pen + math.min(down - 1, 2) * 200 end
        if down >= 4 then pen = pen + (down - 3) * 300 end
    end
    if doubled == 2 then pen = pen * 2 end
    return -pen
end

local IMP = { 20, 50, 90, 130, 170, 220, 270, 320, 370, 430, 500, 600, 750,
              900, 1100, 1300, 1500, 1750, 2000, 2250, 2500, 3000, 3500, 4000 }

-- Converts a point difference to IMPs (sign preserved).
function M.imps(diff)
    local a, n = math.abs(diff), 0
    for _, lim in ipairs(IMP) do
        if a >= lim then n = n + 1 else break end
    end
    return diff < 0 and -n or n
end

return M
