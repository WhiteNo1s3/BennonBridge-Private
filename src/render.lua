-- All rendering for the Bridge game

local C    = require("src.constants")
local AI   = require("src.ai")

local R = {}

-- ── Palette ────────────────────────────────────────────────────────────────
local PAL = {
    felt        = {0.12, 0.42, 0.14},
    felt_inner  = {0.10, 0.38, 0.12},
    card_face   = {1.00, 0.99, 0.97},
    card_back_a = {0.15, 0.25, 0.72},
    card_back_b = {0.10, 0.18, 0.60},
    card_border = {0.55, 0.55, 0.55},
    shadow      = {0, 0, 0, 0.30},
    black_suit  = {0.06, 0.06, 0.06},
    red_suit    = {0.82, 0.08, 0.08},
    panel       = {0.04, 0.04, 0.04, 0.72},
    panel_light = {0.12, 0.12, 0.12, 0.80},
    white       = {1, 1, 1},
    yellow      = {1.00, 0.92, 0.20},
    green_hi    = {0.20, 1.00, 0.30, 0.45},
    gold_hi     = {1.00, 0.88, 0.10, 0.55},
    btn_blue    = {0.18, 0.40, 0.82},
    btn_hover   = {0.28, 0.52, 0.95},
    btn_green   = {0.15, 0.60, 0.22},
    btn_green_h = {0.22, 0.78, 0.30},
    btn_red     = {0.70, 0.15, 0.12},
    dim         = {0, 0, 0, 0.45},
    text_dim    = {0.70, 0.70, 0.70},
}

local CW = C.CARD_W
local CH = C.CARD_H
local CR = C.CARD_RADIUS

local fonts = {}
-- Loaded card-face images: cardImg[rank][suit] = Image | nil
local cardImg = {}
-- Loaded card-back images, in theme order (1..N). currentBack picks one.
local cardBacks = {}
local currentBack = nil   -- Image | nil
R.BACK_COUNT = 0          -- how many themes the user can cycle through

-- Confetti particle system (triggered on a winning result)
local confetti = { particles = {}, active = false, spawnFor = 0 }
local CONFETTI_COLORS = {
    {1.00, 0.30, 0.30}, {1.00, 0.78, 0.20}, {0.30, 0.85, 0.45},
    {0.35, 0.65, 1.00}, {0.95, 0.45, 0.95}, {1.00, 1.00, 0.45},
}

-- Track the previous game state so we can fire confetti on entering RESULT
local prevState = nil

-- ── Hover-animation state (forward declarations so R.update can prune) ─────
-- The actual button() implementation that mutates these lives further down.
local hoverProgress = {}      -- [key] = 0..1
local hoverSeen     = {}      -- [key] = true (this frame)
local HOVER_SPEED   = 12      -- per-second easing rate (≈ 80 ms to settle)

local function pruneHoverState()
    for k in pairs(hoverProgress) do
        if not hoverSeen[k] then hoverProgress[k] = nil end
    end
    hoverSeen = {}
end

