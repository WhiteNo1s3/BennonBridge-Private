-- Simple sound manager.
--
-- The cardgive sound fires once per card during the deal animation (52 cards
-- in rapid succession), so we keep a small pool of pre-loaded Sources and
-- rotate through them; that lets multiple instances overlap without one
-- cutting the next off.

local S = {}

S.enabled = true
local SRC_DIR = "assets/sounds/"

local startGame              -- single instance, only plays once per deal
local cardGivePool = {}
local cardGivePoolIndex = 1
local CARD_GIVE_POOL_SIZE = 8   -- enough for the fastest deals

local winChime               -- procedural: "ta-da!" fanfare on a win
local sweepSwish             -- procedural: felt-brush swish on trick gather
local uiClick                -- procedural: soft tick when a button is pressed

-- ── Procedural sounds ──────────────────────────────────────────────────────
-- Synthesised at load so they ship with the code (no asset files) and stay
-- deliberately GENTLE: a win is a soft four-note bell arpeggio (C-E-G-C),
-- a trick sweep is a short brushed-felt swish. Nothing that could grate on
-- the hundredth hearing.

-- A proper "ta-DA!": a short G4 pickup note, then a full C-major chord
-- blooming with a gentle shimmer on the top note — the classic fanfare
-- shape, kept soft enough to share a room with.
local function makeWinChime()
    local rate = 44100
    local dur  = 1.9
    local n    = math.floor(rate * dur)
    local sd   = love.sound.newSoundData(n, rate, 16, 1)
    local T2   = 0.17                                  -- "DA" lands here
    local chord = {523.25, 659.25, 783.99, 1046.50}    -- C5 E5 G5 C6
    for i = 0, n - 1 do
        local t = i / rate
        local v = 0
        -- "ta": quick G4 pickup, gone by the time the chord lands
        if t < T2 then
            local env = math.exp(-t * 9) * math.min(1, t * 200)
            v = v + 0.9 * env * (math.sin(2 * math.pi * 392.00 * t)
                        + 0.15 * math.sin(4 * math.pi * 392.00 * t))
        end
        -- "DA": the chord blooms and rings out
        if t >= T2 then
            local lt = t - T2
            for k, f in ipairs(chord) do
                local env = math.exp(-lt * 1.9) * math.min(1, lt * 120)
                -- The top note shimmers (slow vibrato) so the ring stays alive
                local fk  = (k == #chord)
                    and f * (1 + 0.005 * math.sin(2 * math.pi * 5.5 * lt))
                    or  f
                v = v + env * (math.sin(2 * math.pi * fk * lt)
                      + 0.15 * math.sin(4 * math.pi * fk * lt))
            end
        end
        v = v * 0.17
        if v > 1 then v = 1 elseif v < -1 then v = -1 end
        sd:setSample(i, v)
    end
    local src = love.audio.newSource(sd, "static")
    src:setVolume(0.62)
    return src
end

-- Soft UI click: a 40ms rounded tick for buttons — tactile, not clacky.
local function makeClick()
    local rate = 44100
    local dur  = 0.045
    local n    = math.floor(rate * dur)
    local sd   = love.sound.newSoundData(n, rate, 16, 1)
    for i = 0, n - 1 do
        local t = i / rate
        local v = math.sin(2 * math.pi * 1400 * t) * math.exp(-t * 110)
                + 0.4 * math.sin(2 * math.pi * 700 * t) * math.exp(-t * 90)
        sd:setSample(i, v * 0.5)
    end
    local src = love.audio.newSource(sd, "static")
    src:setVolume(0.28)
    return src
end

local function makeSweepSwish()
    local rate = 44100
    local dur  = 0.16
    local n    = math.floor(rate * dur)
    local sd   = love.sound.newSoundData(n, rate, 16, 1)
    local rng  = love.math.newRandomGenerator(7)   -- fixed → same swish always
    local lp   = 0
    for i = 0, n - 1 do
        local t     = i / n
        local env   = math.sin(t * math.pi)        -- swell in, fade out
        local noise = rng:random() * 2 - 1
        lp = lp + 0.22 * (noise - lp)              -- one-pole lowpass: soft
        sd:setSample(i, lp * env * 0.9)
    end
    local src = love.audio.newSource(sd, "static")
    src:setVolume(0.30)
    return src
end

function S.load()
    local function newSrc(name, mode)
        if love.filesystem.getInfo(SRC_DIR .. name) then
            return love.audio.newSource(SRC_DIR .. name, mode or "static")
        end
        return nil
    end

    startGame = newSrc("startgame.wav", "static")
    if startGame then startGame:setVolume(0.65) end

    for i = 1, CARD_GIVE_POOL_SIZE do
        local s = newSrc("cardgive.mp3", "static")
        if s then
            s:setVolume(0.6)
            cardGivePool[i] = s
        end
    end

    winChime   = makeWinChime()
    sweepSwish = makeSweepSwish()
    uiClick    = makeClick()
end

function S.setEnabled(on)
    S.enabled = on and true or false
    if not S.enabled then
        love.audio.stop()
    end
end

function S.playStartGame()
    if not S.enabled or not startGame then return end
    startGame:stop()
    startGame:play()
end

function S.playCardGive(speed)
    if not S.enabled or #cardGivePool == 0 then return end
    local src = cardGivePool[cardGivePoolIndex]
    cardGivePoolIndex = (cardGivePoolIndex % #cardGivePool) + 1
    src:stop()
    -- Speed the sound up so rapid deals don't tail-stack into a mush
    src:setPitch(speed or 2.4)
    src:play()
end

-- Soft bell arpeggio — fired together with the confetti on a win.
function S.playWin()
    if not S.enabled or not winChime then return end
    winChime:stop()
    winChime:play()
end

-- Brushed-felt swish as the four cards sweep to the trick winner.
function S.playSweep()
    if not S.enabled or not sweepSwish then return end
    sweepSwish:stop()
    sweepSwish:play()
end

-- Soft tick on every button press (tactile feedback for touch screens).
function S.playClick()
    if not S.enabled or not uiClick then return end
    uiClick:stop()
    uiClick:play()
end

function S.stopAll()
    love.audio.stop()
end

return S
