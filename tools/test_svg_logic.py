import os, re

ROOT   = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC    = os.path.join(ROOT, "SVG")
DST    = os.path.join(ROOT, "assets", "cards")

SUIT_NUM = {"clubs": 1, "diamonds": 2, "hearts": 3, "spades": 4}
RANK_NUM = {"a": 14, "ace": 14, "j": 11, "jack": 11, "q": 12, "queen": 12,
            "k": 13, "king": 13,
            "2": 2, "3": 3, "4": 4, "5": 5, "6": 6,
            "7": 7, "8": 8, "9": 9, "10": 10}

chosen = {}
for f in sorted(os.listdir(SRC)):
    if not f.endswith(".svg"):
        continue
    base = f[:-4]
    m = re.match(r"^(.+?)_of_(.+?)(2)?$", base, re.IGNORECASE)
    if not m:
        print(f"Regex failed for: {f}")
        continue
    rk_s, su_s, alt = m.group(1), m.group(2), m.group(3)
    rk = RANK_NUM.get(rk_s.lower())
    su = SUIT_NUM.get(su_s.lower())
    if rk is None or su is None:
        print(f"Lookup failed for: {rk_s} or {su_s}")
        continue
    key = (rk, su)
    if key in chosen and not alt:       
        pass
    if alt or key not in chosen:
        chosen[key] = f

print(f"Chosen length: {len(chosen)}")
for (rk, su), f in sorted(chosen.items()):
    out = os.path.join(DST, f"r{rk}_s{su}.png")
    print(f"  {f:25s}  ->  {os.path.basename(out)}")
