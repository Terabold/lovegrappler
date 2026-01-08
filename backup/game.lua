-- game.lua (World of Rooms + Camera Clamping + Transitions)
local Input = require("input")
local Map = require("map")

local Game = {}

local GAME_WIDTH = 320
local GAME_HEIGHT = 180
local TILE_SIZE = 8
local BLEED = 2

-- Tile colors (must match editor.lua)
local TILE_COLORS = {
    {0.2, 0.8, 0.3},  -- 1: Ground (green)
    {0.4, 0.4, 0.5},  -- 2: Stone (gray)
    {0.5, 0.8, 1.0},  -- 3: Ice (light blue)
    {0.9, 0.2, 0.2},  -- 4: Danger (red)
    {0.6, 0.4, 0.2},  -- 5: Wood (brown)
}

-- Physics Constants
local PHYSICS = {
    GRAVITY = 900,
    JUMP_FORCE = -200,
    RUN_SPEED = 90,
    WALL_SLIDE_SPEED = 40,
    MAX_FALL = 160,
    WALL_JUMP_KICK_X = 140,
    WALL_JUMP_FORCE_Y = -200,
    WALL_JUMP_TIME = 0.15,
    ACCEL = 600,
    FRICTION = 800,
    AIR_ACCEL = 400,
    AIR_FRICTION = 200,
    COYOTE_TIME = 0.1,
    VAR_JUMP_MULT = 0.5
}

-- Player State
local player = {
    x = 100, y = 100,
    xRemainder = 0, yRemainder = 0,
    renderX = 100, renderY = 100,
    prevRenderX = 100, prevRenderY = 100,
    w = 8, h = 8,
    vx = 0, vy = 0,
    grounded = false,
    onWall = 0,
    coyoteTimer = 0,
    wallJumpTimer = 0,
    dead = false
}

-- Camera State
local camera = {
    x = 0, y = 0,
    prevX = 0, prevY = 0,
    targetX = 0, targetY = 0
}

-- Transition State
local transition = {
    active = false,
    cameraPanDone = false,
    timer = 0,
    duration = 0.2,
    fromRoom = nil,
    toRoom = nil,
    startCamX = 0, startCamY = 0,
    endCamX = 0, endCamY = 0,
    direction = nil,
    targetX = 0, targetY = 0,
    startPlayerX = 0, startPlayerY = 0,
    keepVelX = 0, keepVelY = 0,
    isFirstVisit = false
}

-- Track which rooms have been visited
local visitedRooms = {}

-- Respawn Point
local respawn = {
    x = 50, y = 140,
    room = nil
}

local canvas

-- =============================================================================
-- LOAD / RESET
-- =============================================================================
function Game:load()
    canvas = love.graphics.newCanvas(GAME_WIDTH + BLEED * 2, GAME_HEIGHT + BLEED * 2)
    canvas:setFilter("nearest", "nearest")
    
    -- Load or create world
    if not Map.load("world.lua") then
        Map.createDefaultWorld()
    end
    
    -- Set initial room and spawn
    if Map.rooms[1] then
        Map.currentRoom = Map.rooms[1]
        respawn.room = Map.currentRoom
        respawn.x = Map.currentRoom.x + Map.currentRoom.spawnX
        respawn.y = Map.currentRoom.y + Map.currentRoom.spawnY
        
        -- Mark starting room as visited
        local roomKey = Map.currentRoom.x .. "_" .. Map.currentRoom.y
        visitedRooms[roomKey] = true
    end
    
    self:reset()
end

function Game:reset()
    -- Reset player to respawn point
    player.x = respawn.x - player.w/2
    player.y = respawn.y - player.h
    player.xRemainder = 0
    player.yRemainder = 0
    player.renderX = player.x
    player.renderY = player.y
    player.prevRenderX = player.x
    player.prevRenderY = player.y
    player.vx = 0
    player.vy = 0
    player.grounded = false
    player.onWall = 0
    player.dead = false
    
    -- Reset transition state
    transition.active = false
    
    -- Set camera to room
    if Map.currentRoom then
        camera.x = self:clampCameraX(player.x - GAME_WIDTH/2)
        camera.y = self:clampCameraY(player.y - GAME_HEIGHT/2)
        camera.prevX = camera.x
        camera.prevY = camera.y
    end
end

