-- main.lua (World of Rooms Architecture)
local Input = require("input")
local Game = require("game")
local Editor = require("editor")
local Map = require("map")
local UI = require("ui")

-- Fixed timestep
local TICK_RATE = 1/60
local accumulator = 0

-- App state: "menu", "play", "editor"
local appState = "menu"

-- Game canvas dimensions
local GAME_WIDTH = 320
local GAME_HEIGHT = 180
local BLEED = 2

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    
    -- Load settings
    if UI.loadSettings then UI:loadSettings() end
    if UI.applySettings then UI:applySettings() end
    
    -- Load game and editor
    Game:load()
    Editor:load()
end

function love.update(dt)
    if dt > 0.25 then dt = 0.25 end
    
    Input:update(dt)
    
    if appState == "play" then
        accumulator = accumulator + dt
        while accumulator >= TICK_RATE do
            Game:update(TICK_RATE)
            accumulator = accumulator - TICK_RATE
        end
        
    elseif appState == "editor" then
        Editor:update(dt)
    end
end

function love.draw()
    local winW, winH = love.graphics.getDimensions()
    
    love.graphics.clear(0, 0, 0, 1)
    
    if appState == "play" then
        local alpha = accumulator / TICK_RATE
        local canvas, fracX, fracY = Game:draw(alpha)
        
        -- Integer scale for pixel-perfect rendering
        local scaleX = winW / GAME_WIDTH
        local scaleY = winH / GAME_HEIGHT
        local scale = math.floor(math.min(scaleX, scaleY))
        if scale < 1 then scale = 1 end
        
        local drawW = GAME_WIDTH * scale
        local drawH = GAME_HEIGHT * scale
        local dx = math.floor((winW - drawW) / 2)
        local dy = math.floor((winH - drawH) / 2)
        
        -- Bleed area technique
        local quadX = BLEED + fracX
        local quadY = BLEED + fracY
        local quad = love.graphics.newQuad(
            quadX, quadY,
            GAME_WIDTH, GAME_HEIGHT,
            GAME_WIDTH + BLEED * 2, GAME_HEIGHT + BLEED * 2
        )
        
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(canvas, quad, dx, dy, 0, scale, scale)
        
        -- HUD
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 10)
        
        local room = Map.currentRoom
        if room then
            love.graphics.print("Room: " .. room.name, 10, 25)
        end
        
        love.graphics.setColor(0.6, 0.6, 0.7, 1)
        love.graphics.print("TAB: Editor | ESC: Menu", 10, winH - 20)
        
    elseif appState == "editor" then
        Editor:draw()
        
    elseif appState == "menu" then
        UI:draw()
    end
end

function love.keypressed(key)
    -- Global controls
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
    
    -- Route input
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

function love.resize(w, h)
    -- Handled dynamically in draw
end