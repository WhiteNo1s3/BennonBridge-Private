"""
Rasterize the SVG card faces in SVG/ into PNGs in assets/cards/.
Naming: r<rank>_s<suit>.png   (rank 2..14, suit 1..4 matching constants.lua)
  suits: 1=Clubs 2=Diamonds 3=Hearts 4=Spades
"""
import os, sys, re, resvg_py
defs_injection = """
    <defs>
        <linearGradient id="grad_red" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stop-color="#FF5252" />
            <stop offset="50%" stop-color="#E91E63" />
            <stop offset="100%" stop-color="#880E4F" />
        </linearGradient>
        <linearGradient id="grad_black" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stop-color="#616161" />
            <stop offset="50%" stop-color="#212121" />
            <stop offset="100%" stop-color="#000000" />
        </linearGradient>
    </defs>"""

def normalize_svg(path):
    """Normalize SVGs for resvg AND inject vintage 3D styling dynamically."""
    content = open(path, encoding='utf-8').read()
    
    # Inject 3D lighting gradients
    if '<linearGradient id="grad_red"' not in content:
        content = re.sub(r'(<svg[^>]*>)', r'\1' + defs_injection, content, count=1, flags=re.IGNORECASE)
    
    # Apply 3D gradients to traditional face cards (which use inline CSS styles)
    content = content.replace('fill:#000000', 'fill:url(#grad_black)')
    content = content.replace('fill:#df0000', 'fill:url(#grad_red)')
    
    # Ensure numeric cards are also fully styled
    content = content.replace('fill="#E91E63"', 'fill="url(#grad_red)"')
    content = content.replace('fill="#212121"', 'fill="url(#grad_black)"')
    
    # Apply vintage ivory background to face cards
    content = content.replace('fill:#FFFFFF', 'fill:#FCFAF2')
    # Apply vintage ivory background to numeric cards
    content = content.replace('fill="#ffffff"', 'fill="#FCFAF2"')
    
    # Override fixed dimensions with 100% so viewBox drives the scaling in resvg
    content = re.sub(r'\swidth="[^"]+"',  ' width="100%"',  content, count=1)
    content = re.sub(r'\sheight="[^"]+"', ' height="100%"', content, count=1)
    return content
ROOT   = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC    = os.path.join(ROOT, "SVG")
PREMIUM_SRC = os.path.join(ROOT, "SVG", "faces", "upgraded_svgs_premium")
DST    = os.path.join(ROOT, "assets", "cards")
W, H   = 560, 784   # 8x display size (70x98)
SUIT_NUM = {"clubs": 1, "diamonds": 2, "hearts": 3, "spades": 4}
RANK_NUM = {"a": 14, "ace": 14, "j": 11, "jack": 11, "q": 12, "queen": 12,
            "k": 13, "king": 13,
            "2": 2, "3": 3, "4": 4, "5": 5, "6": 6,
            "7": 7, "8": 8, "9": 9, "10": 10}
os.makedirs(DST, exist_ok=True)
chosen = {}
def scan_dir(d):
    if not os.path.exists(d): return
    for f in sorted(os.listdir(d)):
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
        if key in chosen and not alt:       
            pass
        if alt or key not in chosen:
            chosen[key] = os.path.join(d, f)
scan_dir(SRC)
scan_dir(PREMIUM_SRC)
count = 0
for (rk, su), f in sorted(chosen.items()):
    out = os.path.join(DST, f"r{rk}_s{su}.png")
    data = resvg_py.svg_to_bytes(
        svg_string=normalize_svg(f),
        width=W, height=H)
    with open(out, "wb") as fh:
        fh.write(bytes(data))
    count += 1
    print(f"  {f:25s}  ->  {os.path.basename(out)}")
print(f"\nrasterized {count} files into {DST} at {W}x{H}")
