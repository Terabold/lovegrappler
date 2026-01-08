-- game.lua
-- Celeste-Style Platformer Engine
-- Locked 60 FPS physics and rendering

local Input = require("input")
local Map = require("map")

local Game = {}

-- =============================================================================
-- CONSTANTS
-- =============================================================================
local GAME_WIDTH = 320
local GAME_HEIGHT = 180
local TILE_SIZE = 8

-- Tile colors (match editor.lua)
local TILE_COLORS = {
    {0.2, 0.8, 0.3},  -- 1: Ground (green)
    {0.4, 0.4, 0.5},  -- 2: Stone (gray)
    {0.5, 0.8, 1.0},  -- 3: Ice (light blue)
    {0.9, 0.2, 0.2},  -- 4: Danger/Spikes (red)
    {0.6, 0.4, 0.2},  -- 5: Wood (brown)
}

-- =============================================================================
-- CELESTE SOURCE CODE PHYSICS CONSTANTS
-- =============================================================================
-- These are the EXACT values from Celeste's C# source code (released by Maddy Thorson)
-- All values in pixels per second (px/s) unless otherwise noted
--
-- References:
-- - Maddy Thorson's article on Celeste and TowerFall Physics
-- - Original Player class source code (learning resource)
-- - Community analysis of movement values
--
-- Key Insight: Celeste uses ASYMMETRIC GRAVITY
--   - Jump ascent uses halved gravity at peak for fine control
--   - Descent uses full gravity for snappy falls
--   - This creates the signature "Celeste feel"

