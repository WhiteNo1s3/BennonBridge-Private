import os
import re

input_dir = "source_svgs"
output_dir = "upgraded_svgs_premium"

os.makedirs(input_dir, exist_ok=True)
os.makedirs(output_dir, exist_ok=True)

# 1. The 3D Lighting Module
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

# 2. The Exact Geometry of the Premium Frame
premium_frame = """
    <rect x="5" y="5" width="240" height="340" rx="15" fill="#FCFAF2" stroke="#d0d0d0" stroke-width="1"/>
    <rect x="15" y="15" width="220" height="320" rx="8" fill="none" stroke="#EAE0C8" stroke-width="1.5" opacity="0.8"/>"""

processed_count = 0

for filename in os.listdir(input_dir):
    if not filename.lower().endswith('.svg'):
        continue
        
    filepath = os.path.join(input_dir, filename)
    with open(filepath, 'r', encoding='utf-8') as f:
        svg_data = f.read()

    # Step A: Inject the lighting definitions
    if '<linearGradient id="grad_red"' not in svg_data:
        svg_data = re.sub(r'(<svg[^>]*>)', r'\1' + defs_injection, svg_data, count=1, flags=re.IGNORECASE)

    # Step B: Obliterate the old basic background and inject the premium frame
    # This targets the standard 240x340 white rectangle from our earlier baseline templates
    old_rect_pattern = r'<rect x="5" y="5" width="240" height="340" rx="15" fill="#ffffff"[^>]*>'
    
    if re.search(old_rect_pattern, svg_data):
        svg_data = re.sub(old_rect_pattern, premium_frame.strip(), svg_data, count=1)
    else:
        # Fallback: If the background was already changed to Ivory but is missing the inner frame
        fallback_pattern = r'<rect x="5" y="5" width="240" height="340" rx="15" fill="#FCFAF2"[^>]*>'
        if re.search(fallback_pattern, svg_data) and "Elegant Inner Border" not in svg_data:
             svg_data = re.sub(fallback_pattern, premium_frame.strip(), svg_data, count=1)

    # Step C: Map the 3D lighting to the raw solid colors
    svg_data = svg_data.replace('fill="#E91E63"', 'fill="url(#grad_red)"')
    svg_data = svg_data.replace('fill="#212121"', 'fill="url(#grad_black)"')
    
    output_filepath = os.path.join(output_dir, filename)
    with open(output_filepath, 'w', encoding='utf-8') as f:
        f.write(svg_data)
        
    processed_count += 1

print(f"Standardization complete. Successfully injected the Premium Frame and 3D lighting into {processed_count} files in ./{output_dir}/")