-- Virtual-resolution viewport
--
-- The whole game is laid out in a fixed 1280x800 virtual space. This module
-- maps that virtual space to whatever window size LÖVE is currently in,
-- preserving aspect ratio (letterboxed). Drawing code just uses virtual
-- coords; mouse coords from love callbacks are converted with toVirtual().
--
-- Resulting behaviour: window is freely resizable and the game scales
-- crisply at any size, like Balatro.

local C = require("src.constants")

local V = {}

V.W       = C.SW       -- virtual width  (1280)
V.H       = C.SH       -- virtual height (800)
V.scale   = 1
V.offsetX = 0
V.offsetY = 0

function V.update()
    local winW, winH = love.graphics.getDimensions()

    -- Phone mode: the virtual width follows the device's real aspect ratio
    -- so the table fills the screen edge-to-edge (no dead margins on a
    -- 19.5:9 panel). Height stays fixed at the denser C.SH; layout code
    -- reads C.SW per frame, so everything re-centres automatically.
    if C.PHONE and winH > 0 then
        local w = math.floor(C.SH * (winW / winH) + 0.5)
        C.SW = math.max(C.SW_MIN or 1100, math.min(C.SW_MAX or 1600, w))
        V.W  = C.SW
        V.H  = C.SH
    end

    -- letterbox: pick the smaller scale so both axes fit
    local sx = winW / V.W
    local sy = winH / V.H
    V.scale   = math.min(sx, sy)
    V.offsetX = (winW - V.W * V.scale) / 2
    V.offsetY = (winH - V.H * V.scale) / 2
end

-- Begin drawing transform: call once at the top of love.draw, before
-- anything else. drawEnd() must be called at the end of love.draw.
function V.drawBegin()
    love.graphics.push()
    love.graphics.translate(V.offsetX, V.offsetY)
    love.graphics.scale(V.scale, V.scale)
end

function V.drawEnd()
    love.graphics.pop()
    -- No letterbox bars are painted here: the window is cleared every frame to
    -- the active mood's felt colour (see render.applyMoodBackground), so the
    -- margins on wide/tall displays fill with felt and the table bleeds to the
    -- screen edges. The centred play area is drawn on top inside drawBegin.
end

-- Convert a window coordinate (from love.mouse*) into virtual space.
function V.toVirtual(x, y)
    return (x - V.offsetX) / V.scale,
           (y - V.offsetY) / V.scale
end

function V.mouseVirtual()
    local x, y = love.mouse.getPosition()
    return V.toVirtual(x, y)
end

return V
