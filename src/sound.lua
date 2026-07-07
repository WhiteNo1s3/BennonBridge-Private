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

-- A real "TA-DA!" — organ voicing, not a synth. Each note is a drawbar-style
-- harmonic stack (fundamental + octaves + fifth-ish partials) doubled with a
-- slightly detuned copy for warm chorus, plus a slow tremolo on the held
-- chord. "TA" is a short G-major pickup, "DAAA" a held C-major that breathes
-- out. No pitch vibrato anywhere — that sine-shimmer was the alien part.
local ORGAN_H = {
    {1, 1.00}, {2, 0.55}, {3, 0.22}, {4, 0.30}, {6, 0.12}, {8, 0.06},
}

local function organ(t, f)
    local v = 0
    for _, h in ipairs(ORGAN_H) do
        local hf = f * h[1]
        v = v + h[2] * math.sin(2 * math.pi * hf * t)
        -- chorus: a quiet detuned double gives the pipes their warmth
        v = v + h[2] * 0.32 * math.sin(2 * math.pi * hf * 1.004 * t + 0.7)
    end
    return v
end

local function makeWinChime()
    local rate = 44100
    local dur  = 2.1
    local n    = math.floor(rate * dur)
    local sd   = love.sound.newSoundData(n, rate, 16, 1)
    local T2   = 0.18                                     -- "DA" lands here
    local TA   = {196.00, 246.94, 293.66}                 -- G3 B3 D4
    local DA   = {261.63, 329.63, 392.00, 523.25}         -- C4 E4 G4 C5
    for i = 0, n - 1 do
        local t = i / rate
        local v = 0
        -- "TA": short pickup chord, released before the resolution
        if t < T2 then
            local env = math.min(1, t * 160) * math.exp(-t * 7)
            for _, f in ipairs(TA) do v = v + env * organ(t, f) end
        end
        -- "DAAA": the held chord, swelling in fast, breathing out slowly,
        -- with a gentle organ tremolo (amplitude only, never pitch)
        if t >= T2 then
            local lt   = t - T2
            local env  = math.min(1, lt * 90) * math.exp(-lt * 1.35)
            local trem = 1 + 0.07 * math.sin(2 * math.pi * 5.0 * lt)
            for _, f in ipairs(DA) do v = v + env * trem * organ(lt, f) end
        end
        v = v * 0.052
        if v > 1 then v = 1 elseif v < -1 then v = -1 end
        sd:setSample(i, v)
    end
    local src = love.audio.newSource(sd, "static")
    src:setVolume(0.66)
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
