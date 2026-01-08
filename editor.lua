-- editor.lua (World Level Editor)
local Map = require("map")

local Editor = {}

local TILE_SIZE = 8
local GAME_WIDTH = 320
local GAME_HEIGHT = 180

-- Editor State
local camera = {
    x = 0, y = 0,
    zoom = 1
}

local tools = {
    "tile",    -- Place/erase tiles
    "room",    -- Create/select rooms
    "spawn",   -- Set spawn point
    "entity"   -- Place entities (future)
}
local currentTool = 1
local selectedRoom = nil
local isDragging = false
local dragStart = {x = 0, y = 0}

-- Tile types with colors
local tileTypes = {
    {id = 1, name = "Ground", color = {0.2, 0.8, 0.3}},      -- Green
    {id = 2, name = "Stone",  color = {0.4, 0.4, 0.5}},      -- Gray
    {id = 3, name = "Ice",    color = {0.5, 0.8, 1.0}},      -- Light blue
    {id = 4, name = "Danger", color = {0.9, 0.2, 0.2}},      -- Red (spikes)
    {id = 5, name = "Wood",   color = {0.6, 0.4, 0.2}},      -- Brown
}
local currentTileType = 1

-- Double-click detection
local lastClickTime = 0
local lastClickRoom = nil
local DOUBLE_CLICK_TIME = 0.3

-- Grid snapping
local function snapToGrid(val, gridSize)
    return math.floor(val / gridSize) * gridSize
end

-- World to screen coordinates
local function worldToScreen(wx, wy)
    local winW, winH = love.graphics.getDimensions()
    local sx = (wx - camera.x) * camera.zoom + winW/2
    local sy = (wy - camera.y) * camera.zoom + winH/2
    return sx, sy
end

-- Screen to world coordinates
local function screenToWorld(sx, sy)
    local winW, winH = love.graphics.getDimensions()
    local wx = (sx - winW/2) / camera.zoom + camera.x
    local wy = (sy - winH/2) / camera.zoom + camera.y
    return wx, wy
end

-- =============================================================================
-- LOAD
-- =============================================================================
function Editor:load()
    if #Map.rooms == 0 then
        Map.createDefaultWorld()
    end
    
    if Map.rooms[1] then
        selectedRoom = Map.rooms[1]
        camera.x = selectedRoom.x + selectedRoom.w/2
        camera.y = selectedRoom.y + selectedRoom.h/2
    end
end

-- =============================================================================
-- UPDATE
-- =============================================================================
function Editor:update(dt)
    -- Camera panning with WASD
    local panSpeed = 300 / camera.zoom
    
    if love.keyboard.isDown("a") then camera.x = camera.x - panSpeed * dt end
    if love.keyboard.isDown("d") then camera.x = camera.x + panSpeed * dt end
    if love.keyboard.isDown("w") then camera.y = camera.y - panSpeed * dt end
    if love.keyboard.isDown("s") then camera.y = camera.y + panSpeed * dt end
    
    -- Mouse handling
    local mx, my = love.mouse.getPosition()
    local wx, wy = screenToWorld(mx, my)
    
    -- Left click - place
    if love.mouse.isDown(1) then
        local tool = tools[currentTool]
        
        if tool == "tile" and selectedRoom then
            -- Place tile with selected type
            local tileX = snapToGrid(wx, TILE_SIZE)
            local tileY = snapToGrid(wy, TILE_SIZE)
            Map.setTile(tileX + 1, tileY + 1, currentTileType)
            
        elseif tool == "spawn" and selectedRoom then
            -- Set spawn point - snap to 8x8 grid
            local snapX = snapToGrid(wx - selectedRoom.x, TILE_SIZE)
            local snapY = snapToGrid(wy - selectedRoom.y, TILE_SIZE)
            -- Spawn at BOTTOM of clicked tile (where feet will be)
            -- X = center of tile, Y = bottom of tile
            selectedRoom.spawnX = snapX + TILE_SIZE/2
            selectedRoom.spawnY = snapY + TILE_SIZE  -- Bottom of tile = feet level
        end
    end
    
    -- Right click - erase
    if love.mouse.isDown(2) then
        local tool = tools[currentTool]
        
        if tool == "tile" then
            local tileX = snapToGrid(wx, TILE_SIZE)
            local tileY = snapToGrid(wy, TILE_SIZE)
            Map.setTile(tileX + 1, tileY + 1, 0)
        end
    end
    
    -- Middle click - pan
    if love.mouse.isDown(3) then
        if not isDragging then
            isDragging = true
            dragStart.x, dragStart.y = mx, my
        else
            local dx = (mx - dragStart.x) / camera.zoom
            local dy = (my - dragStart.y) / camera.zoom
            camera.x = camera.x - dx
            camera.y = camera.y - dy
            dragStart.x, dragStart.y = mx, my
        end
    else
        isDragging = false
    end
