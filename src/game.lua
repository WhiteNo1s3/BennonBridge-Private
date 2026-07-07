-- Core game state and logic for Contract Bridge

local C    = require("src.constants")
local Deck = require("src.deck")
local AI   = require("src.ai")
local B    = require("src.bidding")
local A    = require("src.anim")
local S    = require("src.sound")

local Game = {}
Game.__index = Game

function Game.new()
    local g = setmetatable({}, Game)
    g.state        = C.STATE_MENU
    g.seed         = 1
    g.sessionScore = {0, 0}    -- [1]=NS, [2]=EW
    g.matchWins    = {0, 0}    -- [1]=NS wins, [2]=EW wins in a 7-board match
    g.difficulty   = {C.MEDIUM, C.MEDIUM, C.MEDIUM, C.MEDIUM}
    g.aiTimer      = 0
    g.aiDelay      = 0.75      -- seconds between AI actions
    g.trickLinger  = 1.4       -- completed trick stays on the table this long
    return g
end

-- ── Dealing ────────────────────────────────────────────────────────────────

function Game:deal(seed)
    self.seed  = seed
    self.hands = Deck.deal(seed)

    self.hcp = {}
    for p = 1, 4 do self.hcp[p] = Deck.countHCP(self.hands[p]) end

    -- Reset play state (declarer/dummy/contract come from the auction now)
    self.declarer      = nil
    self.dummy         = nil
    self.declaringSide = nil
    self.contract      = nil
    self.trumpSuit     = nil
    self.contractTricks= nil
    self.currentTrick  = {}
    self.trickCount    = 0
    self.tricksDeclarer= 0
    self.tricksDefender= 0
    self.lastTrick     = nil
    self.lastWinner    = nil
    self.handResult    = nil
    self.humanWon      = nil
    self.played        = {}
    self.aiTimer       = 0
    self.leader        = nil
    self.currentPlayer = nil

    -- Snapshot of every hand as dealt (used for the "show original hands"
    -- panel on the loss screen).
    self.initialHands = {}
    for p = 1, 4 do
        self.initialHands[p] = {}
        for i, c in ipairs(self.hands[p]) do
            self.initialHands[p][i] = {rank = c.rank, suit = c.suit}
        end
    end

    -- Rotating dealer: hand 1 = North, hand 2 = East, hand 3 = South, ...
    local dealer = ((seed - 1) % 4) + 1

    self.auction = {
        bids               = {},     -- chronological list of {player, call}
        dealer             = dealer,
        currentBidder      = dealer,
        highBid            = nil,    -- {level, denom, bidder}
        doubled            = false,
        redoubled          = false,
        finished           = false,
        consecutivePasses  = 0,
        allPassed          = false,
        contractDoubler    = nil,
        contractRedoubler  = nil,
    }

    -- Kick off the deal animation if intro animations are enabled.
    if A.enabled then
        S.playStartGame()
        A.startDeal(self.hands, dealer)
        self.state = C.STATE_DEALING
    else
        self.state = C.STATE_AUCTION
    end
end

-- Called from love.update while the deal animation is running.
function Game:_updateDealing(dt)
    A.update(dt)
    if not A.isDealing() then
        self.state = C.STATE_AUCTION
        self.aiTimer = 0
    end
end

-- ── Auction ────────────────────────────────────────────────────────────────

