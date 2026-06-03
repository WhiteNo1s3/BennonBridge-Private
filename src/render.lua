-- All rendering for the Bridge game

local C    = require("src.constants")
local AI   = require("src.ai")
local Mood = require("src.mood")

local R = {}

-- ── Active mood ────────────────────────────────────────────────────────────
-- The mood drives the felt tint AND the static vector decorations on every
-- backdrop. R.setMood is called from main.lua whenever the player tweaks
-- the weather toggle / manual mood picker in the setup screen; the cached
-- settings let us auto-refresh the active mood as wall-clock time crosses
-- into a new band while the game is running.
local activeMood    = Mood.classic
local cachedSettings = nil
local lastClockHour  = nil

-- Push the active mood's felt colour to the window background. LÖVE clears to
-- this every frame, so on wide/tall displays the letterbox margins fill with
-- the same felt instead of black bars — the table bleeds edge-to-edge and the
-- centred play area sits on top. Resolution-independent: works at any size.
local function applyMoodBackground()
    local f = activeMood.felt or {0.10, 0.34, 0.12}
    love.graphics.setBackgroundColor(f[1], f[2], f[3], 1)
end

function R.setMood(settings)
    cachedSettings = settings
    activeMood     = Mood.choose(settings)
    lastClockHour  = (os.date("*t") or {hour = 0}).hour
    applyMoodBackground()
end

-- Called from R.update so a long-running session re-themes itself as the
-- clock rolls into sunrise / noon / afternoon / evening / night.
local function refreshClockMood()
    if not cachedSettings or not cachedSettings.weatherOn then return end
    local h = (os.date("*t") or {hour = 0}).hour
    if h ~= lastClockHour then
        lastClockHour = h
        activeMood    = Mood.choose(cachedSettings)
        applyMoodBackground()
    end
end

-- Expose for the setup screen's preview swatches.
R.Mood = Mood

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

