import re

content = open('SVG/jack_of_clubs2.svg', encoding='utf-8').read()
print("BEFORE:")
print(content[:500])

content = re.sub(r'\swidth="[^"]+"',  ' width="100%"',  content, count=1)
content = re.sub(r'\sheight="[^"]+"', ' height="100%"', content, count=1)

print("\nAFTER:")
print(content[:500])