-- =============================================================================
-- CAMERA CLAMPING
-- =============================================================================
function Game:clampCameraX(camX)
    local room = Map.currentRoom
    if not room then return camX end
    local minX = room.x
    local maxX = room.x + room.w - GAME_WIDTH
    return math.max(minX, math.min(camX, maxX))
end

function Game:clampCameraY(camY)
    local room = Map.currentRoom
    if not room then return camY end
    local minY = room.y
    local maxY = room.y + room.h - GAME_HEIGHT
    return math.max(minY, math.min(camY, maxY))
end

-- =============================================================================
-- ROOM TRANSITIONS
-- =============================================================================
function Game:checkRoomTransition()
    if transition.active then return end
    
    local room = Map.currentRoom
    if not room then return end
    
    local px, py = player.x + player.w/2, player.y + player.h/2
    
    -- Determine which edge player crossed
    local direction = nil
    if px < room.x then direction = "left"
    elseif px >= room.x + room.w then direction = "right"
    elseif py < room.y then direction = "up"
    elseif py >= room.y + room.h then direction = "down"
    end
    
    if direction then
        local newRoom = Map.getNeighborRoom(room, px, py)
        
        if newRoom then
            self:startTransition(room, newRoom, direction)
        else
            -- No room there - push player back
            if direction == "left" then player.x = room.x end
            if direction == "right" then player.x = room.x + room.w - player.w - 1 end
            if direction == "up" then player.y = room.y end
            if direction == "down" then player.y = room.y + room.h - player.h - 1 end
            player.vx = 0
            player.vy = 0
        end
    end
end

function Game:startTransition(fromRoom, toRoom, direction)
    transition.active = true
    transition.cameraPanDone = false
    transition.timer = 0
    transition.fromRoom = fromRoom
    transition.toRoom = toRoom
    transition.direction = direction
    
    -- Store current positions
    transition.startCamX = camera.x
    transition.startCamY = camera.y
    transition.startPlayerX = player.x
    transition.startPlayerY = player.y
    
    -- Determine if going FORWARD (higher order) or BACKWARD (lower order)
    local fromOrder = fromRoom.order or 0
    local toOrder = toRoom.order or 0
    local isGoingForward = toOrder > fromOrder
    
    -- Small buffer to snap player inside room
    local SNAP_BUFFER = 4
    
    if isGoingForward then
        -- GOING FORWARD: Move to spawn point
        transition.targetX = toRoom.x + toRoom.spawnX - player.w/2
        transition.targetY = toRoom.y + toRoom.spawnY - player.h
        transition.keepVelX = 0
        transition.keepVelY = 0
    else
        -- GOING BACKWARD: Snap inside room with buffer
        if direction == "left" then
            transition.targetX = toRoom.x + toRoom.w - player.w - SNAP_BUFFER
            transition.targetY = player.y
        elseif direction == "right" then
            transition.targetX = toRoom.x + SNAP_BUFFER
            transition.targetY = player.y
        elseif direction == "up" then
            transition.targetX = player.x
            transition.targetY = toRoom.y + toRoom.h - player.h - SNAP_BUFFER
        elseif direction == "down" then
            transition.targetX = player.x
            transition.targetY = toRoom.y + SNAP_BUFFER
        end
        transition.keepVelX = player.vx
        transition.keepVelY = player.vy
    end
    
    -- Update respawn point to new room's spawn
    respawn.x = toRoom.x + toRoom.spawnX
    respawn.y = toRoom.y + toRoom.spawnY
    respawn.room = toRoom
    
    -- Calculate target camera position
    local targetCamX = transition.targetX - GAME_WIDTH/2 + player.w/2
    local targetCamY = transition.targetY - GAME_HEIGHT/2 + player.h/2
    
    -- Clamp to new room bounds
    Map.currentRoom = toRoom
    transition.endCamX = self:clampCameraX(targetCamX)
    transition.endCamY = self:clampCameraY(targetCamY)
    Map.currentRoom = fromRoom
end