-- ── Mood backdrop ─────────────────────────────────────────────────────────
-- Single entry point that every R.draw* function calls instead of laying
-- down its own felt prologue. Takes the inner-oval radii so each screen
-- keeps its own table footprint (auction's table is tighter than the main
-- menu's, etc).
local function drawMoodBackdrop(rx, ry)
    activeMood:drawBackdrop(rx, ry)
    -- The corner vignette belongs to the TABLE, so it is drawn here — behind
    -- the cards — not at frame-end over everything. This guarantees the
    -- background never darkens or tints the cards themselves (cards on top).
    R.drawVignette()
end

-- ── Vignette overlay ──────────────────────────────────────────────────────
-- A faint darkening at the four corners of the virtual canvas. Call from
-- main.lua at the very end of every frame's drawing (right before V.drawEnd).
-- We use four large soft ellipses pulled out beyond the canvas edges — cheap
-- and looks like a real radial vignette without needing a shader.
function R.drawVignette()
    -- Four corner ellipses, alpha = 0.55 at the edge, fades to 0 toward centre.
    local function corner(cx, cy)
        for i = 1, 4 do
            local a = 0.08 * (5 - i)         -- 0.32, 0.24, 0.16, 0.08
            local r = 280 + i * 90
            love.graphics.setColor(0, 0, 0, a * 0.35)
            love.graphics.ellipse("fill", cx, cy, r, r * 0.72)
        end
    end
    corner(-60,        -60)
    corner(C.SW + 60,  -60)
    corner(-60,        C.SH + 60)
    corner(C.SW + 60,  C.SH + 60)
    love.graphics.setColor(1, 1, 1, 1)
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

    -- Re-pick the mood if the clock crossed an hour boundary while running.
    refreshClockMood()

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
local function maybeStartConfetti(game)
    if game.state == C.STATE_RESULT and not game.confettiFired then
        game.confettiFired = true
        if game.humanWon then
            confetti.particles = {}
            spawnConfettiBurst()
        else
            confetti.active = false
            confetti.particles = {}
        end
    end
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

local function centredText(font, text, cx, cy, maxWidth)
    love.graphics.setFont(font)
    local tw = (font:getWidth(text))
    local th = (font:getHeight())
    if maxWidth and tw > maxWidth then
        local scale = maxWidth / tw
        love.graphics.push()
        love.graphics.translate(cx, cy)
        love.graphics.scale(scale, scale)
        love.graphics.print(text, -tw/2, -th/2)
        love.graphics.pop()
    else
        love.graphics.print(text, cx - tw/2, cy - th/2)
    end
end

-- ── Modern hover-animated buttons ──────────────────────────────────────────
--
-- Per-button hover progress (0..1) eases towards the hover target every frame
-- and drives lift / scale / colour / glow / shadow. Signature is unchanged so
-- every existing caller keeps working — buttons just look more alive.

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
    local key = btnKey(label, x, y)
    hoverSeen[key] = true
    local prev   = hoverProgress[key] or 0
    local target = hov and 1 or 0
    local dt     = love.timer.getDelta() or 0
    local k      = math.min(1, dt * HOVER_SPEED)
    local raw    = prev + (target - prev) * k
    hoverProgress[key] = raw
    local p = easeOutCubic(raw)        -- 0..1, eased

    -- Press progress: while the user is hovering AND holding mouse-1 down,
    -- the button visually depresses for tactile click feedback.
    local pressKey = key .. "#press"
    hoverSeen[pressKey] = true
    local prevPress = hoverProgress[pressKey] or 0
    local pressTarget = (hov and love.mouse.isDown(1)) and 1 or 0
    local pressK = math.min(1, dt * 22)            -- snappier than hover
    local pressRaw = prevPress + (pressTarget - prevPress) * pressK
    hoverProgress[pressKey] = pressRaw
    local pr = easeOutCubic(pressRaw)              -- 0..1

    -- Derived visual params --------------------------------------------------
    -- Press eats the hover lift (so it feels pushed back into the desk) and
    -- shrinks scale very slightly.
    local lift    = -3 * p + 4 * pr               -- pixels (negative = up)
    local scale   = 1 + 0.035 * p - 0.020 * pr    -- 1.0 → 1.035 → 1.015
    local cx, cy  = x + w/2, y + h/2
    local fillCol = lerpColor(col, hcol, p)
    -- Brighten fill a touch more at full hover for extra "pop"
    fillCol[1] = math.min(1, fillCol[1] + 0.04 * p)
    fillCol[2] = math.min(1, fillCol[2] + 0.04 * p)
    fillCol[3] = math.min(1, fillCol[3] + 0.04 * p)
    -- Press darkens the fill so it visibly responds to clicks
    fillCol[1] = math.max(0, fillCol[1] - 0.12 * pr)
    fillCol[2] = math.max(0, fillCol[2] - 0.12 * pr)
    fillCol[3] = math.max(0, fillCol[3] - 0.12 * pr)

    -- Drop shadow (deeper when hovered → button feels lifted; tighter when
    -- pressed → button feels close to the desk).
    setColor(0, 0, 0, 0.28 + 0.18 * p - 0.10 * pr)
    local shY = 3 + 4 * p - 3 * pr
    love.graphics.rectangle("fill", x + 1, y + shY, w, h, 7)

    -- Body — scaled around centre so the layout / hit-box stays exact -------
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
        setColor(hcol[1], hcol[2], hcol[3], 0.22 * p)
        love.graphics.rectangle("line", x - 3, y - 3, w + 6, h + 6, 10)
        love.graphics.setLineWidth(1)
    end

    -- Label (slight brightness boost on hover) ------------------------------
    setColor(1, 1, 1, math.min(1, 0.92 + 0.08 * p))
    centredText(fonts.med, label, cx, cy)

    love.graphics.pop()
    setColor(1, 1, 1, 1)

    return hov, x, y, w, h
end

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


-- ── Unified card silhouette ────────────────────────────────────────────────
-- Every card — number, court, ace, or back — is drawn through the SAME two
-- calls so they all share one identical rounded-rectangle outline. The source
-- PNGs are inconsistent (numbers 280x392, ace 270x392, courts 539x784, backs
-- 275x392 with near-square corners). That left stray transparent edges, which
-- (a) made a back a slightly different shape/size than a face — the "dink" —
-- and (b) let the felt + mood decorations show through the corners onto the
-- card. We now lay down an OPAQUE card-stock base and clip the artwork to a
-- rounded rect with a stencil, so nothing behind a card can ever bleed onto
-- it and faces/backs are pixel-identical in silhouette.
local function beginCard(x, y, dimmed)
    -- Drop shadow
    setColor(PAL.shadow)
    love.graphics.rectangle("fill", x+2, y+3, CW, CH, CR)
    -- Opaque card-stock base (ivory) — the card is never see-through.
    if dimmed then setColor(0.80, 0.80, 0.80) else setColor(252/255, 250/255, 244/255) end
    love.graphics.rectangle("fill", x, y, CW, CH, CR)
    -- Clip everything drawn before endCard() to the exact rounded card shape.
    -- (stencil respects the current transform, so rotated E/W cards clip too.)
    love.graphics.stencil(function()
        love.graphics.rectangle("fill", x, y, CW, CH, CR)
    end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)
end

local function endCard(x, y, dimmed)
    love.graphics.setStencilTest()
    -- Crisp hairline border on the identical silhouette.
    love.graphics.setLineWidth(1)
    if dimmed then setColor(0.58, 0.58, 0.58) else setColor(208/255, 208/255, 208/255) end
    love.graphics.rectangle("line", x, y, CW, CH, CR)
    setColor(1, 1, 1)
end

-- Draw a face-up card with top-left corner at (x,y)
local function drawCardFace(x, y, card, highlight, dimmed)
    -- Highlight glow ring (drawn behind the card so only its rim peeks out)
    if highlight == "playable" then
        setColor(PAL.green_hi)
        love.graphics.rectangle("fill", x-3, y-3, CW+6, CH+6, CR+2)
    elseif highlight == "selected" then
        setColor(PAL.gold_hi)
        love.graphics.rectangle("fill", x-4, y-4, CW+8, CH+8, CR+3)
    end

    beginCard(x, y, dimmed)
    local img = cardImg[card.rank] and cardImg[card.rank][card.suit]
    if img then
        if dimmed then setColor(0.78, 0.78, 0.78) else setColor(1, 1, 1) end
        -- Number cards and Aces carry a small transparent margin in their
        -- source viewBox; expand a touch so the visible art reaches the card
        -- edge. The stencil clips any overflow, so the silhouette stays exact.
        local expand = (card.rank < 11 or card.rank == 14)
        local tw = expand and CW * (250/240) or CW
        local th = expand and CH * (350/340) or CH
        local dx = x - (tw - CW) / 2
        local dy = y - (th - CH) / 2
        love.graphics.draw(img, dx, dy, 0, tw / img:getWidth(), th / img:getHeight())
    end
    endCard(x, y, dimmed)
end

local function drawCardBack(x, y)
    beginCard(x, y, false)
    if currentBack then
        setColor(1, 1, 1)
        love.graphics.draw(currentBack, x, y, 0,
            CW / currentBack:getWidth(), CH / currentBack:getHeight())
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
    endCard(x, y, false)
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

-- Derived layout anchors (so a card-size change rescales the table). A side
-- (East/West) hand's centre sits SIDE_X in from the screen edge — far enough
-- that the wider rotated cards (half-width = CH/2) never clip. Its seat badge
-- sits SIDE_BADGE in from the edge, just clear of that hand's inboard edge.
local SIDE_X     = CH/2 + 8     -- West baseCX (East = SW - SIDE_X)
local SIDE_BADGE = CH + 30      -- West E/W badge x (East = SW - SIDE_BADGE)

-- Horizontal fan, face-up (South or North)
local function drawHorizHand(hand, baseX, baseY, faceUp, playableSet, selectedIdx, hoverIdx, flip)
    local n = #hand
    if n == 0 then return {} end
    local totalW = (n-1)*OV + CW
    local sx     = baseX - totalW/2
    local hits   = {}

    -- Per-card eased hover / selection progress so cards rise smoothly
    -- instead of snapping. Keyed by rank+suit (stable across deals; pruned
    -- automatically by the hover state cleanup in R.update).
    local dt = love.timer.getDelta() or 0
    local k  = math.min(1, dt * 14)

    for i, card in ipairs(hand) do
        local x = sx + (i-1)*OV

        local kk    = "hand:" .. (card.rank or 0) .. ":" .. (card.suit or 0)
        local sKey  = kk .. "#sel"
        hoverSeen[kk]   = true
        hoverSeen[sKey] = true

        local hPrev = hoverProgress[kk]   or 0
        local sPrev = hoverProgress[sKey] or 0
        local hRaw  = hPrev + ((hoverIdx    == i and 1 or 0) - hPrev) * k
        local sRaw  = sPrev + ((selectedIdx == i and 1 or 0) - sPrev) * k
        hoverProgress[kk]   = hRaw
        hoverProgress[sKey] = sRaw

        local hp = easeOutCubic(hRaw)
        local sp = easeOutCubic(sRaw)
        local liftHov = flip and  8 or -10
        local liftSel = flip and 12 or -14
        local dy = liftHov * hp + liftSel * sp

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

local TRICK_OFFSET = 76

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

-- ── Runtime card scaling ────────────────────────────────────────────────────
-- Re-scale every card-derived layout constant from a chosen base width. The
-- draw functions all close over these module locals, so reassigning them here
-- rescales the whole table coherently with no reload (images keep their linear
-- filter and just draw at a new size). All seat badges, side-hand insets and
-- the trick spread follow from CW/CH, so this stays consistent with the fix
-- that keeps decorations off the cards.
function R.setCardScale(sizeIdx)
    local widths = C.CARD_SIZE_W
    sizeIdx = math.max(1, math.min(#widths, math.floor(sizeIdx or C.CARD_SIZE_DEFAULT)))
    local w = widths[sizeIdx]
    CW = w
    CH = math.floor(w * (134 / 96) + 0.5)
    CR = math.max(4,  math.floor(w * (8  / 96) + 0.5))
    OV = math.max(12, math.floor(w * (30 / 96) + 0.5))
    SIDE_X     = CH / 2 + 8
    SIDE_BADGE = CH + 30
    -- Centre-trick offset: keep the original spacing where there's room, but
    -- never let a played card collide the N/S hands at large sizes. The North
    -- hand's bottom is 18+CH; the North trick card's top is 400-OFFSET-CH, so
    -- we need OFFSET < 382 - 2*CH (leaving a 6px gap). Symmetric for South.
    TRICK_OFFSET = math.floor(math.min(0.58 * CH, 382 - 2 * CH - 6))
    if TRICK_OFFSET < 10 then TRICK_OFFSET = 10 end
    R.CARD_SIZE = sizeIdx
end

-- ── Panels ─────────────────────────────────────────────────────────────────

local function drawPanel(x, y, w, h)
    setColor(PAL.panel)
    love.graphics.rectangle("fill", x, y, w, h, 9)
end

local function drawInfoPanel(game)
    if not game.contract then return end

    local w, h = 240, 180
    local x, y = C.SW - w - 15, 15
    
    -- Drop shadow
    setColor(0, 0, 0, 0.4)
    love.graphics.rectangle("fill", x+4, y+4, w, h, 10)
    
    -- Main slate panel
    setColor(0x2C/255, 0x30/255, 0x3A/255, 0.95)
    love.graphics.rectangle("fill", x, y, w, h, 10)
    
    -- Inner border
    setColor(0x3A/255, 0x40/255, 0x4A/255)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, w, h, 10)
    
    -- Contract Level & Suit
    local level = (game.contract.tricks or 7) - 6
    local extra = ""
    if game.contractRedoubled then extra = " XX"
    elseif game.contractDoubled then extra = " X" end
    
    -- Title: "CURRENT CONTRACT"
    love.graphics.setFont(fonts.small)
    setColor(0.6, 0.65, 0.7)
    centredText(fonts.small, "CURRENT CONTRACT", x + w/2, y + 18)
    
    -- Big Contract display (e.g. "4 S")
    love.graphics.setFont(fonts.large)
    setColor(PAL.white)
    
    local contractText = tostring(level) .. extra
    local cWidth = fonts.large:getWidth(contractText)
    local cx = x + w/2
    
    if game.trumpSuit then
        cWidth = cWidth + 24 -- roughly the space for the pip
        local tx = cx - cWidth/2
        love.graphics.print(contractText, tx, y + 36)
        setColor(C.SUIT_IS_RED[game.trumpSuit] and PAL.red_suit or PAL.white)
        drawPip(game.trumpSuit, tx + cWidth - 8, y + 54, 12)
    else
        contractText = contractText .. " NT"
        centredText(fonts.large, contractText, cx, y + 54)
    end
    
    -- "4 + 6 = 10 Tricks" line
    setColor(PAL.gold_hi)
    love.graphics.setFont(fonts.med)
    local targetLine = string.format("Target: %d + 6 = %d Tricks", level, game.contractTricks)
    centredText(fonts.med, targetLine, cx, y + 90)
    
    -- Declarer
    setColor(0.7, 0.75, 0.8)
    love.graphics.setFont(fonts.small)
    centredText(fonts.small, "Declarer: " .. C.PLAYER_NAMES[game.declarer], cx, y + 116)
    
    -- Separator line
    setColor(0x3A/255, 0x40/255, 0x4A/255)
    love.graphics.line(x + 20, y + 135, x + w - 20, y + 135)
    
    -- Tricks won so far
    local dSide = game.declaringSide == "NS" and "N-S" or "E-W"
    local xSide = game.declaringSide == "NS" and "E-W" or "N-S"
    
    setColor(PAL.white)
    love.graphics.setFont(fonts.med)
    local scoreText = string.format("%s: %d      %s: %d", dSide, game.tricksDeclarer, xSide, game.tricksDefender)
    centredText(fonts.med, scoreText, cx, y + 154)
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
    love.graphics.print(htxt, x + w - (fonts.small:getWidth(htxt)) - 8, y+9)
    love.graphics.setFont(fonts.med)
    setColor(PAL.white)
    love.graphics.print(string.format("N-S : %d", game.sessionScore[1]), x+8, y+28)
    love.graphics.print(string.format("E-W : %d", game.sessionScore[2]), x+8, y+50)
end

-- ── Seat badges: compass direction glyph + role chip ───────────────────────
-- A product-grade replacement for the old "[D]/[dum]" text tags. Each seat
-- gets a small vector compass token (dark disc, accent ring, a needle pointing
-- the seat's true bearing, and the N/E/S/W letter) plus an optional rounded
-- role chip ("DECLARER" / "DUMMY"). Pure vector — crisp at 4K/tablet.

local SEAT_LETTER = {
    [C.NORTH] = "N", [C.EAST] = "E", [C.SOUTH] = "S", [C.WEST] = "W",
}
-- Screen bearing of each seat (radians; 0 = +x/east, clockwise in screen space)
local SEAT_BEARING = {
    [C.NORTH] = -math.pi/2, [C.EAST] = 0, [C.SOUTH] = math.pi/2, [C.WEST] = math.pi,
}

-- Accent colour + active flag for a seat given the current game state.
local function seatAccent(game, p)
    if game.currentPlayer == p then return PAL.yellow, true end
    if game.declarer    == p then return {0.42, 0.92, 0.48}, false end
    if game.dummy       == p then return {0.98, 0.74, 0.30}, false end
    return {0.58, 0.65, 0.76}, false
end

-- Small rounded role chip centred on (cx,cy). Returns its width/height.
local function drawRoleChip(cx, cy, text, bg)
    love.graphics.setFont(fonts.tiny)
    local tw   = fonts.tiny:getWidth(text)
    local pad  = 7
    local w, h = tw + pad*2, 17
    local x, y = cx - w/2, cy - h/2
    setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", x+1, y+1, w, h, 8)
    setColor(bg[1], bg[2], bg[3], 0.96)
    love.graphics.rectangle("fill", x, y, w, h, 8)
    setColor(1, 1, 1, 0.96)
    love.graphics.print(text, x + pad, y + (h - fonts.tiny:getHeight())/2)
    return w, h
end

-- The compass token. r = disc radius.
local function compassToken(cx, cy, r, seat, accent, active)
    -- Drop shadow
    setColor(0, 0, 0, 0.38)
    love.graphics.circle("fill", cx + 1, cy + 2, r)
    -- Base disc (dark slate)
    setColor(0.13, 0.15, 0.20, 0.96)
    love.graphics.circle("fill", cx, cy, r)
    -- Glow halo when it's this seat's turn
    if active then
        for i = 1, 3 do
            setColor(accent[1], accent[2], accent[3], 0.12 * (4 - i))
            love.graphics.circle("line", cx, cy, r + i * 2.4)
        end
    end
    -- Accent ring
    love.graphics.setLineWidth(active and 3 or 2)
    setColor(accent[1], accent[2], accent[3], active and 1.0 or 0.72)
    love.graphics.circle("line", cx, cy, r)
    love.graphics.setLineWidth(1)
    -- Four cardinal markers on the INSIDE of the rim. The seat's own bearing
    -- gets an accent wedge pointing inward (kept fully inside the disc, so it
    -- never pokes off-screen on the East/West edges); the other three are
    -- small faint dots. This reads as a compass without any clipping.
    local da = SEAT_BEARING[seat]
    for i = 0, 3 do
        local a = -math.pi/2 + i * math.pi/2
        if math.abs(((a - da + math.pi) % (math.pi*2)) - math.pi) < 0.01 then
            -- seat's own direction: a short accent wedge inset from the rim,
            -- pointing toward the centre
            local baseR = r - 2.5
            local tipR  = r - 8.5
            local tipx  = cx + math.cos(a) * tipR
            local tipy  = cy + math.sin(a) * tipR
            local b1x   = cx + math.cos(a + 0.42) * baseR
            local b1y   = cy + math.sin(a + 0.42) * baseR
            local b2x   = cx + math.cos(a - 0.42) * baseR
            local b2y   = cy + math.sin(a - 0.42) * baseR
            setColor(accent[1], accent[2], accent[3], 0.95)
            love.graphics.polygon("fill", tipx, tipy, b1x, b1y, b2x, b2y)
        else
            local tx = cx + math.cos(a) * (r - 3.5)
            local ty = cy + math.sin(a) * (r - 3.5)
            setColor(1, 1, 1, 0.20)
            love.graphics.circle("fill", tx, ty, 1.2)
        end
    end
    -- Seat letter, centred
    love.graphics.setFont(fonts.small)
    local L  = SEAT_LETTER[seat]
    local lw = fonts.small:getWidth(L)
    local lh = fonts.small:getHeight()
    setColor(1, 1, 1, 0.97)
    love.graphics.print(L, cx - lw/2, cy - lh/2)
end

local function roleFor(game, p)
    if game.declarer == p then return "DECLARER", {0.16, 0.46, 0.21} end
    if game.dummy    == p then return "DUMMY",    {0.62, 0.42, 0.10} end
    return nil
end

local function drawPlayerLabels(game)
    -- {cx, cy, layout}  layout "h" = horizontal plate (N/S), "v" = compact (E/W)
    -- All derived from card height so a card-size change keeps the badges clear
    -- of the hands. N/S sit just outside their hand; E/W sit inboard of the side
    -- columns in clear felt (SIDE_BADGE), never on top of the cards.
    local pos = {
        [C.NORTH] = {C.SW/2,             18 + CH + 23,        "h"},
        [C.SOUTH] = {C.SW/2,             C.SH - CH - 18 - 23, "h"},
        [C.EAST]  = {C.SW - SIDE_BADGE,  C.SH/2,              "v"},
        [C.WEST]  = {SIDE_BADGE,         C.SH/2,              "v"},
    }

    for p, pt in pairs(pos) do
        local cx, cy, mode = pt[1], pt[2], pt[3]
        local accent, active = seatAccent(game, p)
        local name = C.PLAYER_NAMES[p]
        local hcp  = game.hcp and game.hcp[p]
        local role, roleBg = roleFor(game, p)

        if mode == "h" then
            -- Horizontal name-plate: [token]  Name / HCP  [chip]
            local r       = 17
            local gap     = 9
            love.graphics.setFont(fonts.small)
            local nameW   = fonts.small:getWidth(name)
            love.graphics.setFont(fonts.tiny)
            local hcpStr  = hcp and ("HCP " .. hcp) or ""
            local hcpW    = fonts.tiny:getWidth(hcpStr)
            local textW   = math.max(nameW, hcpW)
            local chipW   = role and (fonts.tiny:getWidth(role) + 14) or 0
            local chipGap = role and 9 or 0
            local totalW  = r*2 + gap + textW + chipGap + chipW
            local x0      = cx - totalW/2

            compassToken(x0 + r, cy, r, p, accent, active)

            local tx = x0 + r*2 + gap
            love.graphics.setFont(fonts.small)
            setColor(active and PAL.yellow or PAL.white)
            love.graphics.print(name, tx, cy - 14)
            love.graphics.setFont(fonts.tiny)
            setColor(PAL.text_dim)
            love.graphics.print(hcpStr, tx, cy + 3)

            if role then
                drawRoleChip(x0 + r*2 + gap + textW + chipGap + chipW/2, cy, role, roleBg)
            end
        else
            -- Compact vertical token at the side edge. HCP under, chip over.
            local r = 16
            compassToken(cx, cy, r, p, accent, active)
            if hcp then
                love.graphics.setFont(fonts.tiny)
                setColor(PAL.text_dim)
                local s  = "HCP " .. hcp
                local sw = fonts.tiny:getWidth(s)
                -- keep on-screen: clamp the label box inside the canvas
                local lx = math.max(2, math.min(C.SW - sw - 2, cx - sw/2))
                setColor(0, 0, 0, 0.35)
                love.graphics.rectangle("fill", lx - 3, cy + r + 2, sw + 6, 15, 6)
                setColor(PAL.text_dim)
                love.graphics.print(s, lx, cy + r + 4)
            end
            if role then
                local cw = fonts.tiny:getWidth(role) + 14
                local ccx = math.max(cw/2 + 2, math.min(C.SW - cw/2 - 2, cx))
                drawRoleChip(ccx, cy - r - 12, role, roleBg)
            end
        end
    end
    setColor(1, 1, 1, 1)
end

-- ── Announcement / calling phase ───────────────────────────────────────────
-- Per Minibridge rules: every hand starts with each player (N->E->S->W)
-- announcing their HCP, then the declaring side and declarer are revealed.
local function drawSpeechBubble(cx, cy, text, anchor)
    love.graphics.setFont(fonts.med)
    local tw  = (fonts.med:getWidth(text))
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
    love.graphics.print(text, bx + pad, by + (bh - (fonts.med:getHeight()))/2)
end

-- A "bidding card" — small card-shaped element placed on the table by a
-- player to record their announcement. Visually mirrors a real playing card:
-- white rounded body, light grey border, big rank-style number, suit pip,
-- rotated repeat in the bottom-right corner, soft shadow.
--
-- For the SUIT decoration we pick the partnership's emblematic suit:
--   N/S -> Hearts (red),  E/W -> Spades (black).
-- This gives each side a distinct visual identity on the calling board.
local BID_BLOCK_W, BID_BLOCK_H, BID_BLOCK_R = 76, 50, 6

local function drawBidCard(cx, cy, hcp, suit, rotation, highlight)
    rotation = rotation or 0
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(rotation)
    local x, y = -BID_BLOCK_W/2, -BID_BLOCK_H/2

    -- Shadow
    setColor(0, 0, 0, 0.4)
    love.graphics.rectangle("fill", x+3, y+4, BID_BLOCK_W, BID_BLOCK_H, BID_BLOCK_R)

    -- Glow ring if active player
    if highlight then
        setColor(PAL.yellow)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", x-4, y-4, BID_BLOCK_W+8, BID_BLOCK_H+8, BID_BLOCK_R+2)
        love.graphics.setLineWidth(1)
    end

    -- Block body - sleek dark grey/blue plastic tile look
    setColor(0.15, 0.18, 0.22)
    love.graphics.rectangle("fill", x, y, BID_BLOCK_W, BID_BLOCK_H, BID_BLOCK_R)
    
    -- Inner flat bevel
    setColor(0.25, 0.28, 0.32)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x+2, y+2, BID_BLOCK_W-4, BID_BLOCK_H-4, BID_BLOCK_R-1)
    love.graphics.setLineWidth(1)

    -- Centre: big HCP value (the "call") in pure white or bright color
    setColor(PAL.white)
    love.graphics.setFont(fonts.large)
    local fw = fonts.large:getWidth(tostring(hcp))
    local fh = fonts.large:getHeight()
    love.graphics.print(tostring(hcp), -fw/2, -fh/2 - 4)

    -- Tiny "PTS" label
    setColor(0.7, 0.7, 0.7)
    love.graphics.setFont(fonts.tiny)
    centredText(fonts.tiny, "PTS", 0, BID_BLOCK_H/2 - 12)

    love.graphics.pop()
end

-- Empty placeholder block slot
local function drawBidCardSlot(cx, cy, rotation, highlight)
    rotation = rotation or 0
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(rotation)
    local x, y = -BID_BLOCK_W/2, -BID_BLOCK_H/2

    setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", x, y, BID_BLOCK_W, BID_BLOCK_H, BID_BLOCK_R)
    
    if highlight then
        setColor(PAL.yellow)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x, y, BID_BLOCK_W, BID_BLOCK_H, BID_BLOCK_R)
    else
        setColor(0.45, 0.45, 0.45, 0.5)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", x, y, BID_BLOCK_W, BID_BLOCK_H, BID_BLOCK_R)
    end
    love.graphics.setLineWidth(1)
    love.graphics.pop()
end

-- ── Dealing animation ─────────────────────────────────────────────────────

function R.drawDealing(game)
    local Anim = require("src.anim")
    drawMoodBackdrop(C.SW * 0.40, C.SH * 0.45)

    -- Player labels (no HCP yet). N/S clear the taller hands.
    local labelPos = {
        [C.NORTH] = {C.SW/2,     18 + CH + 6},
        [C.EAST]  = {C.SW - 38,  C.SH/2},
        [C.SOUTH] = {C.SW/2,     C.SH - CH - 18 - 22},
        [C.WEST]  = {38,         C.SH/2},
    }
    love.graphics.setFont(fonts.small)
    setColor(PAL.text_dim)
    for p, pt in pairs(labelPos) do
        local name = C.PLAYER_NAMES[p]
        if game.auction and game.auction.dealer == p then name = name .. " (D)" end
        local tw = (fonts.small:getWidth(name))
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

    -- Grid cells -----------------------------------------------------------
    -- Each cell carries its own eased hover progress so the highlight slides
    -- in/out smoothly instead of snapping. Selection also eases for a soft
    -- "lock-in" feel.
    local cellDt = love.timer.getDelta() or 0
    local cellK  = math.min(1, cellDt * 16)

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

            -- Eased progress: hover only counts when the cell is legal,
            -- otherwise illegal cells subtly shimmer on hover which is
            -- visually misleading.
            local kk    = "bid:" .. level .. ":" .. denom
            local sKey  = kk .. "#sel"
            hoverSeen[kk]   = true
            hoverSeen[sKey] = true
            local hPrev = hoverProgress[kk]   or 0
            local sPrev = hoverProgress[sKey] or 0
            local hRaw  = hPrev + (((hov and legal) and 1 or 0) - hPrev) * cellK
            local sRaw  = sPrev + ((sel and 1 or 0) - sPrev) * cellK
            hoverProgress[kk]   = hRaw
            hoverProgress[sKey] = sRaw
            local hp = easeOutCubic(hRaw)
            local sp = easeOutCubic(sRaw)

            -- Background — lerp between resting / hover / selected
            local baseBg = legal and {0.99, 0.97, 0.92} or {0.12, 0.12, 0.12}
            local hovBg  = {0.20, 0.20, 0.20}
            local selBg  = {0.55, 0.45, 0.08}
            local bg     = baseBg
            if hp > 0 then bg = lerpColor(baseBg, hovBg, hp) end
            if sp > 0 then bg = lerpColor(bg,     selBg, sp) end
            setColor(bg)
            love.graphics.rectangle("fill", cx, cy, cellW, cellH, 4)

            -- Top sheen on hover for a touch of "lit" feel
            if hp > 0.01 and legal then
                setColor(1, 1, 1, 0.06 * hp)
                love.graphics.rectangle("fill", cx + 1, cy + 1,
                    cellW - 2, math.max(2, cellH * 0.45), 4)
            end

            -- Border — colour eases towards yellow on selection
            local restBorder = legal and {0.65, 0.65, 0.65} or {0.30, 0.30, 0.30}
            local borderCol  = lerpColor(restBorder, PAL.yellow, sp)
            setColor(borderCol)
            love.graphics.setLineWidth(1 + sp)
            love.graphics.rectangle("line", cx, cy, cellW, cellH, 4)
            -- Outer glow ring when selected
            if sp > 0.05 then
                setColor(PAL.yellow[1], PAL.yellow[2], PAL.yellow[3], 0.35 * sp)
                love.graphics.rectangle("line", cx - 2, cy - 2,
                    cellW + 4, cellH + 4, 6)
            end
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
    drawMoodBackdrop(C.SW * 0.40, C.SH * 0.45)

    local hits = {}
    local a    = game.auction

    -- Hand display: South always face-up; others face-down during the auction
    drawHorizHand(game.hands[C.NORTH], C.SW/2, 18,             false, nil, nil, nil, false)
    drawHorizHand(game.hands[C.SOUTH], C.SW/2, C.SH-CH-18,     true,  nil, nil, nil, false)
    drawVertHand (game.hands[C.EAST],  C.SW-SIDE_X, C.SH/2,  math.pi/2, false, nil)
    drawVertHand (game.hands[C.WEST],  SIDE_X,      C.SH/2, -math.pi/2, false, nil)

    -- Player labels with HCP, current bidder highlighted
    local labelPos = {
        [C.NORTH] = {C.SW/2,          18 + CH + 6},      -- just below the taller hand
        [C.EAST]  = {C.SW - 38,       C.SH/2},
        [C.SOUTH] = {C.SW/2,          C.SH - CH - 18 - 22}, -- just above the taller hand
        [C.WEST]  = {38,              C.SH/2},
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
        local tw = (fonts.small:getWidth(name))
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
    drawMoodBackdrop(430, 310)

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
    local eHits = drawVertHand(game.hands[C.EAST], C.SW - SIDE_X, C.SH/2,
                    math.pi/2, eFace, ePlayable)
    local wHits = drawVertHand(game.hands[C.WEST], SIDE_X, C.SH/2,
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
    drawMoodBackdrop(430, 310)

    drawHorizHand(game.hands[C.SOUTH], C.SW/2, C.SH - CH - 18, true, nil, nil, nil, false)
    drawHorizHand(game.hands[C.NORTH], C.SW/2, 18, true, nil, nil, nil, false)

    -- North is the partner whose hand is shown face-up: mark it with the same
    -- product-grade chip used on the table, not a bare debug string. Sits just
    -- below the (now taller) north hand.
    drawRoleChip(C.SW/2, 18 + CH + 14, "DUMMY", {0.62, 0.42, 0.10})

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

-- ── Modern result banner ──────────────────────────────────────────────────
-- A polished card with a soft drop shadow, subtle vertical gradient inside,
-- an accent ribbon along the top edge, and a 2-tone border. Replaces the
-- bare rectangle("fill") + rectangle("line") prologue every winner panel
-- used to do. Cards / text rendered by the caller AFTER this returns sit on
-- top, as expected.
local function drawModernBanner(bx, by, bw, bh, accent, won)
    -- Drop shadow underneath
    for i = 1, 6 do
        love.graphics.setColor(0, 0, 0, 0.05 * (7 - i))
        love.graphics.rectangle("fill",
            bx - i * 0.5, by + i * 1.6, bw + i, bh + i * 0.6, 18)
    end
    -- Main body — vertical gradient via stacked semi-transparent strips
    local segs = 24
    for i = 0, segs - 1 do
        local t = i / (segs - 1)
        -- Top is slightly lighter than the bottom, for depth
        local v = 0.04 + (1 - t) * 0.05
        love.graphics.setColor(v + 0.02, v + 0.03, v + 0.05, 0.92)
        love.graphics.rectangle("fill",
            bx, by + (bh / segs) * i, bw, bh / segs + 1)
    end
    -- Re-cut the rounded corners by stamping a clear rounded mask: easier
    -- to just redraw the body once over the gradient with alpha=0 on the
    -- corners via stencil — but a much cheaper trick is to overdraw a thin
    -- frame matching the felt at each rounded corner. We accept the slight
    -- square corners on the gradient strips and lay the border on top:
    -- Inner glow ring (very subtle)
    love.graphics.setColor(accent[1], accent[2], accent[3], 0.10)
    love.graphics.setLineWidth(6)
    love.graphics.rectangle("line", bx + 3, by + 3, bw - 6, bh - 6, 16)
    -- Crisp outer border in accent colour
    love.graphics.setLineWidth(3)
    love.graphics.setColor(accent[1], accent[2], accent[3], 1.0)
    love.graphics.rectangle("line", bx, by, bw, bh, 18)
    -- Top accent ribbon — small bar across the top edge
    love.graphics.setColor(accent[1], accent[2], accent[3], 0.85)
    love.graphics.rectangle("fill", bx + 24, by - 3, bw - 48, 8, 4)
    -- Two small chevron tabs flanking the ribbon for a trophy-cup feel
    love.graphics.polygon("fill",
        bx + 12, by + 2,  bx + 28, by - 4,  bx + 28, by + 12)
    love.graphics.polygon("fill",
        bx + bw - 12, by + 2,  bx + bw - 28, by - 4,  bx + bw - 28, by + 12)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

-- ── Vector "W" winner badge ───────────────────────────────────────────────
-- A purely-vector ornament for the winner banner. A double-V "W" glyph in
-- a circular medallion, framed by two laurel branches and a crown of three
-- points. Stays crisp at any zoom and any DPI — ideal for 4K / tablet.
-- `won = false` draws a muted gray version (loss screen).
local function drawWinnerBadge(cx, cy, size, won)
    local accent = won and {1.00, 0.82, 0.15} or {0.60, 0.62, 0.66}
    local dark   = won and {0.55, 0.40, 0.05} or {0.30, 0.32, 0.36}
    local glow   = won and {1.00, 0.92, 0.40} or {0.45, 0.48, 0.55}

    -- Soft halo glow
    if won then
        for i = 5, 1, -1 do
            love.graphics.setColor(glow[1], glow[2], glow[3], 0.06 * i)
            love.graphics.circle("fill", cx, cy, size * (0.95 + i * 0.18))
        end
    end

    -- Outer medallion ring
    love.graphics.setColor(dark)
    love.graphics.circle("fill", cx, cy, size * 0.95)
    love.graphics.setColor(accent)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", cx, cy, size * 0.95)
    -- Inner ring
    love.graphics.setLineWidth(1)
    love.graphics.circle("line", cx, cy, size * 0.78)

    -- Inner medallion fill (slightly darker)
    love.graphics.setColor(dark[1] * 0.7, dark[2] * 0.7, dark[3] * 0.7, 1)
    love.graphics.circle("fill", cx, cy, size * 0.78)

    -- The W glyph — two thick V chevrons mirrored. Drawn as 4 trapezoids so
    -- it stays sharp at any scale (no font rasterisation).
    love.graphics.setColor(accent)
    local s   = size * 0.55          -- half-width of the W
    local h   = size * 0.55          -- half-height of the W
    local th  = size * 0.16          -- stroke thickness
    -- Left V: outer-top-left → inner-bottom → outer-top-mid
    love.graphics.polygon("fill",
        cx - s,         cy - h,
        cx - s + th,    cy - h,
        cx - s * 0.18,  cy + h,
        cx - s * 0.18 - th * 0.8, cy + h)
    love.graphics.polygon("fill",
        cx - s * 0.18,  cy + h,
        cx - s * 0.18 + th * 0.8, cy + h,
        cx + th * 0.5,  cy - h * 0.15,
        cx,             cy - h * 0.15)
    -- Right V (mirror)
    love.graphics.polygon("fill",
        cx + s,         cy - h,
        cx + s - th,    cy - h,
        cx + s * 0.18,  cy + h,
        cx + s * 0.18 + th * 0.8, cy + h)
    love.graphics.polygon("fill",
        cx + s * 0.18,  cy + h,
        cx + s * 0.18 - th * 0.8, cy + h,
        cx - th * 0.5,  cy - h * 0.15,
        cx,             cy - h * 0.15)

    -- Crown above: three small triangles sitting on a thin bar
    love.graphics.setColor(accent)
    love.graphics.rectangle("fill",
        cx - size * 0.40, cy - size * 1.08, size * 0.80, size * 0.10, 2)
    for i = -1, 1 do
        local tx = cx + i * size * 0.32
        love.graphics.polygon("fill",
            tx - size * 0.13, cy - size * 1.08,
            tx,                cy - size * 1.45,
            tx + size * 0.13, cy - size * 1.08)
        -- A small gem ball atop each crown spike
        love.graphics.circle("fill", tx, cy - size * 1.48, size * 0.07)
    end

    -- Laurel branches flanking the medallion (six leaves each side)
    love.graphics.setColor(accent[1] * 0.85, accent[2] * 0.85, accent[3] * 0.85, 0.95)
    love.graphics.setLineWidth(2)
    local function laurel(dir)
        local baseA = dir > 0 and math.pi * 0.05 or math.pi * 0.95
        -- Spine
        local spineEndX = cx + math.cos(baseA + math.pi * 0.5) * size * 1.20
                          + dir * size * 0.10
        local spineEndY = cy + math.sin(baseA + math.pi * 0.5) * size * 1.20
        love.graphics.line(
            cx + dir * size * 0.95, cy + size * 0.05,
            spineEndX,              spineEndY)
        -- 5 leaves
        for i = 1, 5 do
            local t  = i / 6
            local lx = cx + dir * size * (0.95 + t * 0.32)
            local ly = cy + size * 0.05 - t * size * 1.05
            local lr = size * 0.18 * (1 - t * 0.45)
            love.graphics.push()
            love.graphics.translate(lx, ly)
            love.graphics.rotate(dir * (-0.45 - t * 0.4))
            -- Leaf shape: filled ellipse
            love.graphics.ellipse("fill", 0, 0, lr * 1.6, lr * 0.6)
            love.graphics.pop()
        end
    end
    laurel( 1)
    laurel(-1)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

-- ── Result screen ──────────────────────────────────────────────────────────
function R.drawResult(game, setupState, mx, my)
    -- Fire confetti once on entry if the human won
    maybeStartConfetti(game)
    
    if not game.resultSeedPrepared then
        game.resultSeedPrepared = true
        if setupState.random then
            setupState.seedBuf = tostring(love.math.random(1, 99999))
        else
            setupState.seedBuf = tostring(game.seed + 1)
        end
    end

    if game.matchMode == "7board" then
        R.drawGame(game, nil, nil, nil, nil)
        
        setColor(0, 0, 0, 0.65)
        love.graphics.rectangle("fill", 0, 0, C.SW, C.SH)
        
        local bw, bh = 720, 440
        local bx, by = C.SW/2 - bw/2, C.SH/2 - bh/2
        local maxTxt = bw - 60        -- safe inner width for centred text

        local won = game.humanWon
        local accent = won and PAL.yellow or {0.85, 0.25, 0.25}
        drawModernBanner(bx, by, bw, bh, accent, won)

        -- Title (auto-shrinks to fit)
        setColor(PAL.yellow)
        centredText(fonts.title,
            "BOARD " .. tostring(game.matchBoard) .. " OF 7 COMPLETE",
            C.SW/2, by + 55, maxTxt)

        setColor(won and {0.35, 0.90, 0.45} or {0.95, 0.35, 0.35})
        local resultStr = won and "NORTH-SOUTH WINS THE BOARD!" or "EAST-WEST WINS THE BOARD!"
        centredText(fonts.large, resultStr, C.SW/2, by + 110, maxTxt)

        local res = game.handResult
        setColor(PAL.white)
        centredText(fonts.med, res.desc, C.SW/2, by + 150, maxTxt)

        setColor(PAL.text_dim)
        love.graphics.setFont(fonts.med)
        love.graphics.print("TEAM", C.SW/2 - 240, by + 200)
        centredText(fonts.med, "BOARDS WON", C.SW/2, by + 200, 160)
        love.graphics.print("TOTAL POINTS", C.SW/2 + 130, by + 200)

        setColor(0.3, 0.4, 0.5, 0.4)
        love.graphics.line(C.SW/2 - 250, by + 230, C.SW/2 + 250, by + 230)

        setColor(PAL.white)
        love.graphics.setFont(fonts.large)
        love.graphics.print("North-South (NS)", C.SW/2 - 240, by + 245)
        centredText(fonts.large, tostring(game.matchWins and game.matchWins[1] or 0), C.SW/2, by + 245, 120)
        love.graphics.print(tostring(game.sessionScore[1]) .. " pts", C.SW/2 + 130, by + 245)

        love.graphics.print("East-West (EW)", C.SW/2 - 240, by + 290)
        centredText(fonts.large, tostring(game.matchWins and game.matchWins[2] or 0), C.SW/2, by + 290, 120)
        love.graphics.print(tostring(game.sessionScore[2]) .. " pts", C.SW/2 + 130, by + 290)

        setColor(0.3, 0.4, 0.5, 0.4)
        love.graphics.line(C.SW/2 - 250, by + 335, C.SW/2 + 330, by + 335)

        setColor(PAL.text_dim)
        centredText(fonts.small,
            "Match Start Seed: #" .. tostring(game.matchStartSeed or game.seed)
            .. "     Board Seed: #" .. tostring(game.seed),
            C.SW/2, by + 360, maxTxt)

        setColor(PAL.yellow)
        local promptText = game.autoSouth and "Auto-advancing in a few seconds..."
            or "Click anywhere to randomize and deal next board"
        centredText(fonts.med, promptText, C.SW/2, by + 395, maxTxt)
        
        local hits = {}
        hits[1] = {type = "next_board_anywhere", x = 0, y = 0, w = C.SW, h = C.SH}
        
        if won then drawConfetti() end
        return hits
    end

    drawMoodBackdrop(C.SW * 0.42, C.SH * 0.48)

    local hits = {}
    local won  = game.humanWon
    local res  = game.handResult

    -- On loss, reveal all four ORIGINAL hands (as they were dealt). On win,
    -- skip that and just show the celebration.
    if not won then
        -- Keep the reveal mini-fans at their original pixel size regardless of
        -- the play-card bump, so they stay clear of the central banner/labels.
        local RS = 0.62 * 70 / CW
        local function fanH(hand, baseX, baseY)
            -- compact horizontal fan, face-up, no interactivity
            local n   = #hand
            local cw  = CW * RS
            local gap = cw * 0.42
            local total = (n - 1) * gap + cw
            local x0  = baseX - total/2
            for i, c in ipairs(hand) do
                love.graphics.push()
                love.graphics.translate(x0 + (i-1)*gap, baseY)
                love.graphics.scale(RS, RS)
                drawCardFace(0, 0, c, nil, false)
                love.graphics.pop()
            end
        end
        local function fanV(hand, baseX, baseY)
            local n   = #hand
            local ch  = CH * RS
            local gap = ch * 0.38
            local total = (n - 1) * gap + ch
            local y0  = baseY - total/2
            for i, c in ipairs(hand) do
                love.graphics.push()
                love.graphics.translate(baseX, y0 + (i-1)*gap)
                love.graphics.scale(RS, RS)
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

    -- Central banner — modern look with shadow, gradient, accent ribbon and
    -- a vector W badge above the headline. Sized to comfortably hold all of
    -- the body text, the seed-input row and the action buttons.
    local bw, bh = 680, 340
    local bx, by = C.SW/2 - bw/2, C.SH/2 - bh/2
    local maxTxt = bw - 60
    local accent = won and PAL.yellow or {0.85, 0.25, 0.25}
    drawModernBanner(bx, by, bw, bh, accent, won)

    -- Vector winner / loss badge, sits above the headline. Doesn't shift the
    -- existing layout below it (the badge is anchored above by+20).
    drawWinnerBadge(C.SW/2, by + 6, 22, won)

    -- Headline (auto-shrinks to fit; YOU WON / You Lost both safely fit).
    if won then
        setColor(PAL.yellow)
        centredText(fonts.title, "YOU WON!", C.SW/2, by + 60, maxTxt)
    else
        setColor({0.95, 0.40, 0.40})
        centredText(fonts.title, "You Lost", C.SW/2, by + 60, maxTxt)
    end

    setColor(PAL.white)
    centredText(fonts.med, res.desc, C.SW/2, by + 140, maxTxt)
    setColor(PAL.text_dim)
    centredText(fonts.small,
        string.format("Declarer took %d / %d tricks    Hand seed #%d",
                      game.tricksDeclarer, game.contractTricks, game.seed),
        C.SW/2, by + 172, maxTxt)
    setColor(PAL.white)
    local sessionLabel = game.matchMode == "7board"
        and string.format("Match Score (Board %d/7)", game.matchBoard or 1)
        or "Session Score"
    centredText(fonts.med,
        string.format("%s   N-S: %d pts     E-W: %d pts",
                      sessionLabel, game.sessionScore[1], game.sessionScore[2]),
        C.SW/2, by + 204, maxTxt)

    -- ── Seed input row (for Next Hand) ──
    local rowY = by + 234        -- shifted +10 to match the +10 body offset
    setColor(PAL.white)
    love.graphics.setFont(fonts.med)
    love.graphics.print("Next Seed:", C.SW/2 - 170, rowY + 6)

    local boxX, boxY, boxW, boxH = C.SW/2 - 70, rowY, 120, 36
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
    if txt == "" then setColor(PAL.text_dim); txt = "..." end
    love.graphics.print(txt, boxX + 10, boxY + 4)
    if focus and (math.floor(love.timer.getTime()*2) % 2 == 0) then
        setColor(PAL.yellow)
        local cw = (fonts.large:getWidth(setupState.seedBuf or ""))
        love.graphics.rectangle("fill", boxX + 10 + cw + 2, boxY + 8, 2, boxH - 16)
    end
    hits[#hits+1] = {type="seedbox", x=boxX, y=boxY, w=boxW, h=boxH}

    local btnRandX = boxX + boxW + 12
    local _, rx, ry, rw, rh = button("Randomize", btnRandX, rowY, 130, boxH, mx, my, PAL.btn_green, PAL.btn_green_h)
    hits[#hits+1] = {type="random_now", x=rx, y=ry, w=rw, h=rh}

    -- Buttons (anchored to bottom of the banner)
    local btnY = by + bh - 60
    local _, r1x, r1y, r1w, r1h = button("Replay Hand", C.SW/2 - 260, btnY, 160, 50, mx, my, PAL.btn_blue, PAL.btn_hover)
    hits[#hits+1] = {type="replay", x=r1x, y=r1y, w=r1w, h=r1h}
    
    local nextText = game.matchMode == "7board" and (game.matchBoard >= 7 and "MATCH SUMMARY" or "Next Board ("..tostring(game.matchBoard+1).."/7)") or "Next Hand"
    local nextCol = {0.15, 0.55, 0.22}
    local nextHov = {0.22, 0.78, 0.30}
    
    local _, n1x, n1y, n1w, n1h = button(nextText, C.SW/2 - 80, btnY, 160, 50, mx, my, nextCol, nextHov)
    hits[#hits+1] = {type="next_hand", x=n1x, y=n1y, w=n1w, h=n1h}
    
    local _, m1x, m1y, m1w, m1h = button("Main Menu", C.SW/2 + 100, btnY, 160, 50, mx, my, PAL.btn_blue, PAL.btn_hover)
    hits[#hits+1] = {type="menu", x=m1x, y=m1y, w=m1w, h=m1h}

    -- Confetti above all on win for the wow effect
    if won then drawConfetti() end

    return hits
end

-- ── Main menu ──────────────────────────────────────────────────────────────
function R.drawMainMenu(mx, my)
    -- Breathing inner oval so the table feels alive (radii pulse ~0.9 Hz).
    local t = love.timer.getTime()
    local breath = 0.5 + 0.5 * math.sin(t * 0.9)
    drawMoodBackdrop(560 + breath * 14, 380 + breath * 9)

    -- Title — gentle scale + glow pulse, drop shadow underneath
    love.graphics.setFont(fonts.title)
    local titlePulse = 0.5 + 0.5 * math.sin(t * 1.6)   -- 0..1
    local tScale     = 1 + 0.025 * titlePulse
    local cxT, cyT   = C.SW/2, 175
    love.graphics.push()
    love.graphics.translate(cxT, cyT)
    love.graphics.scale(tScale, tScale)
    love.graphics.translate(-cxT, -cyT)
    -- Outer glow rings (fades fully when pulse near 0)
    if titlePulse > 0.05 then
        setColor(PAL.yellow[1], PAL.yellow[2], PAL.yellow[3], 0.18 * titlePulse)
        centredText(fonts.title, "BRIDGE", cxT, cyT)
    end
    setColor(0, 0, 0, 0.45)
    centredText(fonts.title, "BRIDGE", cxT + 3, cyT + 3)
    setColor(PAL.yellow[1] + 0.05 * titlePulse,
             PAL.yellow[2] + 0.04 * titlePulse,
             PAL.yellow[3],
             1)
    centredText(fonts.title, "BRIDGE", cxT, cyT)
    love.graphics.pop()

    setColor(PAL.text_dim)
    centredText(fonts.med, "Minibridge — single player", C.SW/2, 232)

    local hits = {}
    local cx = C.SW/2

    local _, x,y,w,h = button("NEW GAME", cx - 130, 310, 260, 60, mx, my,
                              {0.15, 0.55, 0.22}, {0.22, 0.78, 0.30})
    hits[#hits+1] = {type="newgame", x=x,y=y,w=w,h=h}

    local _, ox,oy,ow,oh = button("Options", cx - 100, 390, 200, 48, mx, my,
                                  PAL.btn_blue, PAL.btn_hover)
    hits[#hits+1] = {type="options", x=ox,y=oy,w=ow,h=oh}

    local _, x2,y2,w2,h2 = button("Quit", cx - 80, 460, 160, 44, mx, my,
                                  PAL.btn_blue, PAL.btn_hover)
    hits[#hits+1] = {type="quit", x=x2,y=y2,w=w2,h=h2}

    setColor(PAL.text_dim)
    centredText(fonts.tiny, "You play as South (bottom).  Partners: North-South vs East-West.", C.SW/2, C.SH - 60)
    centredText(fonts.tiny, "Highest-HCP partnership declares.  Window is resizable.",            C.SW/2, C.SH - 44)

    return hits
end

-- ── New-game setup screen (seed input + AI difficulty) ─────────────────────
function R.drawNewGameSetup(setupState, mx, my)
    drawMoodBackdrop(560, 380)

    setColor(PAL.yellow)
    centredText(fonts.huge, "New Game", C.SW/2, 78)
    setColor(PAL.text_dim)
    centredText(fonts.small, "Choose a hand seed and your opponents' difficulty.", C.SW/2, 122)

    local hits = {}

    -- ── Seed input row ──
    setColor(PAL.white)
    love.graphics.setFont(fonts.med)
    local seedLabel = "Hand seed:"
    local rowY = 160
    love.graphics.print(seedLabel, C.SW/2 - 250, rowY + 6)

    -- Text box for the seed (typed input)
    local boxX, boxY, boxW, boxH = C.SW/2 - 130, rowY, 120, 36
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
    if txt == "" then setColor(PAL.text_dim); txt = "..." end
    love.graphics.print(txt, boxX + 10, boxY + 4)
    -- Caret
    if focus and (math.floor(love.timer.getTime()*2) % 2 == 0) then
        setColor(PAL.yellow)
        local cw = (fonts.large:getWidth(setupState.seedBuf or ""))
        love.graphics.rectangle("fill", boxX + 10 + cw + 2, boxY + 8, 2, boxH - 16)
    end
    hits[#hits+1] = {type="seedbox", x=boxX, y=boxY, w=boxW, h=boxH}

    -- Dedicated Randomize Seed Now button
    local btnRandX = boxX + boxW + 12
    local _, rx, ry, rw, rh = button("Randomize", btnRandX, rowY, 130, boxH, mx, my, PAL.btn_green, PAL.btn_green_h)
    hits[#hits+1] = {type="random_now", x=rx, y=ry, w=rw, h=rh}

    -- Auto-Randomize Next Toggle
    local togX = btnRandX + rw + 12
    local randCol  = setupState.random and PAL.btn_green or PAL.btn_blue
    local randHCol = setupState.random and PAL.btn_green_h or PAL.btn_hover
    local _, tx, ty, tw, th = button(
        setupState.random and "Auto-Next: RANDOM" or "Auto-Next: +1",
        togX, rowY, 160, boxH, mx, my, randCol, randHCol)
    hits[#hits+1] = {type="random_toggle", x=tx, y=ty, w=tw, h=th}

    -- ── Match Mode Toggle ──
    local matchRowY = rowY + boxH + 20
    local isMatch = setupState.matchMode == "7board"
    local matchCol  = isMatch and {0.6, 0.2, 0.6} or PAL.btn_blue
    local matchHCol = isMatch and {0.7, 0.3, 0.7} or PAL.btn_hover
    local _, mmx,mmy,mmw,mmh = button(
        isMatch and "Match Mode: 7 Boards" or "Match Mode: Single Game",
        C.SW/2 - 190, matchRowY, 380, 32, mx, my, matchCol, matchHCol)
    hits[#hits+1] = {type="match_toggle", x=mmx, y=mmy, w=mmw, h=mmh}

    -- ── Auto-play South toggle (CPU plays your seat too) ──
    local autoRowY = matchRowY + 44
    local autoCol  = setupState.autoSouth and {0.70, 0.40, 0.10} or PAL.btn_blue
    local autoHCol = setupState.autoSouth and {0.85, 0.50, 0.18} or PAL.btn_hover
    local _, ax,ay,aw,ah = button(
        setupState.autoSouth and "Auto-play South: ON (CPU vs CPU)"
                             or  "Auto-play South: OFF (you play)",
        C.SW/2 - 190, autoRowY, 380, 32, mx, my, autoCol, autoHCol)
    hits[#hits+1] = {type="autosouth", x=ax, y=ay, w=aw, h=ah}

    -- ── Difficulty rows ──
    local diffTitleY = autoRowY + 44
    setColor(PAL.white)
    love.graphics.setFont(fonts.med)
    centredText(fonts.med, "AI Difficulty", C.SW/2, diffTitleY)

    local aiPlayers = {C.NORTH, C.EAST, C.WEST}
    for row, p in ipairs(aiPlayers) do
        local ry = diffTitleY + 20 + (row-1) * 44
        setColor(PAL.text_dim)
        love.graphics.setFont(fonts.small)
        love.graphics.print(C.PLAYER_NAMES[p], C.SW/2 - 260, ry + 10)

        for d = 1, 5 do
            local bx    = C.SW/2 - 190 + (d-1) * 76
            local active= setupState.difficulty[p] == d
            local acol  = active and PAL.btn_green   or PAL.btn_blue
            local ahcol = active and PAL.btn_green_h or PAL.btn_hover
            local _, x,y,w,h = button(C.DIFF_NAMES[d], bx, ry, 70, 32, mx, my, acol, ahcol)
            hits[#hits+1] = {type="diff", player=p, diff=d, x=x,y=y,w=w,h=h}
        end
    end

    -- ── Settings row: intro animation, sound, card-back theme ──
    local setY = diffTitleY + 20 + 3 * 44 + 16
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

    -- ── Weather / Board theme row ──
    -- Weather ON = mood follows wall-clock (sunrise / noon / afternoon /
    -- evening / night). OFF = player picks one of the six boards manually
    -- (Classic is the safe baseline matching V1's static green table).
    local setY2 = setY + 44
    local wCol  = setupState.weatherOn and PAL.btn_green   or PAL.btn_blue
    local wHCol = setupState.weatherOn and PAL.btn_green_h or PAL.btn_hover
    local _, wx, wy, ww, wh = button(
        setupState.weatherOn and "Weather: ON (time of day)" or "Weather: OFF",
        C.SW/2 - 380, setY2, 240, 32, mx, my, wCol, wHCol)
    hits[#hits+1] = {type="weather", x=wx, y=wy, w=ww, h=wh}

    if setupState.weatherOn then
        -- Show which mood the clock currently maps to
        local nowMood = R.Mood.byClock()
        setColor(PAL.text_dim)
        love.graphics.setFont(fonts.small)
        centredText(fonts.small, "Now: " .. nowMood.name,
            C.SW/2 + 40, setY2 + 16)
    else
        -- Manual mood cycler
        setColor(PAL.text_dim)
        love.graphics.setFont(fonts.tiny)
        love.graphics.print("Board:", C.SW/2 - 130, setY2 + 10)

        local currentMood = R.Mood.ALL[setupState.moodId] or R.Mood.classic
        local _, mpx, mpy, mpw, mph = button("<",
            C.SW/2 - 70, setY2, 28, 32, mx, my, PAL.btn_blue, PAL.btn_hover)
        hits[#hits+1] = {type="moodprev", x=mpx, y=mpy, w=mpw, h=mph}

        setColor(PAL.white)
        centredText(fonts.med, currentMood.name, C.SW/2 + 30, setY2 + 16)

        local _, mnx, mny, mnw, mnh = button(">",
            C.SW/2 + 110, setY2, 28, 32, mx, my, PAL.btn_blue, PAL.btn_hover)
        hits[#hits+1] = {type="moodnext", x=mnx, y=mny, w=mnw, h=mnh}
    end

    -- ── Card size cycler (right of the weather / board row) ──
    -- Scales the cards relative to the table. The table itself always responds
    -- to the screen (letterbox viewport); this is the player's size preference.
    do
        local czX = C.SW/2 + 180
        setColor(PAL.text_dim)
        love.graphics.setFont(fonts.tiny)
        love.graphics.print("Cards:", czX, setY2 + 10)
        local _, cpx, cpy, cpw, cph = button("<",
            czX + 48, setY2, 28, 32, mx, my, PAL.btn_blue, PAL.btn_hover)
        hits[#hits+1] = {type="cardsizeprev", x=cpx, y=cpy, w=cpw, h=cph}
        setColor(PAL.white)
        centredText(fonts.med,
            C.CARD_SIZE_NAMES[setupState.cardSize or C.CARD_SIZE_DEFAULT],
            czX + 130, setY2 + 16)
        local _, cnx, cny, cnw, cnh = button(">",
            czX + 184, setY2, 28, 32, mx, my, PAL.btn_blue, PAL.btn_hover)
        hits[#hits+1] = {type="cardsizenext", x=cnx, y=cny, w=cnw, h=cnh}
    end

    -- ── Deal button + Back ──
    local dealY = setY2 + 56
    local _, dx,dy,dw,dh = button("DEAL HAND", C.SW/2 - 120, dealY, 240, 56, mx, my,
        {0.65,0.10,0.10}, {0.82,0.15,0.15})
    hits[#hits+1] = {type="deal", x=dx,y=dy,w=dw,h=dh}

    local _, bx2,by2,bw2,bh2 = button("< Main Menu", 40, 30, 160, 36, mx, my,
        PAL.btn_blue, PAL.btn_hover)
    hits[#hits+1] = {type="back", x=bx2,y=by2,w=bw2,h=bh2}

    return hits
end

-- ── Match Summary Screen ───────────────────────────────────────────────────
function R.drawMatchSummary(game, mx, my)
    drawMoodBackdrop(C.SW * 0.42, C.SH * 0.48)

    local nsScore = game.sessionScore[1]
    local ewScore = game.sessionScore[2]
    local nsWon = nsScore > ewScore
    local isTie = nsScore == ewScore
    local borderColor = isTie and PAL.yellow or (nsWon and {0.2, 0.8, 0.3} or {0.8, 0.2, 0.2})

    if game.showMatchDetailsTable then
        local bw, bh = 1000, 560
        local bx, by = C.SW/2 - bw/2, C.SH/2 - bh/2
        
        setColor(0.04, 0.06, 0.08, 0.95)
        love.graphics.rectangle("fill", bx, by, bw, bh, 20)
        
        setColor(borderColor)
        love.graphics.setLineWidth(4)
        love.graphics.rectangle("line", bx, by, bw, bh, 20)
        love.graphics.setLineWidth(1)
        
        setColor(PAL.yellow)
        centredText(fonts.large, "7-BOARD MATCH DETAILS (TRAVELER SHEET)", C.SW/2, by + 40)
        
        -- Header Row Background
        setColor(0.12, 0.16, 0.22, 0.6)
        love.graphics.rectangle("fill", bx + 30, by + 75, bw - 60, 36, 6)
        
        -- Table headers
        local tx = bx + 40
        love.graphics.setFont(fonts.med)
        setColor(PAL.white)
        
        local colCenters = {
            tx + 40,        -- BOARD
            tx + 140,       -- SEED
            tx + 290,       -- CONTRACT
            tx + 450,       -- DECLARER
            tx + 600,       -- TRICKS
            tx + 740,       -- POINTS
            tx + 860        -- WINNER
        }
        
        centredText(fonts.med, "BOARD", colCenters[1], by + 93)
        centredText(fonts.med, "SEED", colCenters[2], by + 93)
        centredText(fonts.med, "CONTRACT", colCenters[3], by + 93)
        centredText(fonts.med, "DECLARER", colCenters[4], by + 93)
        centredText(fonts.med, "TRICKS", colCenters[5], by + 93)
        centredText(fonts.med, "POINTS", colCenters[6], by + 93)
        centredText(fonts.med, "WINNER", colCenters[7], by + 93)
        
        -- Render data rows
        love.graphics.setFont(fonts.med)
        for i = 1, 7 do
            local ry = by + 120 + (i - 1) * 44
            
            -- Alternating row colors
            if i % 2 == 1 then
                setColor(1, 1, 1, 0.02)
            else
                setColor(1, 1, 1, 0.05)
            end
            love.graphics.rectangle("fill", bx + 30, ry, bw - 60, 40, 4)
            
            local detail = game.matchBoardDetails and game.matchBoardDetails[i]
            if detail then
                -- Board No
                setColor(PAL.text_dim)
                centredText(fonts.med, tostring(detail.board), colCenters[1], ry + 20)
                
                -- Seed
                centredText(fonts.med, "#" .. tostring(detail.seed), colCenters[2], ry + 20)
                
                -- Contract
                local contractStr = "Pass"
                if detail.contract then
                    local lvl = (detail.contract.tricks or 7) - 6
                    local denom = C.CONTRACT_SHORT[detail.contract.suit] or "NT"
                    local extra = ""
                    if detail.contractRedoubled then extra = " XX"
                    elseif detail.contractDoubled then extra = " X" end
                    contractStr = tostring(lvl) .. denom .. extra
                end
                setColor(PAL.white)
                centredText(fonts.med, contractStr, colCenters[3], ry + 20)
                
                -- Declarer
                setColor(PAL.text_dim)
                local declName = detail.declarer and C.PLAYER_NAMES[detail.declarer] or "—"
                centredText(fonts.med, declName, colCenters[4], ry + 20)
                
                -- Tricks Made / Target
                local tricksStr = "—"
                if detail.contract then
                    tricksStr = string.format("%d / %d", detail.tricksDeclarer, detail.contractTricks)
                end
                centredText(fonts.med, tricksStr, colCenters[5], ry + 20)
                
                -- Points
                local ptsStr = tostring(detail.points) .. " pts"
                centredText(fonts.med, ptsStr, colCenters[6], ry + 20)
                
                -- Winner
                local winSide = detail.winnerSide or "—"
                if winSide == "NS" then
                    setColor(0.2, 0.8, 0.3) -- Vibrant green
                elseif winSide == "EW" then
                    setColor(0.9, 0.3, 0.3) -- Coral red
                else
                    setColor(PAL.text_dim)
                end
                centredText(fonts.med, winSide, colCenters[7], ry + 20)
            else
                -- Not played yet
                setColor(PAL.text_dim)
                centredText(fonts.med, tostring(i), colCenters[1], ry + 20)
                centredText(fonts.med, "—", colCenters[2], ry + 20)
                centredText(fonts.med, "—", colCenters[3], ry + 20)
                centredText(fonts.med, "—", colCenters[4], ry + 20)
                centredText(fonts.med, "—", colCenters[5], ry + 20)
                centredText(fonts.med, "—", colCenters[6], ry + 20)
                centredText(fonts.med, "—", colCenters[7], ry + 20)
            end
        end
        
        -- Draw buttons
        local hits = {}
        local btnY = by + bh - 70
        
        -- Back to Summary
        local _, bxS, byS, bwS, bhS = button("< Summary", C.SW/2 - 380, btnY, 160, 50, mx, my, {0.18, 0.35, 0.48}, {0.24, 0.44, 0.60})
        hits[#hits+1] = {type="hide_table", x=bxS, y=byS, w=bwS, h=bhS}
        
        -- Replay Match
        local _, rx, ry, rw, rh = button("Replay Match", C.SW/2 - 200, btnY, 170, 50, mx, my, PAL.btn_blue, PAL.btn_hover)
        hits[#hits+1] = {type="replay_match", x=rx, y=ry, w=rw, h=rh}
        
        -- New Match
        local _, nx, ny, nw, nh = button("New Match", C.SW/2 - 10, btnY, 160, 50, mx, my, {0.15, 0.55, 0.22}, {0.22, 0.78, 0.30})
        hits[#hits+1] = {type="new_match", x=nx, y=ny, w=nw, h=nh}
        
        -- Main Menu
        local _, bx1, by1, bw1, bh1 = button("Main Menu", C.SW/2 + 170, btnY, 170, 50, mx, my, PAL.btn_red, PAL.btn_hover)
        hits[#hits+1] = {type="menu", x=bx1, y=by1, w=bw1, h=bh1}
        
        if nsWon then drawConfetti() end
        
        return hits
    else
        local bw, bh = 720, 440
        local bx, by = C.SW/2 - bw/2, C.SH/2 - bh/2
        local maxTxt = bw - 60        -- safe inner width for centred text

        -- Modern banner + W badge (golden for NS win, neutral otherwise)
        drawModernBanner(bx, by, bw, bh, borderColor, nsWon)
        drawWinnerBadge(C.SW/2, by + 4, 22, nsWon and not isTie)

        setColor(PAL.yellow)
        centredText(fonts.title, "MATCH COMPLETE", C.SW/2, by + 55, maxTxt)

        setColor(PAL.text_dim)
        centredText(fonts.med, "7-Board Match Results", C.SW/2, by + 100, maxTxt)

        local nsWins = game.matchWins and game.matchWins[1] or 0
        local ewWins = game.matchWins and game.matchWins[2] or 0

        -- Two side-by-side score chips; each clipped to its half-width.
        setColor(PAL.white)
        centredText(fonts.large,
            string.format("N-S: %d pts (%d Wins)", nsScore, nsWins),
            C.SW/2 - 140, by + 155, 260)
        centredText(fonts.large,
            string.format("E-W: %d pts (%d Wins)", ewScore, ewWins),
            C.SW/2 + 140, by + 155, 260)

        setColor(borderColor)
        local resultText = "IT'S A TIE!"
        if not isTie then
            resultText = (nsWon and "NORTH-SOUTH" or "EAST-WEST") .. " WINS THE MATCH!"
        end
        centredText(fonts.title, resultText, C.SW/2, by + 215, maxTxt)

        setColor(PAL.text_dim)
        centredText(fonts.small,
            "Match Start Seed: #" .. tostring(game.matchStartSeed or game.seed),
            C.SW/2, by + 275, maxTxt)
        
        local hits = {}
        
        -- Reveal Table button (wide and sleek)
        local _, tx, ty, tw, th = button("Reveal Table", C.SW/2 - 110, by + 305, 220, 38, mx, my, {0.18, 0.35, 0.48}, {0.24, 0.44, 0.60})
        hits[#hits+1] = {type="reveal_table", x=tx, y=ty, w=tw, h=th}
        
        local btnY = by + bh - 70
        
        local _, rx, ry, rw, rh = button("Replay Match", C.SW/2 - 270, btnY, 170, 50, mx, my, PAL.btn_blue, PAL.btn_hover)
        hits[#hits+1] = {type="replay_match", x=rx, y=ry, w=rw, h=rh}
        
        local _, nx, ny, nw, nh = button("New Match", C.SW/2 - 80, btnY, 160, 50, mx, my, {0.15, 0.55, 0.22}, {0.22, 0.78, 0.30})
        hits[#hits+1] = {type="new_match", x=nx, y=ny, w=nw, h=nh}
        
        local _, bx1, by1, bw1, bh1 = button("Main Menu", C.SW/2 + 100, btnY, 170, 50, mx, my, PAL.btn_red, PAL.btn_hover)
        hits[#hits+1] = {type="menu", x=bx1, y=by1, w=bw1, h=bh1}
        
        if nsWon then drawConfetti() end
        
        return hits
    end
end

return R
