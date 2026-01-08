-- grapple.lua
-- Celeste-style Grappling Hook with Rope Physics
-- Uses raycast collision for precise attachment point detection

local Grapple = {}

-- =============================================================================
-- GRAPPLE CONSTANTS
-- =============================================================================
local GRAPPLE = {
    MAX_DISTANCE = 200,         -- Maximum grapple range (pixels)
    SWING_SPEED = 180,          -- How fast you swing on the rope
    PULL_SPEED = 120,           -- How fast rope pulls you in when shortening
    ROPE_ELASTICITY = 0.95,     -- Rope tension (1.0 = perfectly rigid)
    MIN_ROPE_LENGTH = 20,       -- Minimum rope length (pixels)
    SHORTEN_SPEED = 80,         -- How fast rope shortens (px/s)
    LENGTHEN_SPEED = 80,        -- How fast rope lengthens (px/s)

    -- Visual
    ROPE_SEGMENTS = 20,         -- Number of segments for rope rendering
    WAVE_AMPLITUDE = 4,         -- Rope wave amplitude
    WAVE_FREQUENCY = 2,         -- Rope wave frequency
    STRAIGHTEN_SPEED = 8,       -- How fast rope straightens
}

-- =============================================================================
-- GRAPPLE STATE
-- =============================================================================
local state = {
    -- Attachment point
    attachX = 0,
    attachY = 0,
    attached = false,

    -- Rope properties
    ropeLength = 0,
    targetRopeLength = 0,

    -- Animation
    waveSize = GRAPPLE.WAVE_AMPLITUDE,
    animTime = 0,
    shooting = false,
    shootProgress = 0,
}

-- =============================================================================
-- RAYCAST COLLISION (AABB-aware line intersection)
-- =============================================================================

-- Bresenham's line algorithm with AABB collision check
-- Returns: hitX, hitY, hitNormal (or nil if no collision)
function Grapple:raycast(x1, y1, x2, y2, Map)
    local dx = math.abs(x2 - x1)
    local dy = math.abs(y2 - y1)

    local sx = (x1 < x2) and 1 or -1
    local sy = (y1 < y2) and 1 or -1

    local err = dx - dy
    local x, y = x1, y1

    -- Step along the line
    while true do
        -- Check if current point is solid
        if Map.checkSolid(math.floor(x), math.floor(y), 1, 1) then
            -- Found collision! Return the point just before collision
            local hitX = x - sx
            local hitY = y - sy

            -- Calculate hit normal (which direction was hit)
            local normalX = 0
            local normalY = 0

            -- Check which side of the tile we hit
            if Map.checkSolid(math.floor(x - sx), math.floor(y), 1, 1) == false then
                normalX = -sx  -- Hit from horizontal direction
            end
            if Map.checkSolid(math.floor(x), math.floor(y - sy), 1, 1) == false then
                normalY = -sy  -- Hit from vertical direction
            end

            return math.floor(hitX), math.floor(hitY), normalX, normalY
        end

        -- Reached target without collision
        if x == x2 and y == y2 then
            break
        end

        -- Step to next pixel
        local e2 = 2 * err
        if e2 > -dy then
            err = err - dy
            x = x + sx
        end
        if e2 < dx then
            err = err + dx
            y = y + sy
        end
    end

    return nil  -- No collision found
end

-- =============================================================================
-- SHOOT GRAPPLE
-- =============================================================================

function Grapple:shoot(playerX, playerY, playerW, playerH, targetX, targetY, Map)
    -- Calculate shoot direction from player center
    local startX = playerX + playerW / 2
    local startY = playerY + playerH / 2

    -- Calculate direction
    local dx = targetX - startX
    local dy = targetY - startY
    local dist = math.sqrt(dx * dx + dy * dy)

    -- Normalize and clamp to max distance
    if dist > GRAPPLE.MAX_DISTANCE then
        dx = dx / dist * GRAPPLE.MAX_DISTANCE
        dy = dy / dist * GRAPPLE.MAX_DISTANCE
        dist = GRAPPLE.MAX_DISTANCE
    end

    -- Cast ray to find attachment point
    local hitX, hitY, normalX, normalY = self:raycast(
        startX, startY,
        startX + dx, startY + dy,
        Map
    )

    if hitX then
        -- Found attachment point!
        state.attachX = hitX
        state.attachY = hitY
        state.attached = true
        state.shooting = true
        state.shootProgress = 0

        -- Calculate initial rope length
        local ropeX = hitX - startX
        local ropeY = hitY - startY
        state.ropeLength = math.sqrt(ropeX * ropeX + ropeY * ropeY)
        state.targetRopeLength = state.ropeLength
        state.waveSize = GRAPPLE.WAVE_AMPLITUDE
        state.animTime = 0

        return true
    end

    return false  -- No valid attachment point
end

