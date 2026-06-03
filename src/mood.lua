-- src/mood.lua
--
-- Time-of-day moods for the Bridge table.
--
-- A Mood is a small object that carries:
--   • a palette  — felt colour + an optional full-canvas ambient overlay
--   • a vector decoration drawer — pure love.graphics primitives, so every
--     element scales crisply to 4K screens and tablets without rasterising.
--
-- Five moods follow the wall-clock + one "Classic" mood the user can always
-- fall back to (kept as a backup in case the decorations aren't to their
-- taste). The picker is intentionally tiny so the rest of the renderer can
-- be agnostic about which mood is active — it just calls mood:drawBackdrop().
--
-- Time bands (24-h clock):
--     05:00 – 08:00   sunrise   (cool dawn pinks fading to apricot)
--     08:00 – 16:00   noon      (bright daylight; tribal-flower medallions)
--     16:00 – 19:00   afternoon (golden hour; swaying leaves)
--     19:00 – 21:00   evening   (dusk; silhouette birds along the horizon)
--     21:00 – 05:00   night     (deep blue felt; crescent moon + stars)

local C = require("src.constants")

local M = {}

-- ──────────────────────────────────────────────────────────────────────────
-- Mood "class"
-- ──────────────────────────────────────────────────────────────────────────
local Mood = {}
Mood.__index = Mood
M.Mood = Mood

function Mood.new(opts)
    local self = setmetatable({}, Mood)
    self.id         = opts.id
    self.name       = opts.name
    self.felt       = opts.felt       or {0.12, 0.42, 0.14}
    self.felt_inner = opts.felt_inner or {0.10, 0.38, 0.12}
    self.ambient    = opts.ambient    or {0, 0, 0, 0}        -- {r,g,b,a}
    self.drawDeco   = opts.drawDeco   or function() end
    return self
end

-- Draws the full backdrop for one frame: rectangular felt → centre oval
-- ("the table") → ambient tint → decorations. Callers pass the oval's
-- radii so each screen can keep its own table footprint (auction screen
-- uses a smaller oval than the main menu, etc).
function Mood:drawBackdrop(rx, ry)
    rx = rx or C.SW * 0.40
    ry = ry or C.SH * 0.45
    local cx, cy = C.SW / 2, C.SH / 2

    love.graphics.setColor(self.felt)
    love.graphics.rectangle("fill", 0, 0, C.SW, C.SH)

    -- Decorations live BEHIND the inner felt oval so the player's eye is
    -- drawn to the centre but the corners still feel alive. Cards are drawn
    -- by the caller AFTER this returns, so they always stay on top.
    self.drawDeco(self)

    love.graphics.setColor(self.felt_inner)
    love.graphics.ellipse("fill", cx, cy, rx, ry)

    -- Modern table sheen: a soft lighter bloom toward the upper-centre of the
    -- oval (as if a lamp hangs over the table) plus a darker vignette at the
    -- oval's rim. Cheap concentric ellipses, additive-feeling via low alpha.
    local fi = self.felt_inner
    for i = 6, 1, -1 do
        local t = i / 6
        love.graphics.setColor(fi[1] + 0.10, fi[2] + 0.12, fi[3] + 0.08, 0.05)
        love.graphics.ellipse("fill", cx, cy - ry * 0.10,
            rx * 0.74 * t, ry * 0.70 * t)
    end
    -- Rim shadow: a faint dark ring hugging the oval edge for depth.
    love.graphics.setLineWidth(10)
    love.graphics.setColor(0, 0, 0, 0.06)
    love.graphics.ellipse("line", cx, cy, rx - 3, ry - 3)
    love.graphics.setLineWidth(1)

    if self.ambient[4] and self.ambient[4] > 0 then
        love.graphics.setColor(self.ambient)
        love.graphics.rectangle("fill", 0, 0, C.SW, C.SH)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- ──────────────────────────────────────────────────────────────────────────
-- Vector decoration primitives (pure love.graphics, resolution-independent)
-- ──────────────────────────────────────────────────────────────────────────

