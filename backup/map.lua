-- map.lua
-- Celeste-Style Multi-Room World System
-- Rooms placed on global coordinate grid

local Map = {}

-- =============================================================================
-- CONSTANTS
-- =============================================================================
local TILE_SIZE = 8
local SCREEN_WIDTH = 320
local SCREEN_HEIGHT = 180

Map.TILE_SIZE = TILE_SIZE
Map.SCREEN_WIDTH = SCREEN_WIDTH
Map.SCREEN_HEIGHT = SCREEN_HEIGHT

-- Tile Types
Map.TILES = {
    EMPTY   = 0,
    GROUND  = 1,    -- Solid (green)
    STONE   = 2,    -- Solid (gray)
    ICE     = 3,    -- Solid (light blue)
    DANGER  = 4,    -- Spikes (red) - NOT solid, but deadly
    WOOD    = 5,    -- Solid (brown)
}

-- Which tiles block movement
Map.SOLID_TILES = {
    [Map.TILES.GROUND] = true,
    [Map.TILES.STONE]  = true,
    [Map.TILES.ICE]    = true,
    [Map.TILES.WOOD]   = true,
}

-- =============================================================================
-- WORLD STATE
-- =============================================================================
Map.rooms = {}
Map.currentRoom = nil

-- =============================================================================
-- ROOM CREATION
-- =============================================================================

--- Create a new room
---@param x number World X position
---@param y number World Y position
---@param w number? Width (default SCREEN_WIDTH)
---@param h number? Height (default SCREEN_HEIGHT)
---@return table room
function Map.createRoom(x, y, w, h)
    w = w or SCREEN_WIDTH
    h = h or SCREEN_HEIGHT
    
    local cols = math.ceil(w / TILE_SIZE)
    local rows = math.ceil(h / TILE_SIZE)
    
    -- Initialize empty tile grid
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
        entities = {},      -- Spikes, enemies, etc.
        spawnX = 16,        -- Relative to room origin
        spawnY = h - 24,    -- Near floor by default
        name = "Room",
        order = 0,
    }
end

--- Add floor and walls to a room
function Map.addBorders(room)
    local cols = math.ceil(room.w / TILE_SIZE)
    local rows = math.ceil(room.h / TILE_SIZE)
    
    -- Floor
    for col = 1, cols do
        room.tiles[rows][col] = Map.TILES.GROUND
    end
    
    -- Left/Right walls
    for row = 1, rows do
        room.tiles[row][1] = Map.TILES.GROUND
        room.tiles[row][cols] = Map.TILES.GROUND
    end
end

--- Add a room to the world
function Map.addRoom(x, y, w, h)
    local room = Map.createRoom(x, y, w, h)
    Map.addBorders(room)
    room.order = #Map.rooms + 1
    table.insert(Map.rooms, room)
    return room
end

-- =============================================================================
-- ROOM QUERIES
-- =============================================================================

--- Get room containing a world position
function Map.getRoomAt(worldX, worldY)
    for _, room in ipairs(Map.rooms) do
        if worldX >= room.x and worldX < room.x + room.w and
           worldY >= room.y and worldY < room.y + room.h then
            return room
        end
    end
    return nil
end

--- Get neighboring room when crossing boundary
function Map.getNeighborRoom(currentRoom, worldX, worldY)
    for _, room in ipairs(Map.rooms) do
        if room ~= currentRoom then
            if worldX >= room.x and worldX < room.x + room.w and
               worldY >= room.y and worldY < room.y + room.h then
                return room
            end
        end
    end
    return nil
end

-- =============================================================================
-- TILE OPERATIONS
-- =============================================================================

