import resvg_py
import re
from io import BytesIO

def normalize_svg(path):
    content = open(path, encoding='utf-8').read()
    content = re.sub(r'\swidth="[^"]+"',  ' width="100%"',  content, count=1)
    content = re.sub(r'\sheight="[^"]+"', ' height="100%"', content, count=1)
    return content

raw = normalize_svg('SVG/jack_of_clubs2.svg')
d2 = resvg_py.svg_to_bytes(svg_string=raw, width=560, height=784)

# Check top-left pixel (0,0) or (10,10) to see if it's transparent!
# PNG format starts with 8-byte signature, we can just use a simple python PNG parser or just write it out.
open("test_trans.png", "wb").write(bytes(d2))
