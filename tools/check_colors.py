import re

data = open('SVG/jack_of_clubs2.svg', encoding='utf-8').read()
styles = re.findall(r'style="([^"]+)"', data)
colors = set()
for s in styles:
    for rule in s.split(';'):
        if rule.startswith('fill:'):
            colors.add(rule.split(':')[1])
print("Style fills:", colors)

fills = re.findall(r'fill="([^"]+)"', data)
print("Attr fills:", set(fills))
