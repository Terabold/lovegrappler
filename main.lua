-- main.lua
-- Celeste-Accurate Fixed Timestep Engine
-- Physics: Fixed 60 FPS (deterministic)
-- Rendering: Free (no forced sleeping)

local Input = require("input")
local Game = require("game")
local Editor = require("editor")
local Map = require("map")
local UI = require("ui")

-- =============================================================================
-- FIXED TIMESTEP (Gaffer on Games pattern - same as Celeste)
-- =============================================================================
local FIXED_DT = 1 / 60  -- Physics tick rate: 60 FPS
local MAX_FRAME_TIME = 0.25  -- Safety cap to prevent spiral of death
local accumulator = 0

-- Game canvas dimensions (Celeste-style 320x180)
local GAME_WIDTH = 320
local GAME_HEIGHT = 180

-- App state machine
local appState = "menu"         -- "menu", "play", "editor"

-- =============================================================================
-- LOVE CALLBACKS
-- =============================================================================

function love.load()
    -- Pixel-perfect rendering
    love.graphics.setDefaultFilter("nearest", "nearest")

    -- Load settings first
    if UI.loadSettings then UI:loadSettings() end
    if UI.applySettings then UI:applySettings() end

    -- Initialize game and editor
    Game:load()
    Editor:load()
end

function love.update(dt)
    -- Cap dt to prevent spiral of death after long pauses
    if dt > MAX_FRAME_TIME then
        dt = MAX_FRAME_TIME
    end

    -- Always update input first
    Input:update(dt)

    if appState == "play" then
        -- FIXED TIMESTEP ACCUMULATOR
        -- Physics run at locked 60 FPS regardless of rendering FPS
        accumulator = accumulator + dt

        while accumulator >= FIXED_DT do
            Game:update(FIXED_DT)
            accumulator = accumulator - FIXED_DT
        end

    elseif appState == "editor" then
        -- Editor runs at variable timestep
        Editor:update(dt)
    end
end

function love.draw()
    local winW, winH = love.graphics.getDimensions()
    love.graphics.clear(0, 0, 0, 1)

    if appState == "play" then
        -- Alpha represents how far we are between physics steps (0.0 to 1.0)
        -- At 60 FPS this will be ~0, at higher FPS it interpolates
        local alpha = accumulator / FIXED_DT
        local canvas = Game:draw(alpha)

        -- Calculate integer scale for pixel-perfect rendering
        local scaleX = winW / GAME_WIDTH
        local scaleY = winH / GAME_HEIGHT
        local scale = math.floor(math.min(scaleX, scaleY))
        if scale < 1 then scale = 1 end

        -- Center the game canvas
        local drawW = GAME_WIDTH * scale
        local drawH = GAME_HEIGHT * scale
        local dx = math.floor((winW - drawW) / 2)
        local dy = math.floor((winH - drawH) / 2)

        -- Draw the game canvas
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(canvas, dx, dy, 0, scale, scale)

        -- HUD overlay
        love.graphics.setColor(1, 1, 1, 0.8)
        if UI.config.showFPS then
            love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 10)
        end

        local room = Map.currentRoom
        if room then
            love.graphics.print("Room: " .. room.name, 10, 25)
        end

        -- Debug info
        local player = Game.player or {}
        local camData = Game.camera or {}
        love.graphics.setColor(0, 1, 1, 1)
        love.graphics.print(string.format("Pos: %d,%d  Vel: %.2f,%.2f",
            player.x or 0, player.y or 0, player.vx or 0, player.vy or 0), 10, 40)
        love.graphics.print(string.format("Rem: %.3f,%.3f  Cam: %d,%d",
            player.xRemainder or 0, player.yRemainder or 0,
            camData.x or 0, camData.y or 0), 10, 55)

        -- State indicators
        local stateStr = ""
        if player.crouching then stateStr = stateStr .. "[CROUCH] " end
        if player.grabbing then stateStr = stateStr .. "[GRAB] " end
        if player.grounded then stateStr = stateStr .. "[GROUND] " end
        if player.onWall and player.onWall ~= 0 then
            stateStr = stateStr .. "[WALL:" .. (player.onWall == -1 and "L" or "R") .. "] "
        end
        love.graphics.print(string.format("State: %s  Stamina: %.1f/%.1f",
            stateStr, player.stamina or 0, player.maxStamina or 0), 10, 70)

        love.graphics.setColor(0.6, 0.6, 0.7, 1)
        love.graphics.print("C/Ctrl: Grab | Down: Crouch | TAB: Editor | ESC: Menu", 10, winH - 20)

    elseif appState == "editor" then
        Editor:draw()

    elseif appState == "menu" then
        UI:draw()
    end
end

function love.keypressed(key)
    -- Global mode switching
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

    -- Route input to subsystems
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
