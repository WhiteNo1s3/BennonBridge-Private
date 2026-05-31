import os

for fname in os.listdir('SVG'):
    if 'jack' in fname or 'king' in fname or 'queen' in fname:
        path = os.path.join('SVG', fname)
        content = open(path, encoding='utf-8').read()
        
        if 'display:none' in content.replace(' ', '') or 'display="none"' in content.replace(' ', ''):
            print(f"{fname} has hidden elements!")
