import re

with open("src/render.lua", "r", encoding="utf-8") as f:
    code = f.read()

# 1. Revert R.print to love.graphics.print
code = code.replace("R.print", "love.graphics.print")

# 2. Revert getWidth and getHeight * 0.25 additions
code = code.replace(" * 0.25", "")

# 3. Remove the R.print function definition
# It looks like:
# function R.print(text, x, y, r, sx, sy, ox, oy, kx, ky)
#     -- We force 0.25x scaling for our 4x oversampled fonts
#     sx = (sx or 1)
#     sy = (sy or 1)
#     love.graphics.print(text, x, y, r or 0, sx, sy, ox or 0, oy or 0, kx or 0, ky or 0)
# end

# Wait, since I removed `* 0.25`, it looks like:
pattern = r"function love\.graphics\.print\(text, x, y, r, sx, sy, ox, oy, kx, ky\)\n    -- We force 0\.25x scaling for our 4x oversampled fonts\n    sx = \(sx or 1\)\n    sy = \(sy or 1\)\n    love\.graphics\.print\(text, x, y, r or 0, sx, sy, ox or 0, oy or 0, kx or 0, ky or 0\)\nend\n\n"
code = re.sub(pattern, "", code)

# 4. Revert font sizes in R.load
code = code.replace(" * 4", "")

# 5. Remove R.drawOptions from render.lua
options_pattern = r"-- ── Options menu ──.*?end\n\n"
code = re.sub(r"-- ── Options menu ──.*?(?=-- ── New-game setup)", "", code, flags=re.DOTALL)


with open("src/render.lua", "w", encoding="utf-8") as f:
    f.write(code)