--- Get tile at world position
function Map.getTile(worldX, worldY)
    local room = Map.getRoomAt(worldX, worldY)
    if not room then return -1 end  -- Void
    
    local localX = worldX - room.x
    local localY = worldY - room.y
    
    local col = math.floor(localX / TILE_SIZE) + 1
    local row = math.floor(localY / TILE_SIZE) + 1
    
    if row < 1 or col < 1 then return -1 end
    if not room.tiles[row] then return -1 end
    
    return room.tiles[row][col] or 0
end

--- Check if world position has a solid tile
function Map.isSolid(worldX, worldY)
    local tile = Map.getTile(worldX, worldY)
    if tile == -1 then return true end  -- Void is solid
    return Map.SOLID_TILES[tile] == true
end

--- Check solid for rectangle (AABB)
function Map.checkSolid(x, y, w, h)
    -- Sample all corners and edges
    local step = TILE_SIZE - 1
    
    for checkY = y, y + h - 1, step do
        for checkX = x, x + w - 1, step do
            if Map.isSolid(checkX, checkY) then
                return true
            end
        end
        -- Check right edge
        if Map.isSolid(x + w - 1, checkY) then
            return true
        end
    end
    
    -- Check bottom edge
    for checkX = x, x + w - 1, step do
        if Map.isSolid(checkX, y + h - 1) then
            return true
        end
    end
    
    -- Check bottom-right corner
    if Map.isSolid(x + w - 1, y + h - 1) then
        return true
    end
    
    return false
end

--- Set tile at world position
function Map.setTile(worldX, worldY, value)
    local room = Map.getRoomAt(worldX, worldY)
    if not room then return false end
    
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

--- Add an entity to a room
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

--- Get all entities of a type in a room
function Map.getEntities(room, entityType)
    local result = {}
    for _, entity in ipairs(room.entities) do
        if entity.type == entityType then
            table.insert(result, entity)
        end
    end
    return result
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
        room.tiles = rd.tiles
        room.entities = rd.entities or {}
        room.spawnX = rd.spawnX or 16
        room.spawnY = rd.spawnY or room.h - 24
        room.name = rd.name or "Room"
        room.order = rd.order or #Map.rooms + 1
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
        room1.tiles[17][col] = Map.TILES.GROUND
    end
    for col = 22, 32 do
        room1.tiles[14][col] = Map.TILES.GROUND
    end
    
    -- Remove right wall section for exit
    for row = 15, 22 do
        room1.tiles[row][40] = Map.TILES.EMPTY
    end
    
    -- Add some spikes (entity-based)
    Map.addEntity(room1, "spike", 80, 169, {direction = "up"})
    Map.addEntity(room1, "spike", 88, 169, {direction = "up"})
    Map.addEntity(room1, "spike", 96, 169, {direction = "up"})
    
    -- Room 2: Right of room 1
    local room2 = Map.addRoom(320, 0, 320, 180)
    room2.name = "Room 2"
    room2.spawnX = 16
    room2.spawnY = 150
    room2.order = 2
    
    -- Remove left wall section for entry
    for row = 15, 22 do
        room2.tiles[row][1] = Map.TILES.EMPTY
    end
    
    -- Add platforms
    for col = 5, 15 do
        room2.tiles[18][col] = Map.TILES.GROUND
    end
    for col = 25, 35 do
        room2.tiles[15][col] = Map.TILES.GROUND
    end
    
    -- Room 3: Above room 1
    local room3 = Map.addRoom(0, -180, 320, 180)
    room3.name = "Room 3"
    room3.spawnX = 160
    room3.spawnY = 156
    room3.order = 3
    
    -- Remove floor section for entry from below
    for col = 18, 22 do
        room3.tiles[23][col] = Map.TILES.EMPTY
    end
    
    -- Remove ceiling section in room1 for exit upward
    for col = 18, 22 do
        room1.tiles[1][col] = Map.TILES.EMPTY
    end
    
    -- Add platforms
    for col = 10, 30 do
        room3.tiles[20][col] = Map.TILES.GROUND
    end
    
    Map.currentRoom = room1
    return room1
end

return Map