end

-- =============================================================================
-- KEYPRESSED
-- =============================================================================
function Editor:keypressed(key)
    -- Tool Selection
    if key == "1" then currentTool = 1 end -- Tile
    if key == "2" then currentTool = 2 end -- Room
    if key == "3" then currentTool = 3 end -- Spawn
    if key == "4" then currentTool = 4 end -- Entity
    
    -- Tile type selection (Q/E to cycle)
    if key == "q" then
        currentTileType = currentTileType - 1
        if currentTileType < 1 then currentTileType = #tileTypes end
    end
    if key == "e" then
        currentTileType = currentTileType + 1
        if currentTileType > #tileTypes then currentTileType = 1 end
    end
    
    -- Create new room
    if key == "n" then
        local mx, my = love.mouse.getPosition()
        local wx, wy = screenToWorld(mx, my)
        wx = snapToGrid(wx, GAME_WIDTH)
        wy = snapToGrid(wy, GAME_HEIGHT)
        
        -- Check if room already exists at this position
        local existing = Map.getRoomAt(wx + 1, wy + 1)
        if not existing then
            local newRoom = Map.addRoom(wx, wy, GAME_WIDTH, GAME_HEIGHT)
            newRoom.name = "Room " .. #Map.rooms
            selectedRoom = newRoom
        end
    end
    
    -- Delete selected room
    if key == "delete" and selectedRoom then
        Map.removeRoom(selectedRoom)
        selectedRoom = Map.rooms[1]
    end
    
    -- Select room at mouse
    if key == "r" then
        local mx, my = love.mouse.getPosition()
        local wx, wy = screenToWorld(mx, my)
        local room = Map.getRoomAt(wx, wy)
        if room then
            selectedRoom = room
        end
    end
    
    -- Save
    if key == "f5" then
        Map.save("world.lua")
    end
    
    -- Load
    if key == "f9" then
        Map.load("world.lua")
        selectedRoom = Map.rooms[1]
    end
    
    -- Room order controls (for forward/backward detection)
    if key == "[" and selectedRoom then
        selectedRoom.order = (selectedRoom.order or 1) - 1
        if selectedRoom.order < 1 then selectedRoom.order = 1 end
    end
    if key == "]" and selectedRoom then
        selectedRoom.order = (selectedRoom.order or 1) + 1
    end
    
    -- Zoom
    if key == "=" or key == "kp+" then
        camera.zoom = math.min(camera.zoom * 1.5, 4)
    end
    if key == "-" or key == "kp-" then
        camera.zoom = math.max(camera.zoom / 1.5, 0.25)
    end
    if key == "0" then
        camera.zoom = 1
    end
    
    -- Navigate rooms
    if key == "pageup" then
        for i, room in ipairs(Map.rooms) do
            if room == selectedRoom and i > 1 then
                selectedRoom = Map.rooms[i - 1]
                camera.x = selectedRoom.x + selectedRoom.w/2
                camera.y = selectedRoom.y + selectedRoom.h/2
                break
            end
        end
    end
    if key == "pagedown" then
        for i, room in ipairs(Map.rooms) do
            if room == selectedRoom and i < #Map.rooms then
                selectedRoom = Map.rooms[i + 1]
                camera.x = selectedRoom.x + selectedRoom.w/2
                camera.y = selectedRoom.y + selectedRoom.h/2
                break
            end
        end
    end
end

function Editor:wheelmoved(x, y)
    if y > 0 then
        camera.zoom = math.min(camera.zoom * 1.2, 4)
    elseif y < 0 then
        camera.zoom = math.max(camera.zoom / 1.2, 0.25)
    end
end

