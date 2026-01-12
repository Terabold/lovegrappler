-- src/editor/editor.lua
-- Simplified Level Editor

local Map = require("world.map")
local Input = require("core.input")

local Editor = {}

local TILE_SIZE = 8
local GAME_WIDTH = 320
local GAME_HEIGHT = 180

-- Editor State
local camera = { x = 0, y = 0, zoom = 1 }
local mouseWorld = { x = 0, y = 0 }
local lastMouse = { x = 0, y = 0 }
local isDragging = false

local tools = { "select", "tile", "spawn", "hazard" }
local currentTool = 1

local tileTypes = {
    {id = 1,  name = "Ice",       color = {0.6, 0.8, 1.0}},
    {id = 2,  name = "Stonewood", color = {0.5, 0.4, 0.3}},
    {id = 3,  name = "Pinkrockice", color = {0.8, 0.5, 0.7}},
    {id = 4,  name = "Metal",     color = {0.4, 0.4, 0.5}},
    {id = 5,  name = "Pinkrock",  color = {0.9, 0.4, 0.6}},
    {id = 6,  name = "Cyber",     color = {0.2, 0.8, 0.8}},
    {id = 7,  name = "Dirt",      color = {0.6, 0.4, 0.2}},
    {id = 8,  name = "Solidice",  color = {0.4, 0.6, 0.9}},
    {id = 9,  name = "Stone",     color = {0.5, 0.5, 0.5}},
    {id = 10, name = "Stone2",    color = {0.4, 0.4, 0.4}},
    {id = 11, name = "Stone3",    color = {0.6, 0.6, 0.6}},
}
local currentTileType = 1

local hazardTypes = {"spike_up", "spike_down", "spike_left", "spike_right"}
local currentHazard = 1

local selection = {}  -- Selected rooms

-- Coordinate conversion
local function worldToScreen(wx, wy)
    local winW, winH = love.graphics.getDimensions()
    return (wx - camera.x) * camera.zoom + winW/2,
           (wy - camera.y) * camera.zoom + winH/2
end

local function screenToWorld(sx, sy)
    local winW, winH = love.graphics.getDimensions()
    return (sx - winW/2) / camera.zoom + camera.x,
           (sy - winH/2) / camera.zoom + camera.y
end

local function snapToGrid(val)
    return math.floor(val / TILE_SIZE) * TILE_SIZE
end

function Editor:load()
    if #Map.rooms == 0 then
        Map.createDefaultWorld()
    end
    
    -- Center on first room
    if Map.rooms[1] then
        camera.x = Map.rooms[1].x + Map.rooms[1].w / 2
        camera.y = Map.rooms[1].y + Map.rooms[1].h / 2
    end
end

function Editor:update(dt)
    local mx, my = love.mouse.getPosition()
    mouseWorld.x, mouseWorld.y = screenToWorld(mx, my)
    
    -- Pan camera with middle mouse or right mouse
    if love.mouse.isDown(2) or love.mouse.isDown(3) then
        local dx = mx - lastMouse.x
        local dy = my - lastMouse.y
        camera.x = camera.x - dx / camera.zoom
        camera.y = camera.y - dy / camera.zoom
    end
    
    lastMouse.x, lastMouse.y = mx, my
    
    -- Paint tiles while holding left mouse
    if love.mouse.isDown(1) then
        local tool = tools[currentTool]
        
        if tool == "tile" then
            local tileX = snapToGrid(mouseWorld.x)
            local tileY = snapToGrid(mouseWorld.y)
            Map.setTile(tileX, tileY, currentTileType)
        end
    end
end

function Editor:keypressed(key)
    -- Tool selection
    if key == "1" then currentTool = 1
    elseif key == "2" then currentTool = 2
    elseif key == "3" then currentTool = 3
    elseif key == "4" then currentTool = 4
    end
    
    -- Tile type cycling
    if key == "q" then
        currentTileType = currentTileType - 1
        if currentTileType < 1 then currentTileType = #tileTypes end
    elseif key == "e" then
        currentTileType = currentTileType + 1
        if currentTileType > #tileTypes then currentTileType = 1 end
    end
    
    -- Hazard type cycling
    if key == "r" then
        currentHazard = currentHazard + 1
        if currentHazard > #hazardTypes then currentHazard = 1 end
    end
    
    -- New room
    if key == "n" then
        local newX = snapToGrid(mouseWorld.x)
        local newY = snapToGrid(mouseWorld.y)
        local room = Map.addRoom(newX, newY, GAME_WIDTH, GAME_HEIGHT)
        room.name = "Room " .. #Map.rooms
    end
    
    -- Delete selected rooms
    if key == "delete" then
        for _, room in ipairs(selection) do
            Map.removeRoom(room)
        end
        selection = {}
    end
    
    -- Save/Load
    if key == "f5" then
        Map.save("world.lua")
    elseif key == "f9" then
        Map.load("world.lua")
    end
