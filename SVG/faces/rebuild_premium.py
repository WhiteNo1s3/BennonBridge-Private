"""
Rebuild the upgraded_svgs_premium folder from the source face card SVGs.
Copies the detailed artwork SVGs with the '2' suffix naming convention
that the rasterizer expects for override priority.
"""
import os
import re
import shutil

source_dir = os.path.join(os.path.dirname(__file__), "source_svgs")
output_dir = os.path.join(os.path.dirname(__file__), "upgraded_svgs_premium")

os.makedirs(output_dir, exist_ok=True)

# Mapping from short rank prefix to full name (for the '2' suffix naming)
rank_map = {"J": "jack", "Q": "queen", "K": "king"}

# 3D Lighting Gradients
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

# Premium Frame
premium_frame = """
    <rect x="5" y="5" width="240" height="340" rx="15" fill="#FCFAF2" stroke="#d0d0d0" stroke-width="1"/>
    <rect x="15" y="15" width="220" height="320" rx="8" fill="none" stroke="#EAE0C8" stroke-width="1.5" opacity="0.8"/>"""

count = 0

for filename in sorted(os.listdir(source_dir)):
    if not filename.lower().endswith('.svg'):
        continue
    
    # Match patterns like J_of_Clubs.svg or J_of_hearts.svg
    m = re.match(r'^([JQK])_of_(\w+)\.svg$', filename, re.IGNORECASE)
    if not m:
        continue
    
    rank_letter = m.group(1).upper()
    suit_name = m.group(2).lower()
    
    full_rank = rank_map.get(rank_letter)
    if not full_rank:
        continue
    
    # Build the output name with '2' suffix: e.g. jack_of_clubs2.svg
    out_name = f"{full_rank}_of_{suit_name}2.svg"
    
    src_path = os.path.join(source_dir, filename)
    out_path = os.path.join(output_dir, out_name)
    
    # Read, apply premium styling, write
    with open(src_path, 'r', encoding='utf-8') as f:
        svg_data = f.read()
    
    # Inject lighting defs
    if '<linearGradient id="grad_red"' not in svg_data:
        svg_data = re.sub(r'(<svg[^>]*>)', r'\1' + defs_injection, svg_data, count=1, flags=re.IGNORECASE)
    
    # Inject premium frame background
    old_rect_pattern = r'<rect[^>]*fill="#ffffff"[^>]*>'
    if re.search(old_rect_pattern, svg_data, re.IGNORECASE):
        svg_data = re.sub(old_rect_pattern, premium_frame.strip(), svg_data, count=1, flags=re.IGNORECASE)
    
    # Map 3D lighting
    svg_data = svg_data.replace('fill="#E91E63"', 'fill="url(#grad_red)"')
    svg_data = svg_data.replace('fill="#212121"', 'fill="url(#grad_black)"')
    
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(svg_data)
    
    count += 1
    print(f"  {filename} -> {out_name}")

print(f"\nRebuilt {count} premium face card SVGs in {output_dir}")
