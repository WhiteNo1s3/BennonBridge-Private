# Bridge — roadmap (Ben's vision, captured 2026-06-28)

Engine stays LOVE2D (must keep standalone .exe like Balatro + .apk builds). Drive carefully — Ben's hand-built code. Commit before each change; it's all reversible.

## 1. Bigger cards for older eyes (readability)
- Current cap: C.CARD_W_MAX = 128 in src/constants.lua (capped so 4 hands + center trick fit 1280x800).
- Goal: stretch the cap as large as possible; rebuild layout in render.lua / anim.lua so big cards don't collide. Don't rely on the player choosing the biggest slider step.

## 2. Deck themes — a picker with up to 4 decks
1. Regular/boring — plain numerics + plain faces (original look).
2. Ben's illustrated faces + regular numerics  <- current state.
3. 3D dense numerics (denser pips + 3D look).
4. 3D dense numerics + Ben's faces with a 3D effect.
- Needs code: a deck-style setting + load cards from assets/decks/<name>/ instead of one folder. Additive; keep current as default.

## 3. Denser / 3D numerics + proud Ace
- Full SVG sets in C:\Users\Ben\Documents\bennon-cards\svg + tools (build_facecards.py, rasterize_cards.py).
- Make 2-3 numeric versions: denser pip arrangements; a 3D treatment (bevel/shadow on pips + card).
- Ace: bold and 3D, "proud," not a plain single pip.

## 4. More card backs
- Loader auto-discovers any PNG in assets/card_backs + assets/card_backs_thematic, sorted by leading number. Purely additive. Existing 9 stay.
- DONE 2026-06-28: added new backs.

## Order suggested
Backs (done) -> bigger-card cap+layout -> deck-theme picker -> dense/3D numerics + Ace -> wire 3D into themes.
