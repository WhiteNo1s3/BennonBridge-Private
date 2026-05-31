-- AI card-play logic for Bridge (Minibridge variant)
-- Three difficulty levels: Easy, Medium, Hard

local C = require("src.constants")

local AI = {}

-- ── Helpers ────────────────────────────────────────────────────────────────

-- Return the subset of `hand` that are legal to play given `ledSuit`
-- (nil when leading).
function AI.legalCards(hand, ledSuit)
    if not ledSuit then return hand end
    local suited = {}
    for _, c in ipairs(hand) do
        if c.suit == ledSuit then suited[#suited+1] = c end
    end
    return #suited > 0 and suited or hand
end

-- Determine the winner index (1-based) of a trick array [{player,card},...].
-- trump may be nil for NT.
function AI.trickWinnerIdx(trick, trump)
    if #trick == 0 then return nil end
    local ledSuit = trick[1].card.suit
    local bestI, bestC = 1, trick[1].card
    for i = 2, #trick do
        local c = trick[i].card
        local bTrump = (bestC.suit == trump)
        local cTrump = (c.suit == trump)
        if cTrump and not bTrump then
            bestI, bestC = i, c
        elseif cTrump and bTrump and c.rank > bestC.rank then
            bestI, bestC = i, c
        elseif not cTrump and not bTrump
               and c.suit == ledSuit and c.rank > bestC.rank then
            bestI, bestC = i, c
        end
    end
    return bestI
end

local function cheapest(cards)
    local b = cards[1]
    for _, c in ipairs(cards) do if c.rank < b.rank then b = c end end
    return b
end

local function costliest(cards)
    local b = cards[1]
    for _, c in ipairs(cards) do if c.rank > b.rank then b = c end end
    return b
end

-- Cards from `legal` that would win the current (partial) trick
local function winningCards(legal, trick, trump)
    local winners = {}
    for _, c in ipairs(legal) do
        local test = {}
        for _, e in ipairs(trick) do test[#test+1] = e end
        test[#test+1] = {player=0, card=c}
        if AI.trickWinnerIdx(test, trump) == #test then
            winners[#winners+1] = c
        end
    end
    return winners
end

-- Is partner currently the projected winner of the trick?
local function partnerWinning(trick, partner, trump)
    if #trick == 0 then return false end
    local wi = AI.trickWinnerIdx(trick, trump)
    return trick[wi].player == partner
end

-- ── Easy ───────────────────────────────────────────────────────────────────

function AI.easyPlay(legal)
    return legal[love.math.random(1, #legal)]
end

-- ── Medium ─────────────────────────────────────────────────────────────────

local function mediumLead(hand, trump)
    -- Lead top of a sequence, prefer non-trump suits
    local best, bestRank = nil, -1
    for _, c in ipairs(hand) do
        if c.suit ~= trump and c.rank > bestRank then
            best, bestRank = c, c.rank
        end
    end
    return best or costliest(hand)
end

local function mediumFollow(legal, trick, trump, partner)
    if partnerWinning(trick, partner, trump) then
        return cheapest(legal)          -- partner is winning; don't waste
    end
    local w = winningCards(legal, trick, trump)
    if #w > 0 then
        -- Play cheapest winner
        table.sort(w, function(a,b) return a.rank < b.rank end)
        return w[1]
    end
    return cheapest(legal)              -- can't win; pitch smallest
end

function AI.mediumPlay(hand, trick, trump, partner)
    local ledSuit = (#trick > 0) and trick[1].card.suit or nil
    local legal   = AI.legalCards(hand, ledSuit)
    if ledSuit == nil then
        return mediumLead(hand, trump)
    end
    return mediumFollow(legal, trick, trump, partner)
end

-- ── Hard ───────────────────────────────────────────────────────────────────
-- Tracks played cards to make inference-based decisions.

local function hardLead(hand, trump, played)
    -- Cash aces first
    for _, c in ipairs(hand) do
        if c.rank == 14 then return c end
    end

    -- Lead 4th-best of longest non-trump suit
    local suitCards = {}
    for suit = 1, 4 do
        if suit ~= trump then
            local sc = {}
            for _, c in ipairs(hand) do
                if c.suit == suit then sc[#sc+1] = c end
            end
            if #sc > 0 then suitCards[#suitCards+1] = sc end
        end
    end
    if #suitCards == 0 then return cheapest(hand) end

    table.sort(suitCards, function(a,b) return #a > #b end)
    local longest = suitCards[1]
    table.sort(longest, function(a,b) return a.rank > b.rank end)
    local idx = math.min(4, #longest)
    return longest[idx]
end

local function hardFollow(legal, trick, trump, partner, hand)
    if partnerWinning(trick, partner, trump) and #trick >= 2 then
        return cheapest(legal)
    end
    local w = winningCards(legal, trick, trump)
    if #w > 0 then
        table.sort(w, function(a,b) return a.rank < b.rank end)
        return w[1]
    end
    return cheapest(legal)
end

function AI.hardPlay(hand, trick, trump, partner, played)
    local ledSuit = (#trick > 0) and trick[1].card.suit or nil
    local legal   = AI.legalCards(hand, ledSuit)
    if ledSuit == nil then
        return hardLead(hand, trump, played)
    end
    return hardFollow(legal, trick, trump, partner, hand)
end

-- ── Main entry point ───────────────────────────────────────────────────────

-- `state` fields used: hands, currentTrick, trumpSuit, played
function AI.chooseCard(state, player, difficulty)
    local hand    = state.hands[player]
    local trick   = state.currentTrick
    local trump   = state.trumpSuit
    local partner = C.PARTNER[player]

    if difficulty == C.EASY then
        local ledSuit = (#trick > 0) and trick[1].card.suit or nil
        return AI.easyPlay(AI.legalCards(hand, ledSuit))
    elseif difficulty == C.MEDIUM then
        return AI.mediumPlay(hand, trick, trump, partner)
    else
        return AI.hardPlay(hand, trick, trump, partner, state.played)
    end
end

-- ── Minibridge contract selection ──────────────────────────────────────────
-- Called by AI declarer (or as suggestion for human declarer).
-- Returns {suit=1-5, tricks=7-13}
function AI.chooseContract(declarerHand, dummyHand, totalHCP)
    -- Combined suit lengths
    local suitLen = {}
    for s = 1, 4 do
        local n = 0
        for _, c in ipairs(declarerHand) do if c.suit == s then n = n+1 end end
        for _, c in ipairs(dummyHand)    do if c.suit == s then n = n+1 end end
        suitLen[s] = n
    end

    local isGame = totalHCP >= 25

    -- Find best fit (8+ cards), majors preferred
    local bestSuit, bestLen = nil, 7
    for _, s in ipairs({C.HEARTS, C.SPADES, C.DIAMONDS, C.CLUBS}) do
        if suitLen[s] >= 8 and suitLen[s] > bestLen then
            bestSuit, bestLen = s, suitLen[s]
        end
    end

    if isGame then
        if bestSuit then
            return {suit=bestSuit, tricks=C.GAME_TRICKS[bestSuit]}
        else
            return {suit=C.NO_TRUMP, tricks=9}
        end
    else
        -- Part score: estimate tricks from HCP (rough: 7 + (HCP-20)/3)
        local est = math.max(7, math.min(10, 7 + math.floor((totalHCP - 20) / 3)))
        if bestSuit then
            return {suit=bestSuit, tricks=est}
        else
            return {suit=C.NO_TRUMP, tricks=math.min(est, 8)}
        end
    end
end

return AI
