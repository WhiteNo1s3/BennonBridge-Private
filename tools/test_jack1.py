import resvg_py
import re

def normalize_svg(path):
    content = open(path, encoding='utf-8').read()
    content = re.sub(r'\swidth="[^"]+"',  ' width="100%"',  content, count=1)
    content = re.sub(r'\sheight="[^"]+"', ' height="100%"', content, count=1)
    return content

norm = normalize_svg('SVG/jack_of_clubs.svg')
d2 = resvg_py.svg_to_bytes(svg_string=norm, width=560, height=784)
open('test_jack1.png', 'wb').write(bytes(d2))

print(f"jack_of_clubs.svg size: {len(d2)}")