function Game:updateTransition(dt)
    if not transition.active then return end
    
    -- Single phase: Camera pan + Player slide simultaneously
    transition.timer = transition.timer + dt
    local t = transition.timer / transition.duration
    
    -- Smooth easing
    local easeT = t < 1 and (t * t * (3 - 2 * t)) or 1
    
    -- Move camera
    camera.x = transition.startCamX + (transition.endCamX - transition.startCamX) * easeT
    camera.y = transition.startCamY + (transition.endCamY - transition.startCamY) * easeT
    camera.prevX = camera.x
    camera.prevY = camera.y
    
    -- Move player simultaneously
    player.x = transition.startPlayerX + (transition.targetX - transition.startPlayerX) * easeT
    player.y = transition.startPlayerY + (transition.targetY - transition.startPlayerY) * easeT
    player.renderX = player.x
    player.renderY = player.y
    player.prevRenderX = player.x
    player.prevRenderY = player.y
    
    if t >= 1 then
        -- Transition complete
        Map.currentRoom = transition.toRoom
        camera.x = transition.endCamX
        camera.y = transition.endCamY
        player.x = transition.targetX
        player.y = transition.targetY
        player.xRemainder = 0
        player.yRemainder = 0
        
        -- Restore momentum
        if transition.direction == "left" or transition.direction == "right" then
            player.vx = transition.keepVelX
            player.vy = transition.keepVelY
        else
            player.vx = 0
            player.vy = 0
        end
        
        player.grounded = false
        transition.active = false
        transition.cameraPanDone = false
    end
end

-- =============================================================================
-- PHYSICS
-- =============================================================================
function Game:moveX(amount)
    player.xRemainder = player.xRemainder + amount
    local move = math.floor(player.xRemainder + 0.5)
    if move ~= 0 then
        player.xRemainder = player.xRemainder - move
        local sign = move > 0 and 1 or -1
        while move ~= 0 do
            if not Map.checkSolid(player.x + sign, player.y, player.w, player.h) then
                player.x = player.x + sign
                move = move - sign
            else
                player.vx = 0
                player.xRemainder = 0
                break
            end
        end
    end
end

function Game:moveY(amount)
    player.yRemainder = player.yRemainder + amount
    local move = math.floor(player.yRemainder + 0.5)
    if move ~= 0 then
        player.yRemainder = player.yRemainder - move
        local sign = move > 0 and 1 or -1
        while move ~= 0 do
            if not Map.checkSolid(player.x, player.y + sign, player.w, player.h) then
                player.y = player.y + sign
                move = move - sign
            else
                if sign > 0 then
                    player.grounded = true
                end
                player.vy = 0
                player.yRemainder = 0
                break
            end
        end
    end
end

function Game:checkWall()
    player.onWall = 0
    if Map.checkSolid(player.x - 1, player.y, 1, player.h) then
        player.onWall = -1
        return
    end
    if Map.checkSolid(player.x + player.w, player.y, 1, player.h) then
        player.onWall = 1
    end
end

-- =============================================================================
-- UPDATE
-- =============================================================================
function Game:update(dt)
    -- Handle transition
    if transition.active then
        self:updateTransition(dt)
        return
    end
    
    -- Dead?
    if player.dead then
        self:reset()
        return
    end
    
    -- Check room transition
    self:checkRoomTransition()
    
    -- Store previous render position
    player.prevRenderX = player.renderX
    player.prevRenderY = player.renderY
    camera.prevX = camera.x
    camera.prevY = camera.y
    
    -- Ground check
    player.grounded = Map.checkSolid(player.x, player.y + player.h, player.w, 1)
    
    -- Coyote time
    if player.grounded then
        player.coyoteTimer = PHYSICS.COYOTE_TIME
    else
        player.coyoteTimer = player.coyoteTimer - dt
    end
    
    -- Wall check
    self:checkWall()
    
    -- Wall jump timer
    if player.wallJumpTimer > 0 then
        player.wallJumpTimer = player.wallJumpTimer - dt
    end
    
    -- Horizontal input
    local moveX = 0
    if Input:down("left") then moveX = -1 end
    if Input:down("right") then moveX = 1 end
    
    -- Apply acceleration/deceleration
    local accel = player.grounded and PHYSICS.ACCEL or PHYSICS.AIR_ACCEL
    local friction = player.grounded and PHYSICS.FRICTION or PHYSICS.AIR_FRICTION
    
    if player.wallJumpTimer <= 0 then
        if moveX ~= 0 then
            player.vx = player.vx + moveX * accel * dt
            if math.abs(player.vx) > PHYSICS.RUN_SPEED then
                player.vx = moveX * PHYSICS.RUN_SPEED
            end
        else
            if player.vx > 0 then
                player.vx = math.max(0, player.vx - friction * dt)
            elseif player.vx < 0 then
                player.vx = math.min(0, player.vx + friction * dt)
            end
        end
    end
    
    -- Gravity
    if not player.grounded then
        if player.onWall ~= 0 and player.vy > 0 then
            player.vy = math.min(player.vy + PHYSICS.GRAVITY * dt, PHYSICS.WALL_SLIDE_SPEED)
        else
            player.vy = math.min(player.vy + PHYSICS.GRAVITY * dt, PHYSICS.MAX_FALL)
        end
    end
    
    -- Jump
    if Input:consumeJump() then
        if player.coyoteTimer > 0 then
            player.vy = PHYSICS.JUMP_FORCE
            player.coyoteTimer = 0
            player.grounded = false
        elseif player.onWall ~= 0 then
            player.vy = PHYSICS.WALL_JUMP_FORCE_Y
            player.vx = -player.onWall * PHYSICS.WALL_JUMP_KICK_X
            player.wallJumpTimer = PHYSICS.WALL_JUMP_TIME
        end
    end
    
    -- Variable jump
    if not Input:down("jump") and player.vy < 0 then
        player.vy = player.vy * PHYSICS.VAR_JUMP_MULT
    end
    
    -- Move
    self:moveX(player.vx * dt)
    self:moveY(player.vy * dt)
    
    -- Update float render position
    player.renderX = player.x + player.xRemainder
    player.renderY = player.y + player.yRemainder
    
    -- Camera follow
    camera.targetX = player.x - GAME_WIDTH/2 + player.w/2
    camera.targetY = player.y - GAME_HEIGHT/2 + player.h/2
    camera.x = self:clampCameraX(camera.targetX)
    camera.y = self:clampCameraY(camera.targetY)
