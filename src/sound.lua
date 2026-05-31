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

function S.stopAll()
    love.audio.stop()
end

return S
