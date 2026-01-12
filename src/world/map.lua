-- src/world/map.lua
-- Multi-Room World System

local Map = {}

-- Constants
local TILE_SIZE = 8
local SCREEN_WIDTH = 320
local SCREEN_HEIGHT = 180

Map.TILE_SIZE = TILE_SIZE
Map.SCREEN_WIDTH = SCREEN_WIDTH
Map.SCREEN_HEIGHT = SCREEN_HEIGHT

-- World State
Map.rooms = {}
Map.currentRoom = nil

-- =============================================================================
-- ROOM CREATION
-- =============================================================================
function Map.createRoom(x, y, w, h)
    w = w or SCREEN_WIDTH
    h = h or SCREEN_HEIGHT
    
    local cols = math.ceil(w / TILE_SIZE)
    local rows = math.ceil(h / TILE_SIZE)
    
    local tiles = {}
    for row = 1, rows do
        tiles[row] = {}
        for col = 1, cols do
            tiles[row][col] = 0
        end
    end
    
    return {
        x = x,
        y = y,
        w = w,
        h = h,
        tiles = tiles,
        entities = {},
        spawnX = 16,
        spawnY = h - 24,
        name = "Room",
        order = 0,
        colorIndex = 0,
        isFiller = false,
    }
end

function Map.addBorders(room)
    local cols = math.ceil(room.w / TILE_SIZE)
    local rows = math.ceil(room.h / TILE_SIZE)
    
    -- Floor
    for col = 1, cols do
        room.tiles[rows][col] = 1
    end
    
    -- Walls
    for row = 1, rows do
        room.tiles[row][1] = 1
        room.tiles[row][cols] = 1
    end
end

function Map.addRoom(x, y, w, h)
    local room = Map.createRoom(x, y, w, h)
    Map.addBorders(room)
    room.order = #Map.rooms + 1
    table.insert(Map.rooms, room)
    return room
end

function Map.removeRoom(room)
    for i, r in ipairs(Map.rooms) do
        if r == room then
            table.remove(Map.rooms, i)
            if Map.currentRoom == room then
                Map.currentRoom = Map.rooms[1]
            end
            return true
        end
    end
    return false
end

-- =============================================================================
-- ROOM QUERIES
-- =============================================================================
function Map.getRoomAt(worldX, worldY)
    for _, room in ipairs(Map.rooms) do
        if worldX >= room.x and worldX < room.x + room.w and
           worldY >= room.y and worldY < room.y + room.h then
            return room
        end
    end
    return nil
end

-- =============================================================================
-- TILE OPERATIONS
-- =============================================================================
function Map.getTile(worldX, worldY)
    local room = Map.getRoomAt(worldX, worldY)
    if not room then return -1 end
    if room.isFiller then return -1 end
    
    local localX = worldX - room.x
    local localY = worldY - room.y
    
    local col = math.floor(localX / TILE_SIZE) + 1
    local row = math.floor(localY / TILE_SIZE) + 1
    
    if row < 1 or col < 1 then return -1 end
    if not room.tiles[row] then return -1 end
    
    return room.tiles[row][col] or 0
end

function Map.isSolid(worldX, worldY)
    local tile = Map.getTile(worldX, worldY)
    if tile == -1 then return true end
    return tile > 0
end

function Map.checkSolid(x, y, w, h)
    local step = TILE_SIZE - 1
    
    for checkY = y, y + h - 1, step do
        for checkX = x, x + w - 1, step do
            if Map.isSolid(checkX, checkY) then
                return true
            end
        end
        if Map.isSolid(x + w - 1, checkY) then
            return true
        end
    end
    
    for checkX = x, x + w - 1, step do
        if Map.isSolid(checkX, y + h - 1) then
            return true
        end
    end
    
    if Map.isSolid(x + w - 1, y + h - 1) then
        return true
    end
    
    return false
end

function Map.setTile(worldX, worldY, value)
    local room = Map.getRoomAt(worldX, worldY)
    if not room then return false end
    if room.isFiller then return false end
    
    local localX = worldX - room.x
    local localY = worldY - room.y
    
    local col = math.floor(localX / TILE_SIZE) + 1
    local row = math.floor(localY / TILE_SIZE) + 1
    
    if room.tiles[row] and room.tiles[row][col] ~= nil then
        room.tiles[row][col] = value
        return true
    end
    return false
end

-- =============================================================================
-- ENTITY MANAGEMENT
-- =============================================================================
function Map.addEntity(room, entityType, localX, localY, data)
    local entity = {
        type = entityType,
        x = localX,
        y = localY,
        data = data or {}
    }
    table.insert(room.entities, entity)
    return entity
