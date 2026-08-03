function love.conf(t)
    t.title   = "Bridge"
    -- Stable save-directory name for settings.lua, across dev runs, the
    -- fused Bridge.exe and Android (default identity follows the exe/folder
    -- name, which would scatter saves).
    t.identity = "shaltiel-bridge"
    -- Window / taskbar icon (also used by the fused .exe at runtime). A single
    -- high-res PNG; LÖVE downscales it for the title bar and taskbar.
    t.window.icon = "assets/Icon/Icon.png"
    -- Declared per-target so NEITHER build shows the "Compatibility Warning"
    -- dialog: love-android ships LÖVE 12, desktop dev + the fused exe run
    -- 11.5 (current public release). When desktop LÖVE 12 ships, collapse
    -- this to plain "12.0".
    t.version = (love._os == "Android") and "12.0" or "11.5"
    -- LÖVE 12 introduces a new renderer backend selector. We let LÖVE pick
    -- automatically (OpenGL on desktop, Vulkan/Metal where available, GLES on
    -- Android) by not constraining `t.graphics.renderers`.
    t.window.width     = 1280
    t.window.height    = 800
    t.window.minwidth  = 800
    t.window.minheight = 500
    -- Resizable on DESKTOP only (the game rescales to any window size).
    -- On Android a resizable SDL window makes SDL re-request the screen
    -- orientation at window creation and OVERRIDE the manifest's
    -- sensorLandscape — the game would open in portrait. Non-resizable +
    -- width>height makes SDL request sensor-landscape, matching the
    -- manifest. (love._os is available at conf time; verified on 11.5.)
    t.window.resizable = (love._os ~= "Android")
    t.window.msaa      = 4
    t.window.highdpi   = true
    -- Dev/CI: BRIDGE_HIDDEN=1 starts the window invisible so the layout
    -- screenshot harness (main.lua --shot) can render without flashing a
    -- window on the desktop; BRIDGE_SHOT_W/H pick the tested resolution at
    -- window-creation time (setMode can't resize without showing the
    -- window). Inert in normal play.
    if os.getenv("BRIDGE_HIDDEN") == "1" then
        t.window.visible = false
        t.window.width   = tonumber(os.getenv("BRIDGE_SHOT_W")) or t.window.width
        t.window.height  = tonumber(os.getenv("BRIDGE_SHOT_H")) or t.window.height
    end
end
