# Bridge — roadmap

Engine: LOVE2D. Ships as standalone Windows .exe (`build-exe.bat`) and Android .apk (`build-apk.bat`).

## Remaining ideas

### Deck themes — a picker with up to 4 decks
1. Regular — plain numerics + plain faces (original look).
2. Ben's illustrated faces + regular numerics ← current state.
3. 3D dense numerics (denser pips + 3D look).
4. 3D dense numerics + Ben's faces with a 3D effect.

Needs: a deck-style setting + load cards from `assets/decks/<name>/` instead of one folder. Additive; keep the current deck as default. The generated numeric sets already exist in the BennonCards repo (`numerics_dense/`, `numerics_dense3d/`).
