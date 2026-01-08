-- player.lua
-- =============================================================================
-- STANDALONE PLAYER MODULE (Reference Implementation)
-- =============================================================================
-- This module is kept as a clean, reusable reference implementation.
-- The main game (game.lua) uses its own integrated player state for simplicity.
-- Use this module if you want to refactor to a more modular architecture.
-- =============================================================================

local Input = require("input")

local Player = {}

-- =============================================================================
-- PHYSICS CONSTANTS (Celeste-tuned values)
-- =============================================================================
local PHYSICS = {
    -- Gravity & Jumping
    GRAVITY         = 900,
    JUMP_FORCE      = -200,
    MAX_FALL        = 160,          -- Terminal velocity (floaty but heavy)
    
    -- Horizontal Movement
    RUN_SPEED       = 90,
    ACCEL           = 600,
    FRICTION        = 800,
    AIR_ACCEL       = 400,
    AIR_FRICTION    = 200,
    
    -- Wall Mechanics
    WALL_SLIDE_SPEED = 40,
    WALL_JUMP_KICK_X = 140,
    WALL_JUMP_FORCE_Y = -200,
    WALL_JUMP_TIME   = 0.15,
    
    -- Coyote Time & Jump Buffering
    COYOTE_TIME     = 0.1,
    JUMP_BUFFER_TIME = 0.1,
    
    -- Variable Jump Height
    VAR_JUMP_MULT   = 0.5,
}

-- =============================================================================
-- PLAYER STATE
-- =============================================================================
local state = {
    -- Physics position (integer pixels)
    x = 100,
    y = 100,
    
    -- Previous position (for render interpolation)
    prevX = 100,
    prevY = 100,
    
    -- Sub-pixel accumulator
    xRemainder = 0,
    yRemainder = 0,
    
    -- Hitbox dimensions
    w = 8,
    h = 8,
    
    -- Velocity
    vx = 0,
    vy = 0,
    
    -- State flags
    grounded = false,
    onWall = 0,              -- -1 = left, 0 = none, 1 = right
    isWallSliding = false,
    
    -- Timers
    coyoteTimer = 0,
    jumpBufferTimer = 0,
    wallJumpTimer = 0,
    
    -- Variable jump tracking
    jumpHeld = false,
    varJumpApplied = false,
    
    -- Animation state
    animState = "Idle",
    
    -- Death
    dead = false,
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
    state.prevX = state.x
    state.prevY = state.y
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
    state.jumpHeld = false
    state.varJumpApplied = false
    state.animState = "Idle"
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
    
    -- Snapshot previous position for interpolation
    state.prevX = state.x
    state.prevY = state.y
    
    -- Ground check
    state.grounded = Map.checkSolid(state.x, state.y + state.h, state.w, 1)
    
    -- Input
    local inputX, inputY = Input:getAxis()
    
    -- Wall jump timer (locks horizontal input briefly)
    if state.wallJumpTimer > 0 then
        state.wallJumpTimer = state.wallJumpTimer - dt
        inputX = 0
    end
    
    -- Horizontal movement with acceleration
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
    if state.grounded then 
        state.coyoteTimer = PHYSICS.COYOTE_TIME
        state.varJumpApplied = false
    else
        state.coyoteTimer = math.max(0, state.coyoteTimer - dt)
    end
    
    -- Jump
    local jumpPressed = Input:consumeJump()
    local jumpHeldNow = Input:down("jump")
    
    if jumpPressed then
        if state.coyoteTimer > 0 then
            state.vy = PHYSICS.JUMP_FORCE
            state.coyoteTimer = 0
            state.varJumpApplied = false
        elseif state.isWallSliding or (not state.grounded and state.onWall ~= 0) then
            state.vy = PHYSICS.WALL_JUMP_FORCE_Y
            state.vx = -state.onWall * PHYSICS.WALL_JUMP_KICK_X
            state.wallJumpTimer = PHYSICS.WALL_JUMP_TIME
            state.isWallSliding = false
            state.varJumpApplied = false
        end
    end
    
    -- Variable jump height (only apply once when releasing)
    if state.jumpHeld and not jumpHeldNow and state.vy < 0 and not state.varJumpApplied then
        state.vy = state.vy * PHYSICS.VAR_JUMP_MULT
        state.varJumpApplied = true
    end
    state.jumpHeld = jumpHeldNow
    
    -- Move Y
    self:moveY(state.vy * dt, Map)
    
    -- Update animation state
    self:updateAnimState(inputX)
end

-- =============================================================================
-- SUB-PIXEL MOVEMENT (Celeste-style integer physics)
-- =============================================================================

function Player:moveX(amount, Map)
    state.xRemainder = state.xRemainder + amount
    -- CELESTE-CORRECT: Use floor for positive, ceil for negative
    local move = state.xRemainder >= 0 and math.floor(state.xRemainder) or math.ceil(state.xRemainder)
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
    -- CELESTE-CORRECT: Use floor for positive, ceil for negative
    local move = state.yRemainder >= 0 and math.floor(state.yRemainder) or math.ceil(state.yRemainder)
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
-- ANIMATION STATE MACHINE
-- =============================================================================

function Player:updateAnimState(inputX)
    if state.isWallSliding then
        state.animState = "WallSlide"
    elseif not state.grounded then
        if state.vy < 0 then
            state.animState = "Jump"
        else
            state.animState = "Fall"
        end
    elseif state.vx ~= 0 then
        state.animState = "Run"
    else
        state.animState = "Idle"
    end
end

-- =============================================================================
-- DRAW (with interpolation)
-- =============================================================================

function Player:draw(alpha, cameraX, cameraY)
    cameraX = cameraX or 0
    cameraY = cameraY or 0
    
    -- Interpolate between previous and current position
    local lerpX = state.prevX + (state.x - state.prevX) * alpha
    local lerpY = state.prevY + (state.y - state.prevY) * alpha
    
    -- Pixel-snap for clean rendering
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
    state.prevX = x
    state.prevY = y
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
