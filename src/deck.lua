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
