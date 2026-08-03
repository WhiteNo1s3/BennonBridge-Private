# BennonBridge — Handoff / Project State

Onboarding doc for a fresh chat continuing work on this project. Snapshot date: **2026-08-04**.

## What this is
Single-player **Minibridge / contract bridge** game in **LÖVE2D (Lua)**. Human plays South vs 3 AI. Resolution-independent: virtual height is fixed (800 desktop / 620 phone) and the **virtual width adapts to the real aspect ratio on every platform** (clamped 1100–1600, felt-bleed beyond) — 16:9, 16:10, 21:9 and phone panels all get an edge-to-edge table. `conf.lua` declares `t.version` **per-OS** ("12.0" on Android for love-android, "11.5" elsewhere) so no target shows the compatibility warning. Local dev/testing uses LÖVE 11.5 via `lovec.exe`.

## 2026-08-04 ship round (adaptive desktop + persistence + hi-res deck)
- **Desktop layout**: auction board + bidding zone are ONE centred cluster; the three AI seats hold **compact fans** (0.58×) during auction AND play (full-size "back walls" looked terrible on wide screens); a face-up side dummy renders 0.80×. Seat badges anchor to the drawn fan depths, N/S plates sit BESIDE their fans (with a below-left fallback for North on narrow tables). Deal animation lands cards on the exact compact/full slots (anim.lua desktop branch mirrors render's auction anchors).
- **HCP privacy**: badges only show HCP for South and the public dummy (they used to leak concealed hands).
- **Settings persistence**: `src/settings.lua` → `settings.lua` in the save dir; saved on every change (Android never fires love.quit). Save identity is `shaltiel-bridge`. ⚠️ Dev runs save under `%APPDATA%\LOVE\shaltiel-bridge`, the **fused exe saves under `%APPDATA%\shaltiel-bridge`** (LÖVE fused-mode path) — different files, don't chase "missing" settings.
- **Fullscreen**: F11 / Alt+Enter (borderless), state persisted; first run opens maximized; fullscreen toggle also in the in-game Options popover (desktop only). Launch seed is randomized each boot.
- **Dev/screenshot harness** (inert without flags): `lovec . --auction [CODE]` jumps into the auction, `--auto` = spectator, `--dealanim` keeps the deal animation, `--shot FILE DELAY` captures a PNG to the save dir and quits. Env `BRIDGE_HIDDEN=1` + `BRIDGE_SHOT_W/H` render **fully invisible** at any resolution — this is how layouts are verified without touching the desktop. Harness runs never write settings.
- **Hi-res deck**: all 52 faces + all backs now ship at 560-wide (numerics/aces were 270/280-wide). Rendered from the BennonCards **premium-ivory SVG masters** — this also unified the deck (numerics used to be a stale white style that clashed with the ivory courts). The **ornate filigree A♠** (the signature card) was vectorized from the old raster and grafted onto the premium ivory body: new master at `bennon-cards/svg/A_of_Spades.svg` (+ synced `png/`, `backs/` renders) — **left uncommitted in the cards repo**, review & commit there.
- **Shipped artifacts** (built from this branch): `dist\Bridge\` (fused Bridge.exe + LÖVE DLLs), `dist\Bridge-Windows-x64.zip`, `dist\Bridge.apk` (signed release, V2 cert CN=Shaltiel Enterprises).

- **Run it:** double-click `run.bat` (prefers `lovec.exe` so Lua errors print to the console). Or `& "C:\Program Files\LOVE\lovec.exe" "C:\Users\Ben\Documents\bridge"`.
- **Working dir:** `C:\Users\Ben\Documents\bridge`
- **Key files:** `main.lua` (state machine, input), `src/render.lua` (all drawing), `src/game.lua` (rules/state), `src/bidding.lua` (Standard American AI), `src/ai.lua` (card-play AI), `src/anim.lua` (deal animation), `src/constants.lua`, `src/viewport.lua`, `src/sound.lua`.

## Git / repos — READ THIS FIRST (past confusion lived here)
The game repos **moved to the `WhiteNo1s3` org**. Two remotes:
- `origin` → `https://github.com/WhiteNo1s3/BennonBridge.git` (public)
- `bennon-private` → `https://github.com/WhiteNo1s3/BennonBridge-Private.git` (private mirror)

**Branch state (all aligned):** `main` and `v2` on BOTH remotes point at the **same commit** = the current game **+ MIT LICENSE**. `main` is the **default branch** and shows the current game. `v2` == `main` (byte-identical). Develop on either; keep them in sync.

**Archive tags (nothing was lost when branches were realigned):**
- `main-archive-2026-08-03` — the old pre-v2 `main` line.
- `private-v2-archive-2026-08-03` — an old diverged private line.
Recover with `git checkout <tag>`.

**Backups (local, git-ignored):** `assets/cards_OLD_backup_*/`, `backup_assets_cards_OLD_*/` — ignored on purpose; don't commit them.

## Cards — source of truth is a SEPARATE repo
Card art lives in **BennonCards** (private, still under `benshaltiel`): `https://github.com/benshaltiel/BennonCards`, local `C:\Users\Ben\Documents\bennon-cards`. **SVG is the master; the game uses rendered PNGs** (LÖVE can't load SVG).

- The **J/Q/K face cards are Ben's ORIGINAL artwork** (full-bleed square 1024×1024, in `png/originals_1024/`). They are **truly vectorized** (real paths, not a PNG embedded in an SVG, not cropped).
- Pipeline `tools/build_facecards.py`: 1024 → **non-uniform resize** to 560×784 (a crop would chop the corner rank letter) → **vtracer** trace → rounded-corner clip → **svgo**.
- ⚠️ **RUN THE VECTOR TOOLS UNDER PYTHON 3.10** — `vtracer 0.6.15` hard-crashes (access violation) on Python 3.14:
  `& "C:\Program Files\Python310\python.exe" tools\build_facecards.py`
- To change court art: replace `png/originals_1024/*.png` → re-run `build_facecards.py` → copy `bennon-cards\png\r1{1,2,3}_s*.png` into `bridge\assets\cards\`.
- BennonCards layout: `svg/` (52 card-shaped vector masters), `svg/original_facecards_svg/` (square backups), `png/` (game-ready 560×784), `png/originals_1024/` (raw source), `backs/`, `tools/`.

## Card file naming (both repos)
`assets/cards/r{rank}_s{suit}.png` — rank 2..14 (11=J 12=Q 13=K 14=A), suit 1=Clubs 2=Diamonds 3=Hearts 4=Spades. Aspect 5:7 (70:98). Faces + backs share an identical silhouette via stencil clipping in `render.lua`.

## Conventions
- Public credit ships as **WhiteNo1s3 / Shaltiel Enterprises** — never "Ben"/"Bennon" in shipped/user-facing text. applicationId `com.shaltiel.bridge`.
- Commit only when asked; don't push backups; keep `main` and `v2` aligned across both remotes.