end

-- =============================================================================
-- SERIALIZATION
-- =============================================================================
local function serialize(t, indent)
    indent = indent or ""
    local lines = {"{"}
    local nextIndent = indent .. "  "
    
    for k, v in pairs(t) do
        local key = type(k) == "number" and "[" .. k .. "]" or '["' .. tostring(k) .. '"]'
        local val
        
        if type(v) == "table" then
            val = serialize(v, nextIndent)
        elseif type(v) == "string" then
            val = '"' .. v .. '"'
        elseif type(v) == "boolean" then
            val = v and "true" or "false"
        else
            val = tostring(v)
        end
        
        table.insert(lines, nextIndent .. key .. " = " .. val .. ",")
    end
    
    table.insert(lines, indent .. "}")
    return table.concat(lines, "\n")
end

function Map.save(filename)
    local data = { version = 1, rooms = {} }
    
    for _, room in ipairs(Map.rooms) do
        table.insert(data.rooms, {
            x = room.x, y = room.y,
            w = room.w, h = room.h,
            tiles = room.tiles,
            entities = room.entities,
            spawnX = room.spawnX,
            spawnY = room.spawnY,
            name = room.name,
            order = room.order,
            colorIndex = room.colorIndex or 0,
            isFiller = room.isFiller or false,
        })
    end
    
    love.filesystem.write(filename, "return " .. serialize(data))
    print("Saved: " .. filename)
    return true
end

function Map.load(filename)
    if not love.filesystem.getInfo(filename) then
        return false
    end
    
    local chunk = love.filesystem.load(filename)
    if not chunk then return false end
    
    local data = chunk()
    Map.rooms = {}
    
    for _, rd in ipairs(data.rooms) do
        local room = Map.createRoom(rd.x, rd.y, rd.w, rd.h)
        room.tiles = rd.tiles or room.tiles
        room.entities = rd.entities or {}
        room.spawnX = rd.spawnX or 16
        room.spawnY = rd.spawnY or room.h - 24
        room.name = rd.name or "Room"
        room.order = rd.order or #Map.rooms + 1
        room.colorIndex = rd.colorIndex or 0
        room.isFiller = rd.isFiller or false
        
        if room.tiles and #room.tiles > 0 then
            local rows = #room.tiles
            local cols = room.tiles[1] and #room.tiles[1] or 0
            room.h = rows * TILE_SIZE
            room.w = cols * TILE_SIZE
        end
        
        table.insert(Map.rooms, room)
    end
    
    print("Loaded: " .. filename .. " (" .. #Map.rooms .. " rooms)")
    return true
end

-- =============================================================================
-- DEFAULT WORLD
-- =============================================================================
function Map.createDefaultWorld()
    Map.rooms = {}
    
    -- Room 1: Starting room
    local room1 = Map.addRoom(0, 0, 320, 180)
    room1.name = "Start"
    room1.spawnX = 40
    room1.spawnY = 150
    room1.order = 1
    
    -- Add platforms
    for col = 8, 18 do
        room1.tiles[17][col] = 1
    end
    for col = 22, 32 do
        room1.tiles[14][col] = 1
    end
    
    -- Remove right wall for exit
    for row = 15, 22 do
        room1.tiles[row][40] = 0
    end
    
    -- Room 2: Right of room 1
    local room2 = Map.addRoom(320, 0, 320, 180)
    room2.name = "Room 2"
    room2.spawnX = 16
    room2.spawnY = 150
    room2.order = 2
    room2.colorIndex = 1
    
    -- Remove left wall for entry
    for row = 15, 22 do
        room2.tiles[row][1] = 0
    end
    
    -- Add platforms
    for col = 5, 15 do
        room2.tiles[18][col] = 1
    end
    for col = 25, 35 do
        room2.tiles[15][col] = 1
    end
    
    -- Room 3: Above room 1 (small room test)
    local room3 = Map.addRoom(0, -180, 160, 90)  -- Half-size room
    room3.name = "Small Room"
    room3.spawnX = 80
    room3.spawnY = 70
    room3.order = 3
    room3.colorIndex = 2
    
    -- Remove floor section for entry from below
    local cols3 = math.ceil(room3.w / TILE_SIZE)
    local rows3 = math.ceil(room3.h / TILE_SIZE)
    for col = 8, 12 do
        if room3.tiles[rows3] then
            room3.tiles[rows3][col] = 0
        end
    end
    
    -- Remove ceiling section in room1 for exit upward
    for col = 18, 22 do
        room1.tiles[1][col] = 0
    end
    
    Map.currentRoom = room1
    return room1
end

return Map
