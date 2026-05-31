function love.conf(t)
    t.title   = "Bridge"
    -- Target LÖVE 12. The 12.x line is required for the Android build path
    -- (love-android Gradle project) and for the SDF-based default font.
    t.version = "12.0"
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
