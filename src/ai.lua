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

-- ── Harder ─────────────────────────────────────────────────────────────────

local function harderLead(hand, trump, played)
    local bestCard = nil
    local bestScore = -1
    
    for _, c in ipairs(hand) do
        local score = 0
        if c.rank == 14 then score = 50 end -- Cash Aces
        if c.suit ~= trump then
            -- Prefer solid sequences
            local hasNext = false
            for _, c2 in ipairs(hand) do
                if c2.suit == c.suit and c2.rank == c.rank - 1 then
                    hasNext = true; break
                end
            end
            if hasNext then score = score + 10 end
            
            local len = 0
            for _, c2 in ipairs(hand) do if c2.suit == c.suit then len = len + 1 end end
            score = score + len
        end
        if score > bestScore then
            bestScore = score
            bestCard = c
        end
    end
    return bestCard or cheapest(hand)
end

local function harderFollow(legal, trick, trump, partner, hand)
    local w = winningCards(legal, trick, trump)
    -- Finesse logic: playing 3rd
    if #trick == 2 and not partnerWinning(trick, partner, trump) then
        if #w > 0 then
            table.sort(w, function(a,b) return a.rank < b.rank end)
            return w[1]
        end
    end
    
    if partnerWinning(trick, partner, trump) and #trick >= 2 then
        return cheapest(legal)
    end
    if #w > 0 then
        table.sort(w, function(a,b) return a.rank < b.rank end)
        return w[1]
    end
    return cheapest(legal)
end