-- =============================================================================
-- RELEASE GRAPPLE
-- =============================================================================

function Grapple:release()
    state.attached = false
    state.shooting = false
end

-- =============================================================================
-- UPDATE GRAPPLE PHYSICS
-- =============================================================================

function Grapple:update(dt, player, Input)
    if not state.attached then
        return
    end

    state.animTime = state.animTime + dt

    -- Shooting animation
    if state.shooting then
        state.shootProgress = math.min(1, state.shootProgress + dt * 8)
        if state.shootProgress >= 1 then
            state.shooting = false
        end
    else
        -- Rope straightening animation
        if state.waveSize > 0 then
            state.waveSize = math.max(0, state.waveSize - GRAPPLE.STRAIGHTEN_SPEED * dt)
        end
    end

    -- Rope length control
    if Input:down("up") then
        state.targetRopeLength = math.max(GRAPPLE.MIN_ROPE_LENGTH,
            state.targetRopeLength - GRAPPLE.SHORTEN_SPEED * dt)
    end
    if Input:down("down") then
        state.targetRopeLength = state.targetRopeLength + GRAPPLE.LENGTHEN_SPEED * dt
    end

    -- Smoothly interpolate rope length
    state.ropeLength = state.ropeLength + (state.targetRopeLength - state.ropeLength) * 5 * dt

    -- Calculate rope physics
    local playerCenterX = player.x + player.w / 2
    local playerCenterY = player.y + player.h / 2

    local ropeX = state.attachX - playerCenterX
    local ropeY = state.attachY - playerCenterY
    local currentDist = math.sqrt(ropeX * ropeX + ropeY * ropeY)

    -- Only apply rope physics if stretched beyond length
    if currentDist > state.ropeLength then
        -- Normalize rope direction
        local ropeNormX = ropeX / currentDist
        local ropeNormY = ropeY / currentDist

        -- Calculate how much rope is overstretched
        local stretchAmount = currentDist - state.ropeLength

        -- Apply rope tension (pull player toward attach point)
        local pullForce = stretchAmount * GRAPPLE.ROPE_ELASTICITY

        player.vx = player.vx + ropeNormX * pullForce * dt * 60
        player.vy = player.vy + ropeNormY * pullForce * dt * 60

        -- Apply swinging physics (perpendicular to rope)
        local perpX = -ropeNormY
        local perpY = ropeNormX

        -- Player input adds swing velocity
        local swingInput = 0
        if Input:down("left") then swingInput = swingInput - 1 end
        if Input:down("right") then swingInput = swingInput + 1 end

        player.vx = player.vx + perpX * swingInput * GRAPPLE.SWING_SPEED * dt
        player.vy = player.vy + perpY * swingInput * GRAPPLE.SWING_SPEED * dt
    end
end

-- =============================================================================
-- DRAW GRAPPLE ROPE
-- =============================================================================

function Grapple:draw(playerX, playerY, playerW, playerH)
    if not state.attached then
        return
    end

    local startX = playerX + playerW / 2
    local startY = playerY + playerH / 2

    local segments = GRAPPLE.ROPE_SEGMENTS
    local points = {}

    -- Calculate rope curve
    for i = 0, segments do
        local t = i / segments

        -- Apply shooting animation
        if state.shooting then
            t = t * state.shootProgress
        end

        -- Linear interpolation
        local x = startX + (state.attachX - startX) * t
        local y = startY + (state.attachY - startY) * t

        -- Add wave deformation (perpendicular to rope)
        if state.waveSize > 0 then
            local ropeX = state.attachX - startX
            local ropeY = state.attachY - startY
            local ropeDist = math.sqrt(ropeX * ropeX + ropeY * ropeY)

            if ropeDist > 0 then
                -- Perpendicular direction
                local perpX = -ropeY / ropeDist
                local perpY = ropeX / ropeDist

                -- Wave pattern
                local wave = math.sin(t * math.pi * GRAPPLE.WAVE_FREQUENCY + state.animTime * 4)
                wave = wave * math.sin(t * math.pi)  -- Taper at ends
                wave = wave * state.waveSize

                x = x + perpX * wave
                y = y + perpY * wave
            end
        end

        table.insert(points, x)
        table.insert(points, y)
    end

    -- Draw rope as connected line segments
    love.graphics.setColor(0.8, 0.8, 0.8, 1)
    love.graphics.setLineWidth(2)
    if #points >= 4 then
        love.graphics.line(points)
    end

    -- Draw attachment point
    love.graphics.setColor(1, 1, 0, 1)
    love.graphics.circle("fill", state.attachX, state.attachY, 3)
end

-- =============================================================================
-- GETTERS
-- =============================================================================

function Grapple:isAttached()
    return state.attached
end

function Grapple:getAttachPoint()
    return state.attachX, state.attachY
end

function Grapple:getRopeLength()
    return state.ropeLength
end

return Grapple
