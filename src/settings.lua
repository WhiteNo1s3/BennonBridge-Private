-- Persistent player settings.
--
-- A tiny flat key/value store serialized as a Lua chunk in the LÖVE save
-- directory (identity "shaltiel-bridge" — see conf.lua). Saved on every
-- settings change, not just on quit: Android kills apps without firing
-- love.quit, and the file is a few hundred bytes.
--
-- Only numbers, booleans and strings are stored; nested tables (per-seat
-- difficulty) are flattened by the caller (main.lua) into diffN/diffE/diffW.

local S = {}

local FILE = "settings.lua"

-- Returns the saved table, or nil (first run / unreadable file).
function S.load()
    if not love.filesystem.getInfo(FILE) then return nil end
    local chunk = love.filesystem.load(FILE)
    if not chunk then return nil end
    local ok, t = pcall(chunk)
    if ok and type(t) == "table" then return t end
    return nil
end

function S.save(t)
    local parts = {"return {"}
    for k, v in pairs(t) do
        local tv = type(v)
        if tv == "number" or tv == "boolean" then
            parts[#parts + 1] = string.format("  [%q] = %s,", k, tostring(v))
        elseif tv == "string" then
            parts[#parts + 1] = string.format("  [%q] = %q,", k, v)
        end
    end
    parts[#parts + 1] = "}"
    love.filesystem.write(FILE, table.concat(parts, "\n"))
end

return S
