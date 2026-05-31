import os, re, resvg_py

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

with open('SVG/jack_of_clubs2.svg', 'r', encoding='utf-8') as f:
    svg_data = f.read()

# Inject defs
if '<linearGradient id="grad_red"' not in svg_data:
    svg_data = re.sub(r'(<svg[^>]*>)', r'\1' + defs_injection, svg_data, count=1, flags=re.IGNORECASE)

# Replace black and red
svg_data = svg_data.replace('fill:#000000', 'fill:url(#grad_black)')
svg_data = svg_data.replace('fill:#df0000', 'fill:url(#grad_red)')
svg_data = svg_data.replace('fill:#FFFFFF', 'fill:#FCFAF2') # Make the skin/white vintage ivory

# Normalize width/height
svg_data = re.sub(r'\swidth="[^"]+"',  ' width="100%"',  svg_data, count=1)
svg_data = re.sub(r'\sheight="[^"]+"', ' height="100%"', svg_data, count=1)

try:
    d2 = resvg_py.svg_to_bytes(svg_string=svg_data, width=560, height=784)
    with open('test_gradient.png', 'wb') as f:
        f.write(bytes(d2))
    print(f"Rendered test_gradient.png successfully! Size: {len(d2)}")
except Exception as e:
    print("Failed:", e)
