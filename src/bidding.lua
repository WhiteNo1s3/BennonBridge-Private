-- Standard American Yellow-Card style bidding AI for Bridge.
--
-- Implements:
--   * Opening:  1NT (15-17 bal),  2NT (20-21 bal),  2C (22+ or 8.5 tricks),
--               1 of a suit (12-21), weak 2 / 3-level preempts
--   * Responses: Stayman (2C/1NT), Jacoby transfers, single & jump raises,
--                new suit forcing, 1NT response, jump shift, 2-over-1 GF
--   * Opener's rebid: minimum NT rebid, raise, jump rebid, reverse, 3NT
--   * Blackwood (4NT asking aces, 5NT asking kings)
--   * Overcalls (1-level 8+, 2-level 11+, 5+ suit) and Takeout doubles
--   * Negative doubles by responder
--   * Game / slam decisions from agreed fits and HCP totals
--
-- Public entry point:  B.chooseCall(game, player)
--   returns a call object: {type=C.CALL_BID, level, denom}
--                       or {type=C.CALL_PASS|C.CALL_DOUBLE|C.CALL_REDOUBLE}
--
-- The AI looks at: its own hand, the bids made so far by all four players,
-- partner's specific calls, opponent calls, and basic vulnerability-blind
-- judgment for game/slam decisions.

local C = require("src.constants")

local B = {}

-- ── Hand evaluation ────────────────────────────────────────────────────────

local function hcpOf(hand)
    local h = 0
    for _, c in ipairs(hand) do h = h + C.HCP[c.rank - 1] end
    return h
end

