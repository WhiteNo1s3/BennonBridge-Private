# BennonBridge (Minibridge / Contract Bridge)

**Single-player bridge.** Human plays South. North-South vs East-West. Strong AI at multiple difficulties.

LÖVE 12 target (SDF fonts + Android compatibility). Everything laid out in a fixed 1280x800 virtual space and scaled with letterboxing to any window size. Resizable, crisp at any resolution (ultrawide friendly — felt bleeds to screen edges).

**This is the last / complete version** containing everything: mood system, advanced unified graphics + runtime card sizing, full 7-board tournament mode with the Traveler Sheet design (including per-board seeds for perfect replays), bidding, play, sounds, animations, builds, and all the power-user / testing features I added.

## Core Experience
- Human South seat vs three AI opponents.
- Full contract bridge rules (minibridge variant): bidding auction → play → scoring.
- Detailed result and match summary screens.
- Seedable deals for reproducibility + powerful randomizer.

## Major Feature Areas (fucktons of stuff I added)

### Setup / New Game Screen (very rich)
- Seed box: type your own seed (digits only, capped), backspace support, live editing.
- Randomize button (instant new seed).
- Match Mode toggle: Single hand ↔ 7-Board tournament.
- Auto-South toggle: watch the AI play your seat (great for testing / CPU vs CPU demos).
- Card Back Theme: cycle through 9 thematic backs (structured, geometric, art nouveau, poison ivy, dark knight, zombified, cyberpunk, steampunk, art deco).
- Card Size: 6 runtime sizes (Small / Medium / Regular / Big / Bigger / Biggest). Affects every card-derived layout constant. Trick offsets are clamped so big cards never collide hands.
- Mood controls: 
  - Weather On (dynamic by wall-clock time) vs fixed mood.
  - When fixed: cycle through mood themes (classic + others).
- Per-seat difficulty: sliders for North, East, West (South is always locked to HARDEST for fair watching).
- Intro animation toggle, sound master toggle.

### 7-Board Match Mode + Traveler Sheet (the big update with seeds)
- Tracks full match state: matchBoard, matchStartSeed, matchSeeds array, sessionScore, matchWins, matchBoardDetails.
- Every hand end in 7-board mode captures rich per-board record:
  - board number, seed, contract (suit + tricks + doubled/redoubled state), declarer, tricks made by declarer, points awarded, winner side (NS/EW).
- After 7 boards: "MATCH COMPLETE" summary with side-by-side scores + wins.
- "Reveal Table" button opens the full **Traveler Sheet**:
  - Large centered panel with header "7-BOARD MATCH DETAILS (TRAVELER SHEET)".
  - Columns: BOARD | SEED | CONTRACT | DECLARER | TRICKS | POINTS | WINNER.
  - Alternating row colors, proper contract notation (e.g. 4H X), color-coded winner sides.
  - Empty rows show for unplayed boards.
- From the sheet: < Summary, Replay Match (from first seed), New Match (advances start seed by 7), Main Menu.
- Seeds are stored and replayable exactly.
- Next Board / Next Hand logic respects 7-board limit and switches to match summary at the end.

### Graphics & Presentation (V2 polish)
- **Unified card silhouette**: every card (number, court, ace, back) drawn through the same stencil-clipped rounded-rect path. No more "dink" between face and back sizes. Prevents mood decorations bleeding through transparent corners.
- Runtime card scale that rescales layout (not just pixels).
- Mood backdrops (felt + decorative elements change with chosen mood or real time).
- Multiple high-quality SVG-derived card decks and 9 thematic backs.
- Smooth deal animations, trick animations.
- Confetti particle system on big wins (especially match wins).
- Viewport system: virtual 1280x800 → letterboxed real window. Mouse coords converted via toVirtual(). Felt bleeds to edges on ultrawide.
- Seat badges, compass glyphs, role chips, product dummy elements, warm sunrise themes, etc.

