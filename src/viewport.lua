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
    -- Letterbox bars (kept subtle so the felt is the focus)
    local winW, winH = love.graphics.getDimensions()
    love.graphics.setColor(0, 0, 0, 1)
    if V.offsetX > 0 then
        love.graphics.rectangle("fill", 0, 0, V.offsetX, winH)
        love.graphics.rectangle("fill", winW - V.offsetX, 0, V.offsetX, winH)
    end
    if V.offsetY > 0 then
        love.graphics.rectangle("fill", 0, 0, winW, V.offsetY)
        love.graphics.rectangle("fill", 0, winH - V.offsetY, winW, V.offsetY)
    end
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
