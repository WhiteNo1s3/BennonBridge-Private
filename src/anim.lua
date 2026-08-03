-- Animation system for Bridge.
--
-- Currently drives the deal animation:
--   * For each of the 52 cards we compute a destination (the position the
--     card will eventually occupy inside its owner's fanned hand on the
--     felt) and a start delay (cards are dealt one at a time, very fast,
--     clockwise from the dealer).
--   * Each frame we advance every "in flight" card from the deck pile to
--     its destination. Active cards play a "cardgive" sound the moment
--     they enter flight.
--   * When the last card finishes its arc, the animation is "done" and the
--     caller (Game) transitions out of STATE_DEALING.

local C  = require("src.constants")
local S  = require("src.sound")

local A = {}

A.enabled = true        -- "intro animation" master toggle (settings)

-- Public state used by the renderer
A.active           = false
A.cards            = {}       -- per-card animation records (52 of them)
A.elapsed          = 0
A.totalDuration    = 0

-- Tunables -------------------------------------------------------------------
local CARD_TIME    = 0.16     -- per-card flight time (linear interp)
local CARD_DELAY   = 0.04     -- stagger between successive deals
local SOUND_PITCH  = 2.6      -- speedy "tick" for each card

-- Deal flourish (purely visual; cards still land EXACTLY on their slot).
-- Both effects are 0 at t=0 and t=1, so the start pile and final fan are
-- untouched — only the path between them gets nicer.
local DEAL_ARC     = 28       -- px the card lifts at mid-flight (parabolic hop)
local DEAL_SPIN    = 0.30     -- radians of extra twirl that eases out on landing

-- Where the dealer pile sits before the deal
A.DECK_X = C.SW / 2
A.DECK_Y = C.SH / 2

-- Destination positions for each card in a horizontal/vertical fan.
-- These mirror the placement logic in render.drawHorizHand /drawVertHand so
-- the cards land exactly where they'll sit during play. Refreshed from
-- render's live metrics at the start of every deal, because the card-size
-- slider can change them at any time.
local CARD_W       = C.CARD_W
local CARD_H       = C.CARD_H
local OVERLAP      = C.CARD_OVERLAP
local SIDE_X       = C.CARD_H / 2 + 8

-- Both return the CENTRE of the slot's card (drawDealing rotates around the
-- centre), mirroring render.drawHorizHand / drawVertHand exactly:
--   horiz:  x = baseX - span/2 + (i-1)*OV  (top-left)  → centre adds CARD_W/2
--   vert:   cy = baseY - span/2 + (i-1)*OV + CARD_W/2  for BOTH East and West
-- (The old version ran West's fan upward and returned edge coords — cards
-- landed mirrored/half-a-card off, then snapped when the real hand drew.)
local function horizFanXY(baseCX, baseCY, slot, total, w, ov)
    w, ov = w or CARD_W, ov or OVERLAP
    local span = (total - 1) * ov + w
    return baseCX - span/2 + (slot - 1) * ov + w/2, baseCY
end

local function vertFanXY(baseCX, baseCY, slot, total, w, ov)
    w, ov = w or CARD_W, ov or OVERLAP
    local span = (total - 1) * ov + w
    return baseCX, baseCY - span/2 + (slot - 1) * ov + w/2
end

