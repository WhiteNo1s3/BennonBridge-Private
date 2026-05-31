import os, re

for fname in os.listdir('SVG'):
    if 'jack' in fname or 'king' in fname or 'queen' in fname:
        path = os.path.join('SVG', fname)
        content = open(path, encoding='utf-8').read()
        
        has_viewbox = 'viewBox' in content
        external_links = re.findall(r'xlink:href="([^#][^"]+)"', content)
        has_image = '<image' in content
        
        print(f"{fname}: viewBox={has_viewbox}, external={external_links}, image={has_image}")