end

-- =============================================================================
-- DRAW
-- =============================================================================
function Game:draw(alpha)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0.1, 0.1, 0.15, 1)
    
    -- Interpolate positions
    local px = player.prevRenderX + (player.renderX - player.prevRenderX) * alpha
    local py = player.prevRenderY + (player.renderY - player.prevRenderY) * alpha
    local camX = camera.prevX + (camera.x - camera.prevX) * alpha
    local camY = camera.prevY + (camera.y - camera.prevY) * alpha
    
    local camFloorX = math.floor(camX)
    local camFloorY = math.floor(camY)
    
    love.graphics.push()
    love.graphics.translate(BLEED - camFloorX, BLEED - camFloorY)
    
    -- Draw all visible rooms
    for _, room in ipairs(Map.rooms) do
        if room.x + room.w > camFloorX and room.x < camFloorX + GAME_WIDTH and
           room.y + room.h > camFloorY and room.y < camFloorY + GAME_HEIGHT then
            self:drawRoom(room, false)
        end
    end
    
    -- Draw player
    local relX = px - camX
    local relY = py - camY
    local drawRelX = math.floor(relX + 0.5)
    local drawRelY = math.floor(relY + 0.5)
    
    love.graphics.setColor(1, 0.2, 0.2)
    love.graphics.rectangle("fill", camFloorX + drawRelX, camFloorY + drawRelY, player.w, player.h)
    
    love.graphics.pop()
    love.graphics.setCanvas()
    
    local fracX = camX - camFloorX
    local fracY = camY - camFloorY
    
    return canvas, fracX, fracY
end

function Game:drawRoom(room, showDebug)
    local cols = #room.tiles[1] or 0
    local rows = #room.tiles or 0
    
    for row = 1, rows do
        for col = 1, cols do
            local tileValue = room.tiles[row] and room.tiles[row][col]
            if tileValue and tileValue > 0 then
                local x = room.x + (col - 1) * TILE_SIZE
                local y = room.y + (row - 1) * TILE_SIZE
                local color = TILE_COLORS[tileValue] or TILE_COLORS[1]
                love.graphics.setColor(color[1], color[2], color[3])
                love.graphics.rectangle("fill", x, y, TILE_SIZE, TILE_SIZE)
            end
        end
    end
    
    if showDebug then
        love.graphics.setColor(0.3, 0.3, 0.4, 0.5)
        love.graphics.rectangle("line", room.x, room.y, room.w, room.h)
        
        love.graphics.setColor(1, 1, 0, 0.5)
        love.graphics.rectangle("fill", room.x + room.spawnX - 2, room.y + room.spawnY - 2, 4, 4)
    end
end

function Game:getCanvasDimensions()
    return GAME_WIDTH, GAME_HEIGHT, BLEED
end

function Game:getPlayer()
    return player
end

return Game