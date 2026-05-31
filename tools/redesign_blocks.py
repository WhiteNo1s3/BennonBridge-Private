import re

with open("src/render.lua", "r", encoding="utf-8") as f:
    code = f.read()

# 1. Remove drawFaceCardProcedural
proc_pattern = r"-- Procedural J/Q/K face.*?end\n"
code = re.sub(r"-- Procedural J/Q/K face.*?^end\n", "", code, flags=re.MULTILINE | re.DOTALL)

# 2. Update card rendering to not use fallback
#     if img then
#         -- Use SVG-rasterized face
#         if dimmed then setColor(0.75, 0.75, 0.75) else setColor(1, 1, 1) end
#         local sx, sy = CW / img:getWidth(), CH / img:getHeight()
#         love.graphics.draw(img, x, y, 0, sx, sy)
#     else
#         -- J/Q/K — procedural
#         if dimmed then setColor(0.8, 0.8, 0.8) else setColor(PAL.card_face) end
#         drawFaceCardProcedural(x, y, card, scol)
#     end
fallback_pattern = r"    if img then\s+-- Use SVG-rasterized face\s+if dimmed then setColor\(0\.75, 0\.75, 0\.75\) else setColor\(1, 1, 1\) end\s+local sx, sy = CW / img:getWidth\(\), CH / img:getHeight\(\)\s+love\.graphics\.draw\(img, x, y, 0, sx, sy\)\s+else\s+-- J/Q/K — procedural\s+if dimmed then setColor\(0\.8, 0\.8, 0\.8\) else setColor\(PAL\.card_face\) end\s+drawFaceCardProcedural\(x, y, card, scol\)\s+end"
new_card_render = """    if img then
        -- Use SVG-rasterized face
        if dimmed then setColor(0.75, 0.75, 0.75) else setColor(1, 1, 1) end
        local sx, sy = CW / img:getWidth(), CH / img:getHeight()
        love.graphics.draw(img, x, y, 0, sx, sy)
    end"""
code = re.sub(fallback_pattern, new_card_render, code)

# 3. Rewrite drawBidCard and drawBidCardSlot
bid_pattern = r"local BID_CARD_W, BID_CARD_H, BID_CARD_R = 64, 90, 7\n\nlocal function drawBidCard\(cx, cy, hcp, suit, rotation, highlight\).*?end\n\n-- Empty placeholder card slot \(waiting for player to call\)\nlocal function drawBidCardSlot\(cx, cy, rotation, highlight\).*?end\n"

new_bid_code = """local BID_BLOCK_W, BID_BLOCK_H, BID_BLOCK_R = 76, 50, 6

local function drawBidCard(cx, cy, hcp, suit, rotation, highlight)
    rotation = rotation or 0
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(rotation)
    local x, y = -BID_BLOCK_W/2, -BID_BLOCK_H/2

    -- Shadow
    setColor(0, 0, 0, 0.4)
    love.graphics.rectangle("fill", x+3, y+4, BID_BLOCK_W, BID_BLOCK_H, BID_BLOCK_R)

    -- Glow ring if active player
    if highlight then
        setColor(PAL.yellow)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", x-4, y-4, BID_BLOCK_W+8, BID_BLOCK_H+8, BID_BLOCK_R+2)
        love.graphics.setLineWidth(1)
    end

    -- Block body - sleek dark grey/blue plastic tile look
    setColor(0.15, 0.18, 0.22)
    love.graphics.rectangle("fill", x, y, BID_BLOCK_W, BID_BLOCK_H, BID_BLOCK_R)
    
    -- Inner flat bevel
    setColor(0.25, 0.28, 0.32)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x+2, y+2, BID_BLOCK_W-4, BID_BLOCK_H-4, BID_BLOCK_R-1)
    love.graphics.setLineWidth(1)

    -- Centre: big HCP value (the "call") in pure white or bright color
    setColor(PAL.white)
    love.graphics.setFont(fonts.large)
    local fw = fonts.large:getWidth(tostring(hcp))
    local fh = fonts.large:getHeight()
    love.graphics.print(tostring(hcp), -fw/2, -fh/2 - 4)

    -- Tiny "PTS" label
    setColor(0.7, 0.7, 0.7)
    love.graphics.setFont(fonts.tiny)
    centredText(fonts.tiny, "PTS", 0, BID_BLOCK_H/2 - 12)

    love.graphics.pop()
end

-- Empty placeholder block slot
local function drawBidCardSlot(cx, cy, rotation, highlight)
    rotation = rotation or 0
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(rotation)
    local x, y = -BID_BLOCK_W/2, -BID_BLOCK_H/2

    setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", x, y, BID_BLOCK_W, BID_BLOCK_H, BID_BLOCK_R)
    
    if highlight then
        setColor(PAL.yellow)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x, y, BID_BLOCK_W, BID_BLOCK_H, BID_BLOCK_R)
    else
        setColor(0.45, 0.45, 0.45, 0.5)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", x, y, BID_BLOCK_W, BID_BLOCK_H, BID_BLOCK_R)
    end
    love.graphics.setLineWidth(1)
    love.graphics.pop()
end
"""
code = re.sub(bid_pattern, new_bid_code, code, flags=re.DOTALL)

with open("src/render.lua", "w", encoding="utf-8") as f:
    f.write(code)