-- Is the given call legal for the player whose turn it currently is?
function Game:isLegalCall(call)
    local a = self.auction
    if not a or a.finished then return false end
    if call.type == C.CALL_PASS then return true end

    if call.type == C.CALL_BID then
        if call.level < 1 or call.level > 7 then return false end
        if call.denom < 1 or call.denom > 5 then return false end
        if not a.highBid then return true end
        if call.level > a.highBid.level then return true end
        if call.level == a.highBid.level and call.denom > a.highBid.denom then
            return true
        end
        return false
    end

    local me = a.currentBidder
    local mySide = (me == C.NORTH or me == C.SOUTH) and "NS" or "EW"

    if call.type == C.CALL_DOUBLE then
        if not a.highBid then return false end
        if a.doubled or a.redoubled then return false end
        local oppSide = (a.highBid.bidder == C.NORTH or a.highBid.bidder == C.SOUTH)
                        and "NS" or "EW"
        return mySide ~= oppSide
    end

    if call.type == C.CALL_REDOUBLE then
        if not a.highBid then return false end
        if not a.doubled or a.redoubled then return false end
        local hbSide = (a.highBid.bidder == C.NORTH or a.highBid.bidder == C.SOUTH)
                        and "NS" or "EW"
        return mySide == hbSide
    end

    return false
end

-- Record a call by the current bidder.  Returns true if accepted.
function Game:makeCall(call)
    if not self:isLegalCall(call) then return false end
    local a = self.auction
    local me = a.currentBidder

    table.insert(a.bids, {player = me, call = call})

    if call.type == C.CALL_BID then
        a.highBid = {level = call.level, denom = call.denom, bidder = me}
        a.doubled, a.redoubled = false, false
        a.contractDoubler, a.contractRedoubler = nil, nil
        a.consecutivePasses = 0
    elseif call.type == C.CALL_DOUBLE then
        a.doubled = true
        a.contractDoubler = me
        a.consecutivePasses = 0
    elseif call.type == C.CALL_REDOUBLE then
        a.redoubled = true
        a.contractRedoubler = me
        a.consecutivePasses = 0
    else -- pass
        a.consecutivePasses = a.consecutivePasses + 1
    end

    -- Auction ends: 3 consecutive passes after any bid, or 4 passes if no bid
    if a.highBid and a.consecutivePasses >= 3 then
        a.finished = true
        self:_finalizeAuction()
        return true
    end
    if not a.highBid and a.consecutivePasses >= 4 then
        a.finished   = true
        a.allPassed  = true
        -- Passed-out hand: re-deal automatically with seed+1
        self:deal((self.seed or 1) + 1)
        return true
    end

    a.currentBidder = C.NEXT[a.currentBidder]
    return true
end

function Game:_finalizeAuction()
    local a  = self.auction
    local hb = a.highBid
    if not hb then return end

    local winnerSide = (hb.bidder == C.NORTH or hb.bidder == C.SOUTH) and "NS" or "EW"

    -- Declarer: first player on the winning side who bid the final denomination
    local declarer = hb.bidder
    for _, b in ipairs(a.bids) do
        if b.call.type == C.CALL_BID and b.call.denom == hb.denom then
            local bSide = (b.player == C.NORTH or b.player == C.SOUTH) and "NS" or "EW"
            if bSide == winnerSide then declarer = b.player; break end
        end
    end

    self.declaringSide   = winnerSide
    self.declarer        = declarer
    self.dummy           = C.PARTNER[declarer]
    self.contract        = {suit = hb.denom, tricks = hb.level + 6}
    self.trumpSuit       = (hb.denom ~= C.BID_NT) and hb.denom or nil
    self.contractTricks  = self.contract.tricks
    self.contractDoubled   = a.doubled
    self.contractRedoubled = a.redoubled

    self.leader        = C.LHO[self.declarer]
    self.currentPlayer = self.leader
    self.state         = C.STATE_PLAYING
    self.aiTimer       = 0
end

-- Called when the human places a call from the bidding box.
function Game:humanCall(call)
    if self.state ~= C.STATE_AUCTION then return false end
    if self.auction.currentBidder ~= C.SOUTH then return false end
    return self:makeCall(call)
end

-- Auction update: AI players call on a timer
function Game:_updateAuction(dt)
    if self.auction.finished then return end
    local cur = self.auction.currentBidder

    -- Wait for human input unless playtest mode
    local humanTurn = (cur == C.SOUTH) and not self.autoSouth
    if humanTurn then return end

    self.aiTimer = self.aiTimer + dt
    if self.aiTimer < C.AUCTION_AI_DELAY then return end
    self.aiTimer = 0

    local call = B.chooseCall(self, cur)
    -- Sanity check; if the AI produced an illegal call, fall back to pass
    if not self:isLegalCall(call) then call = {type = C.CALL_PASS} end
    self:makeCall(call)