end

function Editor:wheelmoved(x, y)
    local oldZoom = camera.zoom
    camera.zoom = camera.zoom * (1 + y * 0.1)
    camera.zoom = math.max(0.25, math.min(4, camera.zoom))
end

function Editor:mousepressed(x, y, button)
    local wx, wy = screenToWorld(x, y)
    local tool = tools[currentTool]
    
    if button == 1 then
        if tool == "select" then
            -- Find clicked room
            local clickedRoom = nil
            for _, room in ipairs(Map.rooms) do
                if wx >= room.x and wx < room.x + room.w and
                   wy >= room.y and wy < room.y + room.h then
                    clickedRoom = room
                    break
                end
            end
            
            if clickedRoom then
                if love.keyboard.isDown("lctrl") then
                    -- Toggle selection
                    local found = false
                    for i, r in ipairs(selection) do
                        if r == clickedRoom then
                            table.remove(selection, i)
                            found = true
                            break
                        end
                    end
                    if not found then
                        table.insert(selection, clickedRoom)
                    end
                else
                    selection = {clickedRoom}
                end
            else
                selection = {}
            end
            
        elseif tool == "spawn" then
            local room = Map.getRoomAt(wx, wy)
            if room then
                room.spawnX = wx - room.x
                room.spawnY = wy - room.y
            end
            
        elseif tool == "hazard" then
            local room = Map.getRoomAt(wx, wy)
            if room then
                local localX = math.floor((wx - room.x) / TILE_SIZE) + 1
                local localY = math.floor((wy - room.y) / TILE_SIZE) + 1
                
                -- Check if hazard already exists
                local existing = nil
                for i, h in ipairs(room.entities) do
                    if h.x == localX and h.y == localY then
                        existing = i
                        break
                    end
                end
                
                if existing then
                    table.remove(room.entities, existing)
                else
                    table.insert(room.entities, {
                        type = hazardTypes[currentHazard],
                        x = localX,
                        y = localY
                    })
                end
            end
        end
    end
end