local function suitLengths(hand)
    -- Includes a dummy index 5 for NT lookups so `lens[denom]` is always safe
    -- (lens[NT] = 0; you can't have NT as a "suit" in your hand).
    local L = {0, 0, 0, 0, 0}
    for _, c in ipairs(hand) do L[c.suit] = L[c.suit] + 1 end
    return L
end

local function shape(lens)               -- sorted desc, e.g. {5,4,3,1}
    local s = {lens[1], lens[2], lens[3], lens[4]}
    table.sort(s, function(a, b) return a > b end)
    return s
end

local function isBalanced(lens)
    local sh = shape(lens)
    -- 4-3-3-3, 4-4-3-2, or 5-3-3-2 (no singleton/void)
    if sh[4] == 0 then return false end                -- void
    if sh[4] == 1 then return false end                -- singleton
    if sh[1] >= 6 then return false end                -- 6+ card suit
    return true
end

local function isSemiBalanced(lens)
    local sh = shape(lens)
    return (sh[1] <= 5 and sh[4] >= 2) or (sh[1] == 5 and sh[2] == 5)
end

local function longestMajor(lens)
    -- Return suit constant of longer major, or nil if no major has 5+
    local h, s = lens[C.HEARTS], lens[C.SPADES]
    if h >= 5 and h >= s then return C.BID_HEARTS, h end
    if s >= 5            then return C.BID_SPADES, s end
    return nil, 0
end

local function longestSuitForOpening(lens)
    -- Standard American "rule of 5-card majors":
    --   open 1 of a 5+ major
    --   no 5-card major: open longer minor; 4-4 minors -> diamonds, 3-3 -> clubs
    local maj, _ = longestMajor(lens)
    if maj then return maj end
    if lens[C.DIAMONDS] >= 4 and lens[C.DIAMONDS] >= lens[C.CLUBS] then
        return C.BID_DIAMONDS
    end
    if lens[C.CLUBS] >= 4 and lens[C.CLUBS] > lens[C.DIAMONDS] then
        return C.BID_CLUBS
    end
    -- 3-3 minors: clubs; 4-4 minors handled above
    if lens[C.DIAMONDS] == 3 and lens[C.CLUBS] == 3 then return C.BID_CLUBS end
    if lens[C.DIAMONDS] > lens[C.CLUBS] then return C.BID_DIAMONDS end
    return C.BID_CLUBS
end

-- Quick-trick / playing-trick count used to gate strong 2C openings
local function quickTricks(hand)
    -- 0.5 per K, 1 per AK; rough approximation
    local q = 0
    local byS = {{},{},{},{}}
    for _, c in ipairs(hand) do byS[c.suit][#byS[c.suit]+1] = c.rank end
    for s = 1, 4 do
        local has = {}
        for _, r in ipairs(byS[s]) do has[r] = true end
        if has[14] and has[13] then q = q + 2
        elseif has[14] and has[12] then q = q + 1.5
        elseif has[14] then q = q + 1
        elseif has[13] and has[12] then q = q + 1
        elseif has[13] then q = q + 0.5
        end
    end
    return q
end

-- ── Auction parsing helpers ───────────────────────────────────────────────

-- Has the auction been opened by someone other than `me`?
local function lastNonPassCall(auction)
    for i = #auction.bids, 1, -1 do
        local b = auction.bids[i]
        if b.call.type ~= C.CALL_PASS then return b end
    end
    return nil
end

-- The most recent BID (not double/redouble/pass) by any player
local function lastBid(auction)
    for i = #auction.bids, 1, -1 do
        local b = auction.bids[i]
        if b.call.type == C.CALL_BID then return b end
    end
    return nil
end

-- The most recent BID by a specific player (or nil)
local function lastBidBy(auction, player)
    for i = #auction.bids, 1, -1 do
        local b = auction.bids[i]
        if b.player == player and b.call.type == C.CALL_BID then return b end
    end
    return nil
end

-- The most recent BID by partner
local function partnerLastBid(auction, me)
    return lastBidBy(auction, C.PARTNER[me])
end

-- Has partner doubled? (most recent partner call is a double)
local function partnerDoubled(auction, me)
    local partner = C.PARTNER[me]
    for i = #auction.bids, 1, -1 do
        local b = auction.bids[i]
        if b.player == partner then
            return b.call.type == C.CALL_DOUBLE
        end
    end
    return false
end

-- True if I've already made any non-pass call
local function iHaveCalled(auction, me)
    for _, b in ipairs(auction.bids) do
        if b.player == me and b.call.type ~= C.CALL_PASS then return true end
    end
    return false
end

-- "Side" string for a player
local function sideOf(player)
    return (player == C.NORTH or player == C.SOUTH) and "NS" or "EW"
end

-- Has anyone on a side already bid?
local function sideHasBid(auction, side)
    for _, b in ipairs(auction.bids) do
        if b.call.type == C.CALL_BID and sideOf(b.player) == side then
            return true
        end
    end
    return false
end

-- Is a candidate bid level/denom legal given the current highBid?
local function isLegalBid(auction, level, denom)
    local hb = auction.highBid
    if not hb then return true end
    if level > hb.level then return true end
    if level == hb.level and denom > hb.denom then return true end
    return false
end

-- Build a bid call, but only if legal; otherwise return a Pass.
local function tryBid(auction, level, denom)
    if level < 1 or level > 7 then return {type = C.CALL_PASS} end
    if isLegalBid(auction, level, denom) then
        return {type = C.CALL_BID, level = level, denom = denom}
    end
    return {type = C.CALL_PASS}
end

-- ── Opening bids ──────────────────────────────────────────────────────────

local function chooseOpening(hand, hcp, lens)
    -- Strong 2C: 22+ HCP, or 21+ with very strong suits, or playing-tricks
    if hcp >= 22 then return {type=C.CALL_BID, level=2, denom=C.BID_CLUBS} end
    if hcp >= 21 and quickTricks(hand) >= 5 then
        return {type=C.CALL_BID, level=2, denom=C.BID_CLUBS}
    end

    -- 2NT: 20-21 balanced
    if hcp >= 20 and hcp <= 21 and isBalanced(lens) then
        return {type=C.CALL_BID, level=2, denom=C.BID_NT}
    end

    -- 1NT: 15-17 balanced
    if hcp >= 15 and hcp <= 17 and isBalanced(lens) then
        return {type=C.CALL_BID, level=1, denom=C.BID_NT}
    end

    -- Open 1 of a suit: 12-21 HCP
    if hcp >= 12 then
        local denom = longestSuitForOpening(lens)
        return {type=C.CALL_BID, level=1, denom=denom}
    end

    -- Weak 2: 5-11 HCP with a good 6-card suit in D/H/S
    if hcp >= 5 and hcp <= 11 then
        for _, suit in ipairs({C.BID_SPADES, C.BID_HEARTS, C.BID_DIAMONDS}) do
            if lens[suit] >= 6 then
                return {type=C.CALL_BID, level=2, denom=suit}
            end
        end
        -- 3-level preempt with 7+ card suit
        for _, suit in ipairs({C.BID_SPADES, C.BID_HEARTS, C.BID_DIAMONDS, C.BID_CLUBS}) do
            if lens[suit] >= 7 then
                return {type=C.CALL_BID, level=3, denom=suit}
            end
        end
    end

    return {type=C.CALL_PASS}
end

-- ── Response to 1NT (Stayman / Jacoby transfers) ──────────────────────────

local function respondTo1NT(auction, hand, hcp, lens)
    -- 0-7: pass unless we have a transferable major
    -- 8-9 invitational, 10-15 game, 16+ slam interest

    local hHearts = lens[C.HEARTS]
    local hSpades = lens[C.SPADES]
    local longMajor = math.max(hHearts, hSpades)

    -- Slam interest: 16+ HCP with no suit -> 4NT quantitative (we'll treat as
    -- Blackwood-asking for simplicity)
    if hcp >= 16 then
        return tryBid(auction, 4, C.BID_NT)
    end

    -- Game-forcing with 5+ major: Jacoby transfer
    if hcp >= 8 and hHearts >= 5 then
        return tryBid(auction, 2, C.BID_DIAMONDS)   -- transfer to hearts
    end
    if hcp >= 8 and hSpades >= 5 then
        return tryBid(auction, 2, C.BID_HEARTS)     -- transfer to spades
    end

    -- Stayman (asks 4-card major) with 8+ HCP and at least one 4-card major
    if hcp >= 8 and (hHearts >= 4 or hSpades >= 4) then
        return tryBid(auction, 2, C.BID_CLUBS)
    end

    -- 3NT with 10-15 balanced
    if hcp >= 10 and isBalanced(lens) then
        return tryBid(auction, 3, C.BID_NT)
    end

    -- 2NT invitational
    if hcp >= 8 and hcp <= 9 then
        return tryBid(auction, 2, C.BID_NT)
    end

    return {type = C.CALL_PASS}
end

-- Opener's rebid after Stayman 2C
local function rebidAfterStayman(auction, hand, hcp, lens)
    -- 4-card major -> bid it; longer major first
    if lens[C.SPADES] >= 4 and lens[C.SPADES] >= lens[C.HEARTS] then
        return tryBid(auction, 2, C.BID_SPADES)
    end
    if lens[C.HEARTS] >= 4 then
        return tryBid(auction, 2, C.BID_HEARTS)
    end
    return tryBid(auction, 2, C.BID_DIAMONDS)   -- no 4-card major
end

-- Opener completes a Jacoby transfer (must bid the major)
local function completeTransfer(auction, transferTo)
    return tryBid(auction, 2, transferTo)
end

-- ── Responses to 1 of a suit opening ──────────────────────────────────────

local function respondTo1Suit(auction, hand, hcp, lens, openerSuit)
    -- 0-5: Pass (unless we have a fit + shape for a preemptive raise)
    if hcp < 6 then return {type = C.CALL_PASS} end

    local isMajorOpening = (openerSuit == C.BID_HEARTS or openerSuit == C.BID_SPADES)
    local supportLen = lens[openerSuit] or 0

    -- Strong: 13+ HCP with support -> 2-over-1 GF or jump to game
    if hcp >= 13 then
        if isMajorOpening and supportLen >= 3 then
            -- Game raise with 4+ support, 12-15 HCP
            if supportLen >= 4 and hcp <= 15 then
                return tryBid(auction, 4, openerSuit)
            end
            -- Limit raise; conventionally: jump to 3M
            return tryBid(auction, 3, openerSuit)
        end
        -- 2-over-1 in new suit (need 4+ in that suit)
        for _, s in ipairs({C.BID_SPADES, C.BID_HEARTS, C.BID_DIAMONDS, C.BID_CLUBS}) do
            if s ~= openerSuit and lens[s] >= 4 then
                if s > openerSuit then
                    return tryBid(auction, 1, s)
                else
                    return tryBid(auction, 2, s)
                end
            end
        end
        -- 2NT or 3NT response with balanced
        if isBalanced(lens) then
            if hcp >= 13 and hcp <= 15 then return tryBid(auction, 2, C.BID_NT) end
            return tryBid(auction, 3, C.BID_NT)
        end
    end

    -- Limit raise 10-12 with 3+ (4+ for minor) support
    if isMajorOpening and supportLen >= 3 and hcp >= 10 and hcp <= 12 then
        return tryBid(auction, 3, openerSuit)
    end
    if not isMajorOpening and supportLen >= 4 and hcp >= 10 and hcp <= 12 then
        return tryBid(auction, 3, openerSuit)
    end

    -- Single raise 6-9 with support
    if isMajorOpening and supportLen >= 3 and hcp >= 6 and hcp <= 9 then
        return tryBid(auction, 2, openerSuit)
    end

    -- New suit at the 1-level (4+ cards, higher-ranking than opener's)
    for _, s in ipairs({C.BID_DIAMONDS, C.BID_HEARTS, C.BID_SPADES}) do
        if s > openerSuit and lens[s] >= 4 then
            return tryBid(auction, 1, s)
        end
    end

    -- 1NT response (6-9 HCP, no good suit, no fit)
    return tryBid(auction, 1, C.BID_NT)
end

-- ── Opener's rebid (after partner's 1-level response, no interference) ────

local function openerRebid(auction, me, hand, hcp, lens)
    -- Use our FIRST bid (the opening), not the latest one
    local myFirstBid
    for _, b in ipairs(auction.bids) do
        if b.player == me and b.call.type == C.CALL_BID then
            myFirstBid = b; break
        end
    end
    local pBid = partnerLastBid(auction, me)
    if not myFirstBid or not pBid then
        return {type = C.CALL_PASS}
    end
    local mySuit   = myFirstBid.call.denom
    local pSuit    = pBid.call.denom
    local pLen     = lens[pSuit] or 0

    -- If we opened 1NT and we're here, the response wasn't Stayman/transfer.
    -- Treat partner's response as natural: raise to game with extras, else pass.
    if mySuit == C.BID_NT then
        if pSuit == C.BID_NT then
            -- Partner invited / signed off in NT: raise with maximum, else pass
            if hcp >= 17 and pBid.call.level == 2 then
                return tryBid(auction, 3, C.BID_NT)
            end
            return {type = C.CALL_PASS}
        end
        -- Partner bid a major at 3-level (forcing to game): raise with 3-card fit
        if (pSuit == C.BID_HEARTS or pSuit == C.BID_SPADES) and pLen >= 3 then
            return tryBid(auction, 4, pSuit)
        end
        return tryBid(auction, 3, C.BID_NT)
    end

    -- Partner raised our suit -> add up & set level
    if pSuit == mySuit then
        local partnerLevel = pBid.call.level
        if partnerLevel == 2 and hcp >= 17 then     -- partner shows 6-9
            return tryBid(auction, partnerLevel + 1, mySuit)    -- invite
        end
        if partnerLevel == 3 and hcp >= 14 then     -- partner shows 10-12
            if mySuit == C.BID_HEARTS or mySuit == C.BID_SPADES then
                return tryBid(auction, 4, mySuit)
            end
            return tryBid(auction, 3, C.BID_NT)
        end
        if partnerLevel == 4 then
            return {type = C.CALL_PASS}
        end
        return {type = C.CALL_PASS}
    end

    -- Partner bid a new suit -> support / NT rebid / own suit rebid
    if pSuit ~= C.BID_NT and lens[pSuit] >= 4 then
        -- Raise partner's suit at lowest convenient level
        local raiseLevel = 2
        if hcp >= 17 then raiseLevel = 3 end
        if hcp >= 19 and (pSuit == C.BID_HEARTS or pSuit == C.BID_SPADES) then
            raiseLevel = 4
        end
        return tryBid(auction, raiseLevel, pSuit)
    end

    -- Rebid own suit if 6+
    if lens[mySuit] >= 6 then
        local lvl = 2
        if hcp >= 16 then lvl = 3 end
        return tryBid(auction, lvl, mySuit)
    end

    -- 1NT rebid (12-14 balanced equivalent)
    if isBalanced(lens) then
        if hcp >= 18 then return tryBid(auction, 2, C.BID_NT) end
        return tryBid(auction, 1, C.BID_NT)
    end

    -- Bid a new suit (4+ cards, lower-ranking than our first to avoid reversing
    -- on a minimum)
    for _, s in ipairs({C.BID_CLUBS, C.BID_DIAMONDS, C.BID_HEARTS, C.BID_SPADES}) do
        if s ~= mySuit and s ~= pSuit and lens[s] >= 4 then
            if hcp >= 17 or s < mySuit then    -- reverse needs extras
                return tryBid(auction, (s < mySuit) and 1 or 2, s)
            end
        end
    end

    return tryBid(auction, 1, C.BID_NT)
end

-- ── Overcalls and takeout doubles ─────────────────────────────────────────

local function overcallOrDouble(auction, me, hand, hcp, lens, oppBid)
    -- Takeout double: 12+ HCP, short in opp suit, support for unbid suits
    local oppSuit = oppBid.call.denom
    if hcp >= 13 and oppSuit ~= C.BID_NT and lens[oppSuit] <= 2 then
        local sumOthers = 0
        for s = 1, 4 do if s ~= oppSuit then sumOthers = sumOthers + lens[s] end end
        if sumOthers >= 9 then
            return {type = C.CALL_DOUBLE}
        end
    end

    -- 1-level overcall: 8-16 HCP, 5+ suit
    for _, s in ipairs({C.BID_SPADES, C.BID_HEARTS, C.BID_DIAMONDS, C.BID_CLUBS}) do
        if s ~= oppSuit and lens[s] >= 5 then
            local lvl = oppBid.call.level
            if s > oppBid.call.denom then
                -- Can stay at same level
            else
                lvl = lvl + 1
            end
            local needed = (lvl == 1) and 8 or 11
            if hcp >= needed and lvl <= 3 then
                return tryBid(auction, lvl, s)
            end
        end
    end

    -- 1NT overcall: 15-17 with stopper (we'll approximate "stopper" as length 3+
    -- or honor 10+ in opp suit)
    if hcp >= 15 and hcp <= 17 and isBalanced(lens) and oppBid.call.level == 1 then
        local hasStopper = false
        for _, c in ipairs(hand) do
            if c.suit == oppSuit and c.rank >= 11 then hasStopper = true end
        end
        if lens[oppSuit] >= 3 or hasStopper then
            return tryBid(auction, 1, C.BID_NT)
        end
    end

    return {type = C.CALL_PASS}
end

-- ── Slam-interest / Blackwood ─────────────────────────────────────────────

-- Count aces in hand
local function aceCount(hand)
    local a = 0
    for _, c in ipairs(hand) do if c.rank == 14 then a = a + 1 end end
    return a
end

local function kingCount(hand)
    local a = 0
    for _, c in ipairs(hand) do if c.rank == 13 then a = a + 1 end end
    return a
end

-- Response to Blackwood 4NT: 5C=0/4, 5D=1, 5H=2, 5S=3
local function blackwoodAceResponse(hand)
    local n = aceCount(hand)
    if n == 0 or n == 4 then return tryBid({highBid={level=4,denom=C.BID_NT}}, 5, C.BID_CLUBS) end
    if n == 1 then return {type=C.CALL_BID, level=5, denom=C.BID_DIAMONDS} end
    if n == 2 then return {type=C.CALL_BID, level=5, denom=C.BID_HEARTS} end
    return {type=C.CALL_BID, level=5, denom=C.BID_SPADES}
end

local function blackwoodKingResponse(hand)
    local n = kingCount(hand)
    if n == 0 or n == 4 then return {type=C.CALL_BID, level=6, denom=C.BID_CLUBS} end
    if n == 1 then return {type=C.CALL_BID, level=6, denom=C.BID_DIAMONDS} end
    if n == 2 then return {type=C.CALL_BID, level=6, denom=C.BID_HEARTS} end
    return {type=C.CALL_BID, level=6, denom=C.BID_SPADES}
end

-- Is partner's most recent bid 4NT in an auction that established a major fit?
local function partnerAskedBlackwood(auction, me)
    local p = partnerLastBid(auction, me)
    if not p then return false end
    if p.call.level ~= 4 or p.call.denom ~= C.BID_NT then return false end
    -- Look for an established major-suit agreement earlier in the auction
    for _, b in ipairs(auction.bids) do
        if b.call.type == C.CALL_BID and
           (b.call.denom == C.BID_HEARTS or b.call.denom == C.BID_SPADES) and
           sideOf(b.player) == sideOf(me) then
            return true
        end
    end
    return false
end

local function partnerAskedKings(auction, me)
    local p = partnerLastBid(auction, me)
    if not p then return false end
    return p.call.level == 5 and p.call.denom == C.BID_NT
end

-- ── Main entry point ──────────────────────────────────────────────────────

function B.chooseCall(game, me)
    local hand    = game.hands[me]
    local hcp     = hcpOf(hand)
    local lens    = suitLengths(hand)
    local auction = game.auction

    local pCall = partnerLastBid(auction, me)
    local lnp   = lastNonPassCall(auction)

    -- 1) Are we responding to Blackwood?
    if partnerAskedBlackwood(auction, me) then
        return blackwoodAceResponse(hand)
    end
    if partnerAskedKings(auction, me) then
        return blackwoodKingResponse(hand)
    end

    -- 2) Has the auction been opened at all?
    if not lnp then
        return chooseOpening(hand, hcp, lens)
    end

    -- 3) Did partner open? (Partner has a bid, no opponent has interfered yet)
    if pCall and not iHaveCalled(auction, me) then
        local pDenom = pCall.call.denom
        local pLvl   = pCall.call.level

        -- Partner opened 1NT
        if pLvl == 1 and pDenom == C.BID_NT then
            return respondTo1NT(auction, hand, hcp, lens)
        end

        -- Partner opened 2NT
        if pLvl == 2 and pDenom == C.BID_NT then
            if hcp >= 4 then return tryBid(auction, 3, C.BID_NT) end
            return {type = C.CALL_PASS}
        end

        -- Partner opened 2C (strong, forcing). Auto-2D waiting unless 8+ HCP.
        if pLvl == 2 and pDenom == C.BID_CLUBS then
            if hcp >= 8 then
                -- Show 5+ suit at the cheapest level, else 2NT
                for _, s in ipairs({C.BID_SPADES, C.BID_HEARTS, C.BID_DIAMONDS}) do
                    if lens[s] >= 5 then
                        return tryBid(auction, 2, s)
                    end
                end
                return tryBid(auction, 2, C.BID_NT)
            end
            return tryBid(auction, 2, C.BID_DIAMONDS)   -- waiting
        end

        -- Partner opened 1 of a suit
        if pLvl == 1 and pDenom <= 4 then
            return respondTo1Suit(auction, hand, hcp, lens, pDenom)
        end

        -- Partner preempted (2 or 3 of a suit) -> raise to game with a fit
        if pLvl >= 2 then
            local supportLen = lens[pDenom] or 0
            if (pDenom == C.BID_HEARTS or pDenom == C.BID_SPADES) and
               supportLen >= 3 and hcp >= 12 then
                return tryBid(auction, 4, pDenom)
            end
            return {type = C.CALL_PASS}
        end
    end

    -- 4) Opener's rebid: I opened, partner responded, opponents passed
    if iHaveCalled(auction, me) and pCall then
        -- Did we open? Check our first non-pass call
        local myFirst
        for _, b in ipairs(auction.bids) do
            if b.player == me and b.call.type == C.CALL_BID then
                myFirst = b; break
            end
        end
        if myFirst then
            -- After Stayman: partner asked 2C, we answer
            if pCall.call.level == 2 and pCall.call.denom == C.BID_CLUBS and
               myFirst.call.level == 1 and myFirst.call.denom == C.BID_NT then
                return rebidAfterStayman(auction, hand, hcp, lens)
            end
            -- After Jacoby transfer: must complete the transfer
            if myFirst.call.level == 1 and myFirst.call.denom == C.BID_NT then
                if pCall.call.level == 2 and pCall.call.denom == C.BID_DIAMONDS then
                    return completeTransfer(auction, C.BID_HEARTS)
                end
                if pCall.call.level == 2 and pCall.call.denom == C.BID_HEARTS then
                    return completeTransfer(auction, C.BID_SPADES)
                end
            end
            -- General rebid
            return openerRebid(auction, me, hand, hcp, lens)
        end
    end

    -- 5) Opponent opened: overcall / takeout double
    if lnp and sideOf(lnp.player) ~= sideOf(me) and
       lnp.call.type == C.CALL_BID and not iHaveCalled(auction, me) then
        return overcallOrDouble(auction, me, hand, hcp, lens, lnp)
    end

    -- 6) Default: pass
    return {type = C.CALL_PASS}
end

return B
