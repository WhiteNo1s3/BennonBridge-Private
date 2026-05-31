import resvg_py
import re
from PIL import Image
import io

def normalize_svg(path):
    content = open(path, encoding='utf-8').read()
    content = re.sub(r'\swidth="[^"]+"',  ' width="100%"',  content, count=1)
    content = re.sub(r'\sheight="[^"]+"', ' height="100%"', content, count=1)
    return content

norm = normalize_svg('SVG/jack_of_clubs2.svg')
d2 = resvg_py.svg_to_bytes(svg_string=norm, width=560, height=784)

img = Image.open(io.BytesIO(d2))
print("Extrema:", img.getextrema())

colors = img.getcolors(maxcolors=1000)
if colors is None:
    print("More than 1000 colors, this is a real complex image!")
else:
    print("Colors:", colors)
