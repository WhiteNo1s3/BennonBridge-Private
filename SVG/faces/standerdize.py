import os
import re

# Define I/O directories
input_dir = "source_svgs"
output_dir = "upgraded_svgs"

os.makedirs(input_dir, exist_ok=True)
os.makedirs(output_dir, exist_ok=True)

# The standardized 3D Lighting Gradients
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

processed_count = 0

for filename in os.listdir(input_dir):
    if not filename.lower().endswith('.svg'):
        continue
        
    filepath = os.path.join(input_dir, filename)
    
    with open(filepath, 'r', encoding='utf-8') as f:
        svg_data = f.read()

    # 1. Inject the <defs> block immediately after the opening <svg ...> tag
    # We use regex to handle any variations in the opening SVG tag formatting
    if '<linearGradient id="grad_red"' not in svg_data:
        svg_data = re.sub(r'(<svg[^>]*>)', r'\1' + defs_injection, svg_data, count=1, flags=re.IGNORECASE)

    # 2. Target and replace the flat hex codes with the gradient URLs
    # Assuming your flat files use the standard #E91E63 and #212121 we established
    svg_data = svg_data.replace('fill="#E91E63"', 'fill="url(#grad_red)"')
    svg_data = svg_data.replace('fill="#212121"', 'fill="url(#grad_black)"')
    
    # 3. Overwrite the premium ivory background if it uses standard white
    svg_data = svg_data.replace('fill="#ffffff"', 'fill="#FCFAF2"')

    output_filepath = os.path.join(output_dir, filename)
    with open(output_filepath, 'w', encoding='utf-8') as f:
        f.write(svg_data)
        
    processed_count += 1

print(f"Standardization complete. Successfully injected 3D lighting into {processed_count} files in ./{output_dir}/")