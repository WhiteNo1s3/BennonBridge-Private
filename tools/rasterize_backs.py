"""
Rasterize the card-back SVGs in assets/card_backs/ and
assets/card_backs_thematic/ to PNGs alongside them.
LÖVE loads the PNGs at runtime.
"""
import os, resvg_py

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = [os.path.join(ROOT, "assets", "card_backs"),
        os.path.join(ROOT, "assets", "card_backs_thematic")]
W, H = 280, 392     # 4x display size, same as faces

count = 0
for d in DIRS:
    if not os.path.isdir(d):
        continue
    for f in sorted(os.listdir(d)):
        if not f.endswith(".svg"):
            continue
        src = os.path.join(d, f)
        # Strip pt-unit width/height if present (resvg requires plain px)
        content = open(src, encoding="utf-8").read()
        import re
        content = re.sub(r'\swidth="[^"]+"',  ' width="100%"',  content, count=1)
        content = re.sub(r'\sheight="[^"]+"', ' height="100%"', content, count=1)
        out_name = os.path.splitext(f)[0] + ".png"
        out = os.path.join(d, out_name)
        data = resvg_py.svg_to_bytes(svg_string=content, width=W, height=H)
        with open(out, "wb") as fh:
            fh.write(bytes(data))
        print(f"  {f} -> {out_name}")
        count += 1

print(f"\nrasterized {count} backs")
