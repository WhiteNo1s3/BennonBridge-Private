-- Bridge (Minibridge) — LÖVE2D single-player game
-- Human plays South.  North-South vs East-West.
-- Window is freely resizable; everything renders in a virtual 1280x800 space
-- and is scaled with letterboxing to whatever size the window happens to be.

local C    = require("src.constants")
local Game = require("src.game")
local R    = require("src.render")
local V    = require("src.viewport")
local SND  = require("src.sound")
local Anim = require("src.anim")
local Deck = require("src.deck")
local SET  = require("src.settings")

-- ── Global state ───────────────────────────────────────────────────────────

local game        -- Game instance

-- New-game setup state (seed + per-AI difficulty). Replaces what used to be
-- the menu state.
local setupState

-- Per-state hit-test lists, filled in during R.draw* and consumed by clicks
local mainMenuHits    = {}
local setupHits       = {}
local auctionHits     = {}
local southHits, northHits = {}, {}
local resultHits      = {}

-- Per-state interaction state
local southSel, southHov = nil, nil
local northSel, northHov = nil, nil

-- Bidding-box interaction (auction phase). selectedBid is {level, denom} chosen
-- in the grid but not yet confirmed; nil means nothing selected.
local selectedBid = nil

-- In-game options popover (card-size slider) + interaction state
local gameOptsOpen = false
local gameOptsHits = {}

-- Card-size slider drag: holds the active "cardslider" hit (with its track
-- geometry) while the mouse button is down on it, in any screen.
local sliderDrag = nil

-- Long-press magnifier: pendingPress is set on mouse-down over a face-up
-- card; if the button is held LONGPRESS_TIME the card pops up enlarged.
-- A short press-and-release is a normal click (plays the card on release).
local pendingPress = nil      -- {h = hit, t0 = time}
local magnifyCard  = nil
local LONGPRESS_TIME = 0.40

-- Dev screenshot harness state (see the flag parsing in love.load). When
-- devHarness is set, settings are never saved.
local devShot, devHarness = nil, false

-- ── Helpers ────────────────────────────────────────────────────────────────

-- One fresh deal, drawn uniformly across the whole code space. The customer
-- sees it as a compact 4-character code (Deck.encodeSeed); internally the
-- engine spreads it across LÖVE's full 2^64 shuffle space.
local function randomSeed()
    return love.math.random(1, C.SEED_MAX)
end

-- Persist the player-tunable settings. Called on every settings change (not
-- just on quit — Android kills apps without firing love.quit).
local function saveSettings()
    if not setupState or devHarness then return end
    SET.save({
        cardW       = setupState.cardW,
        textSize    = setupState.textSize,
        backTheme   = setupState.backTheme,
        soundOn     = setupState.soundOn and true or false,
        introAnim   = setupState.introAnim and true or false,
        weatherOn   = setupState.weatherOn and true or false,
        moodId      = setupState.moodId,
        matchBoards = setupState.matchBoards,
        matchMode   = setupState.matchMode or "single",
        diffN       = setupState.difficulty[C.NORTH],
        diffE       = setupState.difficulty[C.EAST],
        diffW       = setupState.difficulty[C.WEST],
        fullscreen  = (not C.PHONE) and love.window.getFullscreen() or false,
        maximized   = ((not C.PHONE) and not love.window.getFullscreen()
                          and love.window.isMaximized()) and true or false,
    })
end