end

-- ── Contract ───────────────────────────────────────────────────────────────

function Game:setContract(contract)
    self.contract       = contract
    self.trumpSuit      = (contract.suit ~= C.NO_TRUMP) and contract.suit or nil
    self.contractTricks = contract.tricks
    self.currentPlayer  = self.leader
    self.currentTrick   = {}
    self.state          = C.STATE_PLAYING
    self.aiTimer        = 0
end

-- Auto-suggest best contract for human declarer
function Game:suggestContract()
    return AI.chooseContract(
        self.hands[self.declarer],
        self.hands[self.dummy],
        self.totalDeclHCP
    )
end

-- ── Update loop ────────────────────────────────────────────────────────────

function Game:update(dt)
    if self.state == C.STATE_DEALING then
        self:_updateDealing(dt)
    elseif self.state == C.STATE_AUCTION then
        self:_updateAuction(dt)
    elseif self.state == C.STATE_PLAYING then
        self:_updatePlaying(dt)
    elseif self.state == C.STATE_TRICK_END then
        self:_updateTrickEnd(dt)
    elseif self.state == C.STATE_RESULT then
        -- Auto-advance handled cohesively in main.lua
    end
end

function Game:_isHumanTurn(player)
    -- Playtest mode: AI plays everyone, including the human seat.
    if self.autoSouth then return false end

    -- South is always human.
    -- When South is declarer, human also clicks dummy (North).
    -- When South is dummy (North declares), AI plays South's cards too.
    if self.declaringSide == "NS" then
        if self.declarer == C.SOUTH then
            return player == C.SOUTH or player == self.dummy
        else
            return false   -- South is dummy; North AI controls everything
        end
    else
        -- EW declares; South is a defender
        return player == C.SOUTH
    end
end

function Game:_updatePlaying(dt)
    local p = self.currentPlayer
    if p == nil then return end
    if self:_isHumanTurn(p) then return end   -- wait for mouse click

    self.aiTimer = self.aiTimer + dt
    if self.aiTimer < self.aiDelay then return end
    self.aiTimer = 0

    local diff = self.difficulty[p]
    -- Dummy is played by its declarer at declarer's difficulty
    if p == self.dummy then diff = self.difficulty[self.declarer] end

    local card = AI.chooseCard(self, p, diff)
    self:_playCard(p, card)
end

function Game:_updateTrickEnd(dt)
    -- Let the completed trick sit on the table long enough to read all four
    -- cards before they're swept (longer than the AI play cadence on purpose).
    self.aiTimer = self.aiTimer + dt
    if self.aiTimer < (self.trickLinger or self.aiDelay) then return end
    self.aiTimer = 0
    self:_startNextTrick()
end

-- ── Card play ──────────────────────────────────────────────────────────────