function Editor:draw()
    local winW, winH = love.graphics.getDimensions()
    
    love.graphics.clear(0.15, 0.15, 0.2, 1)
    
    love.graphics.push()
    love.graphics.translate(winW/2, winH/2)
    love.graphics.scale(camera.zoom, camera.zoom)
    love.graphics.translate(-camera.x, -camera.y)
    
    -- Draw grid
    local gridStep = TILE_SIZE * 10
    local startX = math.floor((camera.x - winW/2/camera.zoom) / gridStep) * gridStep
    local startY = math.floor((camera.y - winH/2/camera.zoom) / gridStep) * gridStep
    local endX = camera.x + winW/2/camera.zoom
    local endY = camera.y + winH/2/camera.zoom
    
    love.graphics.setColor(0.25, 0.25, 0.3, 1)
    for x = startX, endX, gridStep do
        love.graphics.line(x, startY, x, endY)
    end
    for y = startY, endY, gridStep do
        love.graphics.line(startX, y, endX, y)
    end
    
    -- Draw rooms
    for i, room in ipairs(Map.rooms) do
        -- Background
        love.graphics.setColor(0.1, 0.1, 0.15, 1)
        love.graphics.rectangle("fill", room.x, room.y, room.w, room.h)
        
        -- Tiles
        if room.tiles then
            local rows = #room.tiles
            for row = 1, rows do
                for col = 1, (room.tiles[row] and #room.tiles[row] or 0) do
                    local tileValue = room.tiles[row][col]
                    if tileValue and tileValue > 0 then
                        local x = room.x + (col - 1) * TILE_SIZE
                        local y = room.y + (row - 1) * TILE_SIZE
                        local tileType = tileTypes[tileValue]
                        local color = tileType and tileType.color or {0.5, 0.5, 0.5}
                        love.graphics.setColor(color[1], color[2], color[3])
                        love.graphics.rectangle("fill", x, y, TILE_SIZE, TILE_SIZE)
                    end
                end
            end
        end
        
        -- Hazards
        for _, h in ipairs(room.entities or {}) do
            if h.type and h.type:find("spike") then
                local x = room.x + (h.x - 1) * TILE_SIZE
                local y = room.y + (h.y - 1) * TILE_SIZE
                love.graphics.setColor(1, 0.3, 0.3)
                
                if h.type == "spike_up" then
                    love.graphics.polygon("fill", x + 4, y + 2, x + 7, y + 7, x + 1, y + 7)
                elseif h.type == "spike_down" then
                    love.graphics.polygon("fill", x + 4, y + 6, x + 7, y + 1, x + 1, y + 1)
                elseif h.type == "spike_left" then
                    love.graphics.polygon("fill", x + 2, y + 4, x + 7, y + 1, x + 7, y + 7)
                elseif h.type == "spike_right" then
                    love.graphics.polygon("fill", x + 6, y + 4, x + 1, y + 1, x + 1, y + 7)
                end
            end
        end
        
        -- Spawn point
        local sx = room.x + (room.spawnX or 16)
        local sy = room.y + (room.spawnY or room.h - 24)
        love.graphics.setColor(0.3, 0.8, 1.0, 0.8)
        love.graphics.rectangle("fill", sx - 4, sy - 8, 8, 8)
        
        -- Border
        local isSelected = false
        for _, r in ipairs(selection) do
            if r == room then isSelected = true; break end
        end
        
        love.graphics.setLineWidth(isSelected and 3 or 1)
        if isSelected then
            love.graphics.setColor(1, 0, 0, 1)
        elseif i == 1 then
            love.graphics.setColor(0, 1, 1, 1)
        else
            love.graphics.setColor(0.3, 0.4, 0.4, 1)
        end
        love.graphics.rectangle("line", room.x, room.y, room.w, room.h)
        
        -- Room name
        love.graphics.setColor(1, 1, 1, 0.6)
        love.graphics.print(i .. ": " .. (room.name or "Room"), room.x + 4, room.y + 4)
    end
    
    love.graphics.setLineWidth(1)
    
    -- Draw cursor preview
    local tool = tools[currentTool]
    if tool == "tile" then
        local tileX = snapToGrid(mouseWorld.x)
        local tileY = snapToGrid(mouseWorld.y)
        local tileType = tileTypes[currentTileType]
        love.graphics.setColor(tileType.color[1], tileType.color[2], tileType.color[3], 0.6)
        love.graphics.rectangle("fill", tileX, tileY, TILE_SIZE, TILE_SIZE)
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.rectangle("line", tileX, tileY, TILE_SIZE, TILE_SIZE)
    elseif tool == "hazard" then
        local tileX = snapToGrid(mouseWorld.x)
        local tileY = snapToGrid(mouseWorld.y)
        love.graphics.setColor(1, 0.3, 0.3, 0.6)
        love.graphics.rectangle("fill", tileX, tileY, TILE_SIZE, TILE_SIZE)
    end
    
    love.graphics.pop()
    
    -- UI
    self:drawUI()
end

function Editor:drawUI()
    local winW, winH = love.graphics.getDimensions()
    
    -- Left panel
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", 0, 0, 200, 180)
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("MAP EDITOR", 10, 10)
    love.graphics.setColor(0.7, 0.7, 0.8, 1)
    love.graphics.print("Tool: " .. tools[currentTool], 10, 30)
    love.graphics.print(string.format("Zoom: %.1fx", camera.zoom), 10, 45)
    love.graphics.print("Rooms: " .. #Map.rooms, 10, 60)
    
    if tools[currentTool] == "tile" then
        love.graphics.setColor(tileTypes[currentTileType].color[1], 
                              tileTypes[currentTileType].color[2], 
                              tileTypes[currentTileType].color[3])
        love.graphics.print("Tile: " .. tileTypes[currentTileType].name, 10, 80)
    elseif tools[currentTool] == "hazard" then
        love.graphics.setColor(1, 0.3, 0.3)
        love.graphics.print("Hazard: " .. hazardTypes[currentHazard], 10, 80)
    end
    
    -- Selected room info
    if #selection == 1 then
        local room = selection[1]
        love.graphics.setColor(1, 1, 0, 1)
        love.graphics.print(room.name, 10, 100)
        love.graphics.setColor(0.3, 1, 0.3)
        love.graphics.print(string.format("%dx%d at (%d,%d)", 
            room.w, room.h, room.x, room.y), 10, 115)
    end
    
    -- Bottom help
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", 0, winH - 40, winW, 40)
    
    love.graphics.setColor(0.6, 0.6, 0.7, 1)
    love.graphics.print("1-4: Tools | Q/E: Cycle Tile | R: Cycle Hazard | N: New Room | Del: Delete | F5: Save | F9: Load | TAB: Play", 10, winH - 32)
    love.graphics.print("Mouse: LMB Paint | RMB/MMB Pan | Scroll Zoom", 10, winH - 16)
end

return Editor
