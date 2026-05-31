import os

# The Premium Casino Ivory Finish
bg_color = "#FCFAF2" 
inner_border_color = "#EAE0C8"

suits = {
    'Hearts': {'color': '#E91E63', 'path': 'M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z'},
    'Diamonds': {'color': '#E91E63', 'path': 'M12 2L2 12l10 10 10-10L12 2z'},
    'Clubs': {'color': '#212121', 'path': 'M 12,2 C 8,2 6.5,5 8,7.5 C 8.5,8.5 9.5,9 10.5,9.5 C 8.5,9.5 6,9 4.5,11 C 3,13 4.5,16 7,16 C 8.5,16 10,15 11,14 C 11,16 10,19 9,21 L 15,21 C 14,19 13,16 13,14 C 14,15 15.5,16 17,16 C 19.5,16 21,13 19.5,11 C 18,9 15.5,9.5 13.5,9.5 C 14.5,9 15.5,8.5 16,7.5 C 17.5,5 16,2 12,2 Z'},
    'Spades': {'color': '#212121', 'path': 'M12 2C12 2 4 11 4 15c0 2.21 1.79 4 4 4 1.34 0 2.53-.66 3.22-1.67V21h1.56v-3.67c.69 1.01 1.88 1.67 3.22 1.67 2.21 0 4-1.79 4-4 0-4-8-13-8-13z'}
}

layouts = {
    'J': [(125, 175, False)],
    'Q': [(125, 175, False)],
    'K': [(125, 175, False)]
}

output_dir = "."

svg_template = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 250 350" width="100%" height="100%">
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

    <g fill="{color}">
        {pips_content}
    </g>
</svg>"""

for suit_name, suit_data in suits.items():
    for rank, positions in layouts.items():
        filename = os.path.join(output_dir, f"{rank}_of_{suit_name}.svg")
        
        pips_content = ""
        # Vary the scale slightly to differentiate J, Q, K
        scale = 3.5
        if rank == 'Q': scale = 4.5
        if rank == 'K': scale = 5.5
        
        for (x, y, flip) in positions:
            offset_x = x - (12 * scale)
            offset_y = y - (12 * scale)
            
            transform = f"translate({offset_x}, {offset_y}) scale({scale})"
            if flip:
                transform = f"rotate(180 {x} {y}) " + transform
                
            pips_content += f'<g transform="{transform}"><path d="{suit_data["path"]}" /></g>\n        '
        
        svg_content = svg_template.format(
            rank=rank,
            color=suit_data['color'],
            path=suit_data['path'],
            bg=bg_color,
            border=inner_border_color,
            pips_content=pips_content.strip()
        )
        
        with open(filename, 'w') as f:
            f.write(svg_content)

print(f"Successfully generated premium face cards in {output_dir}")
