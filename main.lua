-- main.lua
-- Clean Celeste-Style Engine with proper frame timing

-- Add src folder to require path
love.filesystem.setRequirePath("src/?.lua;src/?/init.lua;" .. love.filesystem.getRequirePath())

local Input = require("core.input")
local Game = require("core.game")
local Editor = require("editor.editor")
local UI = require("ui.menu")

-- Constants
local GAME_WIDTH = 320
local GAME_HEIGHT = 180
local TARGET_FPS = 60
local FIXED_DT = 1 / TARGET_FPS

-- Frame timing (proper accumulator method)
local accumulator = 0
local MAX_FRAME_TIME = 0.25  -- Prevent spiral of death

-- State
local appState = "menu"  -- "menu", "play", "editor"

function love.load(arg)
    love.graphics.setDefaultFilter("nearest", "nearest")
    
    -- Load UI settings first
    if UI.loadSettings then UI:loadSettings() end
    if UI.applySettings then UI:applySettings() end
    
    Game:load()
    Editor:load()
end

function love.update(dt)
    -- Cap dt to prevent spiral of death
    dt = math.min(dt, MAX_FRAME_TIME)
    
    -- Accumulate time
    accumulator = accumulator + dt
    
    -- Run fixed timestep updates
    while accumulator >= FIXED_DT do
        Input:update(FIXED_DT)
        
        if appState == "play" then
            Game:update(FIXED_DT)
        elseif appState == "editor" then
            Editor:update(FIXED_DT)
        end
        
        accumulator = accumulator - FIXED_DT
    end
    
    -- No interpolation needed - we use integer positions (Celeste-style)
end

function love.draw()
    local winW, winH = love.graphics.getDimensions()
    love.graphics.clear(0, 0, 0, 1)
    
    if appState == "play" then
        -- Get game canvas with interpolation
        local canvas = Game:draw()
        
        -- Integer scaling
        local scaleX = winW / GAME_WIDTH
        local scaleY = winH / GAME_HEIGHT
        local scale = math.floor(math.min(scaleX, scaleY))
        if scale < 1 then scale = 1 end
        
        local drawW = GAME_WIDTH * scale
        local drawH = GAME_HEIGHT * scale
        local dx = math.floor((winW - drawW) / 2)
        local dy = math.floor((winH - drawH) / 2)
        
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(canvas, dx, dy, 0, scale, scale)
        
        -- Draw transition overlay (fade effect)
        Game:drawTransition(dx, dy, drawW, drawH)
        
        -- HUD
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 10)
        
        local room = Game:getCurrentRoom()
        if room then
            love.graphics.print("Room: " .. room.name, 10, 25)
        end
        
        local p = Game:getPlayerState()
        love.graphics.setColor(0, 1, 1, 1)
        love.graphics.print(string.format("Pos: %d,%d  Vel: %.1f,%.1f", 
            p.x or 0, p.y or 0, p.speedX or 0, p.speedY or 0), 10, 40)
        
        love.graphics.setColor(0.6, 0.6, 0.7, 1)
        love.graphics.print("C/Ctrl: Grab | Down: Crouch | TAB: Editor | ESC: Menu", 10, winH - 20)
        
    elseif appState == "editor" then
        Editor:draw()
        
    elseif appState == "menu" then
        UI:draw()
    end
end

function love.keypressed(key)
    if key == "tab" then
        if appState == "play" then
            appState = "editor"
        elseif appState == "editor" then
            appState = "play"
            Game:load()
        end
        return
    end
    
    if key == "escape" then
        if appState == "play" or appState == "editor" then
            appState = "menu"
        else
            love.event.quit()
        end
        return
    end
    
    Input:keypressed(key)
    
    if appState == "menu" then
        local result = UI:keypressed(key)
        if result == "play" then
            appState = "play"
            Game:reset()
        elseif result == "editor" then
            appState = "editor"
        end
    elseif appState == "editor" then
        Editor:keypressed(key)
    end
end

function love.wheelmoved(x, y)
    if appState == "editor" then
        Editor:wheelmoved(x, y)
    end
end

function love.mousepressed(x, y, button)
    if appState == "editor" then
        Editor:mousepressed(x, y, button)
    end
end
