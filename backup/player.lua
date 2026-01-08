-- player.lua
-- Standalone Player Module (Reference Implementation)
-- This module is kept for reference but game.lua uses its own integrated player state
-- Can be used for future modular refactoring

local Input = require("input")

local Player = {}

-- =============================================================================
-- PHYSICS CONSTANTS
-- =============================================================================
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
    JUMP_BUFFER_TIME = 0.1,
    VAR_JUMP_MULT = 0.5    
}

-- =============================================================================
-- PLAYER STATE
-- =============================================================================
local state = {
    x = 100,
    y = 100,
    prev_x = 100,
    prev_y = 100,
    xRemainder = 0,
    yRemainder = 0,
    w = 8,
    h = 8,
    vx = 0,
    vy = 0,
    grounded = false,
    onWall = 0,
    isWallSliding = false,
    coyoteTimer = 0,
    jumpBufferTimer = 0,
    wallJumpTimer = 0,
    state = "Idle",
    dead = false
}

-- =============================================================================
-- LIFECYCLE
-- =============================================================================

function Player:load()
    self:reset(100, 100)
end

function Player:reset(x, y)
    state.x = x or 100
    state.y = y or 100
    state.prev_x = state.x
    state.prev_y = state.y
    state.xRemainder = 0
    state.yRemainder = 0
    state.vx = 0
    state.vy = 0
    state.grounded = false
    state.onWall = 0
    state.isWallSliding = false
    state.coyoteTimer = 0
    state.jumpBufferTimer = 0
    state.wallJumpTimer = 0
    state.state = "Idle"
    state.dead = false
end

function Player:getState()
    return state
end

function Player:getPhysics()
    return PHYSICS
end

-- =============================================================================
-- UPDATE (Requires Map module for collision)
-- =============================================================================

function Player:update(dt, Map)
    if state.dead then return end
    
    -- Snapshot for interpolation
    state.prev_x = state.x
    state.prev_y = state.y
    
    -- Ground check
    state.grounded = Map.checkSolid(state.x, state.y + state.h, state.w, 1)
    
    -- Input
    local inputX, inputY = Input:getAxis()
    if state.wallJumpTimer > 0 then
        state.wallJumpTimer = state.wallJumpTimer - dt
        inputX = 0
    end
    
    -- Horizontal movement
    local targetSpeed = inputX * PHYSICS.RUN_SPEED
    local accel = state.grounded and PHYSICS.ACCEL or PHYSICS.AIR_ACCEL
    local friction = state.grounded and PHYSICS.FRICTION or PHYSICS.AIR_FRICTION
    
    if inputX ~= 0 then
        if state.vx < targetSpeed then
            state.vx = math.min(targetSpeed, state.vx + accel * dt)
        elseif state.vx > targetSpeed then
            state.vx = math.max(targetSpeed, state.vx - accel * dt)
        end
    else
        if state.vx > 0 then
            state.vx = math.max(0, state.vx - friction * dt)
        elseif state.vx < 0 then
            state.vx = math.min(0, state.vx + friction * dt)
        end
        if math.abs(state.vx) < 1 then state.vx = 0 end
    end
    
    -- Gravity
    state.vy = state.vy + PHYSICS.GRAVITY * dt
    
    -- Move X with sub-pixel accumulation
    self:moveX(state.vx * dt, Map)
    
    -- Wall check
    self:checkWall(Map)
    
    -- Wall slide
    state.isWallSliding = false
    if not state.grounded and state.onWall ~= 0 then
        local pushing = (state.onWall == -1 and inputX == -1) or 
                        (state.onWall == 1 and inputX == 1)
        if state.vy > 0 and pushing then
            state.isWallSliding = true
            if state.vy > PHYSICS.WALL_SLIDE_SPEED then 
                state.vy = PHYSICS.WALL_SLIDE_SPEED 
            end
        end
    end
    
    -- Terminal velocity
    if not state.isWallSliding and state.vy > PHYSICS.MAX_FALL then 
        state.vy = PHYSICS.MAX_FALL 
    end
    
    -- Coyote time
    state.coyoteTimer = math.max(0, state.coyoteTimer - dt)
    if state.grounded then 
        state.coyoteTimer = PHYSICS.COYOTE_TIME 
    end
    
    -- Jump buffer
    state.jumpBufferTimer = math.max(0, state.jumpBufferTimer - dt)
    
    -- Jump
    if Input:consumeJump() then
        if state.coyoteTimer > 0 then
            state.vy = PHYSICS.JUMP_FORCE
            state.coyoteTimer = 0
        elseif state.isWallSliding or (not state.grounded and state.onWall ~= 0) then
            state.vy = PHYSICS.WALL_JUMP_FORCE_Y
            state.vx = -state.onWall * PHYSICS.WALL_JUMP_KICK_X
            state.wallJumpTimer = PHYSICS.WALL_JUMP_TIME
            state.isWallSliding = false
        end
    end
    
    -- Variable jump height
    if not Input:down("jump") and state.vy < 0 then
        state.vy = state.vy * PHYSICS.VAR_JUMP_MULT
    end
    
    -- Move Y
    self:moveY(state.vy * dt, Map)
    
    -- Update state machine
    self:updateState(inputX)