function AI.harderPlay(hand, trick, trump, partner, played)
    local ledSuit = (#trick > 0) and trick[1].card.suit or nil
    local legal   = AI.legalCards(hand, ledSuit)
    if ledSuit == nil then
        return harderLead(hand, trump, played)
    end
    return harderFollow(legal, trick, trump, partner, hand)
end

-- ── Hardest ────────────────────────────────────────────────────────────────

local function hardestFollow(legal, trick, trump, partner, hand, played)
    local w = winningCards(legal, trick, trump)

    if #trick == 1 then
        -- SECOND HAND LOW, Cover an honor with an honor
        local ledCard = trick[1].card
        if ledCard.rank >= 10 and #w > 0 then
            table.sort(w, function(a,b) return a.rank < b.rank end)
            return w[1]
        else
            return cheapest(legal)
        end
    elseif #trick == 2 then
        -- THIRD HAND HIGH
        if not partnerWinning(trick, partner, trump) then
            if #w > 0 then
                table.sort(w, function(a,b) return a.rank < b.rank end)
                return w[#w] -- Play highest winner to force out 4th hand's stop
            end
        end
        return cheapest(legal)
    else
        -- FOURTH HAND
        if not partnerWinning(trick, partner, trump) and #w > 0 then
            table.sort(w, function(a,b) return a.rank < b.rank end)
            return w[1] -- Play lowest winner to take trick
        end
        return cheapest(legal)
    end
end

function AI.hardestPlay(hand, trick, trump, partner, played)
    local ledSuit = (#trick > 0) and trick[1].card.suit or nil
    local legal   = AI.legalCards(hand, ledSuit)
    if ledSuit == nil then
        return harderLead(hand, trump, played) -- Lead logic is same as harder for now
    end
    return hardestFollow(legal, trick, trump, partner, hand, played)
end

-- ── Monte-Carlo rollout engine ─────────────────────────────────────────────
-- The "reach" upgrade for the top difficulty levels. Instead of judging one
-- trick at a time, the AI: (1) collects every card it can't see, (2) deals
-- them randomly into the hidden hands many times over (each a plausible
-- world consistent with the play so far), (3) plays each world out to the
-- END of the hand with fast heuristics for all four seats, and (4) picks
-- the candidate card that wins its side the most tricks on average.
--
-- Visibility is honest bridge knowledge: the AI sees its own hand, and the
-- dummy once one is up (dummy is public). When the AI is playing the dummy's
-- cards it also sees the declarer's hand — exactly what a human declarer
-- knows. It never peeks at defenders' holdings.

-- Fast per-seat heuristic used inside rollouts (medium strength for speed).
local function rolloutChoose(hand, trick, trump, partner)
    local ledSuit = (#trick > 0) and trick[1].card.suit or nil
    local legal   = AI.legalCards(hand, ledSuit)
    if ledSuit == nil then
        return mediumLead(hand, trump) or legal[1]
    end
    return mediumFollow(legal, trick, trump, partner)
end

-- Play one hypothetical world to the end of the hand. `hands` is mutated.
-- Returns tricks won by `mySide` ("NS"/"EW"), including the current trick.
local function playOut(hands, trick, toAct, trump, mySide)
    local sideOf = {"NS", "EW", "NS", "EW"}
    local won    = 0
    local t      = {}
    for i, e in ipairs(trick) do t[i] = e end

    while true do
        -- Complete the current trick
        while #t < 4 do
            local hand = hands[toAct]
            if #hand == 0 then return won end   -- safety: shouldn't happen
            local card = rolloutChoose(hand, t, trump, C.PARTNER[toAct])
            for i, c in ipairs(hand) do
                if c == card then table.remove(hand, i) break end
            end
            t[#t+1] = {player = toAct, card = card}
            toAct = C.NEXT[toAct]
        end
        local wi     = AI.trickWinnerIdx(t, trump)
        local winner = t[wi].player
        if sideOf[winner] == mySide then won = won + 1 end
        if #hands[winner] == 0 then return won end   -- hand over
        toAct = winner
        t     = {}
    end
end

-- Deal the unseen cards randomly into the hidden seats (counts must match
-- how many cards each seat still holds). Returns a full hands[1..4] table of
-- COPIES safe for the rollout to mutate.
local function sampleWorld(state, player, unseen, hiddenSeats, rng)
    local hands = {}
    for p = 1, 4 do
        hands[p] = {}
        if not hiddenSeats[p] then
            for i, c in ipairs(state.hands[p]) do hands[p][i] = c end
        end
    end
    -- Shuffle the unseen pool (Fisher-Yates on a copy)
    local pool = {}
    for i, c in ipairs(unseen) do pool[i] = c end
    for i = #pool, 2, -1 do
        local j = rng:random(1, i)
        pool[i], pool[j] = pool[j], pool[i]
    end
    -- Deal sequentially into hidden seats, respecting their true counts
    local k = 1
    for p = 1, 4 do
        if hiddenSeats[p] then
            for _ = 1, #state.hands[p] do
                hands[p][#hands[p]+1] = pool[k]
                k = k + 1
            end
        end
    end
    return hands
end

-- Full Monte-Carlo decision. `worlds` = hypothetical deals per candidate.
local function monteCarloPlay(state, player, worlds)
    local trick   = state.currentTrick
    local trump   = state.trumpSuit
    local ledSuit = (#trick > 0) and trick[1].card.suit or nil
    local legal   = AI.legalCards(state.hands[player], ledSuit)
    if #legal == 1 then return legal[1] end

    local mySide  = (player == C.NORTH or player == C.SOUTH) and "NS" or "EW"

    -- Which seats can this player legitimately see?
    local visible = {[player] = true}
    if state.dummy then
        visible[state.dummy] = true                    -- dummy is public
        if player == state.dummy and state.declarer then
            visible[state.declarer] = true             -- declarer runs dummy
        end
    end
    local hiddenSeats = {}
    for p = 1, 4 do hiddenSeats[p] = not visible[p] end

    -- Unseen pool = every card not in a visible hand and not already played
    local seen = {}
    for p = 1, 4 do
        if visible[p] then
            for _, c in ipairs(state.hands[p]) do
                seen[c.suit * 100 + c.rank] = true
            end
        end
    end
    for _, e in ipairs(state.played) do
        seen[e.card.suit * 100 + e.card.rank] = true
    end
    local unseen = {}
    for suit = 1, 4 do
        for rank = 2, 14 do
            if not seen[suit * 100 + rank] then
                unseen[#unseen+1] = {suit = suit, rank = rank}
            end
        end
    end

    -- Deterministic per-decision RNG: same table state → same choice, so
    -- replaying a seed replays the whole hand identically.
    local rngSeed = (state.seed or 1) * 131 + #state.played * 17 + player
    local rng = love.math.newRandomGenerator(rngSeed)

    local bestCard, bestScore = nil, -math.huge
    for _, cand in ipairs(legal) do
        local total = 0
        for _ = 1, worlds do
            local hands = sampleWorld(state, player, unseen, hiddenSeats, rng)
            -- Play the candidate, then roll the rest of the hand out
            local myHand = hands[player]
            for i, c in ipairs(myHand) do
                if c.suit == cand.suit and c.rank == cand.rank then
                    table.remove(myHand, i) break
                end
            end
            local t = {}
            for i, e in ipairs(trick) do t[i] = e end
            t[#t+1] = {player = player, card = cand}
            total = total + playOut(hands, t, C.NEXT[player], trump, mySide)
        end
        local avg = total / worlds
        -- Tie-break: save honours — prefer the cheaper card on equal tricks
        if avg > bestScore + 0.001
           or (math.abs(avg - bestScore) <= 0.001
               and bestCard and cand.rank < bestCard.rank) then
            bestScore, bestCard = avg, cand
        end
    end
    return bestCard or legal[1]
end

-- ── Main entry point ───────────────────────────────────────────────────────

-- Rollout budget per candidate card, by difficulty. EASY..HARD keep their
-- classic single-trick heuristics; HARDER and HARDEST look ahead to the end
-- of the hand through sampled worlds (HARDEST samples 3x more). Budgets are
-- sized from measured cost (~0.1ms/world on desktop): worst-case decisions
-- stay well under the AI's own 0.75s think delay even on a phone.
local MC_WORLDS = {
    [C.HARDER]  = 40,
    [C.HARDEST] = 120,
}

-- `state` fields used: hands, currentTrick, trumpSuit, played, dummy,
-- declarer, seed
function AI.chooseCard(state, player, difficulty)
    local hand    = state.hands[player]
    local trick   = state.currentTrick
    local trump   = state.trumpSuit
    local partner = C.PARTNER[player]

    if difficulty == C.EASY then
        -- A believable NEWBIE, not a random-number generator: about a third
        -- of the time they do the obvious sensible thing (so the game still
        -- feels like bridge), the rest is a guess — wasted honours, missed
        -- wins — exactly the mistakes a beginner at the table would make,
        -- and visible enough that the player learns from them.
        if love.math.random() < 0.35 then
            return AI.mediumPlay(hand, trick, trump, partner)
        end
        local ledSuit = (#trick > 0) and trick[1].card.suit or nil
        return AI.easyPlay(AI.legalCards(hand, ledSuit))
    elseif difficulty == C.MEDIUM then
        return AI.mediumPlay(hand, trick, trump, partner)
    elseif difficulty == C.HARD then
        return AI.hardPlay(hand, trick, trump, partner, state.played)
    end

    -- HARDER / HARDEST: full Monte-Carlo lookahead to the end of the hand.
    -- HARDEST thinks tightest exactly where it matters most: when it is
    -- DECLARING (playing its own hand or the dummy it controls, both of
    -- which it can see) the sample budget rises ~70%, so the declarer line
    -- is as close to correct as the engine gets — even a weak partner's
    -- defence elsewhere won't stop it fighting for the contract.
    local worlds = MC_WORLDS[difficulty] or 16
    if difficulty == C.HARDEST
       and (player == state.declarer or player == state.dummy) then
        worlds = 200
    end
    local ok, card = pcall(monteCarloPlay, state, player, worlds)
    if ok and card then return card end
    -- Engine hiccup (should not happen): fall back to the classic heuristic
    if difficulty == C.HARDER then
        return AI.harderPlay(hand, trick, trump, partner, state.played)
    end
    return AI.hardestPlay(hand, trick, trump, partner, state.played)
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
