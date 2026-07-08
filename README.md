# Bridge

**Single-player contract bridge (Minibridge) for Windows, Android and tablets.**
You play South against three AI opponents. Built with [LÖVE](https://love2d.org) — one code base, native feel on every screen.

## 📥 Download

Grab the latest build from **[Releases](../../releases)** →

| Platform | File |
|---|---|
| Android phone / tablet | `ShaltielBridge-android.apk` |
| Windows | `ShaltielBridge-windows.zip` (unzip, run `Bridge.exe`) |

No ads, no accounts, no network — fully offline.

## ✨ Highlights

- **Phone-native layout** — on Android your hand fills the screen at full size, opponents appear as compass badges holding visible card fans, and the app locks to landscape. On PC you get the classic four-hand table. Tablets work out of the box.
- **Serious AI** — five difficulty tiers. *Easy* plays like a believable newbie; *Harder*/*Hardest* run Monte-Carlo lookahead, dealing the unseen cards into hundreds of sampled worlds and playing each to the end of the hand. Hardest thinks deepest when declaring. Deterministic per deal — replays are exact.
- **Deal codes** — every deal is a 4-character code (e.g. `K7QX`): 1.3 million distinct deals, easy to read to a friend, type it in to play the same hand anywhere.
- **Standard match play** — single hands, or tournaments of 8 / 12 / 16 boards with a full traveler sheet (contract, declarer, tricks, points, winner per board).
- **Accessible by design** — three text sizes (Large is bold, everything reacts live), continuous card-size slider with true-size preview, 44px-minimum touch targets, tap feedback on every button.
- **Atmosphere** — the table re-themes itself with the time of day (sunrise → night) or stays on your chosen felt; 9 card-back themes; deal flourish, card-flight and trick-sweep animations; gentle synthesized sounds with a ta-da + confetti on your wins.

## 🎮 Play

- **Bid** from the bidding box (Standard American), then play tricks by tapping/clicking a card.
- Long-press a card to magnify it; flick it toward the centre to play it (touch).
- The gold halo shows which card won the trick; the pill tells you who took it.
- **Options** (in game) adjusts card size and text size live.

## 🔧 Run from source

Install [LÖVE 11.5](https://love2d.org), then:

```bat
run.bat            # or: love .
```

Build the distributables:

```bat
build-exe.bat      # dist/Bridge/Bridge.exe  (branded, standalone)
build-apk.bat      # dist/Bridge.apk         (see android/README.md for setup)
```

## 📁 Structure

```
main.lua           entry point, input, screen flow
src/
  game.lua         rules, auction, scoring
  ai.lua           five tiers incl. Monte-Carlo rollout engine
  bidding.lua      Standard American auction logic
  render.lua       all drawing: table, cards, screens (PC + phone layouts)
  mood.lua         time-of-day table themes
  deck.lua         deal engine + deal codes
  anim.lua         deal animation
  sound.lua        procedural + sampled audio
  viewport.lua     virtual-resolution scaling (any window, any device)
  constants.lua    every tunable in one place
assets/            card art, backs, icon, sounds
android/           Android build configuration (see its README)
```

---

A **Shaltiel Enterprises** production, developed by **WhiteNo1s3** — made with love for the family bridge table. 🂡