function Editor:mousepressed(x, y, button)
    if button == 1 then  -- Left click
        local wx, wy = screenToWorld(x, y)
        local clickedRoom = Map.getRoomAt(wx, wy)
        
        if clickedRoom then
            local currentTime = love.timer.getTime()
            
            -- Check for double-click on same room
            if clickedRoom == lastClickRoom and (currentTime - lastClickTime) < DOUBLE_CLICK_TIME then
                -- Double-click: select this room
                selectedRoom = clickedRoom
                -- Center camera on room
                camera.x = selectedRoom.x + selectedRoom.w/2
                camera.y = selectedRoom.y + selectedRoom.h/2
            end
            
            lastClickTime = currentTime
            lastClickRoom = clickedRoom
        end
    end
end

-- =============================================================================
-- DRAW
-- =============================================================================
function Editor:draw()
    local winW, winH = love.graphics.getDimensions()
    
    -- Background
    love.graphics.clear(0.15, 0.15, 0.2, 1)
    
    -- Draw grid
    love.graphics.push()
    love.graphics.translate(winW/2, winH/2)
    love.graphics.scale(camera.zoom, camera.zoom)
    love.graphics.translate(-camera.x, -camera.y)
    
    self:drawGrid()
    self:drawRooms()
    self:drawCursor()
    
    love.graphics.pop()
    
    -- Draw UI
    self:drawUI()
end

function Editor:drawGrid()
    -- Draw world grid
    love.graphics.setColor(0.2, 0.2, 0.25, 0.5)
    
    local startX = snapToGrid(camera.x - 500/camera.zoom, GAME_WIDTH)
    local startY = snapToGrid(camera.y - 400/camera.zoom, GAME_HEIGHT)
    local endX = camera.x + 500/camera.zoom
    local endY = camera.y + 400/camera.zoom
    
    for x = startX, endX, GAME_WIDTH do
        love.graphics.line(x, startY, x, endY)
    end
    for y = startY, endY, GAME_HEIGHT do
        love.graphics.line(startX, y, endX, y)
    end
    
    -- Origin marker
    love.graphics.setColor(1, 0, 0, 0.8)
    love.graphics.line(-10, 0, 10, 0)
    love.graphics.setColor(0, 1, 0, 0.8)
    love.graphics.line(0, -10, 0, 10)
end

function Editor:drawRooms()
    for _, room in ipairs(Map.rooms) do
        local isSelected = (room == selectedRoom)
        
        -- Room background
        if isSelected then
            love.graphics.setColor(0.2, 0.25, 0.3, 1)
        else
            love.graphics.setColor(0.15, 0.15, 0.2, 1)
        end
        love.graphics.rectangle("fill", room.x, room.y, room.w, room.h)
        
        -- Draw tiles
        local cols = #room.tiles[1] or 0
        local rows = #room.tiles or 0
        
        for row = 1, rows do
            for col = 1, cols do
                local tileValue = room.tiles[row] and room.tiles[row][col]
                if tileValue and tileValue > 0 then
                    local x = room.x + (col - 1) * TILE_SIZE
                    local y = room.y + (row - 1) * TILE_SIZE
                    -- Get color from tile type
                    local tileType = tileTypes[tileValue] or tileTypes[1]
                    love.graphics.setColor(tileType.color[1], tileType.color[2], tileType.color[3])
                    love.graphics.rectangle("fill", x, y, TILE_SIZE, TILE_SIZE)
                end
            end
        end
        
        -- Room border
        if isSelected then
            love.graphics.setColor(1, 1, 0, 1)
            love.graphics.setLineWidth(2/camera.zoom)
        else
            love.graphics.setColor(0.5, 0.5, 0.6, 1)
            love.graphics.setLineWidth(1/camera.zoom)
        end
        love.graphics.rectangle("line", room.x, room.y, room.w, room.h)
        love.graphics.setLineWidth(1)
        
        -- Spawn point - show where player will stand
        local sx = room.x + room.spawnX  -- Feet X (center)
        local sy = room.y + room.spawnY  -- Feet Y (bottom)
        
        -- Draw player-sized rectangle (body above feet)
        local playerW, playerH = 8, 8
        local drawX = sx - playerW/2
        local drawY = sy - playerH  -- Body above feet
        
        -- Cyan color for spawn indicator
        love.graphics.setColor(0.3, 0.8, 1.0, 0.8)
        love.graphics.rectangle("fill", drawX, drawY, playerW, playerH)
        
        -- Draw border
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("line", drawX, drawY, playerW, playerH)
        
        -- Draw feet line (magenta)
        love.graphics.setColor(1, 0.3, 1, 1)
        love.graphics.line(sx - 4, sy, sx + 4, sy)
        
        -- Room name
        love.graphics.setColor(1, 1, 1, 0.7)
        love.graphics.print(room.name, room.x + 4, room.y + 4)
    end