-- Tribal/flower medallion: N petals around an inner circle. The petals are
-- filled diamonds with a slight off-axis offset so the motif feels organic
-- rather than mechanical. Used by the noon mood in the four corners.
local function tribalMedallion(cx, cy, r, petals, col, alpha)
    local n = petals or 10
    love.graphics.setColor(col[1], col[2], col[3], alpha)
    for i = 1, n do
        local a   = (i / n) * math.pi * 2
        local sa  = a + math.pi / 2
        local r2  = r * 0.55
        local pw  = r * 0.18
        local x1  = cx + math.cos(a) * r * 0.18
        local y1  = cy + math.sin(a) * r * 0.18
        local x2  = cx + math.cos(a) * r
        local y2  = cy + math.sin(a) * r
        local mxL = cx + math.cos(a) * r2 + math.cos(sa) * pw
        local myL = cy + math.sin(a) * r2 + math.sin(sa) * pw
        local mxR = cx + math.cos(a) * r2 - math.cos(sa) * pw
        local myR = cy + math.sin(a) * r2 - math.sin(sa) * pw
        love.graphics.polygon("fill", x1, y1, mxL, myL, x2, y2, mxR, myR)
    end
    -- Inner concentric rings
    love.graphics.setLineWidth(1.5)
    love.graphics.setColor(col[1], col[2], col[3], alpha * 1.4)
    love.graphics.circle("line", cx, cy, r * 0.42)
    love.graphics.circle("line", cx, cy, r * 0.22)
    love.graphics.circle("fill", cx, cy, r * 0.08)
    love.graphics.setLineWidth(1)
end