### Bidding & Play
- Full interactive auction (bidding box, passes, contracts).
- Legal card enforcement during play.
- AI opponents with real logic (legal cards, trick winner calculation, cheapest/costliest heuristics, winning cards detection).
- 5 difficulty tiers (Easy → Hardest). South uses Hardest when autoSouth is on.

### Audio
- Pooled card-give sounds (8 sources) so rapid 52-card deals don't stack into mush.
- Pitch/speed adjustment on deal sounds for fast deals.
- Start game sting.
- Master enable/disable that affects everything.

### Power User / Testing / Replay Features
- Exact seed replay (type the seed from any previous board or match start).
- Randomize at any time.
- Auto-South + auto-advance through results (perfect for letting CPUs play full matches while you watch).
- Full match replay from original seed.
- New Match starts a fresh 7-board series with advanced seed.
- Per-board matchBoardDetails are queryable (great for analysis or future UI).

### Other Polish
- Keyboard repeat for seed editing.
- Escape to close things, full hit-testing for all buttons/sliders/toggles.
- Clean result flow with "next anywhere" on the summary banner in 7-board mode.
- Confetti only on NS wins (your side).

## Project Structure
```
Documents/bridge/
├── main.lua                 # Entry, setup, all the click handlers, 7-board orchestration, seed/mood/cardSize state
├── conf.lua                 # LÖVE 12 config, resizable, msaa, highdpi
├── src/
│   ├── game.lua             # Game class, deal, auction, play loop, _endHand (board details capture), scoring
│   ├── render.lua           # Everything visual: unified cards, mood backdrops, bidding box, result/match screens, Traveler Sheet, confetti, buttons
│   ├── bidding.lua          # Auction logic
│   ├── ai.lua               # Full AI (legal cards, trick winner, play strategy, 5 tiers)
│   ├── mood.lua             # Dynamic theming system + backdrop drawing
│   ├── deck.lua / anim.lua / sound.lua / viewport.lua / constants.lua
├── assets/                  # Baked cards + 9 backs + sounds + icon
├── dist/                    # Built exe + APKs (after running build scripts)
├── build-exe.bat / build-apk scripts
└── run.bat / run.sh
```

## Running & Building
- Double-click `run.bat` (or run.sh). Kills previous LOVE instance first.
- `build-exe.bat`: Builds game.love then fuses with branded LOVE runtime (icon + version strings applied *before* fusing — important).
- Android path supported (love-android-main in other folders).

## Asset Sources (for when I forget)
Editable vectors + generation pipeline live in:
- Desktop/BennonBridge-1.0 (and Desktop/bridge tools copies)
- Folders: SVG/, vector_deck_numerics*, faces/, tools/ (rasterize_cards.py, check_svgs.py, redesign_blocks.py, scale_fonts.py, various test_*.py, generate_premium_faces, etc.)

Baked PNGs are committed in this repo's assets/.

## Git & Private History
- Primary work: `Documents/bridge` on `v2` branch.
- My original "fucktons of features" update work (especially the 7-board Traveler Sheet + seeds tracking) was prototyped in `Desktop/bridge` and lives forever in local branch `personal/bridge-7board-traveler-update`.
- Private GitHub mirror: https://github.com/benshaltiel/BennonBridge-Private (contains the complete last version).

## Memory Note (critical for me)
When I forget:
- The **last version that has it all** (mood + graphics + full 7-table design style with seeds, contracts, declarer, tricks, points, winner) is right here in `Documents/bridge`.
- Lots of power-user stuff was added: card size live, weather moods, auto-South CPU watching, seed everything, rich bidding UI, pooled fast-deal audio, unified silhouette rendering, ultrawide bleed, etc.
- See `Documents/MyProjects/OVERVIEW.md` for the big picture across all my projects.
- Git history on v2 + the personal branch in the scratch copy are the external brain.

Personal hobby project. All vectors, tools, code, and design by me.

Enjoy the game — the 7-board with the full traveler sheet and seeds is especially satisfying.

## Credits

Built by [WhiteNo1s3](https://github.com/WhiteNo1s3). Released under the MIT License.

