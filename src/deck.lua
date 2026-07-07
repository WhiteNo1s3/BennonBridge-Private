local C = require("src.constants")

local Deck = {}

function Deck.new()
    local d = {}
    for suit = 1, 4 do
        for rank = 2, 14 do
            d[#d+1] = {suit=suit, rank=rank}
        end
    end
    return d
end

-- Fisher-Yates using a LÖVE RandomGenerator (seeded)
function Deck.shuffle(deck, rng)
    for i = #deck, 2, -1 do
        local j = rng:random(1, i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end

-- Deal 52 cards into 4 hands of 13, using integer seed.
-- Returns hands[1..4], each a sorted array of {suit,rank}.
function Deck.deal(seed)
    local rng  = love.math.newRandomGenerator(seed)
    local deck = Deck.new()
    Deck.shuffle(deck, rng)

    local hands = {{},{},{},{}}
    for i, card in ipairs(deck) do
        hands[((i-1) % 4) + 1][#hands[((i-1) % 4) + 1]+1] = card
    end

    for p = 1, 4 do
        -- Sort: by suit desc, then rank desc within suit
        table.sort(hands[p], function(a,b)
            if a.suit ~= b.suit then return a.suit > b.suit end
            return a.rank > b.rank
        end)
    end
    return hands
end

function Deck.countHCP(hand)
    local hcp = 0
    for _, c in ipairs(hand) do
        hcp = hcp + C.HCP[c.rank - 1]
    end
    return hcp
end

function Deck.suitLen(hand, suit)
    local n = 0
    for _, c in ipairs(hand) do
        if c.suit == suit then n = n + 1 end
    end
    return n
end

-- ── Deal codes ─────────────────────────────────────────────────────────────
-- "Long in the back office, short on the box": internally a deal is an
-- integer spread across LÖVE's full 2^64 shuffle space, but the customer
-- sees a compact 1-4 character CODE in base-34 (digits + letters, minus the
-- confusable I and O). Four characters cover 34^4 = 1,336,336 distinct
-- deals — more than the old six digits, in a third of the width.
local CODE_ALPHA = "0123456789ABCDEFGHJKLMNPQRSTUVWXYZ"
local CODE_VAL   = {}
for i = 1, #CODE_ALPHA do CODE_VAL[CODE_ALPHA:sub(i, i)] = i - 1 end
CODE_VAL["O"] = 0   -- forgive the two ambiguous glyphs
CODE_VAL["I"] = 1

function Deck.encodeSeed(n)
    n = math.floor(tonumber(n) or 1)
    n = (n - 1) % C.SEED_MAX            -- 0-based inside the code space
    local s = ""
    repeat
        local d = n % 34
        s = CODE_ALPHA:sub(d + 1, d + 1) .. s
        n = math.floor(n / 34)
    until n == 0
    return s
end

-- Returns the integer seed for a typed code, or nil if it isn't one.
-- Case-insensitive; whitespace ignored; O/I read as 0/1.
function Deck.decodeSeed(str)
    if type(str) ~= "string" then return nil end
    str = str:upper():gsub("%s", "")
    if str == "" or #str > (C.CODE_LEN or 4) then return nil end
    local n = 0
    for i = 1, #str do
        local v = CODE_VAL[str:sub(i, i)]
        if not v then return nil end
        n = n * 34 + v
    end
    return (n % C.SEED_MAX) + 1
end

function Deck.rankName(rank)  return C.RANK_NAMES[rank - 1] end
function Deck.suitSym(suit)   return C.SUIT_SYMBOLS[suit]   end

function Deck.cardLabel(card)
    return C.RANK_NAMES[card.rank-1] .. C.SUIT_SYMBOLS[card.suit]
end

-- Remove card from hand (modifies in place), returns true on success
function Deck.removeCard(hand, card)
    for i, c in ipairs(hand) do
        if c.suit == card.suit and c.rank == card.rank then
            table.remove(hand, i)
            return true
        end
    end
    return false
end

return Deck
