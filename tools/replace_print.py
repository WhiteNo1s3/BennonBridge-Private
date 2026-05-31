import re

with open("src/render.lua", "r", encoding="utf-8") as f:
    code = f.read()

# Replace all `love.graphics.print` with `R.print`
code = code.replace("love.graphics.print", "R.print")

# Inject R.print definition near the top of the file, after `local R = {}`
# and update font generation to be 4x.
# Wait, I can do this using standard python string replaces.

with open("src/render.lua", "w", encoding="utf-8") as f:
    f.write(code)