end

-- =============================================================================
-- SUB-PIXEL MOVEMENT
-- =============================================================================

function Player:moveX(amount, Map)
    state.xRemainder = state.xRemainder + amount
    local move = math.floor(state.xRemainder + 0.5)
    if move ~= 0 then
        state.xRemainder = state.xRemainder - move
        local sign = move > 0 and 1 or -1
        while move ~= 0 do
            if not Map.checkSolid(state.x + sign, state.y, state.w, state.h) then
                state.x = state.x + sign
                move = move - sign
            else
                state.vx = 0
                state.xRemainder = 0
                break
            end
        end
    end
end

function Player:moveY(amount, Map)
    state.yRemainder = state.yRemainder + amount
    local move = math.floor(state.yRemainder + 0.5)
    if move ~= 0 then
        state.yRemainder = state.yRemainder - move
        local sign = move > 0 and 1 or -1
        while move ~= 0 do
            if not Map.checkSolid(state.x, state.y + sign, state.w, state.h) then
                state.y = state.y + sign
                move = move - sign
            else
                if sign > 0 then
                    state.grounded = true
                end
                state.vy = 0
                state.yRemainder = 0
                break
            end
        end
    end
end

function Player:checkWall(Map)
    state.onWall = 0
    if Map.checkSolid(state.x - 1, state.y, 1, state.h) then
        state.onWall = -1
        return
    end
    if Map.checkSolid(state.x + state.w, state.y, 1, state.h) then
        state.onWall = 1
    end
end

-- =============================================================================
-- STATE MACHINE
-- =============================================================================

function Player:updateState(inputX)
    if state.isWallSliding then
        state.state = "WallSlide"
    elseif not state.grounded then
        if state.vy < 0 then
            state.state = "Jump"
        else
            state.state = "Fall"
        end
    elseif state.grounded then
        if state.vx ~= 0 then
            state.state = "Run"
        else
            state.state = "Idle"
        end
    end
end

-- =============================================================================
-- DRAW
-- =============================================================================

function Player:draw(alpha, cameraX, cameraY)
    cameraX = cameraX or 0
    cameraY = cameraY or 0
    
    -- Interpolate
    local lerpX = state.prev_x * (1 - alpha) + state.x * alpha
    local lerpY = state.prev_y * (1 - alpha) + state.y * alpha
    
    -- Round for pixel-perfect
    local drawX = math.floor(lerpX - cameraX + 0.5)
    local drawY = math.floor(lerpY - cameraY + 0.5)
    
    love.graphics.setColor(0.9, 0.2, 0.2)
    love.graphics.rectangle("fill", drawX, drawY, state.w, state.h)
    
    return drawX, drawY
end

-- =============================================================================
-- UTILITY
-- =============================================================================

function Player:kill()
    state.dead = true
end

function Player:isAlive()
    return not state.dead
end

function Player:getPosition()
    return state.x, state.y
end

function Player:setPosition(x, y)
    state.x = x
    state.y = y
    state.prev_x = x
    state.prev_y = y
    state.xRemainder = 0
    state.yRemainder = 0
end

function Player:getVelocity()
    return state.vx, state.vy
end

function Player:setVelocity(vx, vy)
    state.vx = vx
    state.vy = vy
end

return Player
