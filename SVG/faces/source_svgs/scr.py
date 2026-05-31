import os

# --- Specifications ---
bg_color = "#FCFAF2" 
inner_border_color = "#EAE0C8"

suits = {
    'Hearts': {'color': 'url(#grad_red)', 'path': 'M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z'},
    'Diamonds': {'color': 'url(#grad_red)', 'path': 'M12 2L2 12l10 10 10-10L12 2z'},
    'Clubs': {'color': 'url(#grad_black)', 'path': 'M 12,2 C 8,2 6.5,5 8,7.5 C 8.5,8.5 9.5,9 10.5,9.5 C 8.5,9.5 6,9 4.5,11 C 3,13 4.5,16 7,16 C 8.5,16 10,15 11,14 C 11,16 10,19 9,21 L 15,21 C 14,19 13,16 13,14 C 14,15 15.5,16 17,16 C 19.5,16 21,13 19.5,11 C 18,9 15.5,9.5 13.5,9.5 C 14.5,9 15.5,8.5 16,7.5 C 17.5,5 16,2 12,2 Z'},
    'Spades': {'color': 'url(#grad_black)', 'path': 'M12 2C12 2 4 11 4 15c0 2.21 1.79 4 4 4 1.34 0 2.53-.66 3.22-1.67V21h1.56v-3.67c.69 1.01 1.88 1.67 3.22 1.67 2.21 0 4-1.79 4-4 0-4-8-13-8-13z'}
}
ranks = ['J', 'Q', 'K']

output_dir = "vector_deck_faces_premium"
art_dir = "face_art_inserts"
os.makedirs(output_dir, exist_ok=True)
os.makedirs(art_dir, exist_ok=True)

# Master Template with embedded 3D Lighting and Premium Frame
svg_template = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 250 350" width="100%" height="100%">
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
    </defs>

    <rect x="5" y="5" width="240" height="340" rx="15" fill="{bg}" stroke="#d0d0d0" stroke-width="1"/>
    <rect x="15" y="15" width="220" height="320" rx="8" fill="none" stroke="{border}" stroke-width="1.5" opacity="0.8"/>
    
    <g fill="{color}">
        <text x="32" y="52" font-family="Arial, sans-serif" font-size="42" font-weight="bold" text-anchor="middle" letter-spacing="-2">{rank}</text>
        <g transform="translate(20, 58) scale(1)">
            <path d="{path}" />
        </g>
    </g>

    <g fill="{color}" transform="rotate(180 125 175)">
        <text x="32" y="52" font-family="Arial, sans-serif" font-size="42" font-weight="bold" text-anchor="middle" letter-spacing="-2">{rank}</text>
        <g transform="translate(20, 58) scale(1)">
            <path d="{path}" />
        </g>
    </g>

    <g id="traditional-art-insert" transform="translate(45, 60) scale(0.8)">
        {embedded_art}
    </g>
</svg>"""

count = 0
for suit_name, suit_data in suits.items():
    for rank in ranks:
        art_filename = os.path.join(art_dir, f"{rank}_{suit_name}_art.svg")
        
        embedded_art = ""
        if os.path.exists(art_filename):
            with open(art_filename, 'r', encoding='utf-8') as art_file:
                embedded_art = art_file.read()
        else:
            embedded_art = f''

        filename = os.path.join(output_dir, f"{rank}_of_{suit_name}.svg")
        svg_content = svg_template.format(
            rank=rank,
            color=suit_data['color'], # This correctly applies the gradient URL
            path=suit_data['path'],
            bg=bg_color,
            border=inner_border_color,
            embedded_art=embedded_art
        )
        
        with open(filename, 'w', encoding='utf-8') as f:
            f.write(svg_content)
        count += 1

print(f"Standardization complete. Successfully compiled {count} premium face cards in ./{output_dir}/")