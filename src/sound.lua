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

local winChime               -- procedural: soft bell arpeggio on a win
local sweepSwish             -- procedural: felt-brush swish on trick gather

-- ── Procedural sounds ──────────────────────────────────────────────────────
-- Synthesised at load so they ship with the code (no asset files) and stay
-- deliberately GENTLE: a win is a soft four-note bell arpeggio (C-E-G-C),
-- a trick sweep is a short brushed-felt swish. Nothing that could grate on
-- the hundredth hearing.

local function makeWinChime()
    local rate  = 44100
    local dur   = 1.6
    local n     = math.floor(rate * dur)
    local sd    = love.sound.newSoundData(n, rate, 16, 1)
    local notes = {523.25, 659.25, 783.99, 1046.50}    -- C5 E5 G5 C6
    for i = 0, n - 1 do
        local t = i / rate
        local v = 0
        for k, f in ipairs(notes) do
            local t0 = (k - 1) * 0.14
            if t >= t0 then
                local lt  = t - t0
                local env = math.exp(-lt * 3.0)
                -- Fundamental + a whisper of 2nd harmonic = soft bell
                v = v + env * (math.sin(2 * math.pi * f * lt)
                             + 0.18 * math.sin(4 * math.pi * f * lt))
            end
        end
        v = v * 0.20
        if v > 1 then v = 1 elseif v < -1 then v = -1 end
        sd:setSample(i, v)
    end
    local src = love.audio.newSource(sd, "static")
    src:setVolume(0.55)
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

function S.stopAll()
    love.audio.stop()
end

return S
