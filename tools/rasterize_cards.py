"""
Rasterize all card-face SVGs into PNGs in assets/cards/.

Output naming: r<rank>_s<suit>.png
  ranks: 2..10, 11=J, 12=Q, 13=K, 14=A
  suits: 1=Clubs 2=Diamonds 3=Hearts 4=Spades

Recognises both naming styles found in vector_deck_numerics/:
  "<Rank>_of_<Suit>.svg"          (A, 2..10, jack/queen/king)
  Files ending "2.svg" are alternate styles -- ignored, we use the first.

PNG resolution is high (4x display) so the textures stay sharp when the
LÖVE window is resized larger.
"""
import os, re, resvg_py

def normalize_svg(path):
    """Some SVGs declare width/height in pt units (e.g. 167.08pt) which
    resvg rejects with 'invalid size'. We override them to 100%, letting
    the viewBox drive the rendering at the requested output size."""
    content = open(path, encoding='utf-8').read()
    content = re.sub(r'\swidth="[^"]+"',  ' width="100%"',  content, count=1)
    content = re.sub(r'\sheight="[^"]+"', ' height="100%"', content, count=1)
    return content

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC  = os.path.join(ROOT, "vector_deck_numerics")
DST  = os.path.join(ROOT, "assets", "cards")
W, H = 280, 392    # 4x display (display is 70x98)

SUIT_NUM = {"clubs": 1, "diamonds": 2, "hearts": 3, "spades": 4}
RANK_NUM = {"a": 14, "ace": 14, "j": 11, "jack": 11, "q": 12, "queen": 12,
            "k": 13, "king": 13,
            "2": 2, "3": 3, "4": 4, "5": 5, "6": 6,
            "7": 7, "8": 8, "9": 9, "10": 10}

os.makedirs(DST, exist_ok=True)

# Group files by (rank, suit), preferring the variant without trailing "2"
chosen = {}                 # (rank, suit) -> filename
for f in sorted(os.listdir(SRC)):
    if not f.endswith(".svg"):
        continue
    base = f[:-4]
    m = re.match(r"^(.+?)_of_(.+?)(2)?$", base, re.IGNORECASE)
    if not m:
        continue
    rk_s, su_s, alt = m.group(1), m.group(2), m.group(3)
    rk = RANK_NUM.get(rk_s.lower())
    su = SUIT_NUM.get(su_s.lower())
    if rk is None or su is None:
        continue
    key = (rk, su)
    if key in chosen and alt:           # already have non-alt; keep it
        continue
    if key in chosen and not alt:       # prefer non-alt over alt
        chosen[key] = f
    elif key not in chosen:
        chosen[key] = f

count = 0
for (rk, su), f in sorted(chosen.items()):
    out = os.path.join(DST, f"r{rk}_s{su}.png")
    data = resvg_py.svg_to_bytes(
        svg_string=normalize_svg(os.path.join(SRC, f)),
        width=W, height=H)
    with open(out, "wb") as fh:
        fh.write(bytes(data))
    count += 1
    print(f"  {f:32s} -> r{rk:>2}_s{su}.png")

print(f"\nrasterized {count}/52 cards into {DST}  ({W}x{H})")
