function love.conf(t)
    t.title   = "Bridge"
    -- Window / taskbar icon (also used by the fused .exe at runtime). A single
    -- high-res PNG; LÖVE downscales it for the title bar and taskbar.
    t.window.icon = "assets/Icon/Icon.png"
    -- Dev runtime is LÖVE 11.5 (current public release). When packaging the
    -- Android build, flip this to whatever love-android ships with (12.x).
    -- Keeping this in sync with the installed runtime silences the
    -- "Compatibility Warning" dialog at launch.
    t.version = "11.5"
    -- LÖVE 12 introduces a new renderer backend selector. We let LÖVE pick
    -- automatically (OpenGL on desktop, Vulkan/Metal where available, GLES on
    -- Android) by not constraining `t.graphics.renderers`.
    t.window.width     = 1280
    t.window.height    = 800
    t.window.minwidth  = 800
    t.window.minheight = 500
    t.window.resizable = true     -- the game rescales to any window size
    t.window.msaa      = 4
    t.window.highdpi   = true
end