-- A six-pointed tribal star with a hollow centre — used as a secondary motif
-- in the noon mood. Six lines radiating from the centre, then a connecting
-- hex outline.
local function tribalStar(cx, cy, r, col, alpha)
    love.graphics.setColor(col[1], col[2], col[3], alpha)
    love.graphics.setLineWidth(1.5)
    for i = 0, 5 do
        local a = i * math.pi / 3
        love.graphics.line(cx, cy,
            cx + math.cos(a) * r, cy + math.sin(a) * r)
    end
    -- Outer hex ring
    local pts = {}
    for i = 0, 5 do
        local a = (i + 0.5) * math.pi / 3
        pts[#pts+1] = cx + math.cos(a) * r * 0.72
        pts[#pts+1] = cy + math.sin(a) * r * 0.72
    end
    love.graphics.polygon("line", pts)
    love.graphics.setLineWidth(1)
end

-- Sunburst rays around (cx,cy). Used for the sunrise mood — rays fan
-- outward from a horizon point in the corner of the canvas.
local function sunburst(cx, cy, rInner, rOuter, rays, col, alpha, startA, sweep)
    startA = startA or 0
    sweep  = sweep  or (math.pi * 2)
    love.graphics.setColor(col[1], col[2], col[3], alpha)
    local step = sweep / rays
    for i = 0, rays - 1 do
        local a   = startA + i * step
        local aw  = step * 0.32   -- half-width of each ray
        local x1  = cx + math.cos(a - aw) * rInner
        local y1  = cy + math.sin(a - aw) * rInner
        local x2  = cx + math.cos(a + aw) * rInner
        local y2  = cy + math.sin(a + aw) * rInner
        local x3  = cx + math.cos(a + aw) * rOuter
        local y3  = cy + math.sin(a + aw) * rOuter
        local x4  = cx + math.cos(a - aw) * rOuter
        local y4  = cy + math.sin(a - aw) * rOuter
        love.graphics.polygon("fill", x1, y1, x2, y2, x3, y3, x4, y4)
    end
end

-- A glowing sun disc: layered halo rings fading outward, a warm core, and a
-- bright hot-spot near the top so it reads as a light source rather than a
-- flat circle. Pairs with sunburst() rays for the sunrise mood.
local function sunDisc(cx, cy, r, coreCol, glowCol, alpha)
    alpha = alpha or 1
    -- Outer halo — many soft rings of decreasing alpha for a smooth bloom.
    for i = 12, 1, -1 do
        love.graphics.setColor(glowCol[1], glowCol[2], glowCol[3], 0.030 * i * alpha)
        love.graphics.circle("fill", cx, cy, r * (1 + i * 0.42))
    end
    -- Core disc.
    love.graphics.setColor(coreCol[1], coreCol[2], coreCol[3], 0.95 * alpha)
    love.graphics.circle("fill", cx, cy, r)
    -- Inner brighter ring + hot-spot to fake a top-lit gradient.
    love.graphics.setColor(1.0, 0.96, 0.80, 0.55 * alpha)
    love.graphics.circle("fill", cx, cy - r * 0.12, r * 0.72)
    love.graphics.setColor(1.0, 1.0, 0.92, 0.65 * alpha)
    love.graphics.circle("fill", cx - r * 0.10, cy - r * 0.22, r * 0.40)
    love.graphics.setColor(1, 1, 1, 1)
end

-- A simple silhouette bird ("seagull" U-shape) drawn with two arcs. Used as
-- a flock for the evening mood.
local function silhouetteBird(cx, cy, w, col, alpha)
    love.graphics.setColor(col[1], col[2], col[3], alpha)
    love.graphics.setLineWidth(math.max(1, w * 0.10))
    -- Left wing arc
    love.graphics.arc("line", "open",
        cx - w * 0.5, cy, w * 0.5, math.pi * 0.10, math.pi * 0.80, 12)
    -- Right wing arc
    love.graphics.arc("line", "open",
        cx + w * 0.5, cy, w * 0.5, math.pi * 0.20, math.pi * 0.90, 12)
    love.graphics.setLineWidth(1)
end

-- Crescent moon — bright disc with a dark "bite" drawn over it. Includes a
-- multi-ring soft glow underneath. Used by the night mood.
local function crescentMoon(cx, cy, r, biteCol)
    -- Outer halo (six rings of decreasing alpha)
    for i = 6, 1, -1 do
        love.graphics.setColor(1.0, 0.96, 0.78, 0.04 * i)
        love.graphics.circle("fill", cx, cy, r * (1 + i * 0.45))
    end
    -- Disc
    love.graphics.setColor(0.98, 0.96, 0.82, 0.95)
    love.graphics.circle("fill", cx, cy, r)
    -- Bite — punched out by overdrawing with the felt colour (passed in by
    -- the caller so the bite matches whatever the night-felt tint is).
    love.graphics.setColor(biteCol[1], biteCol[2], biteCol[3], 1)
    love.graphics.circle("fill", cx + r * 0.32, cy - r * 0.18, r * 0.94)
    -- Subtle crater dots on the visible crescent
    love.graphics.setColor(0.78, 0.76, 0.60, 0.55)
    love.graphics.circle("fill", cx - r * 0.42, cy + r * 0.10, r * 0.07)
    love.graphics.circle("fill", cx - r * 0.18, cy + r * 0.36, r * 0.05)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Scattered star field, fixed seed so they don't flicker between frames.
-- Avoids the centre play area and the four hand zones.
local function starField(seed, count)
    local r = love.math.newRandomGenerator(seed or 1)
    local cx, cy = C.SW / 2, C.SH / 2
    for i = 1, count do
        local x = r:random(20, C.SW - 20)
        local y = r:random(20, C.SH - 20)
        -- Reject if too close to the centre oval (where cards & auction live)
        local dx, dy = x - cx, y - cy
        if (dx * dx) / (480 * 480) + (dy * dy) / (340 * 340) > 1 then
            -- Reject hand zones (top/bottom horizontal strips ~110px each)
            if y > 130 and y < C.SH - 130 then
                local a = 0.22 + r:random() * 0.45
                love.graphics.setColor(1, 1, 0.96, a)
                love.graphics.circle("fill", x, y, 0.8 + r:random() * 1.5)
                if i % 7 == 0 then
                    love.graphics.setLineWidth(1)
                    love.graphics.setColor(1, 1, 0.96, a * 0.55)
                    love.graphics.line(x - 4, y, x + 4, y)
                    love.graphics.line(x, y - 4, x, y + 4)
                end
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Stylised leaf (almond/eye shape) — used to compose afternoon foliage.
-- Drawn as a 12-sided polygon so it stays vector-crisp at any zoom.
local function leaf(cx, cy, w, h, angle, col, alpha)
    local pts = {}
    local segs = 14
    for i = 0, segs - 1 do
        local t  = i / segs * math.pi * 2
        local lx = math.cos(t) * w * 0.5
        local ly = math.sin(t) * h * 0.5
        -- Pointy ends: sharpen the x-extremes by stretching them outward
        if math.abs(math.cos(t)) > 0.95 then lx = lx * 1.25 end
        local rx = cx + math.cos(angle) * lx - math.sin(angle) * ly
        local ry = cy + math.sin(angle) * lx + math.cos(angle) * ly
        pts[#pts+1] = rx
        pts[#pts+1] = ry
    end
    love.graphics.setColor(col[1], col[2], col[3], alpha)
    love.graphics.polygon("fill", pts)
    -- Mid vein
    love.graphics.setColor(col[1] * 0.7, col[2] * 0.7, col[3] * 0.7, alpha * 1.2)
    love.graphics.setLineWidth(1)
    love.graphics.line(
        cx - math.cos(angle) * w * 0.6, cy - math.sin(angle) * w * 0.6,
        cx + math.cos(angle) * w * 0.6, cy + math.sin(angle) * w * 0.6)
end

-- ──────────────────────────────────────────────────────────────────────────
-- Mood instances
-- ──────────────────────────────────────────────────────────────────────────

-- CLASSIC — the backup; identical to V1's static felt, no decorations.
M.classic = Mood.new{
    id   = "classic",
    name = "Classic",
}

-- SUNRISE — warm golden dawn. A real sun sits in the top-right sky with
-- golden rays fanning across the upper canvas, the felt is a warm morning
-- grass, and a soft amber ambient washes the whole scene. Sun + rays stay
-- in the top band, well clear of every hand.
M.sunrise = Mood.new{
    id         = "sunrise",
    name       = "Sunrise",
    felt       = {0.22, 0.34, 0.17},     -- warm morning grass (was cool teal)
    felt_inner = {0.18, 0.30, 0.14},
    ambient    = {1.00, 0.74, 0.40, 0.09},  -- golden wash over everything
    drawDeco   = function(self)
        local SUN_X, SUN_Y, SUN_R = C.SW - 150, 116, 50
        -- Golden rays fanning DOWN/OUT from the sun, swept so they stay in the
        -- top half and never reach the hands. Drawn first so the disc sits on top.
        sunburst(SUN_X, SUN_Y, SUN_R * 0.9, 900, 30,
            {1.00, 0.86, 0.45}, 0.07,
            math.pi * 0.42, math.pi * 1.16)
        -- A second, tighter set of brighter rays for sparkle near the disc.
        sunburst(SUN_X, SUN_Y, SUN_R * 1.05, 360, 16,
            {1.00, 0.93, 0.62}, 0.10,
            math.pi * 0.50, math.pi * 1.00)
        -- The sun itself.
        sunDisc(SUN_X, SUN_Y, SUN_R, {1.00, 0.80, 0.32}, {1.00, 0.78, 0.40}, 1.0)
        -- A faint warm horizon glow band low across the table edges (behind the
        -- inner oval) to suggest early light pooling on the felt.
        for i = 1, 5 do
            love.graphics.setColor(1.00, 0.72, 0.34, 0.035 * (6 - i))
            love.graphics.ellipse("fill", C.SW / 2, C.SH * 0.30,
                C.SW * (0.45 + i * 0.06), 30 + i * 10)
        end
        -- A single soft petal medallion in the opposite (top-left) corner to
        -- balance the composition.
        tribalMedallion(96, 92, 52, 8, {1.0, 0.86, 0.62}, 0.10)
        love.graphics.setColor(1, 1, 1, 1)
    end,
}

-- NOON — bright daylight, tribal-flower medallions in all four corners and
-- a six-pointed tribal star on each side edge. This is the most decorative
-- mood; alpha is low so the table still reads green.
M.noon = Mood.new{
    id         = "noon",
    name       = "Noon",
    felt       = {0.14, 0.46, 0.16},     -- brighter, more saturated grass
    felt_inner = {0.11, 0.40, 0.13},
    drawDeco   = function(self)
        local petalCol = {1.00, 0.95, 0.55}     -- pale gold
        local lineCol  = {1.00, 0.92, 0.40}
        -- Four corner medallions
        tribalMedallion(70,        70,        56, 12, petalCol, 0.16)
        tribalMedallion(C.SW - 70, 70,        56, 12, petalCol, 0.16)
        tribalMedallion(70,        C.SH - 70, 56, 12, petalCol, 0.16)
        tribalMedallion(C.SW - 70, C.SH - 70, 56, 12, petalCol, 0.16)
        -- Six-pointed tribal stars along the side midpoints
        tribalStar(32,         C.SH / 2, 30, lineCol, 0.18)
        tribalStar(C.SW - 32,  C.SH / 2, 30, lineCol, 0.18)
    end,
}

-- AFTERNOON — golden hour. Warmer felt, leafy ornaments creeping in from
-- the corners as if branches reached over the table edge.
M.afternoon = Mood.new{
    id         = "afternoon",
    name       = "Afternoon",
    felt       = {0.18, 0.40, 0.14},
    felt_inner = {0.14, 0.34, 0.11},
    ambient    = {1.00, 0.78, 0.45, 0.06},
    drawDeco   = function(self)
        local leafCol = {0.92, 0.78, 0.30}    -- warm golden green
        -- Top-left cluster: three leaves of varying angle
        leaf( 60,  90, 110, 36, -math.pi * 0.25, leafCol, 0.18)
        leaf(110, 145,  90, 28, -math.pi * 0.10, leafCol, 0.15)
        leaf( 30, 160, 100, 30,  math.pi * 0.10, leafCol, 0.16)
        -- Top-right cluster (mirrored)
        leaf(C.SW -  60,  90, 110, 36,  math.pi * 1.25, leafCol, 0.18)
        leaf(C.SW - 110, 145,  90, 28,  math.pi * 1.10, leafCol, 0.15)
        leaf(C.SW -  30, 160, 100, 30,  math.pi * 0.90, leafCol, 0.16)
        -- Bottom corners — single leaf each, smaller, well away from hands
        leaf( 60, C.SH - 130,  80, 26,  math.pi * 0.25, leafCol, 0.14)
        leaf(C.SW - 60, C.SH - 130,  80, 26, -math.pi * 0.25, leafCol, 0.14)
    end,
}

-- EVENING — dusk. Purple/blue felt with a horizon-glow band and a small
-- flock of silhouette birds along the upper area.
M.evening = Mood.new{
    id         = "evening",
    name       = "Evening",
    felt       = {0.16, 0.18, 0.30},
    felt_inner = {0.12, 0.14, 0.24},
    ambient    = {0.85, 0.45, 0.55, 0.05},
    drawDeco   = function(self)
        -- Horizon glow band (warm orange behind everything, low alpha)
        for i = 1, 6 do
            love.graphics.setColor(1.00, 0.55, 0.25, 0.05 * (7 - i))
            love.graphics.ellipse("fill", C.SW / 2, C.SH * 0.50,
                C.SW * (0.50 + i * 0.05), 18 + i * 6)
        end
        -- Bird flock: V-formation in the upper third
        local bcol = {0.04, 0.04, 0.08}
        silhouetteBird(180, 90, 24, bcol, 0.55)
        silhouetteBird(225, 75, 20, bcol, 0.55)
        silhouetteBird(270, 88, 22, bcol, 0.55)
        silhouetteBird(310, 80, 18, bcol, 0.55)
        -- A trailing single bird far right
        silhouetteBird(C.SW - 210, 110, 26, bcol, 0.50)
        silhouetteBird(C.SW - 250, 130, 18, bcol, 0.45)
    end,
}

-- NIGHT — deep blue felt, crescent moon in the top-left, scattered stars
-- everywhere outside the play area. Bright moon glow but on the side so it
-- doesn't fight with the HUD or hands.
M.night = Mood.new{
    id         = "night",
    name       = "Night",
    felt       = {0.04, 0.06, 0.14},
    felt_inner = {0.06, 0.10, 0.20},
    ambient    = {0.05, 0.05, 0.18, 0.04},
    drawDeco   = function(self)
        starField(20260601, 90)
        -- Moon on the top-left, away from the centre oval and the player's
        -- hand. Bite uses the felt colour so it punches a clean crescent.
        crescentMoon(108, 120, 46, self.felt)
    end,
}

-- ──────────────────────────────────────────────────────────────────────────
-- Public picker
-- ──────────────────────────────────────────────────────────────────────────

M.ORDER = { "classic", "sunrise", "noon", "afternoon", "evening", "night" }

-- All moods, indexable by id.
M.ALL = {
    classic   = M.classic,
    sunrise   = M.sunrise,
    noon      = M.noon,
    afternoon = M.afternoon,
    evening   = M.evening,
    night     = M.night,
}

-- Pick the mood corresponding to the current wall-clock hour.
function M.byClock(now)
    local h
    if type(now) == "table" and now.hour then
        h = now.hour
    else
        h = (os.date("*t") or {hour = 12}).hour
    end
    if     h >= 5  and h < 8  then return M.sunrise
    elseif h >= 8  and h < 16 then return M.noon
    elseif h >= 16 and h < 19 then return M.afternoon
    elseif h >= 19 and h < 21 then return M.evening
    else                           return M.night end
end

-- Pick mood from user settings. `weatherOn = true` follows the clock.
-- Otherwise uses the chosen `moodId` (defaults to classic).
function M.choose(settings)
    if settings and settings.weatherOn then
        return M.byClock()
    end
    local id = (settings and settings.moodId) or "classic"
    return M.ALL[id] or M.classic
end

return M
