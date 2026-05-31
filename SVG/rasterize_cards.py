"""
Rasterize the SVG card faces in vector_deck_numerics/ into PNGs in assets/cards/.
Naming: r<rank>_s<suit>.png   (rank 2..14, suit 1..4 matching constants.lua)
  suits: 1=Clubs 2=Diamonds 3=Hearts 4=Spades
"""
import os, sys, resvg_py

ROOT   = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC    = os.path.join(ROOT, "SVG")
DST    = os.path.join(ROOT, "assets", "cards")
W, H   = 140, 196   # 2x display size (70x98)

SUIT_NUM = {"Clubs": 1, "Diamonds": 2, "Hearts": 3, "Spades": 4}
RANK_NUM = {"A": 14, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6,
            "7": 7, "8": 8, "9": 9, "10": 10}

os.makedirs(DST, exist_ok=True)
count = 0
for f in sorted(os.listdir(SRC)):
    if not f.endswith(".svg"):
        continue
    name = f[:-4]                # e.g. "A_of_Spades"
    rk_s, _, su = name.partition("_of_")
    rk = RANK_NUM.get(rk_s)
    su = SUIT_NUM.get(su)
    if rk is None or su is None:
        print(f"  skip {f}")
        continue
    out = os.path.join(DST, f"r{rk}_s{su}.png")
    data = resvg_py.svg_to_bytes(svg_path=os.path.join(SRC, f), width=W, height=H)
    with open(out, "wb") as fh:
        fh.write(bytes(data))
    count += 1
    print(f"  {f}  ->  {os.path.basename(out)}")

print(f"\nrasterized {count} files into {DST}")