function Game:humanPlay(card)
    if self.state ~= C.STATE_PLAYING then return end
    local p = self.currentPlayer
    if not self:_isHumanTurn(p) then return end

    -- Validate legality
    local ledSuit = (#self.currentTrick > 0) and self.currentTrick[1].card.suit or nil
    local legal   = AI.legalCards(self.hands[p], ledSuit)
    for _, lc in ipairs(legal) do
        if lc.suit == card.suit and lc.rank == card.rank then
            self.aiTimer = 0
            self:_playCard(p, card)
            return
        end
    end
end

function Game:_playCard(player, card)
    Deck.removeCard(self.hands[player], card)
    self.currentTrick[#self.currentTrick+1] = {player=player, card=card}
    self.played[#self.played+1] = {player=player, card=card}
    -- Soft card-on-felt tick for every play (deal uses a faster 2.6 pitch;
    -- this slower one reads as a deliberate "placing" sound).
    S.playCardGive(1.15)

    if #self.currentTrick == 4 then
        self:_completeTrick()
    else
        self.currentPlayer = C.NEXT[self.currentPlayer]
    end
end

function Game:_completeTrick()
    local wi     = AI.trickWinnerIdx(self.currentTrick, self.trumpSuit)
    local winner = self.currentTrick[wi].player

    if winner == self.declarer or winner == self.dummy then
        self.tricksDeclarer = self.tricksDeclarer + 1
    else
        self.tricksDefender = self.tricksDefender + 1
    end

    self.trickCount  = self.trickCount + 1
    self.lastTrick   = self.currentTrick
    self.lastWinner  = winner

    if self.trickCount == 13 then
        self:_endHand()
    else
        self.pendingLeader = winner
        self.state         = C.STATE_TRICK_END
        self.aiTimer       = 0
    end
end

function Game:_startNextTrick()
    self.currentPlayer = self.pendingLeader
    self.currentTrick  = {}
    self.state         = C.STATE_PLAYING
    self.aiTimer       = 0
end

-- ── Scoring ────────────────────────────────────────────────────────────────

function Game:_endHand()
    local made   = self.tricksDeclarer
    local needed = self.contractTricks
    local suit   = self.contract.suit

    local result = {}

    if made >= needed then
        -- Base 50 + trick points for all tricks above 6
        local pts = 50
        local tricksAbove6 = made - 6
        if suit == C.NO_TRUMP then
            pts = pts + 10 + tricksAbove6 * 30
        elseif suit == C.HEARTS or suit == C.SPADES then
            pts = pts + tricksAbove6 * 30
        else
            pts = pts + tricksAbove6 * 20
        end

        -- Game bonus if bid to game level
        local gameLevel = C.GAME_TRICKS[suit]
        if needed >= gameLevel then pts = pts + 250 end

        result.declarerWins = true
        result.points       = pts
        result.desc = string.format(
            "Made! %d/%d tricks — %d pts to %s",
            made, needed, pts, self.declaringSide)
    else
        local down = needed - made
        local pts  = down * 50

        result.declarerWins = false
        result.points       = pts
        result.desc = string.format(
            "Down %d (%d/%d tricks) — %d pts to %s",
            down, made, needed, pts,
            self.declaringSide == "NS" and "EW" or "NS")
    end

    self.handResult = result

    if result.declarerWins then
        local idx = (self.declaringSide == "NS") and 1 or 2
        self.sessionScore[idx] = self.sessionScore[idx] + result.points
        self.matchWins = self.matchWins or {0, 0}
        self.matchWins[idx] = self.matchWins[idx] + 1
    else
        local idx = (self.declaringSide == "NS") and 2 or 1
        self.sessionScore[idx] = self.sessionScore[idx] + result.points
        self.matchWins = self.matchWins or {0, 0}
        self.matchWins[idx] = self.matchWins[idx] + 1
    end

    -- The human is South (NS partnership). They win if their side scored
    -- the points, regardless of whether they were declaring or defending.
    local humanSideIsDeclaring = (self.declaringSide == "NS")
    self.humanWon = (humanSideIsDeclaring == result.declarerWins)

    -- Capture board details
    if self.matchMode == "7board" then
        self.matchBoardDetails = self.matchBoardDetails or {}
        local winnerSide = result.declarerWins and self.declaringSide or (self.declaringSide == "NS" and "EW" or "NS")
        self.matchBoardDetails[self.matchBoard or 1] = {
            board = self.matchBoard or 1,
            seed = self.seed,
            contract = self.contract and {suit = self.contract.suit, tricks = self.contract.tricks} or nil,
            contractTricks = self.contractTricks,
            contractDoubled = self.contractDoubled,
            contractRedoubled = self.contractRedoubled,
            declarer = self.declarer,
            tricksDeclarer = self.tricksDeclarer,
            points = result.points,
            winnerSide = winnerSide
        }
    end

    self.state = C.STATE_RESULT
end

return Game