-- Public: start a fresh deal animation for the four hands.
-- `hands`: array indexed 1..4, each a table of 13 card descriptors {rank,suit}.
-- `dealer`: which player gets the first card; we then proceed clockwise.
function A.startDeal(hands, dealer)
    A.active        = true
    A.elapsed       = 0
    A.cards         = {}

    -- Pull current card metrics from the renderer (lazy require: render also
    -- lazy-requires this module, so neither top-level requires the other).
    local R = require("src.render")
    if R.metrics then
        CARD_W, CARD_H, OVERLAP, SIDE_X = R.metrics()
    end

    -- Build the destination for every card. Then build the per-card animation
    -- entries in deal order: dealer's LHO gets nothing first; we deal from
    -- dealer's LHO clockwise. Actually in bridge the dealer deals one card at
    -- a time starting with their LHO. We'll just deal in clockwise order from
    -- the dealer's LHO for visual flavour.
    local order = {C.NEXT[dealer], C.NEXT[C.NEXT[dealer]],
                   C.NEXT[C.NEXT[C.NEXT[dealer]]], dealer}

    -- Player position centers + orientation (matches render).
    -- PHONE: every seat is a real fan — the three AI seats hold card backs
    -- at the table edges (render's PH.side_w metric: 0.64× the base card),
    -- South fans big across the bottom (PH.south_w: 1.33×, widened overlap).
    -- These mirror render.lua's phone drawGame anchors exactly, so cards
    -- land on the very slots they'll occupy during play.
    local posOf
    if C.PHONE then
        local backW  = math.floor(CARD_W * C.PHONE_SIDE_SCALE + 0.5)
        local backH  = math.floor(backW * (134 / 96) + 0.5)
        local backOV = math.max(12, math.floor(backW * (32 / 96) + 0.5))
        local sideX  = backH/2 + 8
        local sW     = math.floor(CARD_W * C.PHONE_SOUTH_SCALE + 0.5)
        local sH     = math.floor(sW * (134 / 96) + 0.5)
        local sOV    = math.max(12, math.floor(sW * (32 / 96) + 0.5))
        sOV = math.max(sOV, math.min(84, math.floor((C.SW * 0.84 - sW) / 12)))
        -- North lands in the AUCTION screen's compact top-right fan (the
        -- auction is the very next screen after the deal); the other three
        -- land on their shared auction/play anchors.
        posOf = {
            [C.NORTH] = {cx = C.SW - 150,         cy = 100 + backH/2,     angle = 0,         horiz = true,  w = backW, ov = 14},
            [C.SOUTH] = {cx = C.SW/2,             cy = C.SH - 12 - sH/2,  angle = 0,         horiz = true,  w = sW,    ov = sOV},
            [C.EAST]  = {cx = C.SW - sideX - 10,  cy = C.SH/2 + 42,       angle = math.pi/2, horiz = false, w = backW, ov = backOV},
            [C.WEST]  = {cx = sideX + 10,         cy = C.SH/2 + 42,       angle =-math.pi/2, horiz = false, w = backW, ov = backOV},
        }
    else
        -- Desktop: mirrors render.lua's AUCTION anchors (the next screen) —
        -- South full-size bottom, the three AI seats as COMPACT fans of
        -- backs (0.58× cards, tight overlap), so dealt cards land exactly
        -- on the slots they'll occupy.
        local backW  = math.floor(CARD_W * 0.58 + 0.5)
        local backH  = math.floor(backW * (134 / 96) + 0.5)
        local sideCX = backH/2 + 8 + 6
        posOf = {
            [C.NORTH] = {cx = C.SW/2,         cy = 48 + backH/2,          angle = 0,         horiz = true,  w = backW,  ov = 14},
            [C.SOUTH] = {cx = C.SW/2,         cy = C.SH - 18 - CARD_H/2,  angle = 0,         horiz = true,  w = CARD_W, ov = OVERLAP},
            [C.EAST]  = {cx = C.SW - sideCX,  cy = C.SH/2,                angle = math.pi/2, horiz = false, w = backW,  ov = 14},
            [C.WEST]  = {cx = sideCX,         cy = C.SH/2,                angle =-math.pi/2, horiz = false, w = backW,  ov = 14},
        }
    end

    -- Issue cards one at a time, advancing the player after each
    local slots = {[1] = 0, [2] = 0, [3] = 0, [4] = 0}
    local pIdx  = 1
    local total = 52
    for i = 1, total do
        local player = order[((i - 1) % 4) + 1]
        slots[player] = slots[player] + 1

        local pos = posOf[player]
        local toX, toY
        if pos.horiz then
            toX, toY = horizFanXY(pos.cx, pos.cy, slots[player], 13, pos.w, pos.ov)
        else
            toX, toY = vertFanXY(pos.cx, pos.cy, slots[player], 13, pos.w, pos.ov)
        end

        A.cards[i] = {
            player = player,
            slot   = slots[player],
            fromX  = A.DECK_X,
            fromY  = A.DECK_Y,
            toX    = toX,
            toY    = toY,
            angle  = pos.angle,
            delay  = (i - 1) * CARD_DELAY,
            t      = 0,           -- 0..1 interpolation
            started = false,      -- track sound trigger
            done    = false,
        }
    end

    A.totalDuration = (total - 1) * CARD_DELAY + CARD_TIME + 0.10
end

function A.update(dt)
    if not A.active then return end
    A.elapsed = A.elapsed + dt

    local allDone = true
    for _, c in ipairs(A.cards) do
        local local_t = A.elapsed - c.delay
        if local_t >= 0 and not c.started then
            c.started = true
            S.playCardGive(SOUND_PITCH)
        end
        if local_t >= CARD_TIME then
            c.t    = 1
            c.done = true
        elseif local_t > 0 then
            c.t = local_t / CARD_TIME
            allDone = false
        else
            allDone = false      -- not yet started
        end
    end

    if allDone or A.elapsed >= A.totalDuration then
        A.active = false
    end
end

-- Returns true if a deal animation is currently running.
function A.isDealing()
    return A.active
end

-- Current (x, y, angle) for card i during the deal. The renderer queries this
-- to draw the card back at the interpolated position.
function A.cardPos(i)
    local c = A.cards[i]
    if not c then return nil end
    -- Ease-out so the card decelerates as it lands
    local t = c.t
    local e = 1 - (1 - t) * (1 - t)
    local x = c.fromX + (c.toX - c.fromX) * e
    local y = c.fromY + (c.toY - c.fromY) * e
    -- Parabolic hop: peaks at mid-flight, exactly 0 at the pile and the slot.
    y = y - math.sin(t * math.pi) * DEAL_ARC
    -- Twirl that eases out to the card's final angle; direction follows travel.
    local dir = (c.toX >= c.fromX) and 1 or -1
    local angle = c.angle + (1 - e) * DEAL_SPIN * dir
    return x, y, angle, c.player
end

return A