end

function Editor:drawCursor()
    local mx, my = love.mouse.getPosition()
    local wx, wy = screenToWorld(mx, my)
    
    local tool = tools[currentTool]
    
    if tool == "tile" then
        local tileX = snapToGrid(wx, TILE_SIZE)
        local tileY = snapToGrid(wy, TILE_SIZE)
        -- Show preview with current tile color
        local tileType = tileTypes[currentTileType]
        love.graphics.setColor(tileType.color[1], tileType.color[2], tileType.color[3], 0.6)
        love.graphics.rectangle("fill", tileX, tileY, TILE_SIZE, TILE_SIZE)
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.rectangle("line", tileX, tileY, TILE_SIZE, TILE_SIZE)
        
    elseif tool == "room" then
        local roomX = snapToGrid(wx, GAME_WIDTH)
        local roomY = snapToGrid(wy, GAME_HEIGHT)
        love.graphics.setColor(0, 1, 1, 0.3)
        love.graphics.rectangle("fill", roomX, roomY, GAME_WIDTH, GAME_HEIGHT)
        love.graphics.setColor(0, 1, 1, 1)
        love.graphics.rectangle("line", roomX, roomY, GAME_WIDTH, GAME_HEIGHT)
        
    elseif tool == "spawn" then
        -- Show spawn preview snapped to grid
        local room = Map.getRoomAt(wx, wy)
        if room then
            local snapX = snapToGrid(wx - room.x, TILE_SIZE) + room.x + TILE_SIZE/2
            local snapY = snapToGrid(wy - room.y, TILE_SIZE) + room.y + TILE_SIZE  -- Bottom of tile
            
            -- Ghost player indicator (feet at snapY, body above)
            local playerW, playerH = 8, 8
            local drawX = snapX - playerW/2
            local drawY = snapY - playerH  -- Player body above feet position
            
            -- Cyan preview
            love.graphics.setColor(0.3, 0.8, 1.0, 0.5)
            love.graphics.rectangle("fill", drawX, drawY, playerW, playerH)
            love.graphics.setColor(1, 1, 1, 0.8)
            love.graphics.rectangle("line", drawX, drawY, playerW, playerH)
            
            -- Feet marker (magenta)
            love.graphics.setColor(1, 0.3, 1, 0.8)
            love.graphics.line(snapX - 4, snapY, snapX + 4, snapY)
        else
            -- No room under cursor
            love.graphics.setColor(1, 0.3, 0.3, 0.5)
            love.graphics.circle("line", wx, wy, 6)
        end
    end
end

function Editor:drawUI()
    local winW, winH = love.graphics.getDimensions()
    
    -- Background panel
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, 200, 200)
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("LEVEL EDITOR", 10, 10)
    love.graphics.print("Tool: " .. tools[currentTool], 10, 30)
    love.graphics.print("Rooms: " .. #Map.rooms, 10, 50)
    
    if selectedRoom then
        love.graphics.print("Selected: " .. selectedRoom.name, 10, 70)
        love.graphics.print(string.format("Pos: %d, %d  Order: %d", selectedRoom.x, selectedRoom.y, selectedRoom.order or 0), 10, 90)
    end
    
    love.graphics.print("Zoom: " .. string.format("%.1fx", camera.zoom), 10, 110)
    
    -- Tile palette
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Tile: " .. tileTypes[currentTileType].name, 10, 130)
    
    -- Draw tile palette swatches
    for i, tile in ipairs(tileTypes) do
        local px = 10 + (i-1) * 20
        local py = 148
        
        -- Swatch background
        love.graphics.setColor(tile.color[1], tile.color[2], tile.color[3])
        love.graphics.rectangle("fill", px, py, 16, 16)
        
        -- Selection indicator
        if i == currentTileType then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.rectangle("line", px-1, py-1, 18, 18)
        end
    end
    
    -- Controls help
    love.graphics.setColor(0.6, 0.6, 0.7, 1)
    love.graphics.print("1-4: Tools | Q/E: Tile Type", 10, 175)
    love.graphics.print("N: New Room | R: Select | [/]: Order", 10, 190)
    love.graphics.print("F5: Save | F9: Load", 10, 205)
    
    -- Bottom bar
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, winH - 30, winW, 30)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("TAB: Play | WASD: Pan | Scroll: Zoom | Left: Paint | Right: Erase", 10, winH - 22)
end

return Editor
