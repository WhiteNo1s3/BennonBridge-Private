local C = {}

-- Suits
C.CLUBS    = 1
C.DIAMONDS = 2
C.HEARTS   = 3
C.SPADES   = 4

C.SUIT_NAMES   = {"Clubs", "Diamonds", "Hearts", "Spades"}
C.SUIT_SYMBOLS = {"\xE2\x99\xA3", "\xE2\x99\xA6", "\xE2\x99\xA5", "\xE2\x99\xA0"}  -- ♣♦♥♠
C.SUIT_IS_RED  = {false, true, true, false}

-- Ranks: internal value = 2..14 (Ace=14)
-- Index into these arrays = rank - 1
C.RANK_NAMES = {"2","3","4","5","6","7","8","9","10","J","Q","K","A"}

-- High-card points by rank index (rank-1)
C.HCP = {0,0,0,0,0,0,0,0,0,1,2,3,4}
-- rank 2(1)=0 ... 10(9)=0, J(10)=1, Q(11)=2, K(12)=3, A(13)=4

-- Players
C.NORTH = 1
C.EAST  = 2
C.SOUTH = 3   -- human
C.WEST  = 4

C.PLAYER_NAMES = {"North","East","South","West"}

-- Partnerships
C.PARTNER = {3, 4, 1, 2}     -- N<->S, E<->W

-- Play order: clockwise N->E->S->W
C.NEXT = {2, 3, 4, 1}

-- Left-hand opponent (and previous in play order)
-- LHO[N]=W, LHO[E]=N, LHO[S]=E, LHO[W]=S
C.LHO = {4, 1, 2, 3}

-- Contract suit constants
C.NO_TRUMP = 5

C.CONTRACT_NAMES  = {"Clubs","Diamonds","Hearts","Spades","No Trump"}
C.CONTRACT_SHORT  = {"C","D","H","S","NT"}

-- Tricks needed for GAME in each strain
C.GAME_TRICKS = {11, 11, 10, 10, 9}   -- C, D, H, S, NT

-- Per-trick point values (for scoring trick points above 6)
C.TRICK_PTS = {20, 20, 30, 30, 30}    -- C,D=20; H,S,NT=30 (NT also has 10-pt bonus)

-- Difficulty levels
C.EASY    = 1
C.MEDIUM  = 2
C.HARD    = 3
C.HARDER  = 4
C.HARDEST = 5
C.DIFF_NAMES = {"Easy", "Medium", "Hard", "Harder", "Hardest"}

-- Game states
C.STATE_MENU      = "menu"
C.STATE_NEWGAME   = "newgame"
C.STATE_DEALING   = "dealing"       -- intro deal animation
C.STATE_AUCTION   = "auction"
C.STATE_PLAYING   = "playing"
C.STATE_TRICK_END = "trick_end"
C.STATE_RESULT    = "result"

-- Call types (one call per player per turn during the auction)
C.CALL_BID       = "bid"
C.CALL_PASS      = "pass"
C.CALL_DOUBLE    = "double"
C.CALL_REDOUBLE  = "redouble"

-- Bid denominations: 1..4 align with suits, 5 = NT
C.BID_CLUBS    = 1
C.BID_DIAMONDS = 2
C.BID_HEARTS   = 3
C.BID_SPADES   = 4
C.BID_NT       = 5

C.DENOM_SHORT  = {"C", "D", "H", "S", "NT"}
C.DENOM_NAMES  = {"Clubs", "Diamonds", "Hearts", "Spades", "No Trump"}
C.IS_MAJOR     = {false, false, true, true, false}   -- per denom 1..5
C.IS_MINOR     = {true,  true,  false, false, false}

-- AI delay between calls during the auction
C.AUCTION_AI_DELAY = 0.9

-- Display
C.SW = 1280
C.SH = 800

-- Card size drives the whole table layout. Seat badges, side-hand insets and
-- the trick spread are derived from CARD_H in render.lua, so bumping these four
-- numbers rescales everything coherently. Enlarged for phone readability
-- (was 70x98); keeps the original ~70:98 aspect.
C.CARD_W       = 96
C.CARD_H       = 134
C.CARD_RADIUS  = 8
C.CARD_OVERLAP = 30   -- horizontal/vertical overlap in a fan

return C
