-- conf.lua
function love.conf(t)
    t.identity = "celeste_engine"
    t.version = "11.4"

    t.window.title = "Celeste Engine"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
    t.window.minwidth = 320
    t.window.minheight = 180
    -- VSync setting: will be controlled by settings menu
    -- Default to ON (vsync = 1) like Celeste
    -- Game runs at locked 60 FPS regardless of vsync setting
    t.window.vsync = 1
    t.window.highdpi = true

    t.modules.physics = false
    t.modules.touch = false
    t.modules.joystick = true
    t.modules.video = false
end