-- Restore saved settings into a freshly-built setupState, validating every
-- value (the file is user-editable; a bad value must never wedge the game).
local function restoreSettings(saved)
    if not saved then return end
    local function num(v, lo, hi)
        if type(v) ~= "number" or v ~= v then return nil end
        return math.max(lo, math.min(hi, v))
    end
    setupState.cardW = num(saved.cardW, C.CARD_W_MIN, C.CARD_W_MAX)
                           or setupState.cardW
    local ts = num(saved.textSize, 1, #C.TEXT_SCALES)
    if ts then setupState.textSize = math.floor(ts) end
    if type(saved.backTheme) == "number" and R.BACK_COUNT > 0 then
        setupState.backTheme =
            ((math.floor(saved.backTheme) - 1) % R.BACK_COUNT) + 1
    end
    if type(saved.soundOn)   == "boolean" then setupState.soundOn   = saved.soundOn   end
    if type(saved.introAnim) == "boolean" then setupState.introAnim = saved.introAnim end
    if type(saved.weatherOn) == "boolean" then setupState.weatherOn = saved.weatherOn end
    for _, id in ipairs(R.Mood.ORDER) do
        if id == saved.moodId then setupState.moodId = saved.moodId break end
    end
    for _, n in ipairs(C.MATCH_LENGTHS) do
        if n == saved.matchBoards then setupState.matchBoards = n break end
    end
    if saved.matchMode == "single" or saved.matchMode == "7board" then
        setupState.matchMode = saved.matchMode
    end
    local dn = num(saved.diffN, C.EASY, C.HARDEST)
    local de = num(saved.diffE, C.EASY, C.HARDEST)
    local dw = num(saved.diffW, C.EASY, C.HARDEST)
    if dn then setupState.difficulty[C.NORTH] = math.floor(dn) end
    if de then setupState.difficulty[C.EAST]  = math.floor(de) end
    if dw then setupState.difficulty[C.WEST]  = math.floor(dw) end
end

-- Borderless-desktop fullscreen, F11 / Alt+Enter (desktop only; Android is
-- inherently fullscreen).
local function toggleFullscreen()
    if C.PHONE then return end
    love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
    V.update()
    saveSettings()
end

local function hitTest(hits, x, y)
    for i = #hits, 1, -1 do        -- reverse: topmost wins
        local h = hits[i]
        if x >= h.x and x <= h.x+h.w and y >= h.y and y <= h.y+h.h then
            return h
        end
    end
    return nil
end

local function applySetupDifficulty()
    game.difficulty = {
        [C.NORTH] = setupState.difficulty[C.NORTH],
        [C.EAST]  = setupState.difficulty[C.EAST],
        -- South seat uses HARDEST whether you're playing or the AI is — when
        -- watching CPU-vs-CPU we want a fair, strong opponent for the human's
        -- side, not a weakened one.
        [C.SOUTH] = C.HARDEST,
        [C.WEST]  = setupState.difficulty[C.WEST],
    }
    -- Flag the game so its update loop knows South is a CPU
    game.autoSouth = setupState.autoSouth
end

local function dealFromSetup()
    applySetupDifficulty()
    southSel, southHov = nil, nil
    northSel, northHov = nil, nil
    selectedBid  = nil
    pendingPress = nil
    magnifyCard  = nil
    gameOptsOpen = false
    sliderDrag   = nil
    -- Apply settings to the global subsystems
    Anim.enabled = setupState.introAnim and true or false
    SND.setEnabled(setupState.soundOn and true or false)
    R.setBackTheme(setupState.backTheme)
    R.setMood(setupState)
    -- Parse the deal code; anything unreadable = fresh random deal
    local seed = Deck.decodeSeed(setupState.seedBuf) or randomSeed()
    setupState.seed    = seed
    setupState.seedBuf = Deck.encodeSeed(seed)
    
    game.matchMode = setupState.matchMode
    game.confettiFired = false
    
    if game.matchMode == "7board" then
        if not game.matchBoard or game.matchBoard == 1 then
            game.matchBoard = 1
            game.matchLength = setupState.matchBoards or C.MATCH_DEFAULT
            game.matchStartSeed = seed
            game.matchSeeds = {seed}
            game.matchWins = {0, 0}
            game.sessionScore = {0, 0}
            game.matchBoardDetails = {}
            game.showMatchDetailsTable = false
        end
    else
        game.sessionScore = {0, 0}
    end
    
    game:deal(seed)
end

-- ── LÖVE callbacks ─────────────────────────────────────────────────────────

function love.load()
    love.keyboard.setKeyRepeat(true)   -- for backspacing the seed
    V.update()
    R.load()
    SND.load()
    game = Game.new()
    -- Every launch opens on a fresh random deal code (type or Randomize to
    -- change it) — two players installing the game must not get the same
    -- first deal.
    local seed0 = randomSeed()
    setupState = {
        seedBuf = Deck.encodeSeed(seed0),
        seed    = seed0,
        random  = false,
        autoSouth = false,
        introAnim = true,    -- deal animation at start of hand
        soundOn   = true,    -- master sound toggle
        backTheme = 1,       -- 1..9 (rotates through card-back PNGs)
        cardW     = C.CARD_W_DEFAULT,      -- continuous card width (slider)
        matchBoards = C.MATCH_DEFAULT,     -- boards per match (8/12/16, standard)
        textSize  = C.PHONE and 3 or C.TEXT_DEFAULT,  -- phones open Extra Large
        -- Table mood (V2): when weatherOn is true the board re-themes itself
        -- by wall-clock time; otherwise it sticks to the player-chosen moodId.
        weatherOn = true,
        moodId    = "classic",
        difficulty = {
            [C.NORTH] = C.MEDIUM,
            [C.EAST]  = C.MEDIUM,
            [C.WEST]  = C.MEDIUM,
        },
    }
    -- Saved settings override the defaults above (validated field by field)
    local saved = SET.load()
    restoreSettings(saved)
    R.setMood(setupState)
    R.setCardScale(setupState.cardW)
    R.setTextScale(setupState.textSize)
    R.setBackTheme(setupState.backTheme)
    SND.setEnabled(setupState.soundOn and true or false)
    Anim.enabled = setupState.introAnim and true or false
    -- Desktop window state: returning players get back the mode they left in
    -- (fullscreen or maximized); first run opens maximized. Skipped for the
    -- hidden screenshot harness (maximize would un-hide the window).
    if not C.PHONE and os.getenv("BRIDGE_HIDDEN") ~= "1" then
        if saved and saved.fullscreen then
            love.window.setFullscreen(true, "desktop")
        elseif not saved or saved.maximized ~= false then
            love.window.maximize()
        end
        V.update()
    end
    game.state = C.STATE_MENU

    -- Dev harness (inert without flags; combine with BRIDGE_HIDDEN=1 and
    -- BRIDGE_SHOT_W/H for a fully invisible run at any resolution):
    --   --auction [CODE]     jump straight into a deal's auction
    --   --auto               spectator mode: the AI also plays South
    --   --shot FILE DELAY    render, save FILE (PNG, in the save dir)
    --                        after DELAY seconds, quit
    -- Harness runs NEVER save settings (devHarness gates saveSettings), so
    -- test runs can't corrupt a real player profile.
    for i, v in ipairs(arg or {}) do
        if v == "--auto" then
            devHarness = true
            setupState.autoSouth = true
        elseif v == "--auction" then
            devHarness = true
            if arg[i + 1] then setupState.seedBuf = tostring(arg[i + 1]):upper() end
            setupState.introAnim = false     -- dealFromSetup copies this into Anim
            setupState.soundOn   = false     -- silent: harness must not be heard
        elseif v == "--dealanim" then        -- (after --auction) keep the deal anim
            setupState.introAnim = true
        elseif v == "--shot" then
            devHarness = true
            devShot = {
                file  = arg[i + 1] or "shot.png",
                delay = tonumber(arg[i + 2]) or 1.0,
                t0    = love.timer.getTime(),
            }
        end
    end
    for _, v in ipairs(arg or {}) do
        if v == "--auction" then
            dealFromSetup()
            break
        end
    end
end

-- Screenshot-harness pump, called from love.update: waits out the delay,
-- captures one frame, quits. No-op unless --shot was passed.
local function devShotUpdate()
    if not devShot then return end
    local now = love.timer.getTime()
    if devShot.quitAt then
        if now >= devShot.quitAt then love.event.quit() end
    elseif now - devShot.t0 >= devShot.delay then
        love.graphics.captureScreenshot(devShot.file)
        -- One more presented frame must pass before the PNG lands on disk
        devShot.quitAt = now + 0.25
    end
end

function love.quit()
    saveSettings()
end

function love.resize(w, h)
    V.update()
end

function love.update(dt)
    V.update()        -- cheap; safe to refresh every frame
    devShotUpdate()   -- no-op outside the dev screenshot harness

    if game.state == C.STATE_RESULT and game.autoSouth then
        -- Handle result auto-advance for CPU testing
        local linger = game.humanWon and 8.0 or 4.0
        game.aiTimer = (game.aiTimer or 0) + dt
        if game.aiTimer > linger then
            game.aiTimer = 0
            if game.matchMode == "7board" then
                if game.matchBoard >= (game.matchLength or 7) then
                    game.state = "match_summary"
                else
                    game.matchBoard = game.matchBoard + 1
                    local nextSeed
                    if game.matchSeeds and game.matchSeeds[game.matchBoard] then
                        nextSeed = game.matchSeeds[game.matchBoard]
                    else
                        if setupState.random then
                            nextSeed = randomSeed()
                        else
                            nextSeed = game.seed + 1
                        end
                        game.matchSeeds = game.matchSeeds or {}
                        game.matchSeeds[game.matchBoard] = nextSeed
                    end
                    setupState.seedBuf = Deck.encodeSeed(nextSeed)
                    dealFromSetup()
                end
            else
                -- Single match auto-advance
                if setupState.random then
                    setupState.seedBuf = Deck.encodeSeed(randomSeed())
                else
                    setupState.seedBuf = Deck.encodeSeed(game.seed + 1)
                end
                dealFromSetup()
            end
        end
    else
        game:update(dt)
    end
    R.update(dt)      -- drives confetti / future animation particles

    -- Long-press: holding a face-up card for LONGPRESS_TIME reveals it
    if pendingPress and not magnifyCard then
        if love.timer.getTime() - pendingPress.t0 >= LONGPRESS_TIME then
            magnifyCard = pendingPress.h.card
        end
    end
end

function love.draw()
    V.drawBegin()

    local mx, my = V.mouseVirtual()

    if game.state == C.STATE_MENU then
        mainMenuHits = R.drawMainMenu(setupState, mx, my)

    elseif game.state == C.STATE_NEWGAME then
        setupHits = R.drawNewGameSetup(setupState, mx, my)

    elseif game.state == C.STATE_DEALING then
        R.drawDealing(game)

    elseif game.state == C.STATE_AUCTION then
        auctionHits = R.drawAuction(game, mx, my, selectedBid)

    elseif game.state == C.STATE_PLAYING
        or game.state == C.STATE_TRICK_END then
        -- magnifyCard (long-press) is passed as the reveal card: it slides
        -- out of its fan in place rather than covering the table.
        southHits, northHits = R.drawGame(
            game, southSel, southHov, northSel, northHov, magnifyCard)
        -- In-game options trigger + popover (card-size slider, live)
        gameOptsHits = R.drawGameOptions(gameOptsOpen, mx, my)

    elseif game.state == C.STATE_RESULT then
        resultHits = R.drawResult(game, setupState, mx, my)

    elseif game.state == "match_summary" then
        resultHits = R.drawMatchSummary(game, mx, my)
    end

    -- (Vignette now drawn inside each screen's backdrop, BEHIND the cards, so
    -- the background never sits on top of a card.)

    V.drawEnd()
end

-- ── Input ──────────────────────────────────────────────────────────────────

-- Map a drag/click x-position on a card-size slider back to a width and
-- apply it immediately (this is what makes the preview live).
local function applyCardSlider(h, x)
    local v = (x - h.trackX) / h.trackW
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    setupState.cardW = C.CARD_W_MIN + v * (C.CARD_W_MAX - C.CARD_W_MIN)
    R.setCardScale(setupState.cardW)
end

-- Whose cards may the human click right now? (South always; plus dummy when
-- South declares. Spectator mode plays nothing — game.autoSouth gates that
-- in Game:_isHumanTurn, but clicks are also ignored via onPlayPress.)
local function isHumanTurnFor(p)
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

function love.mousemoved(x, y)
    x, y = V.toVirtual(x, y)

    -- Live slider drag (setup screen or in-game options)
    if sliderDrag and love.mouse.isDown(1) then
        applyCardSlider(sliderDrag, x)
        return
    end

    -- Swipe-to-play (touch friendly): press a card and flick it towards the
    -- table centre — up from the South hand, down from the dummy at the top.
    -- Fires regardless of the long-press reveal being up, so "press, see the
    -- card, flick it in" is one continuous gesture.
    if pendingPress and love.mouse.isDown(1)
       and game.state == C.STATE_PLAYING then
        local towardCentre = pendingPress.fromNorth and (y - pendingPress.y0)
                                                     or (pendingPress.y0 - y)
        if towardCentre > 55 then
            local pp = pendingPress
            pendingPress = nil
            magnifyCard  = nil
            local cp = game.currentPlayer
            if cp and isHumanTurnFor(cp) then
                -- humanPlay validates legality + that the card is cp's
                game:humanPlay(pp.h.card)
                southSel, northSel = nil, nil
                southHov = nil
            end
            return
        end
    end

    southHov = nil
    if game.state == C.STATE_PLAYING then
        local cp = game.currentPlayer
        if cp == C.SOUTH then
            local h = hitTest(southHits, x, y)
            if h then southHov = h.idx end
        end
    end
end

function love.mousepressed(x, y, btn)
    if btn ~= 1 then return end
    x, y = V.toVirtual(x, y)

    -- Touch feedback: any button under this press pops visibly (phones have
    -- no hover, and even the quickest tap must react).
    R.pulseAt(x, y)

    if     game.state == C.STATE_MENU      then onMainMenuClick(x, y)
    elseif game.state == C.STATE_NEWGAME   then onSetupClick(x, y)
    elseif game.state == C.STATE_DEALING   then game.state = C.STATE_AUCTION
                                                Anim.active = false
    elseif game.state == C.STATE_AUCTION   then onAuctionClick(x, y)
    elseif game.state == C.STATE_PLAYING
        or game.state == C.STATE_TRICK_END then onPlayPress(x, y)
    elseif game.state == C.STATE_RESULT or game.state == "match_summary" then onResultClick(x, y)
    end
end

function love.mousereleased(x, y, btn)
    if btn ~= 1 then return end
    x, y = V.toVirtual(x, y)

    if sliderDrag then
        sliderDrag = nil
        saveSettings()      -- card size settles on release
    end

    if game.state == C.STATE_PLAYING or game.state == C.STATE_TRICK_END then
        onPlayRelease(x, y)
    else
        pendingPress = nil
        magnifyCard  = nil
    end
end

function love.textinput(text)
    if (game.state == C.STATE_NEWGAME or game.state == C.STATE_RESULT) and setupState.seedFocus then
        -- Deal codes are base-34: letters and digits, up to 4 characters
        if text:match("%w") and #setupState.seedBuf < (C.CODE_LEN or 4) then
            setupState.seedBuf = setupState.seedBuf .. text:upper()
        end
    end
end

function love.keypressed(key)
    -- Fullscreen: F11 or Alt+Enter, any screen (desktop only)
    if key == "f11" or ((key == "return" or key == "kpenter")
                        and love.keyboard.isDown("lalt", "ralt")) then
        toggleFullscreen()
        return
    end

    if key == "escape" then
        -- Layered dismissal: dialog → magnifier → options popover → screen
        if setupState.confirmSpectator then setupState.confirmSpectator = false return end
        if magnifyCard then magnifyCard = nil pendingPress = nil return end
        if gameOptsOpen then gameOptsOpen = false return end
        if game.state == C.STATE_MENU then
            love.event.quit()
        elseif game.state == C.STATE_NEWGAME then
            game.state = C.STATE_MENU
        else
            -- During a hand, Esc backs out to main menu (forfeit current hand)
            game.state = C.STATE_MENU
        end
        return
    end

    -- Seed input editing
    if (game.state == C.STATE_NEWGAME or game.state == C.STATE_RESULT) and setupState.seedFocus then
        if key == "backspace" then
            setupState.seedBuf = setupState.seedBuf:sub(1, -2)
        elseif key == "return" or key == "kpenter" then
            dealFromSetup()
        end
        return
    end

    if key == "space" or key == "return" then
        if game.state == C.STATE_MENU then
            game.state = C.STATE_NEWGAME
        elseif game.state == C.STATE_NEWGAME then
            dealFromSetup()
        elseif game.state == C.STATE_AUCTION then
            -- Space = Pass for the human when it's their turn
            if game.auction and game.auction.currentBidder == C.SOUTH
               and not game.autoSouth then
                game:humanCall({type = C.CALL_PASS})
                selectedBid = nil
            end
        end
    end
end

-- ── Main menu ──────────────────────────────────────────────────────────────

function onMainMenuClick(x, y)
    local h = hitTest(mainMenuHits, x, y)
    if not h then
        -- Click-away from the confirm dialog = "No"
        setupState.confirmSpectator = false
        return
    end
    SND.playClick()
    if h.type == "newgame" then
        game.sessionScore = {0, 0}
        game.matchBoard = 1
        setupState.matchMode = setupState.matchMode or "single"
        game.state = C.STATE_NEWGAME

    elseif h.type == "mode" then
        if setupState.autoSouth then
            -- Back to human: no confirmation needed
            setupState.autoSouth = false
        else
            -- Switching to spectator: confirm first (touch mis-tap guard)
            setupState.confirmSpectator = true
        end

    elseif h.type == "spec_yes" then
        setupState.autoSouth = true
        setupState.confirmSpectator = false

    elseif h.type == "spec_no" then
        setupState.confirmSpectator = false

    elseif h.type == "quit" then
        love.event.quit()
    end
end

-- ── New-game setup ────────────────────────────────────────────────────────

function onSetupClick(x, y)
    local h = hitTest(setupHits, x, y)
    setupState.seedFocus = false
    if not h then return end
    SND.playClick()

    if h.type == "deal" then
        if setupState.random then
            setupState.seedBuf = Deck.encodeSeed(randomSeed())
        end
        dealFromSetup()

    elseif h.type == "seedbox" then
        setupState.seedFocus = true

    elseif h.type == "random_now" then
        setupState.seedBuf = Deck.encodeSeed(randomSeed())

    elseif h.type == "random_toggle" then
        setupState.random = not setupState.random

    elseif h.type == "match_toggle" then
        setupState.matchMode = setupState.matchMode == "7board" and "single" or "7board"

    elseif h.type == "match_minus" or h.type == "match_plus" then
        -- Step through the standard contest lengths (8 / 12 / 16) only.
        local lens = C.MATCH_LENGTHS
        local idx = 1
        for i, n in ipairs(lens) do
            if n == (setupState.matchBoards or C.MATCH_DEFAULT) then idx = i break end
        end
        idx = idx + (h.type == "match_plus" and 1 or -1)
        idx = math.max(1, math.min(#lens, idx))
        setupState.matchBoards = lens[idx]

    elseif h.type == "textsize" then
        setupState.textSize = ((setupState.textSize or C.TEXT_DEFAULT) % #C.TEXT_SCALES) + 1
        R.setTextScale(setupState.textSize)

    elseif h.type == "introanim" then
        setupState.introAnim = not setupState.introAnim
        Anim.enabled = setupState.introAnim

    elseif h.type == "sound" then
        setupState.soundOn = not setupState.soundOn
        SND.setEnabled(setupState.soundOn)

    elseif h.type == "backprev" then
        if R.BACK_COUNT > 0 then
            setupState.backTheme = ((setupState.backTheme - 2) % R.BACK_COUNT) + 1
            R.setBackTheme(setupState.backTheme)
        end

    elseif h.type == "backnext" then
        if R.BACK_COUNT > 0 then
            setupState.backTheme = (setupState.backTheme % R.BACK_COUNT) + 1
            R.setBackTheme(setupState.backTheme)
        end

    elseif h.type == "cardslider" then
        sliderDrag = h
        applyCardSlider(h, x)

    elseif h.type == "weather" then
        setupState.weatherOn = not setupState.weatherOn
        R.setMood(setupState)

    elseif h.type == "moodprev" or h.type == "moodnext" then
        -- Cycle through R.Mood.ORDER (only meaningful when weather is off).
        local order = R.Mood.ORDER
        local idx = 1
        for i, id in ipairs(order) do
            if id == setupState.moodId then idx = i break end
        end
        if h.type == "moodprev" then
            idx = ((idx - 2) % #order) + 1
        else
            idx = (idx % #order) + 1
        end
        setupState.moodId = order[idx]
        R.setMood(setupState)

    elseif h.type == "diff" then
        setupState.difficulty[h.player] = h.diff

    elseif h.type == "back" then
        game.state = C.STATE_MENU
    end

    saveSettings()
end

-- ── Auction (contract bridge bidding) ─────────────────────────────────────

function onAuctionClick(x, y)
    local h = hitTest(auctionHits, x, y)
    if not h then return end
    -- Only act on human's turn
    if not game.auction or game.auction.currentBidder ~= C.SOUTH then return end
    if game.autoSouth then return end
    SND.playClick()

    if h.type == "bidcell" then
        -- Cell click selects (or deselects) the bid; doesn't submit yet
        if selectedBid and selectedBid.level == h.level
           and selectedBid.denom == h.denom then
            selectedBid = nil
        else
            -- Only allow legal bids
            if game:isLegalCall({type = C.CALL_BID, level = h.level, denom = h.denom}) then
                selectedBid = {level = h.level, denom = h.denom}
            end
        end

    elseif h.type == "pass" then
        game:humanCall({type = C.CALL_PASS})
        selectedBid = nil

    elseif h.type == "double" then
        game:humanCall({type = C.CALL_DOUBLE})
        selectedBid = nil

    elseif h.type == "redouble" then
        game:humanCall({type = C.CALL_REDOUBLE})
        selectedBid = nil

    elseif h.type == "confirm" then
        if selectedBid then
            game:humanCall({
                type  = C.CALL_BID,
                level = selectedBid.level,
                denom = selectedBid.denom,
            })
            selectedBid = nil
        end
    end
end

-- ── Card play ─────────────────────────────────────────────────────────────
-- Press/release pair. A press queues the card; a quick release on the same
-- card plays it; holding LONGPRESS_TIME instead reveals the card in place
-- (release closes it without playing — peeking is always safe); pressing
-- and swiping towards the table centre plays it (touch gesture).
-- (isHumanTurnFor lives near the top of the input section, because the
-- swipe handler in love.mousemoved needs it too.)

function onPlayPress(x, y)
    -- Options UI sits above the table: check it first
    local oh = hitTest(gameOptsHits, x, y)
    if oh then
        if oh.type == "optsgear" then
            SND.playClick()
            gameOptsOpen = not gameOptsOpen
        elseif oh.type == "cardslider" then
            sliderDrag = oh
            applyCardSlider(oh, x)
        elseif oh.type == "textsize" then
            SND.playClick()
            setupState.textSize = ((setupState.textSize or C.TEXT_DEFAULT) % #C.TEXT_SCALES) + 1
            R.setTextScale(setupState.textSize)
            saveSettings()
        elseif oh.type == "fullscreen" then
            SND.playClick()
            toggleFullscreen()
        end
        return
    end
    if gameOptsOpen then
        -- Click-away closes the popover and consumes the press, so opening
        -- options can never accidentally play a card.
        gameOptsOpen = false
        return
    end

    -- Face-up card press → queue for click-play, long-press reveal, or
    -- swipe-to-play. South is always face-up; North joins when it's dummy.
    local h, fromNorth = hitTest(southHits, x, y), false
    if not h and game.dummy == C.NORTH then
        h = hitTest(northHits, x, y)
        fromNorth = h and true or false
    end
    if h then
        pendingPress = {
            h = h, t0 = love.timer.getTime(),
            x0 = x, y0 = y, fromNorth = fromNorth,
        }
    end
end

function onPlayRelease(x, y)
    -- Closing the magnifier never plays the card
    if magnifyCard then
        magnifyCard  = nil
        pendingPress = nil
        return
    end
    if not pendingPress then return end
    local pressed = pendingPress.h
    pendingPress  = nil

    if game.state ~= C.STATE_PLAYING then return end
    local cp = game.currentPlayer
    if not cp or not isHumanTurnFor(cp) then return end

    local hits = (cp == C.SOUTH) and southHits or northHits
    local h    = hitTest(hits, x, y)
    if not h then return end
    -- Only play if the release lands on the card that was pressed
    if h.card ~= pressed.card then return end

    game:humanPlay(h.card)
    southSel, northSel = nil, nil
    southHov = nil
end

-- ── Result ────────────────────────────────────────────────────────────────

function onResultClick(x, y)
    local h = hitTest(resultHits, x, y)
    setupState.seedFocus = false
    if not h then return end
    SND.playClick()

    if h.type == "reveal_table" then
        game.showMatchDetailsTable = true
        return
    elseif h.type == "hide_table" then
        game.showMatchDetailsTable = false
        return
    end
    
    if h.type == "next_board_anywhere" then
        if game.matchBoard >= (game.matchLength or 7) then
            game.state = "match_summary"
            return
        end
        game.matchBoard = game.matchBoard + 1
        
        local nextSeed
        if game.matchSeeds and game.matchSeeds[game.matchBoard] then
            nextSeed = game.matchSeeds[game.matchBoard]
        else
            if setupState.random then
                nextSeed = randomSeed()
            else
                nextSeed = game.seed + 1
            end
            game.matchSeeds = game.matchSeeds or {}
            game.matchSeeds[game.matchBoard] = nextSeed
        end
        setupState.seedBuf = Deck.encodeSeed(nextSeed)
        dealFromSetup()
        return
    end

    if h.type == "seedbox" then
        setupState.seedFocus = true
    elseif h.type == "random_now" then
        setupState.seedBuf = Deck.encodeSeed(randomSeed())
    elseif h.type == "replay" then
        setupState.seedBuf = Deck.encodeSeed(game.seed)
        dealFromSetup()
        
    elseif h.type == "next_hand" then
        if game.matchMode == "7board" then
            if game.matchBoard >= (game.matchLength or 7) then
                game.state = "match_summary"
                return
            end
            game.matchBoard = game.matchBoard + 1
        end
        
        dealFromSetup()
        
    elseif h.type == "replay_match" then
        game.matchBoard = 1
        game.sessionScore = {0, 0}
        game.matchWins = {0, 0}
        game.matchBoardDetails = {}
        game.showMatchDetailsTable = false
        local firstSeed = game.matchSeeds and game.matchSeeds[1] or game.matchStartSeed or 1
        setupState.seedBuf = Deck.encodeSeed(firstSeed)
        dealFromSetup()

    elseif h.type == "new_match" then
        game.matchBoard = 1
        game.sessionScore = {0, 0}
        game.matchWins = {0, 0}
        game.matchBoardDetails = {}
        game.showMatchDetailsTable = false
        local newStartSeed
        if setupState.random then
            newStartSeed = randomSeed()
        else
            newStartSeed = (game.matchStartSeed or game.seed or 1) + (game.matchLength or 7)
        end
        game.matchStartSeed = newStartSeed
        game.matchSeeds = {newStartSeed}
        setupState.seedBuf = Deck.encodeSeed(newStartSeed)
        dealFromSetup()

    elseif h.type == "menu" then
        game.state = C.STATE_MENU
    end
end