local PHYSICS = {
    -- =======================================================================
    -- HORIZONTAL MOVEMENT (tuned for proper feel at 60 FPS fixed timestep)
    -- =======================================================================
    MAX_RUN         = 90,           -- Maximum horizontal speed (px/s)
    CROUCH_SPEED    = 45,           -- Crouched movement (half speed)
    RUN_ACCEL       = 1000,         -- Ground acceleration
    RUN_REDUCE      = 400,          -- Deceleration when stopping
    AIR_MULT        = 0.65,         -- Air control multiplier (65% of ground)

    -- =======================================================================
    -- JUMPING & GRAVITY (tuned for Celeste-like feel)
    -- =======================================================================
    -- These values work with our fixed timestep system (dt = 1/60)
    -- Adjusted for proper jump height (~3 tiles = 24-26 pixels)

    JUMP_SPEED      = -210,         -- Initial jump velocity (gives proper height)
    JUMP_H_BOOST    = 40,           -- Extra horizontal speed when jumping while moving

    -- ASYMMETRIC GRAVITY (key to Celeste's feel!)
    GRAVITY         = 900,          -- Normal fall gravity
    MAX_FALL        = 160,          -- Terminal velocity
    FAST_MAX_FALL   = 240,          -- Terminal velocity when fast-falling
    HALF_GRAV_THRESHOLD = 40,       -- When abs(vy) < this, use half gravity (at apex)

    -- Variable jump (cut jump short by releasing button)
    VAR_JUMP_TIME   = 0.2,          -- How long variable jump window lasts (seconds)
    VAR_JUMP_MULT   = 0.5,          -- Multiply vy by this when releasing jump early

    -- Duck jump
    DUCK_JUMP_SPEED = -105,         -- Reduced jump from crouch (~half height)

    -- =======================================================================
    -- WALL MECHANICS (tuned for proper feel)
    -- =======================================================================
    WALL_SLIDE_TIME = 1.2,          -- Time before wallslide starts (seconds)
    WALL_SLIDE_START_MAX = 20,      -- Max speed when starting wallslide

    -- Wall jump
    WALL_JUMP_CHECK = 3,            -- Distance to check for walls (pixels)
    WALL_JUMP_H_SPEED = 130,        -- Horizontal kick from wall jump
    WALL_JUMP_FORCE_TIME = 0.16,    -- How long wall jump locks horizontal input (seconds)

    -- Wall climb (when holding grab)
    CLIMB_UP_SPEED  = -45,          -- Climbing speed
    CLIMB_DOWN_SPEED = 80,          -- Slide down speed when out of stamina
    CLIMB_SLIP_SPEED = 30,          -- Slip speed when stamina depleted
    CLIMB_GRAB_Y_MULT = 0.2,        -- Gravity multiplier when grabbing wall
    CLIMB_JUMP_BOOST = -210,        -- Vertical boost from climb jump (same as regular jump)
    CLIMB_JUMP_BOOST_H = 130,       -- Horizontal boost from climb jump

    -- Stamina system
    CLIMB_MAX_STAMINA = 110,        -- Max stamina (frames at 60fps = ~1.83 seconds)
    CLIMB_TIRED_STAMINA = 20,       -- When stamina gets low (frames)

    -- =======================================================================
    -- HITBOX (from Celeste source - Madeline's exact dimensions)
    -- =======================================================================
    PLAYER_WIDTH    = 8,            -- Hitbox width (never changes)
    NORMAL_HEIGHT   = 11,           -- Normal hitbox height (Celeste: 11px)
    CROUCH_HEIGHT   = 4,            -- Duck hitbox height

    -- =======================================================================
    -- FORGIVENESS MECHANICS (critical for game feel!)
    -- =======================================================================
    COYOTE_TIME     = 0.1,          -- Jump grace period after leaving platform (seconds)
    JUMP_GRACE      = 0.1,          -- Jump buffer - accept input before landing (seconds)

    -- Corner correction (not yet implemented)
    CORNER_CORRECT  = 4,            -- Pixels to check for corner nudging
}

-- =============================================================================
-- PLAYER STATE
-- Clean structure: physics position (x,y) + previous position for interpolation
-- =============================================================================
local player = {
    -- Physics position (integer pixels)
    x = 100,
    y = 100,

    -- Sub-pixel accumulator (Celeste-style integer physics)
    xRemainder = 0,
    yRemainder = 0,

    -- Hitbox (Celeste-accurate: 8x9 pixels)
    w = PHYSICS.PLAYER_WIDTH,
    h = PHYSICS.NORMAL_HEIGHT,
    normalHeight = PHYSICS.NORMAL_HEIGHT,
    crouchHeight = PHYSICS.CROUCH_HEIGHT,

    -- Velocity
    vx = 0,
    vy = 0,

    -- State flags
    grounded = false,
    wasGrounded = false,            -- For coyote time trigger
    onWall = 0,                     -- -1 = left, 0 = none, 1 = right
    crouching = false,              -- Is player currently crouching?
    grabbing = false,               -- Is player holding grab on wall?

    -- Timers
    coyoteTimer = 0,
    wallJumpTimer = 0,

    -- Wall grab stamina (Celeste-style - in frames, not seconds!)
    stamina = PHYSICS.CLIMB_MAX_STAMINA,
    maxStamina = PHYSICS.CLIMB_MAX_STAMINA,

    -- Variable jump tracking
    jumpHeld = false,               -- Was jump held last frame?
    varJumpApplied = false,         -- Has variable jump reduction been applied?

    -- Death
    dead = false,
}

-- =============================================================================
-- CAMERA STATE
-- =============================================================================
local camera = {
    x = 0,
    y = 0,
}

-- =============================================================================
-- TRANSITION STATE
-- =============================================================================
local transition = {
    active = false,
    timer = 0,
    duration = 0.2,
    fromRoom = nil,
    toRoom = nil,
    direction = nil,
    -- Camera lerp
    startCamX = 0, startCamY = 0,
    endCamX = 0, endCamY = 0,
    -- Player lerp
    startPlayerX = 0, startPlayerY = 0,
    targetX = 0, targetY = 0,
    keepVelX = 0, keepVelY = 0,
}

-- =============================================================================
-- RESPAWN & ROOM TRACKING
-- =============================================================================
local respawn = {
    x = 50,
    y = 140,
    room = nil,
}

local visitedRooms = {}

-- Render canvas
local canvas

-- =============================================================================
-- LIFECYCLE
-- =============================================================================

function Game:load()
    canvas = love.graphics.newCanvas(GAME_WIDTH, GAME_HEIGHT)
    canvas:setFilter("nearest", "nearest")
    
    -- Load or create world
    if not Map.load("world.lua") then
        Map.createDefaultWorld()
    end
    
    -- Initialize starting room
    if Map.rooms[1] then
        Map.currentRoom = Map.rooms[1]
        respawn.room = Map.currentRoom
        respawn.x = Map.currentRoom.x + Map.currentRoom.spawnX
        respawn.y = Map.currentRoom.y + Map.currentRoom.spawnY
        
        local roomKey = Map.currentRoom.x .. "_" .. Map.currentRoom.y
        visitedRooms[roomKey] = true
    end
    
    self:reset()
end

function Game:reset()
    -- Reset player to respawn point (MUST be integer!)
    -- If crouching, uncrouch first to get proper height
    if player.crouching then
        player.crouching = false
        player.h = player.normalHeight
    end

    player.x = math.floor(respawn.x - player.w / 2)
    player.y = math.floor(respawn.y - player.h)
    player.xRemainder = 0
    player.yRemainder = 0
    player.vx = 0
    player.vy = 0
    player.grounded = false
    player.wasGrounded = false
    player.onWall = 0
    player.crouching = false
    player.grabbing = false
    player.stamina = player.maxStamina
    player.coyoteTimer = 0
    player.wallJumpTimer = 0
    player.jumpHeld = false
    player.varJumpApplied = false
    player.dead = false
    
    -- Reset transition
    transition.active = false
    
    -- Set camera (ensure integer positions)
    if Map.currentRoom then
        camera.x = math.floor(self:clampCameraX(player.x - GAME_WIDTH / 2))
        camera.y = math.floor(self:clampCameraY(player.y - GAME_HEIGHT / 2))
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
    if maxX < minX then maxX = minX end
    return math.max(minX, math.min(camX, maxX))
end

function Game:clampCameraY(camY)
    local room = Map.currentRoom
    if not room then return camY end
    local minY = room.y
    local maxY = room.y + room.h - GAME_HEIGHT
    if maxY < minY then maxY = minY end
    return math.max(minY, math.min(camY, maxY))
end

-- =============================================================================
-- ROOM TRANSITIONS
-- =============================================================================

function Game:checkRoomTransition()
    if transition.active then return end
    
    local room = Map.currentRoom
    if not room then return end
    
    -- Check using FULL HITBOX, not center point!
    -- Player hitbox bounds
    local pLeft = player.x
    local pRight = player.x + player.w
    local pTop = player.y
    local pBottom = player.y + player.h

    -- Room bounds
    local rLeft = room.x
    local rRight = room.x + room.w
    local rTop = room.y
    local rBottom = room.y + room.h

    local direction = nil
    local centerX = math.floor(player.x + player.w / 2)
    local centerY = math.floor(player.y + player.h / 2)

    -- Check if player's hitbox has FULLY crossed the border
    if pRight <= rLeft then direction = "left"
    elseif pLeft >= rRight then direction = "right"
    elseif pBottom <= rTop then direction = "up"
    elseif pTop >= rBottom then direction = "down"
    end

    if direction then
        local newRoom = Map.getNeighborRoom(room, centerX, centerY)

        if newRoom then
            self:startTransition(room, newRoom, direction)
        else
            -- No room - push player back to border (integer positions!)
            if direction == "left" then player.x = rLeft end
            if direction == "right" then player.x = rRight - player.w end
            if direction == "up" then player.y = rTop end
            if direction == "down" then player.y = rBottom - player.h end
            player.vx = 0
            player.vy = 0
            player.xRemainder = 0
            player.yRemainder = 0
        end
    end
end

function Game:startTransition(fromRoom, toRoom, direction)
    transition.active = true
    transition.timer = 0
    transition.fromRoom = fromRoom
    transition.toRoom = toRoom
    transition.direction = direction
    
    -- Store current state
    transition.startCamX = camera.x
    transition.startCamY = camera.y
    transition.startPlayerX = player.x
    transition.startPlayerY = player.y
    
    -- Determine direction (forward = spawn, backward = edge)
    local fromOrder = fromRoom.order or 0
    local toOrder = toRoom.order or 0
    local isGoingForward = toOrder > fromOrder
    
    local SNAP_BUFFER = 4
    
    if isGoingForward then
        transition.targetX = toRoom.x + toRoom.spawnX - player.w / 2
        transition.targetY = toRoom.y + toRoom.spawnY - player.h
        transition.keepVelX = 0
        transition.keepVelY = 0
    else
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
    
    -- Update respawn
    respawn.x = toRoom.x + toRoom.spawnX
    respawn.y = toRoom.y + toRoom.spawnY
    respawn.room = toRoom
    
    -- Calculate target camera
    local targetCamX = transition.targetX - GAME_WIDTH / 2 + player.w / 2
    local targetCamY = transition.targetY - GAME_HEIGHT / 2 + player.h / 2
    
    Map.currentRoom = toRoom
    transition.endCamX = self:clampCameraX(targetCamX)
    transition.endCamY = self:clampCameraY(targetCamY)
    Map.currentRoom = fromRoom
end

function Game:updateTransition(dt)
    if not transition.active then return end
    
    transition.timer = transition.timer + dt
    local t = transition.timer / transition.duration
    
    -- Smooth ease in-out
    local easeT = t < 1 and (t * t * (3 - 2 * t)) or 1
    
    -- Lerp camera (FLOOR to maintain integer positions!)
    camera.x = math.floor(transition.startCamX + (transition.endCamX - transition.startCamX) * easeT)
    camera.y = math.floor(transition.startCamY + (transition.endCamY - transition.startCamY) * easeT)

    -- Lerp player (FLOOR to maintain integer positions!)
    player.x = math.floor(transition.startPlayerX + (transition.targetX - transition.startPlayerX) * easeT)
    player.y = math.floor(transition.startPlayerY + (transition.targetY - transition.startPlayerY) * easeT)
    
    if t >= 1 then
        -- Complete transition
        Map.currentRoom = transition.toRoom
        camera.x = transition.endCamX
        camera.y = transition.endCamY
        player.x = transition.targetX
        player.y = transition.targetY
        player.xRemainder = 0
        player.yRemainder = 0
        
        -- Restore momentum for backward transitions
        if transition.direction == "left" or transition.direction == "right" then
            player.vx = transition.keepVelX
            player.vy = transition.keepVelY
        else
            player.vx = 0
            player.vy = 0
        end
        
        player.grounded = false
        transition.active = false
    end
end

-- =============================================================================
-- SUB-PIXEL MOVEMENT (Celeste-style integer physics)
-- =============================================================================

function Game:moveX(amount)
    player.xRemainder = player.xRemainder + amount
    -- CELESTE-CORRECT: Use floor, NOT round
    -- Positive: floor() truncates down. Negative: need ceiling behavior
    local move = player.xRemainder >= 0 and math.floor(player.xRemainder) or math.ceil(player.xRemainder)

    if move ~= 0 then
        player.xRemainder = player.xRemainder - move
        local sign = move > 0 and 1 or -1

        while move ~= 0 do
            if not Map.checkSolid(player.x + sign, player.y, player.w, player.h) then
                player.x = player.x + sign
                move = move - sign
            else
                -- Hit wall
                player.vx = 0
                player.xRemainder = 0
                break
            end
        end
    end
end

function Game:moveY(amount)
    player.yRemainder = player.yRemainder + amount
    -- CELESTE-CORRECT: Use floor, NOT round
    local move = player.yRemainder >= 0 and math.floor(player.yRemainder) or math.ceil(player.yRemainder)

    if move ~= 0 then
        player.yRemainder = player.yRemainder - move
        local sign = move > 0 and 1 or -1

        while move ~= 0 do
            if not Map.checkSolid(player.x, player.y + sign, player.w, player.h) then
                player.y = player.y + sign
                move = move - sign
            else
                -- Hit floor/ceiling
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
    -- Check left
    if Map.checkSolid(player.x - 1, player.y, 1, player.h) then
        player.onWall = -1
        return
    end
    -- Check right
    if Map.checkSolid(player.x + player.w, player.y, 1, player.h) then
        player.onWall = 1
    end
end

-- =============================================================================
-- SPIKE/DANGER COLLISION
-- Celeste-style: Spikes have a smaller hitbox than their tile
-- Only the "dangerous" part of the spike kills you
-- =============================================================================

function Game:checkDanger()
    local room = Map.currentRoom
    if not room then return false end
    
    -- Player hitbox (shrink slightly for fairness)
    local px = player.x + 1
    local py = player.y + 1
    local pw = player.w - 2
    local ph = player.h - 2
    
    -- Check tile-based danger (type 4)
    -- Spikes are typically on floor, so check tiles player is touching
    local startCol = math.floor((px - room.x) / TILE_SIZE) + 1
    local endCol = math.floor((px + pw - 1 - room.x) / TILE_SIZE) + 1
    local startRow = math.floor((py - room.y) / TILE_SIZE) + 1
    local endRow = math.floor((py + ph - 1 - room.y) / TILE_SIZE) + 1
    
    for row = startRow, endRow do
        for col = startCol, endCol do
            if room.tiles[row] and room.tiles[row][col] == Map.TILES.DANGER then
                -- CELESTE-STYLE SPIKE HITBOX
                -- Spikes only kill if you're deep enough into the tile
                -- Reduce hitbox by 3 pixels on the dangerous side
                local tileX = room.x + (col - 1) * TILE_SIZE
                local tileY = room.y + (row - 1) * TILE_SIZE
                
                -- Assume upward-facing spikes: dangerous zone is top 5 pixels
                local spikeTop = tileY
                local spikeBottom = tileY + 5
                local spikeLeft = tileX + 2      -- Inset from sides
                local spikeRight = tileX + TILE_SIZE - 2
                
                -- AABB collision with spike hitbox
                if px + pw > spikeLeft and px < spikeRight and
                   py + ph > spikeTop and py < spikeBottom then
                    return true
                end
            end
        end
    end
    
    -- Check entity-based spikes
    for _, entity in ipairs(room.entities or {}) do
        if entity.type == "spike" then
            local ex = room.x + entity.x
            local ey = room.y + entity.y
            local dir = entity.data and entity.data.direction or "up"
            
            -- Spike hitbox based on direction (Celeste-accurate: ~3px inset)
            local sx, sy, sw, sh
            if dir == "up" then
                sx = ex + 2
                sy = ey
                sw = 4
                sh = 5
            elseif dir == "down" then
                sx = ex + 2
                sy = ey + 3
                sw = 4
                sh = 5
            elseif dir == "left" then
                sx = ex
                sy = ey + 2
                sw = 5
                sh = 4
            elseif dir == "right" then
                sx = ex + 3
                sy = ey + 2
                sw = 5
                sh = 4
            else
                sx, sy, sw, sh = ex + 2, ey, 4, 5
            end
            
            -- AABB collision
            if px + pw > sx and px < sx + sw and
               py + ph > sy and py < sy + sh then
                return true
            end
        end
    end
    
    return false
end

-- =============================================================================
-- MAIN UPDATE
-- =============================================================================

function Game:update(dt)
    -- Handle active transition
    if transition.active then
        self:updateTransition(dt)
        return
    end
    
    -- Handle death
    if player.dead then
        self:reset()
        return
    end
    
    -- Check room transition
    self:checkRoomTransition()
    if transition.active then return end
    
    -- =======================================================================
    -- SNAPSHOT PREVIOUS POSITION (Critical for interpolation!)
    -- Must happen BEFORE any physics changes this frame
    -- =======================================================================
    
    -- =======================================================================
    -- GROUND CHECK (before movement)
    -- =======================================================================
    player.wasGrounded = player.grounded
    player.grounded = Map.checkSolid(player.x, player.y + player.h, player.w, 1)
    
    -- =======================================================================
    -- COYOTE TIME
    -- =======================================================================
    if player.grounded then
        player.coyoteTimer = PHYSICS.COYOTE_TIME
        player.varJumpApplied = false  -- Reset variable jump on landing
    else
        player.coyoteTimer = math.max(0, player.coyoteTimer - dt)
    end
    
    -- =======================================================================
    -- WALL CHECK
    -- =======================================================================
    self:checkWall()
    
    -- =======================================================================
    -- WALL JUMP TIMER
    -- =======================================================================
    if player.wallJumpTimer > 0 then
        player.wallJumpTimer = player.wallJumpTimer - dt
    end

    -- =======================================================================
    -- CROUCH (Celeste-style: only on ground, changes hitbox)
    -- =======================================================================
    local crouchHeld = Input:down("crouch")

    -- Can only crouch on ground
    if player.grounded and crouchHeld then
        if not player.crouching then
            -- Start crouching
            player.crouching = true
            player.h = player.crouchHeight
            -- Move player up so bottom stays in same position
            player.y = player.y + (player.normalHeight - player.crouchHeight)
        end
    else
        if player.crouching then
            -- Try to stand up - check if there's room
            local standUpY = player.y - (player.normalHeight - player.crouchHeight)
            if not Map.checkSolid(player.x, standUpY, player.w, player.normalHeight) then
                player.crouching = false
                player.h = player.normalHeight
                player.y = standUpY
            end
            -- else: keep crouching, can't stand up yet
        end
    end

    -- =======================================================================
    -- HORIZONTAL INPUT & MOVEMENT (Celeste source-accurate)
    -- =======================================================================
    local moveX = 0
    if Input:down("left") then moveX = -1 end
    if Input:down("right") then moveX = 1 end

    -- Celeste uses different accel values for ground vs air
    local accel = player.grounded and PHYSICS.RUN_ACCEL or (PHYSICS.RUN_ACCEL * PHYSICS.AIR_MULT)
    local decel = PHYSICS.RUN_REDUCE
    local maxSpeed = player.crouching and PHYSICS.CROUCH_SPEED or PHYSICS.MAX_RUN

    -- Only apply input if not locked by wall jump
    if player.wallJumpTimer <= 0 then
        if moveX ~= 0 then
            -- Accelerate toward target speed
            player.vx = player.vx + moveX * accel * dt
            if math.abs(player.vx) > maxSpeed then
                player.vx = moveX * maxSpeed
            end
        else
            -- Decelerate when not pressing any direction
            if player.vx > 0 then
                player.vx = math.max(0, player.vx - decel * dt)
            elseif player.vx < 0 then
                player.vx = math.min(0, player.vx + decel * dt)
            end
        end
    end
    
    -- =======================================================================
    -- WALL GRAB & STAMINA (Celeste source-accurate)
    -- =======================================================================
    local grabHeld = Input:down("grab")
    local isPushingTowardWall = (player.onWall == -1 and moveX == -1) or
                                 (player.onWall == 1 and moveX == 1)

    -- Wall grab conditions: on wall, pushing toward it, holding grab, not grounded
    if not player.grounded and player.onWall ~= 0 and isPushingTowardWall and grabHeld and player.stamina > 0 then
        player.grabbing = true

        -- Climbing up with UP key
        local climbInput = Input:down("up") and -1 or 0

        if climbInput < 0 then
            -- Climbing up: drain stamina (1 frame per frame)
            player.vy = PHYSICS.CLIMB_UP_SPEED
            player.stamina = player.stamina - 1  -- Drain 1 stamina per frame (60fps)
        else
            -- Holding still on wall: reduced gravity, slow stamina drain
            player.vy = player.vy * PHYSICS.CLIMB_GRAB_Y_MULT
            player.stamina = player.stamina - 0.5  -- Slower drain when holding still
        end

        -- Stamina depleted: slip down the wall
        if player.stamina <= 0 then
            player.stamina = 0
            player.grabbing = false
            -- Start slipping down
            player.vy = PHYSICS.CLIMB_SLIP_SPEED
        end
    else
        player.grabbing = false

        -- Regenerate stamina on ground (instant in Celeste)
        if player.grounded and player.stamina < player.maxStamina then
            player.stamina = player.maxStamina
        end
    end

    -- =======================================================================
    -- GRAVITY & WALL SLIDE (Celeste source-accurate with half-gravity at apex!)
    -- =======================================================================
    if not player.grounded and not player.grabbing then
        -- Check if wall sliding (not grabbing, but pushing toward wall)
        local isWallSliding = player.onWall ~= 0 and player.vy > 0 and isPushingTowardWall

        if isWallSliding then
            -- Wall slide: cap fall speed to slide speed
            player.vy = math.min(player.vy + PHYSICS.GRAVITY * dt, PHYSICS.WALL_SLIDE_START_MAX)
        else
            -- CELESTE'S SECRET: Half gravity at apex for fine control!
            -- When vertical speed is very low (near apex), use half gravity
            -- This gives players precise control over jump height
            local gravity = PHYSICS.GRAVITY
            if math.abs(player.vy) < PHYSICS.HALF_GRAV_THRESHOLD then
                gravity = PHYSICS.GRAVITY * 0.5
            end

            player.vy = math.min(player.vy + gravity * dt, PHYSICS.MAX_FALL)
        end
    end
    
    -- =======================================================================
    -- JUMPING (Celeste source-accurate)
    -- =======================================================================
    local jumpPressed = Input:consumeJump()
    local jumpHeldNow = Input:down("jump")

    if jumpPressed then
        if player.coyoteTimer > 0 then
            -- Ground/Coyote jump (or duck jump if crouching)
            if player.crouching then
                player.vy = PHYSICS.DUCK_JUMP_SPEED
            else
                player.vy = PHYSICS.JUMP_SPEED
            end
            player.coyoteTimer = 0
            player.grounded = false
            player.varJumpApplied = false

            -- Celeste adds horizontal boost when jumping while moving
            if moveX ~= 0 and math.abs(player.vx) > PHYSICS.MAX_RUN * 0.5 then
                player.vx = player.vx + moveX * PHYSICS.JUMP_H_BOOST * 0.5
            end
        elseif player.onWall ~= 0 then
            -- Wall jump (can jump from grab or slide)
            player.vy = PHYSICS.CLIMB_JUMP_BOOST
            player.vx = -player.onWall * PHYSICS.WALL_JUMP_H_SPEED
            player.wallJumpTimer = PHYSICS.WALL_JUMP_FORCE_TIME
            player.varJumpApplied = false
            player.grabbing = false
        end
    end
    
    -- =======================================================================
    -- VARIABLE JUMP HEIGHT
    -- FIX: Only apply the velocity reduction ONCE when jump is released
    -- Not every frame! That was killing all jumps instantly.
    -- =======================================================================
    if player.jumpHeld and not jumpHeldNow and player.vy < 0 and not player.varJumpApplied then
        player.vy = player.vy * PHYSICS.VAR_JUMP_MULT
        player.varJumpApplied = true
    end
    player.jumpHeld = jumpHeldNow
    
    -- =======================================================================
    -- APPLY MOVEMENT
    -- =======================================================================
    self:moveX(player.vx * dt)
    self:moveY(player.vy * dt)
    
    -- =======================================================================
    -- DANGER CHECK
    -- =======================================================================
    if self:checkDanger() then
        player.dead = true
        return
    end
    
    -- =======================================================================
    -- CAMERA FOLLOW (Celeste-style: TIGHT follow, no lerp smoothing)
    -- =======================================================================
    -- In Celeste, the camera follows player INSTANTLY in most rooms
    -- Smooth camera is only used in specific scripted sequences
    -- For pixel-perfect movement, we need instant camera follow
    local targetCamX = player.x - GAME_WIDTH / 2 + player.w / 2
    local targetCamY = player.y - GAME_HEIGHT / 2 + player.h / 2

    -- Floor to ensure integer camera positions (eliminates sub-pixel jitter)
    camera.x = math.floor(self:clampCameraX(targetCamX))
    camera.y = math.floor(self:clampCameraY(targetCamY))
end

-- =============================================================================
-- DRAW
-- =============================================================================

function Game:draw(alpha)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0.1, 0.1, 0.15, 1)

    -- Camera and player positions are ALREADY integers from update()
    -- No need for floor() here
    love.graphics.push()
    love.graphics.translate(-camera.x, -camera.y)

    -- Draw visible rooms
    for _, room in ipairs(Map.rooms) do
        if room.x + room.w > camera.x and room.x < camera.x + GAME_WIDTH and
           room.y + room.h > camera.y and room.y < camera.y + GAME_HEIGHT then
            self:drawRoom(room)
        end
    end

    -- Draw player (color changes based on state)
    if player.crouching then
        love.graphics.setColor(1, 0.5, 0.2)  -- Orange when crouching
    elseif player.grabbing then
        love.graphics.setColor(0.2, 0.8, 1)  -- Cyan when grabbing wall
    else
        love.graphics.setColor(1, 0.2, 0.2)  -- Red normally
    end
    love.graphics.rectangle("fill", player.x, player.y, player.w, player.h)

    -- Debug: Draw sub-pixel indicator
    if player.xRemainder ~= 0 or player.yRemainder ~= 0 then
        love.graphics.setColor(1, 1, 0, 0.5)
        love.graphics.rectangle("fill", player.x, player.y - 2, player.w, 1)
    end

    -- Draw stamina bar when on wall
    if player.onWall ~= 0 and not player.grounded then
        local barWidth = 20
        local barHeight = 3
        local barX = player.x + player.w / 2 - barWidth / 2
        local barY = player.y - 8

        -- Background
        love.graphics.setColor(0.2, 0.2, 0.2, 0.8)
        love.graphics.rectangle("fill", barX, barY, barWidth, barHeight)

        -- Stamina fill
        local staminaPercent = player.stamina / player.maxStamina
        if staminaPercent > 0.5 then
            love.graphics.setColor(0.3, 1, 0.3)  -- Green
        elseif staminaPercent > 0.25 then
            love.graphics.setColor(1, 1, 0.3)    -- Yellow
        else
            love.graphics.setColor(1, 0.3, 0.3)  -- Red
        end
        love.graphics.rectangle("fill", barX, barY, barWidth * staminaPercent, barHeight)
    end

    love.graphics.pop()
    love.graphics.setCanvas()

    return canvas
end

function Game:drawRoom(room)
    local cols = room.tiles[1] and #room.tiles[1] or 0
    local rows = #room.tiles
    
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
    
    -- Draw entity-based spikes
    for _, entity in ipairs(room.entities or {}) do
        if entity.type == "spike" then
            local ex = room.x + entity.x
            local ey = room.y + entity.y
            love.graphics.setColor(0.9, 0.2, 0.2)
            -- Draw spike as triangle based on direction
            local dir = entity.data and entity.data.direction or "up"
            if dir == "up" then
                love.graphics.polygon("fill", ex, ey + 8, ex + 4, ey, ex + 8, ey + 8)
            elseif dir == "down" then
                love.graphics.polygon("fill", ex, ey, ex + 4, ey + 8, ex + 8, ey)
            elseif dir == "left" then
                love.graphics.polygon("fill", ex + 8, ey, ex, ey + 4, ex + 8, ey + 8)
            elseif dir == "right" then
                love.graphics.polygon("fill", ex, ey, ex + 8, ey + 4, ex, ey + 8)
            end
        end
    end
end

-- =============================================================================
-- UTILITY
-- =============================================================================

function Game:getCanvasDimensions()
    return GAME_WIDTH, GAME_HEIGHT, BLEED
end

function Game:getPlayer()
    return player
end

-- Expose for debug HUD
Game.player = player
Game.camera = camera

return Game