function R.load()
    fonts.tiny   = love.graphics.newFont(11)
    fonts.small  = love.graphics.newFont(13)
    fonts.med    = love.graphics.newFont(16)
    fonts.large  = love.graphics.newFont(22)
    fonts.huge   = love.graphics.newFont(34)
    fonts.title  = love.graphics.newFont(64)
    fonts.cardRk = love.graphics.newFont(13)
    fonts.cardFace = love.graphics.newFont(34)

    -- All 52 cards are now rasterized as PNGs in assets/cards
    for r = 2, 14 do
        cardImg[r] = {}
        for s = 1, 4 do
            local path = string.format("assets/cards/r%d_s%d.png", r, s)
            if love.filesystem.getInfo(path) then
                local img = love.graphics.newImage(path)
                img:setFilter("linear", "linear")
                cardImg[r][s] = img
            end
        end
    end

    -- Card backs from both theme folders, sorted by their leading digit
    local function loadBacksFrom(dir)
        if not love.filesystem.getInfo(dir) then return end
        local files = love.filesystem.getDirectoryItems(dir)
        table.sort(files)
        for _, f in ipairs(files) do
            if f:match("%.png$") then
                local img = love.graphics.newImage(dir .. "/" .. f)
                img:setFilter("linear", "linear")
                cardBacks[#cardBacks + 1] = img
            end
        end
    end
    loadBacksFrom("assets/card_backs")
    loadBacksFrom("assets/card_backs_thematic")
    R.BACK_COUNT = #cardBacks
    currentBack  = cardBacks[1]
end

function R.setBackTheme(idx)
    if #cardBacks == 0 then return end
    idx = ((idx - 1) % #cardBacks) + 1
    currentBack = cardBacks[idx]
end

-- ── Confetti ──────────────────────────────────────────────────────────────
local function spawnConfettiBurst()
    confetti.active   = true
    confetti.spawnFor = 6.0   -- spawn for 6s; particles linger ~2-3s after
end

function R.update(dt)
    -- Discard stale per-button hover progress every frame (cheap, ~tens of keys)
    pruneHoverState()

    if not confetti.active then return end
    if confetti.spawnFor > 0 then
        confetti.spawnFor = confetti.spawnFor - dt
        for _ = 1, 4 do
            confetti.particles[#confetti.particles+1] = {
                x   = love.math.random() * C.SW,
                y   = -20,
                vx  = (love.math.random() - 0.5) * 160,
                vy  = 80 + love.math.random() * 160,
                rot = love.math.random() * math.pi * 2,
                rotV= (love.math.random() - 0.5) * 12,
                col = CONFETTI_COLORS[love.math.random(#CONFETTI_COLORS)],
                size= 6 + love.math.random() * 8,
                life= 4 + love.math.random() * 3,
            }
        end
    end
    for i = #confetti.particles, 1, -1 do
        local p = confetti.particles[i]
        p.vy   = p.vy + 380 * dt          -- gravity
        p.vx   = p.vx * (1 - dt * 0.4)
        p.x    = p.x + p.vx * dt
        p.y    = p.y + p.vy * dt
        p.rot  = p.rot + p.rotV * dt
        p.life = p.life - dt
        if p.life <= 0 or p.y > C.SH + 40 then
            table.remove(confetti.particles, i)
        end
    end
    if confetti.spawnFor <= 0 and #confetti.particles == 0 then
        confetti.active = false
    end
end

local function drawConfetti()
    if not confetti.active then return end
    for _, p in ipairs(confetti.particles) do
        love.graphics.push()
        love.graphics.translate(p.x, p.y)
        love.graphics.rotate(p.rot)
        love.graphics.setColor(p.col[1], p.col[2], p.col[3], math.min(1, p.life/1.5))
        love.graphics.rectangle("fill", -p.size/2, -p.size/3, p.size, p.size*0.5, 1)
        love.graphics.pop()
    end
end

-- Called by drawResult on state-entry to trigger celebrations.
local function maybeStartConfetti(humanWon, currentState)
    if currentState == C.STATE_RESULT and prevState ~= C.STATE_RESULT then
        if humanWon then
            confetti.particles = {}
            spawnConfettiBurst()
        else
            confetti.active = false
            confetti.particles = {}
        end
    end
    prevState = currentState
end

-- ── Low-level helpers ──────────────────────────────────────────────────────

-- Accepts either setColor(tableRGBA [, alpha]) or setColor(r, g, b [, a])
local function setColor(a, b, c, d)
    if type(a) == "table" then
        if b then
            love.graphics.setColor(a[1], a[2], a[3], b)
        else
            love.graphics.setColor(a)
        end
    else
        love.graphics.setColor(a, b, c, d)
    end
end

local function centredText(font, text, cx, cy)
    love.graphics.setFont(font)
    local tw = font:getWidth(text)
    local th = font:getHeight()
    love.graphics.print(text, cx - tw/2, cy - th/2)
end

-- ── Modern hover-animated buttons ──────────────────────────────────────────
--
-- Each button is identified by its (x, y, label) tuple, which is stable across
-- frames. We track a 0..1 "hover progress" per button (declared above so
-- R.update can prune stale entries) and ease it towards the target every
-- frame, then drive lift / scale / colour / glow / shadow from that single
-- value. The button() signature is unchanged so callers keep working — they
-- just look noticeably more alive.

local function btnKey(label, x, y)
    return label .. "@" .. math.floor(x) .. "," .. math.floor(y)
end

local function easeOutCubic(t)
    local u = 1 - t
    return 1 - u * u * u
end

local function lerp(a, b, t) return a + (b - a) * t end

local function lerpColor(c1, c2, t)
    return {
        lerp(c1[1], c2[1], t),
        lerp(c1[2], c2[2], t),
        lerp(c1[3], c2[3], t),
        lerp(c1[4] or 1, c2[4] or 1, t),
    }
end

local function button(label, x, y, w, h, mx, my, col, hcol)
    local hov = mx >= x and mx <= x+w and my >= y and my <= y+h

    -- Advance the per-button hover progress towards its target.
    local key  = btnKey(label, x, y)
    hoverSeen[key] = true
    local prev = hoverProgress[key] or 0
    local target = hov and 1 or 0
    local dt   = love.timer.getDelta() or 0
    local k    = math.min(1, dt * HOVER_SPEED)
    local raw  = prev + (target - prev) * k
    hoverProgress[key] = raw
    local p = easeOutCubic(raw)        -- 0..1, eased

    -- Derived visual params --------------------------------------------------
    local lift     = -3 * p                   -- pixels (negative = up)
    local scale    = 1 + 0.035 * p            -- 1.0 → 1.035
    local cx, cy   = x + w/2, y + h/2
    local fillCol  = lerpColor(col, hcol, p)
    -- Brighten fill a touch more at full hover for extra "pop"
    fillCol[1] = math.min(1, fillCol[1] + 0.04 * p)
    fillCol[2] = math.min(1, fillCol[2] + 0.04 * p)
    fillCol[3] = math.min(1, fillCol[3] + 0.04 * p)

    -- Drop shadow (deeper when hovered → button feels lifted) ----------------
    setColor(0, 0, 0, 0.28 + 0.18 * p)
    local shY = 3 + 4 * p
    love.graphics.rectangle("fill", x + 1, y + shY, w, h, 7)

    -- Body — scaled around centre so the layout/hit-box stays exact ---------
    love.graphics.push()
    love.graphics.translate(cx, cy + lift)
    love.graphics.scale(scale, scale)
    love.graphics.translate(-cx, -cy)

    setColor(fillCol)
    love.graphics.rectangle("fill", x, y, w, h, 7)

    -- Inner top highlight (subtle sheen) ------------------------------------
    setColor(1, 1, 1, 0.10 + 0.08 * p)
    love.graphics.rectangle("fill", x + 2, y + 2, w - 4, math.max(2, h * 0.38), 6)

    -- Animated glow outline (only visible while hovering) -------------------
    if p > 0.01 then
        love.graphics.setLineWidth(2)
        setColor(hcol[1], hcol[2], hcol[3], 0.65 * p)
        love.graphics.rectangle("line", x - 1, y - 1, w + 2, h + 2, 8)
        -- second, softer ring further out for a halo feel
        setColor(hcol[1], hcol[2], hcol[3], 0.22 * p)
        love.graphics.rectangle("line", x - 3, y - 3, w + 6, h + 6, 10)
        love.graphics.setLineWidth(1)
    end

    -- Label (slight brightness boost on hover) ------------------------------
    setColor(1, 1, 1, 1)
    if p > 0 then
        setColor(1, 1, 1, math.min(1, 0.92 + 0.08 * p))
    end
    centredText(fonts.med, label, cx, cy)

    love.graphics.pop()
    -- Reset colour so subsequent draws don't inherit our tint
    setColor(1, 1, 1, 1)

    return hov, x, y, w, h
end

-- (pruneHoverState is declared earlier so R.update can call it.)

-- ── Suit pips (vector shapes — LÖVE's default font lacks ♠♥♦♣ glyphs) ───────
-- Draws a filled suit symbol centred at (cx,cy). `s` ≈ half-height.
-- Caller sets the colour beforehand.
local function drawPip(suit, cx, cy, s)
    if suit == C.DIAMONDS then
        love.graphics.polygon("fill",
            cx, cy-s,  cx+s*0.72, cy,  cx, cy+s,  cx-s*0.72, cy)

    elseif suit == C.HEARTS then
        local r = s*0.52
        love.graphics.circle("fill", cx - r*0.7, cy - r*0.45, r)
        love.graphics.circle("fill", cx + r*0.7, cy - r*0.45, r)
        love.graphics.polygon("fill",
            cx - s*0.92, cy - r*0.25,  cx + s*0.92, cy - r*0.25,  cx, cy + s)

    elseif suit == C.SPADES then
        local r = s*0.52
        love.graphics.polygon("fill",
            cx, cy - s,  cx - s*0.92, cy + r*0.25,  cx + s*0.92, cy + r*0.25)
        love.graphics.circle("fill", cx - r*0.7, cy + r*0.05, r)
        love.graphics.circle("fill", cx + r*0.7, cy + r*0.05, r)
        love.graphics.polygon("fill",
            cx - s*0.34, cy + s,  cx + s*0.34, cy + s,
            cx + s*0.10, cy + r*0.2,  cx - s*0.10, cy + r*0.2)

    else -- CLUBS
        local r = s*0.42
        love.graphics.circle("fill", cx,            cy - s*0.42, r)
        love.graphics.circle("fill", cx - s*0.55,   cy + s*0.18, r)
        love.graphics.circle("fill", cx + s*0.55,   cy + s*0.18, r)
        love.graphics.polygon("fill",
            cx - s*0.34, cy + s,  cx + s*0.34, cy + s,
            cx + s*0.10, cy,      cx - s*0.10, cy)
    end
end

R.drawPip = drawPip

-- ── Card drawing ───────────────────────────────────────────────────────────

-- Procedural J/Q/K face (no SVG art) — matches the SVG style: white card,
-- light grey border, rank letter in corners with pip, big rank letter centre.
local function drawFaceCardProcedural(x, y, card, scol)
    local rkStr = C.RANK_NAMES[card.rank - 1]
    -- Face background
    setColor(PAL.card_face)
    love.graphics.rectangle("fill", x, y, CW, CH, CR)
    setColor(0.88, 0.88, 0.88)
    love.graphics.setLineWidth(1.5)
    love.graphics.rectangle("line", x+1, y+1, CW-2, CH-2, CR)
    love.graphics.setLineWidth(1)

    -- Corner rank + pip (top-left and bottom-right rotated)
    setColor(scol)
    love.graphics.setFont(fonts.cardRk)
    love.graphics.print(rkStr, x+5, y+3)
    drawPip(card.suit, x+11, y+26, 5)

    love.graphics.push()
    love.graphics.translate(x + CW - 5, y + CH - 3)
    love.graphics.rotate(math.pi)
    love.graphics.setFont(fonts.cardRk)
    love.graphics.print(rkStr, 0, 0)
    drawPip(card.suit, 6, 24, 5)
    love.graphics.pop()

    -- Big centre letter
    love.graphics.setFont(fonts.cardFace)
    local fw = fonts.cardFace:getWidth(rkStr)
    local fh = fonts.cardFace:getHeight()
    love.graphics.print(rkStr, x + CW/2 - fw/2, y + CH/2 - fh/2)
end

-- Draw a face-up card with top-left corner at (x,y)
local function drawCardFace(x, y, card, highlight, dimmed)
    local scol = C.SUIT_IS_RED[card.suit] and PAL.red_suit or PAL.black_suit

    -- Shadow
    setColor(PAL.shadow)
    love.graphics.rectangle("fill", x+2, y+3, CW, CH, CR)

    -- Highlight ring
    if highlight == "playable" then
        setColor(PAL.green_hi)
        love.graphics.rectangle("fill", x-3, y-3, CW+6, CH+6, CR+2)
    elseif highlight == "selected" then
        setColor(PAL.gold_hi)
        love.graphics.rectangle("fill", x-4, y-4, CW+8, CH+8, CR+3)
    end

    local img = cardImg[card.rank] and cardImg[card.rank][card.suit]
    if img then
        -- Use SVG-rasterized face
        if dimmed then setColor(0.75, 0.75, 0.75) else setColor(1, 1, 1) end
        local sx, sy = CW / img:getWidth(), CH / img:getHeight()
        love.graphics.draw(img, x, y, 0, sx, sy)
    else
        -- J/Q/K — procedural
        if dimmed then setColor(0.8, 0.8, 0.8) else setColor(PAL.card_face) end
        drawFaceCardProcedural(x, y, card, scol)
    end
end

local function drawCardBack(x, y)
    -- Drop shadow
    setColor(PAL.shadow)
    love.graphics.rectangle("fill", x+2, y+3, CW, CH, CR)

    if currentBack then
        setColor(1, 1, 1)
        local sx = CW / currentBack:getWidth()
        local sy = CH / currentBack:getHeight()
        love.graphics.draw(currentBack, x, y, 0, sx, sy)
    else
        setColor(PAL.card_back_a)
        love.graphics.rectangle("fill", x, y, CW, CH, CR)
        setColor(PAL.card_back_b)
        love.graphics.rectangle("fill", x+5, y+5, CW-10, CH-10, CR-2)
        love.graphics.setLineWidth(1)
        setColor(0.08, 0.14, 0.55, 0.6)
        for i = 0, 5 do
            local fx = x+5 + i*(CW-10)/5
            local fy = y+5 + i*(CH-10)/5
            love.graphics.line(fx, y+5, fx, y+CH-5)
            love.graphics.line(x+5, fy, x+CW-5, fy)
        end
    end
end

-- Draw a card rotated 90° around its centre point (cx,cy).
-- angle: math.pi/2 = CW (East), -math.pi/2 = CCW (West)
local function drawCardRotated(cx, cy, card, angle, faceUp, highlight)
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(angle)
    if faceUp then
        drawCardFace(-CW/2, -CH/2, card, highlight, false)
    else
        drawCardBack(-CW/2, -CH/2)
    end
    love.graphics.pop()
end

-- ── Hand layouts ───────────────────────────────────────────────────────────
-- Each draw function returns a hitbox list: [{card, x, y, w, h, idx}]

local OV = C.CARD_OVERLAP

-- Horizontal fan, face-up (South or North)
local function drawHorizHand(hand, baseX, baseY, faceUp, playableSet, selectedIdx, hoverIdx, flip)
    local n = #hand
    if n == 0 then return {} end
    local totalW = (n-1)*OV + CW
    local sx     = baseX - totalW/2
    local hits   = {}

    for i, card in ipairs(hand) do
        local x  = sx + (i-1)*OV
        local dy = 0
        if hoverIdx == i then dy = flip and 8 or -10 end
        if selectedIdx == i then dy = flip and 12 or -14 end
        local hl = nil
        if selectedIdx == i then hl = "selected"
        elseif playableSet and playableSet[i] then hl = "playable" end

        if faceUp then
            drawCardFace(x, baseY + dy, card, hl, false)
        else
            drawCardBack(x, baseY + dy)
        end
        hits[#hits+1] = {card=card, x=x, y=baseY+dy, w=CW, h=CH, idx=i}
    end
    return hits
end

-- Vertical fan (East/West), rotated
local function drawVertHand(hand, baseCX, baseY, angle, faceUp, playableSet)
    local n = #hand
    if n == 0 then return {} end
    local totalH = (n-1)*OV + CW   -- rotated: card width is the spread dimension
    local sy     = baseY - totalH/2
    local hits   = {}

    for i, card in ipairs(hand) do
        local cy  = sy + (i-1)*OV + CW/2
        local hl  = playableSet and playableSet[i] and "playable" or nil
        drawCardRotated(baseCX, cy, card, angle, faceUp, hl)
        -- Hitbox in rotated space: card rotated 90° means H×W bounding box centred on (baseCX,cy)
        hits[#hits+1] = {card=card, x=baseCX-CH/2, y=cy-CW/2, w=CH, h=CW, idx=i}
    end
    return hits
end

-- Build a set of which indices in `hand` are legal given current trick
local function legalSet(hand, trick)
    local ledSuit = (#trick > 0) and trick[1].card.suit or nil
    local legal   = AI.legalCards(hand, ledSuit)
    local set     = {}
    for _, lc in ipairs(legal) do
        for i, hc in ipairs(hand) do
            if hc.suit == lc.suit and hc.rank == lc.rank then set[i] = true end
        end
    end
    return set
end

-- ── Trick display ──────────────────────────────────────────────────────────

local TRICK_OFFSET = 58

local trickPos = {
    [C.NORTH] = function() return C.SW/2 - CW/2, C.SH/2 - TRICK_OFFSET - CH end,
    [C.EAST]  = function() return C.SW/2 + TRICK_OFFSET,   C.SH/2 - CH/2    end,
    [C.SOUTH] = function() return C.SW/2 - CW/2, C.SH/2 + TRICK_OFFSET      end,
    [C.WEST]  = function() return C.SW/2 - TRICK_OFFSET - CW, C.SH/2 - CH/2 end,
}

local function drawTrick(trick)
    for _, entry in ipairs(trick) do
        local x, y = trickPos[entry.player]()
        drawCardFace(x, y, entry.card, nil, false)
    end
end

-- ── Panels ─────────────────────────────────────────────────────────────────

local function drawPanel(x, y, w, h)
    setColor(PAL.panel)
    love.graphics.rectangle("fill", x, y, w, h, 9)
end

local function drawInfoPanel(game)
    local x, y, w, h = C.SW-210, 8, 202, 170
    drawPanel(x, y, w, h)
    setColor(PAL.white)
    love.graphics.setFont(fonts.med)

    local function row(label, val, ly)
        setColor(PAL.text_dim); love.graphics.print(label, x+8, ly)
        setColor(PAL.white);    love.graphics.print(val,   x+100, ly)
    end

    local ry = y + 8
    if game.contract then
        -- Bid level = tricks - 6 (1..7).  Suit-short includes "NT".
        local level = (game.contract.tricks or 7) - 6
        local sn    = C.CONTRACT_SHORT[game.contract.suit]
        local extra = ""
        if game.contractRedoubled then extra = " XX"
        elseif game.contractDoubled then extra = " X" end
        row("Contract:", level .. sn .. extra, ry); ry = ry+22
        row("Declarer:", C.PLAYER_NAMES[game.declarer],       ry); ry = ry+22
        setColor(PAL.text_dim); love.graphics.print("Trump:", x+8, ry)
        if game.trumpSuit then
            setColor(C.SUIT_IS_RED[game.trumpSuit] and PAL.red_suit or PAL.white)
            drawPip(game.trumpSuit, x+110, ry+9, 7)
        else
            setColor(PAL.white); love.graphics.print("NT", x+100, ry)
        end
        ry = ry+22
        row("Need:",     game.contractTricks .. " tricks",    ry); ry = ry+22
        local dSide = game.declaringSide == "NS" and "N-S" or "E-W"
        local xSide = game.declaringSide == "NS" and "E-W" or "N-S"
        row(dSide..":",  tostring(game.tricksDeclarer),       ry); ry = ry+22
        row(xSide..":",  tostring(game.tricksDefender),       ry); ry = ry+22
    end
    if game.hcp then
        ry = ry + 4
        setColor(PAL.text_dim)
        love.graphics.setFont(fonts.small)
        love.graphics.print(string.format("HCP  N:%d  E:%d  S:%d  W:%d",
            game.hcp[1],game.hcp[2],game.hcp[3],game.hcp[4]), x+8, ry)
    end
end

local function drawScorePanel(game)
    local x, y, w, h = 8, 8, 185, 76
    drawPanel(x, y, w, h)
    love.graphics.setFont(fonts.med)
    setColor(PAL.yellow)
    love.graphics.print("SCORE", x+8, y+6)
    love.graphics.setFont(fonts.small)
    setColor(PAL.text_dim)
    local htxt = string.format("Hand #%d", game.seed)
    love.graphics.print(htxt, x + w - fonts.small:getWidth(htxt) - 8, y+9)
    love.graphics.setFont(fonts.med)
    setColor(PAL.white)
    love.graphics.print(string.format("N-S : %d", game.sessionScore[1]), x+8, y+28)
    love.graphics.print(string.format("E-W : %d", game.sessionScore[2]), x+8, y+50)
end

local function drawPlayerLabels(game)
    -- positions: {cx, cy}
    local pos = {
        [C.NORTH] = {C.SW/2, 136},
        [C.EAST]  = {C.SW - 22, C.SH/2},
        [C.SOUTH] = {C.SW/2, C.SH - 138},
        [C.WEST]  = {22,     C.SH/2},
    }

    for p, pt in pairs(pos) do
        local name = C.PLAYER_NAMES[p]
        local tags = ""
        if game.declarer == p then tags = tags .. "[D]" end
        if game.dummy    == p then tags = tags .. "[dum]" end
        local label = name .. (game.hcp and string.format("(%d)", game.hcp[p]) or "")
        if tags ~= "" then label = label .. " " .. tags end

        love.graphics.setFont(fonts.small)
        if game.currentPlayer == p then
            setColor(PAL.yellow)
        elseif game.declarer == p then
            setColor(0.4, 1.0, 0.4)
        else
            setColor(PAL.white)
        end

        local tw = fonts.small:getWidth(label)
        love.graphics.print(label, pt[1] - tw/2, pt[2])
    end
end

-- ── Announcement / calling phase ───────────────────────────────────────────
-- Per Minibridge rules: every hand starts with each player (N->E->S->W)
-- announcing their HCP, then the declaring side and declarer are revealed.
local function drawSpeechBubble(cx, cy, text, anchor)
    love.graphics.setFont(fonts.med)
    local tw  = fonts.med:getWidth(text)
    local pad = 10
    local bw  = tw + pad*2
    local bh  = 32
    local bx, by
    if anchor == "below" then
        bx, by = cx - bw/2, cy + 4
    elseif anchor == "above" then
        bx, by = cx - bw/2, cy - bh - 4
    elseif anchor == "right" then
        bx, by = cx + 6,    cy - bh/2
    else -- left
        bx, by = cx - bw - 6, cy - bh/2
    end
    setColor(0.99, 0.97, 0.88, 0.96)
    love.graphics.rectangle("fill", bx, by, bw, bh, 9)
    setColor(0.30, 0.22, 0.05)
    love.graphics.setLineWidth(1.5)
    love.graphics.rectangle("line", bx, by, bw, bh, 9)
    love.graphics.setLineWidth(1)
    love.graphics.print(text, bx + pad, by + (bh - fonts.med:getHeight())/2)
end

-- A "bidding card" — small card-shaped element placed on the table by a
-- player to record their announcement. Visually mirrors a real playing card:
-- white rounded body, light grey border, big rank-style number, suit pip,
-- rotated repeat in the bottom-right corner, soft shadow.
--
-- For the SUIT decoration we pick the partnership's emblematic suit:
--   N/S -> Hearts (red),  E/W -> Spades (black).
-- This gives each side a distinct visual identity on the calling board.
local BID_CARD_W, BID_CARD_H, BID_CARD_R = 64, 90, 7

local function drawBidCard(cx, cy, hcp, suit, rotation, highlight)
    rotation = rotation or 0
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(rotation)
    local x, y = -BID_CARD_W/2, -BID_CARD_H/2

    -- Shadow
    setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", x+3, y+4, BID_CARD_W, BID_CARD_H, BID_CARD_R)

    -- Glow ring if active player
    if highlight then
        setColor(PAL.yellow)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", x-4, y-4, BID_CARD_W+8, BID_CARD_H+8, BID_CARD_R+2)
        love.graphics.setLineWidth(1)
    end

    -- Card body
    setColor(PAL.card_face)
    love.graphics.rectangle("fill", x, y, BID_CARD_W, BID_CARD_H, BID_CARD_R)
    setColor(0.78, 0.78, 0.78)
    love.graphics.setLineWidth(1.4)
    love.graphics.rectangle("line", x+1, y+1, BID_CARD_W-2, BID_CARD_H-2, BID_CARD_R)
    love.graphics.setLineWidth(1)

    local scol = C.SUIT_IS_RED[suit] and PAL.red_suit or PAL.black_suit

    -- Top-left: HCP "rank" + suit pip (mirrors a real card)
    setColor(scol)
    love.graphics.setFont(fonts.cardRk)
    love.graphics.print(tostring(hcp), x+5, y+3)
    drawPip(suit, x+10, y+24, 4)

    -- Bottom-right: rotated 180° (same as a real playing card)
    love.graphics.push()
    love.graphics.translate(x + BID_CARD_W - 5, y + BID_CARD_H - 3)
    love.graphics.rotate(math.pi)
    love.graphics.setFont(fonts.cardRk)
    love.graphics.print(tostring(hcp), 0, 0)
    drawPip(suit, 5, 22, 4)
    love.graphics.pop()

    -- Centre: big HCP value (the "call")
    setColor(scol)
    love.graphics.setFont(fonts.cardFace)
    local fw = fonts.cardFace:getWidth(tostring(hcp))
    local fh = fonts.cardFace:getHeight()
    love.graphics.print(tostring(hcp), -fw/2, -fh/2)

    -- Tiny "pts" label below the centre number
    setColor(0.45, 0.45, 0.45)
    love.graphics.setFont(fonts.tiny)
    centredText(fonts.tiny, "pts", 0, BID_CARD_H/2 - 18)

    love.graphics.pop()
end

-- Empty placeholder card slot (waiting for player to call)
local function drawBidCardSlot(cx, cy, rotation, highlight)
    rotation = rotation or 0
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(rotation)
    local x, y = -BID_CARD_W/2, -BID_CARD_H/2

    setColor(0, 0, 0, 0.30)
    love.graphics.rectangle("fill", x, y, BID_CARD_W, BID_CARD_H, BID_CARD_R)
    if highlight then
        setColor(PAL.yellow)
        love.graphics.setLineWidth(2)
    else
        setColor(0.45, 0.45, 0.45, 0.7)
        love.graphics.setLineWidth(1)
    end
    -- Dashed-ish border (12 short segments around the rectangle)
    for i = 0, 11 do
        local t = i / 12
        love.graphics.points(x + t * BID_CARD_W, y)
    end
    love.graphics.rectangle("line", x, y, BID_CARD_W, BID_CARD_H, BID_CARD_R)
    love.graphics.setLineWidth(1)

    if highlight then
        setColor(PAL.yellow)
        love.graphics.setFont(fonts.small)
        centredText(fonts.small, "?", 0, -5)
    end
    love.graphics.pop()
end

-- ── Dealing animation ─────────────────────────────────────────────────────

function R.drawDealing(game)
    local Anim = require("src.anim")
    setColor(PAL.felt)
    love.graphics.rectangle("fill", 0, 0, C.SW, C.SH)
    setColor(PAL.felt_inner)
    love.graphics.ellipse("fill", C.SW/2, C.SH/2, C.SW*0.40, C.SH*0.45)

    -- Player labels (no HCP yet)
    local labelPos = {
        [C.NORTH] = {C.SW/2,     136},
        [C.EAST]  = {C.SW - 38,  C.SH/2},
        [C.SOUTH] = {C.SW/2,     C.SH - 138},
        [C.WEST]  = {38,         C.SH/2},
    }
    love.graphics.setFont(fonts.small)
    setColor(PAL.text_dim)
    for p, pt in pairs(labelPos) do
        local name = C.PLAYER_NAMES[p]
        if game.auction and game.auction.dealer == p then name = name .. " (D)" end
        local tw = fonts.small:getWidth(name)
        love.graphics.print(name, pt[1] - tw/2, pt[2])
    end

    -- Title
    setColor(PAL.dim)
    love.graphics.rectangle("fill", 0, 0, C.SW, 42)
    setColor(PAL.yellow)
    centredText(fonts.large, "Dealing...", C.SW/2, 21)

    -- Deck pile at centre (small visual cue before the first card flies)
    if Anim.elapsed < 0.10 then
        for i = 0, 6 do
            drawCardBack(Anim.DECK_X - CW/2 - i, Anim.DECK_Y - CH/2 - i)
        end
    end

    -- Every card in flight or landed: draw at interpolated pos
    for i, c in ipairs(Anim.cards) do
        if c.started then
            local x, y, angle = Anim.cardPos(i)
            love.graphics.push()
            love.graphics.translate(x, y)
            love.graphics.rotate(angle or 0)
            drawCardBack(-CW/2, -CH/2)
            love.graphics.pop()
        end
    end
end

-- ── Auction screen (contract-bridge bidding) ─────────────────────────────

-- Draw a small "call token" — looks like a bridge bidding-box card.
-- For a bid, shows the level + suit pip (or "NT"); for pass/double/redouble
-- shows the short label.
local function drawCallToken(x, y, w, h, call, opts)
    opts = opts or {}
    setColor(opts.bg or {1, 0.99, 0.96})
    love.graphics.rectangle("fill", x, y, w, h, 4)
    setColor(opts.border or {0.65, 0.65, 0.65})
    love.graphics.setLineWidth(opts.thick and 2 or 1)
    love.graphics.rectangle("line", x, y, w, h, 4)
    love.graphics.setLineWidth(1)

    if call.type == C.CALL_PASS then
        setColor(0.35, 0.35, 0.35)
        centredText(fonts.small, "Pass", x + w/2, y + h/2)
    elseif call.type == C.CALL_DOUBLE then
        setColor(0.78, 0.20, 0.20)
        centredText(fonts.small, "X", x + w/2, y + h/2)
    elseif call.type == C.CALL_REDOUBLE then
        setColor(0.78, 0.20, 0.20)
        centredText(fonts.small, "XX", x + w/2, y + h/2)
    elseif call.type == C.CALL_BID then
        local denom = call.denom
        local scol  = (denom == C.BID_NT) and {0.05, 0.05, 0.05}
                       or (C.SUIT_IS_RED[denom] and PAL.red_suit or PAL.black_suit)
        setColor(scol)
        love.graphics.setFont(fonts.med)
        love.graphics.print(tostring(call.level), x + 5, y + h/2 - 10)
        if denom == C.BID_NT then
            love.graphics.setFont(fonts.small)
            love.graphics.print("NT", x + 17, y + h/2 - 7)
        else
            drawPip(denom, x + w - 11, y + h/2, 6)
        end
    end
end

-- Draw the auction history as a 4-column table (N E S W).
local function drawAuctionBoard(game, x, y, w, h)
    local a = game.auction
    setColor(0.05, 0.05, 0.05, 0.85)
    love.graphics.rectangle("fill", x, y, w, h, 9)
    setColor(0.85, 0.72, 0.18)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, w, h, 9)
    love.graphics.setLineWidth(1)

    setColor(PAL.yellow)
    centredText(fonts.med, "AUCTION", x + w/2, y + 12)

    -- Column headers (N E S W in clockwise display order)
    local cols = {C.NORTH, C.EAST, C.SOUTH, C.WEST}
    local colW = (w - 16) / 4
    love.graphics.setFont(fonts.small)
    for i, p in ipairs(cols) do
        local cx = x + 8 + (i - 0.5) * colW
        if p == a.dealer then
            setColor(PAL.yellow)
            centredText(fonts.small, C.PLAYER_NAMES[p]:sub(1,1) .. " (D)", cx, y + 36)
        elseif p == a.currentBidder and not a.finished then
            setColor(PAL.yellow)
            centredText(fonts.small, C.PLAYER_NAMES[p]:sub(1,1), cx, y + 36)
        else
            setColor(PAL.text_dim)
            centredText(fonts.small, C.PLAYER_NAMES[p]:sub(1,1), cx, y + 36)
        end
    end
    setColor(0.45, 0.35, 0.10)
    love.graphics.rectangle("fill", x + 10, y + 52, w - 20, 1)

    -- Place each bid in its player's column. We index rows by the round number,
    -- but for empty leading cells (because the dealer wasn't N), we leave
    -- placeholders.
    local startCol = nil
    for i, p in ipairs(cols) do
        if p == a.dealer then startCol = i; break end
    end
    if not startCol then startCol = 1 end

    local cellH  = 28
    local maxRows = math.floor((h - 68) / cellH)
    local startY  = y + 60

    local function colIndex(player)
        for i, p in ipairs(cols) do if p == player then return i end end
        return 1
    end

    for i, b in ipairs(a.bids) do
        local pos = i + (startCol - 1)
        local row = math.floor((pos - 1) / 4)
        local col = ((pos - 1) % 4) + 1
        if row < maxRows then
            local cx = x + 8 + (col - 1) * colW + 4
            local cy = startY + row * cellH
            drawCallToken(cx, cy, colW - 8, cellH - 4, b.call)
        end
    end

    -- Highlight current bidder column when auction is live
    if not a.finished then
        local cur = a.currentBidder
        local i = colIndex(cur)
        setColor(PAL.yellow)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x + 8 + (i-1)*colW, y + 28, colW, 16, 3)
        love.graphics.setLineWidth(1)
    end
end

-- Draw the bidding box — the 7x5 grid of bids plus the Pass/Double/Redouble
-- action buttons.
local function drawBiddingBox(game, x, y, mx, my, selectedBid, hits)
    local a       = game.auction
    local cellW   = 56
    local cellH   = 36
    local gap     = 4
    local cols    = 5
    local rows    = 7
    local boxW    = cols * cellW + (cols + 1) * gap
    local boxH    = rows * cellH + (rows + 1) * gap + 50

    setColor(0.05, 0.05, 0.05, 0.85)
    love.graphics.rectangle("fill", x, y, boxW, boxH, 9)
    setColor(0.85, 0.72, 0.18)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, boxW, boxH, 9)
    love.graphics.setLineWidth(1)

    setColor(PAL.yellow)
    centredText(fonts.med, "BIDDING BOX", x + boxW/2, y + 6)

    -- Column suit headers
    love.graphics.setFont(fonts.small)
    for c = 1, cols do
        local cx = x + gap + (c - 0.5) * (cellW + gap)
        local cy = y + 30
        if c == C.BID_NT then
            setColor(PAL.white)
            centredText(fonts.small, "NT", cx, cy)
        else
            setColor(C.SUIT_IS_RED[c] and PAL.red_suit or PAL.white)
            drawPip(c, cx, cy, 7)
        end
    end

    -- Grid cells
    for level = 1, 7 do
        for denom = 1, 5 do
            local cx = x + gap + (denom - 1) * (cellW + gap)
            local cy = y + 50 + (level - 1) * (cellH + gap)
            local call = {type = C.CALL_BID, level = level, denom = denom}
            local legal = game:isLegalCall(call)
            local sel   = selectedBid and selectedBid.level == level
                                       and selectedBid.denom == denom
            local hov   = mx >= cx and mx <= cx + cellW
                          and my >= cy and my <= cy + cellH

            -- Background
            if not legal then
                setColor(0.12, 0.12, 0.12)
            elseif sel then
                setColor(0.55, 0.45, 0.08)
            elseif hov then
                setColor(0.20, 0.20, 0.20)
            else
                setColor(0.99, 0.97, 0.92)
            end
            love.graphics.rectangle("fill", cx, cy, cellW, cellH, 4)

            -- Border
            if sel then
                setColor(PAL.yellow)
                love.graphics.setLineWidth(2)
            else
                setColor(legal and {0.65, 0.65, 0.65} or {0.30, 0.30, 0.30})
            end
            love.graphics.rectangle("line", cx, cy, cellW, cellH, 4)
            love.graphics.setLineWidth(1)

            -- Label
            local scol = (denom == C.BID_NT) and {0.15, 0.15, 0.15}
                          or (C.SUIT_IS_RED[denom] and PAL.red_suit or PAL.black_suit)
            if not legal then scol = {0.45, 0.45, 0.45} end
            if sel then scol = PAL.yellow end
            setColor(scol)
            love.graphics.setFont(fonts.med)
            love.graphics.print(tostring(level), cx + 7, cy + 8)
            if denom == C.BID_NT then
                love.graphics.setFont(fonts.small)
                love.graphics.print("NT", cx + 22, cy + 12)
            else
                drawPip(denom, cx + cellW - 13, cy + cellH/2, 6)
            end

            hits[#hits+1] = {
                type = "bidcell", level = level, denom = denom,
                x = cx, y = cy, w = cellW, h = cellH,
                legal = legal,
            }
        end
    end
end

-- Pass / Double / Redouble / Confirm action row
local function drawAuctionActionRow(game, x, y, mx, my, selectedBid, hits)
    local btnW, btnH, gap = 90, 40, 8
    local cur = game.auction.currentBidder

    -- Pass
    local passLegal = game:isLegalCall({type = C.CALL_PASS})
    local passCol   = passLegal and PAL.btn_blue or {0.18, 0.18, 0.20}
    local _, bx, by, bw, bh = button("Pass", x, y, btnW, btnH, mx, my,
                                      passCol, PAL.btn_hover)
    hits[#hits+1] = {type = "pass", x=bx, y=by, w=bw, h=bh}

    -- Double
    local dblLegal = game:isLegalCall({type = C.CALL_DOUBLE})
    local dblCol   = dblLegal and {0.65, 0.15, 0.15} or {0.20, 0.20, 0.20}
    local dblHov   = dblLegal and {0.82, 0.18, 0.18} or {0.22, 0.22, 0.22}
    local _, x2, y2, w2, h2 = button("X (Double)", x + (btnW+gap), y, btnW+15, btnH,
                                      mx, my, dblCol, dblHov)
    hits[#hits+1] = {type = "double", x=x2, y=y2, w=w2, h=h2}

    -- Redouble
    local rdblLegal = game:isLegalCall({type = C.CALL_REDOUBLE})
    local rdblCol   = rdblLegal and {0.55, 0.10, 0.55} or {0.20, 0.20, 0.20}
    local rdblHov   = rdblLegal and {0.72, 0.15, 0.72} or {0.22, 0.22, 0.22}
    local _, x3, y3, w3, h3 = button("XX (Redouble)", x + 2*(btnW+gap) + 15, y,
                                      btnW + 30, btnH, mx, my, rdblCol, rdblHov)
    hits[#hits+1] = {type = "redouble", x=x3, y=y3, w=w3, h=h3}

    -- Confirm (only enabled when a bid is selected)
    local cnfCol = selectedBid and PAL.btn_green or {0.20, 0.20, 0.20}
    local cnfHov = selectedBid and PAL.btn_green_h or {0.22, 0.22, 0.22}
    local cnfLbl = selectedBid
        and string.format("Bid %d%s >",
            selectedBid.level,
            (selectedBid.denom == C.BID_NT) and "NT" or C.DENOM_SHORT[selectedBid.denom])
        or  "Bid >"
    local _, x4, y4, w4, h4 = button(cnfLbl, x + 3*(btnW+gap) + 45, y, btnW + 40, btnH,
                                      mx, my, cnfCol, cnfHov)
    hits[#hits+1] = {type = "confirm", x=x4, y=y4, w=w4, h=h4}
end

function R.drawAuction(game, mx, my, selectedBid)
    -- Felt + table oval
    setColor(PAL.felt)
    love.graphics.rectangle("fill", 0, 0, C.SW, C.SH)
    setColor(PAL.felt_inner)
    love.graphics.ellipse("fill", C.SW/2, C.SH/2, C.SW*0.40, C.SH*0.45)

    local hits = {}
    local a    = game.auction

    -- Hand display: South always face-up; others face-down during the auction
    drawHorizHand(game.hands[C.NORTH], C.SW/2, 18,             false, nil, nil, nil, false)
    drawHorizHand(game.hands[C.SOUTH], C.SW/2, C.SH-CH-18,     true,  nil, nil, nil, false)
    drawVertHand (game.hands[C.EAST],  C.SW-55, C.SH/2,  math.pi/2, false, nil)
    drawVertHand (game.hands[C.WEST],  55,      C.SH/2, -math.pi/2, false, nil)

    -- Player labels with HCP, current bidder highlighted
    local labelPos = {
        [C.NORTH] = {C.SW/2,    136},
        [C.EAST]  = {C.SW - 38, C.SH/2},
        [C.SOUTH] = {C.SW/2,    C.SH - 138},
        [C.WEST]  = {38,        C.SH/2},
    }
    love.graphics.setFont(fonts.small)
    for p, pt in pairs(labelPos) do
        local name = C.PLAYER_NAMES[p]
        if a.dealer == p then name = name .. " (D)" end
        if a.currentBidder == p and not a.finished then
            setColor(PAL.yellow)
        else
            setColor(PAL.white)
        end
        local hcp = game.hcp and game.hcp[p] or 0
        -- Only show HCP for human player (would be unfair to leak others')
        if p == C.SOUTH then
            name = name .. string.format("  (%d HCP)", hcp)
        end
        local tw = fonts.small:getWidth(name)
        love.graphics.print(name, pt[1] - tw/2, pt[2])
    end

    -- Title banner
    setColor(PAL.dim)
    love.graphics.rectangle("fill", 0, 0, C.SW, 42)
    setColor(PAL.yellow)
    centredText(fonts.large, "Auction", C.SW/2, 21)

    -- ── Auction history board (left of centre) ──
    drawAuctionBoard(game, 145, 170, 360, 380)

    -- ── Bidding box / interaction zone (right of centre) ──
    local boxX = 555
    local boxY = 170
    local humanTurn = (a.currentBidder == C.SOUTH) and not game.autoSouth and not a.finished

    if humanTurn then
        drawBiddingBox(game, boxX, boxY, mx, my, selectedBid, hits)
        drawAuctionActionRow(game, boxX, boxY + 360, mx, my, selectedBid, hits)

        setColor(PAL.yellow)
        centredText(fonts.med, "Your turn — choose a bid or Pass",
                    boxX + 280, boxY + 415)
    else
        -- Status panel during AI calls
        local pw, ph = 590, 320
        setColor(0.05, 0.05, 0.05, 0.78)
        love.graphics.rectangle("fill", boxX, boxY, pw, ph, 9)
        setColor(PAL.text_dim)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", boxX, boxY, pw, ph, 9)

        setColor(PAL.yellow)
        centredText(fonts.med, "Waiting on calls", boxX + pw/2, boxY + 16)

        -- Show the running contract
        setColor(PAL.white)
        if a.highBid then
            local lbl = string.format("Current high bid: %d%s by %s",
                a.highBid.level,
                a.highBid.denom == C.BID_NT and "NT" or C.DENOM_SHORT[a.highBid.denom],
                C.PLAYER_NAMES[a.highBid.bidder])
            centredText(fonts.med, lbl, boxX + pw/2, boxY + 60)
            if a.doubled then
                setColor(0.95, 0.4, 0.4)
                centredText(fonts.small, "Doubled (X)", boxX + pw/2, boxY + 88)
            end
            if a.redoubled then
                setColor(0.95, 0.4, 0.95)
                centredText(fonts.small, "Redoubled (XX)", boxX + pw/2, boxY + 108)
            end
        else
            setColor(PAL.text_dim)
            centredText(fonts.small, "No bids yet", boxX + pw/2, boxY + 60)
        end

        setColor(PAL.text_dim)
        if a.currentBidder then
            centredText(fonts.med,
                string.format("%s is thinking...", C.PLAYER_NAMES[a.currentBidder]),
                boxX + pw/2, boxY + 140)
        end

        -- Hint to the human if they're waiting on AI partners
        if not humanTurn and not game.autoSouth then
            setColor(PAL.text_dim)
            centredText(fonts.tiny,
                "Bidding goes clockwise from the dealer (D).  Your turn highlights yellow.",
                boxX + pw/2, boxY + 260)
        end
    end

    return hits
end

-- Remove obsolete helpers from older minibridge code
R.drawAnnouncement = nil

-- ── Public draw functions ──────────────────────────────────────────────────

-- Draw main playing table. Returns southHits, northHits, eastHits, westHits.
function R.drawGame(game, southSel, southHov, northSel, northHov)
    -- Background
    setColor(PAL.felt)
    love.graphics.rectangle("fill", 0, 0, C.SW, C.SH)
    setColor(PAL.felt_inner)
    love.graphics.ellipse("fill", C.SW/2, C.SH/2, 430, 310)

    -- Determine face-up and playable sets
    local function isHumanTurn(p)
        if game.declaringSide == "NS" then
            if game.declarer == C.SOUTH then
                return p == C.SOUTH or p == game.dummy
            else
                return false
            end
        else
            return p == C.SOUTH
        end
    end

    local sPlayable, nPlayable, ePlayable, wPlayable = nil, nil, nil, nil
    if game.state == C.STATE_PLAYING then
        local cp = game.currentPlayer
        if isHumanTurn(cp) then
            local ps = legalSet(game.hands[cp], game.currentTrick)
            if cp == C.SOUTH then sPlayable = ps
            elseif cp == C.NORTH then nPlayable = ps
            elseif cp == C.EAST  then ePlayable = ps
            elseif cp == C.WEST  then wPlayable = ps
            end
        end
    end

    -- Face-up logic
    local nFace = (game.dummy == C.NORTH) or false
    local sFace = true
    local eFace = (game.dummy == C.EAST)  or false
    local wFace = (game.dummy == C.WEST)  or false

    -- Draw hands
    local nHits = drawHorizHand(game.hands[C.NORTH], C.SW/2, 18,
                    nFace, nPlayable, northSel, northHov, false)
    local sHits = drawHorizHand(game.hands[C.SOUTH], C.SW/2, C.SH - CH - 18,
                    sFace, sPlayable, southSel, southHov, false)
    local eHits = drawVertHand(game.hands[C.EAST], C.SW - 55, C.SH/2,
                    math.pi/2, eFace, ePlayable)
    local wHits = drawVertHand(game.hands[C.WEST], 55, C.SH/2,
                    -math.pi/2, wFace, wPlayable)

    -- Trick in centre
    local trickToShow = game.currentTrick
    if game.state == C.STATE_TRICK_END and game.lastTrick then
        trickToShow = game.lastTrick
    end
    if trickToShow then drawTrick(trickToShow) end

    -- Trick-end banner
    if game.state == C.STATE_TRICK_END and game.lastWinner then
        setColor(PAL.dim)
        love.graphics.rectangle("fill", C.SW/2-160, C.SH/2-22, 320, 44, 8)
        setColor(PAL.yellow)
        centredText(fonts.large,
            C.PLAYER_NAMES[game.lastWinner] .. " wins trick " .. game.trickCount,
            C.SW/2, C.SH/2)
    end

    -- Thinking indicator for AI
    if game.state == C.STATE_PLAYING then
        local cp = game.currentPlayer
        if cp and not isHumanTurn(cp) then
            love.graphics.setFont(fonts.small)
            setColor(PAL.text_dim)
            love.graphics.print("Thinking...", C.SW/2 - 30, C.SH/2 - 8)
        end
    end

    drawPlayerLabels(game)
    drawInfoPanel(game)
    drawScorePanel(game)

    return sHits, nHits, eHits, wHits
end

-- ── Bidding screen ─────────────────────────────────────────────────────────
-- Returns {suitBtns=[{suit,x,y,w,h}], trickBtns=[{tricks,x,y,w,h}], autoBtns=[]}
function R.drawBidding(game, selSuit, selTricks, mx, my)
    -- Table background (with hands visible)
    setColor(PAL.felt)
    love.graphics.rectangle("fill", 0, 0, C.SW, C.SH)
    setColor(PAL.felt_inner)
    love.graphics.ellipse("fill", C.SW/2, C.SH/2, 430, 310)

    drawHorizHand(game.hands[C.SOUTH], C.SW/2, C.SH - CH - 18, true, nil, nil, nil, false)
    drawHorizHand(game.hands[C.NORTH], C.SW/2, 18, true, nil, nil, nil, false)

    love.graphics.setFont(fonts.tiny)
    setColor(0.9, 0.7, 0.3)
    local dw = fonts.tiny:getWidth("DUMMY")
    love.graphics.print("DUMMY", C.SW/2 - dw/2, 126)

    drawScorePanel(game)

    -- HCP info
    love.graphics.setFont(fonts.med)
    setColor(PAL.white)
    local nsHCP = game.hcp[C.NORTH] + game.hcp[C.SOUTH]
    local info  = string.format("N-S total HCP: %d  (%s)",
        nsHCP, nsHCP >= 25 and "GAME — bid for 25+ pts!" or "Part score")
    centredText(fonts.med, info, C.SW/2, C.SH/2 - 90)

    -- Dialog panel
    local px, py, pw, ph = C.SW/2 - 300, C.SH/2 - 75, 600, 190
    setColor(PAL.panel_light)
    love.graphics.rectangle("fill", px, py, pw, ph, 10)

    setColor(PAL.yellow)
    centredText(fonts.large, "Choose Contract  (you are Declarer)", C.SW/2, py + 22)

    -- Suit row
    local suitDefs = {
        {name="Clubs",    suit=C.CLUBS,     col={0.28,0.28,0.28}},
        {name="Diamonds", suit=C.DIAMONDS,  col={0.72,0.12,0.12}},
        {name="Hearts",   suit=C.HEARTS,    col={0.72,0.12,0.12}},
        {name="Spades",   suit=C.SPADES,    col={0.28,0.28,0.28}},
        {name="No Trump", suit=C.NO_TRUMP,  col={0.18,0.35,0.72}},
    }

    local bw, bh = 96, 34
    local suitY  = py + 48
    local suitHits = {}
    local totalBW  = #suitDefs * bw + (#suitDefs - 1) * 8
    local ssx      = C.SW/2 - totalBW/2

    for i, sd in ipairs(suitDefs) do
        local bx  = ssx + (i-1)*(bw+8)
        local hov = mx >= bx and mx <= bx+bw and my >= suitY and my <= suitY+bh
        local sel = selSuit == sd.suit
        if sel then
            setColor(PAL.yellow)
            love.graphics.rectangle("fill", bx-3, suitY-3, bw+6, bh+6, 8)
        end
        setColor(hov and {sd.col[1]+0.15, sd.col[2]+0.15, sd.col[3]+0.15} or sd.col)
        love.graphics.rectangle("fill", bx, suitY, bw, bh, 6)
        setColor(PAL.white)
        if sd.suit ~= C.NO_TRUMP then
            drawPip(sd.suit, bx+15, suitY+bh/2, 8)
            love.graphics.setFont(fonts.small)
            love.graphics.print(sd.name, bx+28, suitY+bh/2 - 7)
        else
            centredText(fonts.small, sd.name, bx+bw/2, suitY+bh/2)
        end
        suitHits[#suitHits+1] = {suit=sd.suit, x=bx, y=suitY, w=bw, h=bh}
    end

    -- Tricks row (7..13)
    local tw2, th2 = 64, 30
    local trickY   = py + 100
    local trickHits= {}
    local totalTW  = 7*tw2 + 6*6
    local tsx      = C.SW/2 - totalTW/2

    love.graphics.setFont(fonts.small)
    setColor(PAL.text_dim)
    love.graphics.print("Tricks to make:", tsx, trickY - 18)

    for t = 7, 13 do
        local bx  = tsx + (t-7)*(tw2+6)
        local hov = mx >= bx and mx <= bx+tw2 and my >= trickY and my <= trickY+th2
        local sel = selTricks == t
        if sel then setColor(PAL.yellow)
        else        setColor(hov and PAL.btn_hover or PAL.btn_blue) end
        love.graphics.rectangle("fill", bx, trickY, tw2, th2, 5)
        setColor(PAL.white)
        centredText(fonts.med, tostring(t), bx+tw2/2, trickY+th2/2)
        trickHits[#trickHits+1] = {tricks=t, x=bx, y=trickY, w=tw2, h=th2}
    end

    -- Auto / Confirm row
    local autoBtns = {}
    local by2 = py + 148
    local _, ax, ay, aw, ah = button("Auto-select", C.SW/2-170, by2, 140, 32, mx, my, PAL.btn_green, PAL.btn_green_h)
    autoBtns[#autoBtns+1] = {type="auto", x=ax, y=ay, w=aw, h=ah}

    if selSuit and selTricks then
        local _, cx2, cy2, cw2, ch2 = button(
            string.format("Confirm %d%s", selTricks, C.CONTRACT_SHORT[selSuit]),
            C.SW/2 + 30, by2, 140, 32, mx, my, PAL.btn_blue, PAL.btn_hover)
        autoBtns[#autoBtns+1] = {type="confirm", x=cx2, y=cy2, w=cw2, h=ch2}
    end

    return suitHits, trickHits, autoBtns
end

-- ── Result screen ──────────────────────────────────────────────────────────
function R.drawResult(game, mx, my)
    -- Fire confetti once on entry if the human won
    maybeStartConfetti(game.humanWon, game.state)

    setColor(PAL.felt)
    love.graphics.rectangle("fill", 0, 0, C.SW, C.SH)
    setColor(PAL.felt_inner)
    love.graphics.ellipse("fill", C.SW/2, C.SH/2, C.SW*0.42, C.SH*0.48)

    local hits = {}
    local won  = game.humanWon
    local res  = game.handResult

    -- On loss, reveal all four ORIGINAL hands (as they were dealt). On win,
    -- skip that and just show the celebration.
    if not won then
        local function fanH(hand, baseX, baseY)
            -- compact horizontal fan, face-up, no interactivity
            local n   = #hand
            local cw  = CW * 0.62
            local gap = cw * 0.42
            local total = (n - 1) * gap + cw
            local x0  = baseX - total/2
            for i, c in ipairs(hand) do
                love.graphics.push()
                love.graphics.translate(x0 + (i-1)*gap, baseY)
                love.graphics.scale(0.62, 0.62)
                drawCardFace(0, 0, c, nil, false)
                love.graphics.pop()
            end
        end
        local function fanV(hand, baseX, baseY)
            local n   = #hand
            local ch  = CH * 0.62
            local gap = ch * 0.38
            local total = (n - 1) * gap + ch
            local y0  = baseY - total/2
            for i, c in ipairs(hand) do
                love.graphics.push()
                love.graphics.translate(baseX, y0 + (i-1)*gap)
                love.graphics.scale(0.62, 0.62)
                drawCardFace(0, 0, c, nil, false)
                love.graphics.pop()
            end
        end
        setColor(PAL.text_dim)
        love.graphics.setFont(fonts.tiny)
        local function nameAt(p, x, y)
            local tag = (p == game.declarer) and " (Decl)"
                     or (p == game.dummy)    and " (Dummy)" or ""
            local n   = (game.hcp and game.hcp[p]) or 0
            local s   = string.format("%s%s — %d HCP", C.PLAYER_NAMES[p], tag, n)
            centredText(fonts.tiny, s, x, y)
        end
        fanH(game.initialHands[C.NORTH], C.SW/2,    115);     nameAt(C.NORTH, C.SW/2, 65)
        fanH(game.initialHands[C.SOUTH], C.SW/2,    C.SH-90); nameAt(C.SOUTH, C.SW/2, C.SH-140)
        fanV(game.initialHands[C.EAST],  C.SW-120,  C.SH/2);  nameAt(C.EAST,  C.SW-120, C.SH/2-160)
        fanV(game.initialHands[C.WEST],  120,       C.SH/2);  nameAt(C.WEST,  120,      C.SH/2-160)
    end

    -- Confetti rendered behind the central banner on a win
    if won then drawConfetti() end

    -- Central banner (tall enough to comfortably contain the buttons below
    -- the score line, with no overlap)
    local bw, bh = 660, 320
    local bx, by = C.SW/2 - bw/2, C.SH/2 - bh/2
    setColor(0, 0, 0, 0.78)
    love.graphics.rectangle("fill", bx, by, bw, bh, 14)
    setColor(won and PAL.yellow or {0.85, 0.25, 0.25})
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", bx, by, bw, bh, 14)
    love.graphics.setLineWidth(1)

    if won then
        setColor(PAL.yellow)
        centredText(fonts.title, "YOU WON!", C.SW/2, by + 50)
    else
        setColor({0.95, 0.40, 0.40})
        centredText(fonts.title, "You Lost", C.SW/2, by + 50)
    end

    setColor(PAL.white)
    centredText(fonts.med, res.desc, C.SW/2, by + 130)
    setColor(PAL.text_dim)
    centredText(fonts.small,
        string.format("Declarer took %d / %d tricks    Hand seed #%d",
                      game.tricksDeclarer, game.contractTricks, game.seed),
        C.SW/2, by + 162)
    setColor(PAL.white)
    centredText(fonts.med,
        string.format("Session   N-S: %d pts     E-W: %d pts",
                      game.sessionScore[1], game.sessionScore[2]),
        C.SW/2, by + 194)

    -- Buttons (anchored to bottom of the banner, well below the score line)
    local btnY = by + bh - 70
    local _, x1, y1, w1, h1 = button("NEW GAME",   C.SW/2 - 180, btnY, 170, 50, mx, my,
        {0.15, 0.55, 0.22}, {0.22, 0.78, 0.30})
    hits[#hits+1] = {type="newgame", x=x1, y=y1, w=w1, h=h1}
    local _, x2, y2, w2, h2 = button("Main Menu",  C.SW/2 + 10,  btnY, 170, 50, mx, my,
        PAL.btn_blue, PAL.btn_hover)
    hits[#hits+1] = {type="menu",    x=x2, y=y2, w=w2, h=h2}

    -- Confetti above all on win for the wow effect
    if won then drawConfetti() end

    return hits
end

-- ── Main menu ──────────────────────────────────────────────────────────────
function R.drawMainMenu(mx, my)
    setColor(PAL.felt)
    love.graphics.rectangle("fill", 0, 0, C.SW, C.SH)
    setColor(PAL.felt_inner)
    love.graphics.ellipse("fill", C.SW/2, C.SH/2, 560, 380)

    -- Title with a soft drop-shadow
    love.graphics.setFont(fonts.title)
    setColor(0, 0, 0, 0.45)
    centredText(fonts.title, "BRIDGE", C.SW/2 + 3, 178)
    setColor(PAL.yellow)
    centredText(fonts.title, "BRIDGE", C.SW/2, 175)

    setColor(PAL.text_dim)
    centredText(fonts.med, "Minibridge — single player", C.SW/2, 232)

    local hits = {}
    local cx = C.SW/2

    local _, x,y,w,h = button("NEW GAME", cx - 130, 340, 260, 60, mx, my,
                              {0.15, 0.55, 0.22}, {0.22, 0.78, 0.30})
    hits[#hits+1] = {type="newgame", x=x,y=y,w=w,h=h}

    local _, x2,y2,w2,h2 = button("Quit", cx - 80, 430, 160, 44, mx, my,
                                  PAL.btn_blue, PAL.btn_hover)
    hits[#hits+1] = {type="quit", x=x2,y=y2,w=w2,h=h2}

    setColor(PAL.text_dim)
    centredText(fonts.tiny, "You play as South (bottom).  Partners: North-South vs East-West.", C.SW/2, C.SH - 60)
    centredText(fonts.tiny, "Highest-HCP partnership declares.  Window is resizable.",            C.SW/2, C.SH - 44)

    return hits
end

-- ── New-game setup screen (seed input + AI difficulty) ─────────────────────
function R.drawNewGameSetup(setupState, mx, my)
    setColor(PAL.felt)
    love.graphics.rectangle("fill", 0, 0, C.SW, C.SH)
    setColor(PAL.felt_inner)
    love.graphics.ellipse("fill", C.SW/2, C.SH/2, 560, 380)

    setColor(PAL.yellow)
    centredText(fonts.huge, "New Game", C.SW/2, 78)
    setColor(PAL.text_dim)
    centredText(fonts.small, "Choose a hand seed and your opponents' difficulty.", C.SW/2, 122)

    local hits = {}

    -- ── Seed input row ──
    setColor(PAL.white)
    love.graphics.setFont(fonts.med)
    local seedLabel = "Hand seed:"
    local lblW = fonts.med:getWidth(seedLabel)
    local rowY = 175
    love.graphics.print(seedLabel, C.SW/2 - 180, rowY + 6)

    -- Text box for the seed (typed input)
    local boxX, boxY, boxW, boxH = C.SW/2 - 180 + lblW + 14, rowY, 150, 36
    local focus = setupState.seedFocus
    setColor(focus and {0.20, 0.30, 0.50} or {0.12, 0.18, 0.30})
    love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 6)
    setColor(focus and PAL.yellow or {0.4, 0.5, 0.7})
    love.graphics.setLineWidth(focus and 2 or 1)
    love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 6)
    love.graphics.setLineWidth(1)
    setColor(PAL.white)
    love.graphics.setFont(fonts.large)
    local txt = setupState.seedBuf
    if txt == "" then setColor(PAL.text_dim); txt = "type number..." end
    love.graphics.print(txt, boxX + 10, boxY + 4)
    -- Caret
    if focus and (math.floor(love.timer.getTime()*2) % 2 == 0) then
        setColor(PAL.yellow)
        local cw = fonts.large:getWidth(setupState.seedBuf or "")
        love.graphics.rectangle("fill", boxX + 10 + cw + 2, boxY + 8, 2, boxH - 16)
    end
    hits[#hits+1] = {type="seedbox", x=boxX, y=boxY, w=boxW, h=boxH}

    -- Random toggle (re-rolls a fresh seed every Deal)
    local randX = boxX + boxW + 16
    local randCol  = setupState.random and PAL.btn_green   or PAL.btn_blue
    local randHCol = setupState.random and PAL.btn_green_h or PAL.btn_hover
    local _, x,y,w,h = button(
        setupState.random and "Randomize: ON" or "Randomize: OFF",
        randX, rowY, 170, boxH, mx, my, randCol, randHCol)
    hits[#hits+1] = {type="random", x=x,y=y,w=w,h=h}

    setColor(PAL.text_dim)
    love.graphics.setFont(fonts.tiny)
    centredText(fonts.tiny,
        "Type a number, or turn Randomize ON to roll a new seed on Deal.",
        C.SW/2, rowY + boxH + 10)

    -- ── Auto-play South toggle (CPU plays your seat too) ──
    local autoRowY = rowY + boxH + 26
    local autoCol  = setupState.autoSouth and {0.70, 0.40, 0.10} or PAL.btn_blue
    local autoHCol = setupState.autoSouth and {0.85, 0.50, 0.18} or PAL.btn_hover
    local _, ax,ay,aw,ah = button(
        setupState.autoSouth and "Auto-play South: ON (CPU vs CPU)"
                             or  "Auto-play South: OFF (you play)",
        C.SW/2 - 190, autoRowY, 380, 32, mx, my, autoCol, autoHCol)
    hits[#hits+1] = {type="autosouth", x=ax, y=ay, w=aw, h=ah}

    -- ── Difficulty rows ──
    setColor(PAL.white)
    love.graphics.setFont(fonts.med)
    centredText(fonts.med, "AI Difficulty", C.SW/2, 284)

    local aiPlayers = {C.NORTH, C.EAST, C.WEST}
    for row, p in ipairs(aiPlayers) do
        local ry = 304 + (row-1) * 44
        setColor(PAL.text_dim)
        love.graphics.setFont(fonts.small)
        love.graphics.print(C.PLAYER_NAMES[p], C.SW/2 - 200, ry + 10)

        for d = 1, 3 do
            local bx    = C.SW/2 - 100 + (d-1) * 100
            local active= setupState.difficulty[p] == d
            local acol  = active and PAL.btn_green   or PAL.btn_blue
            local ahcol = active and PAL.btn_green_h or PAL.btn_hover
            local _, x,y,w,h = button(C.DIFF_NAMES[d], bx, ry, 88, 32, mx, my, acol, ahcol)
            hits[#hits+1] = {type="diff", player=p, diff=d, x=x,y=y,w=w,h=h}
        end
    end

    -- ── Settings row: intro animation, sound, card-back theme ──
    local setY = 452
    -- Intro animation toggle
    local introCol  = setupState.introAnim and PAL.btn_green   or PAL.btn_blue
    local introHCol = setupState.introAnim and PAL.btn_green_h or PAL.btn_hover
    local _, sx, sy, sw, sh = button(
        setupState.introAnim and "Intro Anim: ON" or "Intro Anim: OFF",
        C.SW/2 - 380, setY, 160, 32, mx, my, introCol, introHCol)
    hits[#hits+1] = {type="introanim", x=sx, y=sy, w=sw, h=sh}

    -- Sound toggle
    local sndCol  = setupState.soundOn and PAL.btn_green   or PAL.btn_blue
    local sndHCol = setupState.soundOn and PAL.btn_green_h or PAL.btn_hover
    local _, sx2, sy2, sw2, sh2 = button(
        setupState.soundOn and "Sound: ON" or "Sound: OFF",
        C.SW/2 - 210, setY, 140, 32, mx, my, sndCol, sndHCol)
    hits[#hits+1] = {type="sound", x=sx2, y=sy2, w=sw2, h=sh2}

    -- Card back theme preview + cycler
    local backX = C.SW/2 - 60
    setColor(PAL.text_dim)
    love.graphics.setFont(fonts.tiny)
    love.graphics.print("Back theme:", backX, setY + 2)
    -- Preview swatch
    local pvW, pvH = 44, 32
    setColor(0, 0, 0, 0.3)
    love.graphics.rectangle("fill", backX + 78, setY, pvW, pvH, 4)
    if currentBack then
        setColor(1, 1, 1)
        love.graphics.draw(currentBack, backX + 78, setY, 0,
            pvW / currentBack:getWidth(), pvH / currentBack:getHeight())
    end
    setColor(PAL.text_dim)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", backX + 78, setY, pvW, pvH, 4)
    -- prev / next theme buttons
    local _, px, py, pw, ph = button("<", backX + 130, setY, 32, 32, mx, my,
        PAL.btn_blue, PAL.btn_hover)
    hits[#hits+1] = {type="backprev", x=px, y=py, w=pw, h=ph}
    local _, nx, ny, nw, nh = button(">", backX + 170, setY, 32, 32, mx, my,
        PAL.btn_blue, PAL.btn_hover)
    hits[#hits+1] = {type="backnext", x=nx, y=ny, w=nw, h=nh}

    -- ── Deal button + Back ──
    local _, dx,dy,dw,dh = button("DEAL HAND", C.SW/2 - 120, 510, 240, 56, mx, my,
        {0.65,0.10,0.10}, {0.82,0.15,0.15})
    hits[#hits+1] = {type="deal", x=dx,y=dy,w=dw,h=dh}

    local _, bx2,by2,bw2,bh2 = button("< Main Menu", 40, 30, 160, 36, mx, my,
        PAL.btn_blue, PAL.btn_hover)
    hits[#hits+1] = {type="back", x=bx2,y=by2,w=bw2,h=bh2}

    return hits
end

return R
