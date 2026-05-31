import resvg_py
import re

def normalize_svg(path):
    content = open(path, encoding='utf-8').read()
    content = re.sub(r'\swidth="[^"]+"',  ' width="100%"',  content, count=1)
    content = re.sub(r'\sheight="[^"]+"', ' height="100%"', content, count=1)
    return content

raw = open('SVG/jack_of_clubs2.svg', encoding='utf-8').read()
norm = normalize_svg('SVG/jack_of_clubs2.svg')

try:
    d1 = resvg_py.svg_to_bytes(svg_string=raw, width=560, height=784)
    print(f"RAW rendered OK, size: {len(d1)} bytes")
except Exception as e:
    print(f"RAW failed: {e}")

try:
    d2 = resvg_py.svg_to_bytes(svg_string=norm, width=560, height=784)
    print(f"NORM rendered OK, size: {len(d2)} bytes")
    # Check if image is blank (all 0s)
    if all(b == 0 for b in d2):
        print("NORM is completely blank (all zeroes)!")
except Exception as e:
    print(f"NORM failed: {e}")
