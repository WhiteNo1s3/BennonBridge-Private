import re

with open("src/render.lua", "r", encoding="utf-8") as f:
    code = f.read()

# Replace any `somefont:getWidth(args)` with `(somefont:getWidth(args) * 0.25)`
# We need to be careful not to replace `img:getWidth()`.
# We know the fonts are named `fonts.X` or `font`.
code = re.sub(r'(fonts?\.[a-zA-Z]+:getWidth\([^)]*\))', r'(\1 * 0.25)', code)
code = re.sub(r'(fonts?\.[a-zA-Z]+:getHeight\([^)]*\))', r'(\1 * 0.25)', code)

# Also `font:getWidth(text)` and `font:getHeight()` inside centredText are already modified,
# but we might double-multiply them. Let's revert the manual ones first or just handle them.
# The `font:` variable is used in `centredText`.
code = re.sub(r'(font:getWidth\([^)]*\))', r'(\1 * 0.25)', code)
code = re.sub(r'(font:getHeight\([^)]*\))', r'(\1 * 0.25)', code)

# Wait, `img:getWidth()` is fine, it won't match `font` or `fonts.X`.
# Let's fix double replacements if any.
code = code.replace("((font:getWidth(text) * 0.25) * 0.25)", "(font:getWidth(text) * 0.25)")
code = code.replace("((font:getHeight() * 0.25) * 0.25)", "(font:getHeight() * 0.25)")

with open("src/render.lua", "w", encoding="utf-8") as f:
    f.write(code)
