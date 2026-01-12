-- src/core/game.lua
local Map = require("world.map")
local Input = require("core.input")

local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local lg = love.graphics

local GW, GH, TILE = 320, 180, 8

-- Physics constants (inlined for speed)
local MAX_RUN, RUN_ACCEL, RUN_REDUCE, AIR_MULT = 90, 1000, 400, 0.65
local JUMP_SPD, JUMP_H, VAR_TIME, GRACE = -105, 40, 0.2, 0.1
local GRAV, MAX_FALL, HALF_TH = 900, 160, 40
local WALL_SLIDE, WALL_H, WALL_TIME = 20, 130, 0.16
local STAMINA_MAX, CLIMB_UP, CLIMB_SLIP = 110, -45, 30
local H_NORM, H_DUCK, CORNER = 11, 6, 4

-- Pre-allocated colors (r,g,b as array for speed)
local TC = {{.6,.8,1},{.5,.4,.3},{.8,.5,.7},{.4,.4,.5},{.9,.4,.6},{.2,.8,.8},{.6,.4,.2},{.4,.6,.9},{.5,.5,.5},{.4,.4,.4},{.6,.6,.6}}

-- Player state (all locals for speed)
local px, py, pw, ph = 50, 140, 7, H_NORM
local vx, vy, rx, ry = 0, 0, 0, 0
local grounded, onWall, facing = false, 0, 1
local ducking, climbing, stamina = false, false, STAMINA_MAX
local graceT, varT, varSpd, wallT = 0, 0, 0, 0
local dead = false

-- Camera
local camX, camY = 0, 0

-- Transition
local trActive, trPhase, trTimer, trAlpha = false, 0, 0, 0
local trRoom, trLock = nil, 0
local TR_DUR, TR_LOCK = 0.12, 0.05

-- Respawn
local spX, spY, spRoom = 50, 140, nil

local canvas
local Game = {}

-- Inline helpers
local function sign(x) return x > 0 and 1 or x < 0 and -1 or 0 end
local function appr(v, t, d) return v < t and min(v + d, t) or max(v - d, t) end
local function solid(x, y, w, h) return Map.checkSolid(x, y, w, h) end

-- Movement with remainder system
local function moveX(amt)
    rx = rx + amt
    local mv = floor(rx + 0.5)
    if mv == 0 then return end
    rx = rx - mv
    local s = sign(mv)
    while mv ~= 0 do
        if not solid(px + s, py, pw, ph) then
            px, mv = px + s, mv - s
        else
            for n = 1, CORNER do
                if not solid(px + s, py - n, pw, ph) then px, py, mv = px + s, py - n, mv - s break end
                if not solid(px + s, py + n, pw, ph) then px, py, mv = px + s, py + n, mv - s break end
            end
            if mv ~= 0 and (solid(px + s, py, pw, ph)) then vx, rx = 0, 0 return end
        end
    end
end

local function moveY(amt)
    ry = ry + amt
    local mv = floor(ry + 0.5)
    if mv == 0 then return end
    ry = ry - mv
    local s = sign(mv)
    while mv ~= 0 do
        if not solid(px, py + s, pw, ph) then
            py, mv = py + s, mv - s
        else
            if s < 0 then
                for n = 1, CORNER do
                    if not solid(px - n, py + s, pw, ph) then px, py, mv = px - n, py + s, mv - s break end
                    if not solid(px + n, py + s, pw, ph) then px, py, mv = px + n, py + s, mv - s break end
                end
                if mv ~= 0 and solid(px, py + s, pw, ph) then vy, ry = 0, 0 return end
            else
                grounded, vy, ry = true, 0, 0 return
            end
        end
    end
end

local function depenetrate()
    if not solid(px, py, pw, ph) then return end
    for d = 1, 8 do
        if not solid(px, py - d, pw, ph) then py = py - d return end
        if not solid(px - d, py, pw, ph) then px = px - d return end
        if not solid(px + d, py, pw, ph) then px = px + d return end
        if not solid(px, py + d, pw, ph) then py = py + d return end
    end
end

-- Camera: small rooms lock to room origin, large rooms follow player
local function updateCam()
    local r = Map.currentRoom
    if not r then return end
    
    -- Small room: camera = room origin (room draws at screen 0,0)
    -- Large room: follow player with edge clamping
    if r.w <= GW then camX = r.x
    else camX = floor(max(r.x, min(px + pw/2 - GW/2, r.x + r.w - GW))) end
    
    if r.h <= GH then camY = r.y
    else camY = floor(max(r.y, min(py + ph/2 - GH/2, r.y + r.h - GH))) end
end

-- Transition
local function startTr(room)
    if trActive then return end
    trActive, trPhase, trTimer, trRoom = true, 1, 0, room
end

local function updateTr(dt)
    if trLock > 0 then trLock = trLock - dt end
    if not trActive then return false end
    
    trTimer = trTimer + dt
    
    if trPhase == 1 then -- Fade out
        trAlpha = min(1, trTimer / TR_DUR)
        if trTimer >= TR_DUR then
            trAlpha = 1
            Map.currentRoom = trRoom
            px = floor(trRoom.x + trRoom.spawnX - pw/2)
            py = floor(trRoom.y + trRoom.spawnY - ph)
            rx, ry, vx, vy = 0, 0, 0, 0
            depenetrate()
            if (trRoom.order or 0) > (spRoom and spRoom.order or 0) then
                spRoom, spX, spY = trRoom, trRoom.x + trRoom.spawnX, trRoom.y + trRoom.spawnY
            end
            updateCam()
            trPhase, trTimer = 2, 0
        end
    elseif trPhase == 2 then -- Fade in
        trAlpha = 1 - min(1, trTimer / TR_DUR)
        if trTimer >= TR_DUR then
            trActive, trPhase, trAlpha, trLock = false, 0, 0, TR_LOCK
        end
    end
    return true -- Block movement during any transition phase
end

local function checkTr()
    local r = Map.currentRoom
    if not r or trActive then return end
    local cx, cy = px + pw/2, py + ph/2
    if cx >= r.x and cx < r.x + r.w and cy >= r.y and cy < r.y + r.h then return end
    local rooms = Map.rooms
    for i = 1, #rooms do
        local rm = rooms[i]
        if not rm.isFiller and rm ~= r and cx >= rm.x and cx < rm.x + rm.w and cy >= rm.y and cy < rm.y + rm.h then
            startTr(rm) return
        end
    end
end

local function checkHazard()
    local r = Map.currentRoom
    if not r then return false end
    local hz = r.hazards or r.entities
    if not hz then return false end
    local rx, ry = r.x, r.y
    for i = 1, #hz do
        local h = hz[i]
        local t = h.type
        if t and t:find("spike") then
            local hx, hy, hw, hh = rx + (h.x-1)*TILE, ry + (h.y-1)*TILE, TILE, TILE
            if t == "spike_up" then hy, hh = hy + 4, 4
            elseif t == "spike_down" then hh = 4
            elseif t == "spike_left" then hx, hw = hx + 4, 4
            elseif t == "spike_right" then hw = 4 end
            if px < hx + hw and px + pw > hx and py < hy + hh and py + ph > hy then return true end
        end
    end
    return false
end

function Game:load()
    canvas = lg.newCanvas(GW, GH)
    canvas:setFilter("nearest", "nearest")
    if not Map.load("world.lua") then Map.createDefaultWorld() end
    if Map.rooms[1] then
        Map.currentRoom = Map.rooms[1]
        spRoom = Map.currentRoom
        spX, spY = spRoom.x + spRoom.spawnX, spRoom.y + spRoom.spawnY
    end
    self:respawnPlayer()
end

function Game:respawnPlayer()
    px, py = floor(spX - pw/2), floor(spY - ph)
    rx, ry, vx, vy = 0, 0, 0, 0
    depenetrate()
    grounded = solid(px, py + 1, pw, ph)
    onWall, ducking, climbing, facing = 0, false, false, 1
    graceT, varT, varSpd, wallT = 0, 0, 0, 0
    stamina, dead, ph = STAMINA_MAX, false, H_NORM
    trActive, trPhase, trAlpha, trLock = false, 0, 0, 0
    updateCam()
end
Game.reset = Game.respawnPlayer

function Game:update(dt)
    if dead then
        if Input:pressed("jump") or Input:pressed("dash") then self:respawnPlayer() end
        return
    end
    
    -- Transition blocks ALL movement
    if updateTr(dt) then return end
    
    -- Small lock after transition
    local canMove = trLock <= 0
    
    -- Timers
    if graceT > 0 then graceT = graceT - dt end
    if varT > 0 then varT = varT - dt end
    if wallT > 0 then wallT = wallT - dt end
    
    grounded = solid(px, py + 1, pw, ph)
    if grounded then graceT, stamina = GRACE, STAMINA_MAX end
    
    onWall = 0
    if solid(px - 1, py, 1, ph) then onWall = -1 end
    if solid(px + pw, py, 1, ph) then onWall = 1 end
    
    local ix = 0
    if canMove then
        if Input:down("left") then ix = -1 end
        if Input:down("right") then ix = 1 end
    end
    if ix ~= 0 then facing = ix end
    
    local jp = canMove and Input:consumeJump() or false
    local jh = canMove and Input:down("jump") or false
    local gh = canMove and Input:down("grab") or false
    local dh = canMove and Input:down("down") or false
    
    -- Duck
    if grounded and dh and not ducking then
        ducking, ph, py = true, H_DUCK, py + H_NORM - H_DUCK
    elseif ducking and (not dh or not grounded) then
        if not solid(px, py - (H_NORM - H_DUCK), pw, H_NORM) then
            ducking, ph, py = false, H_NORM, py - (H_NORM - H_DUCK)
        end
    end
    
    -- Climb
    local canClimb = onWall ~= 0 and gh and stamina > 0 and not ducking
    if canClimb and not climbing then climbing, vy = true, 0
    elseif climbing and not canClimb then climbing = false end
    
    if climbing then
        stamina = stamina - 10 * dt
        if Input:down("up") then vy, stamina = CLIMB_UP, stamina - 35 * dt
        elseif Input:down("down") then vy = CLIMB_SLIP
        else vy = 0 end
        if stamina <= 0 then climbing, stamina = false, 0 end
    end
    
    local pushW = (onWall == -1 and ix == -1) or (onWall == 1 and ix == 1)
    
    -- Horizontal
    if not climbing then
        local m = grounded and 1 or AIR_MULT
        local mx = ducking and MAX_RUN/2 or MAX_RUN
        if wallT <= 0 then
            vx = ix ~= 0 and appr(vx, ix * mx, RUN_ACCEL * m * dt) or appr(vx, 0, RUN_REDUCE * m * dt)
        end
    else vx = 0 end
    
    -- Jump
    if jp then
        if graceT > 0 and not climbing then
            vy, varT, varSpd, graceT = JUMP_SPD, VAR_TIME, JUMP_SPD, 0
            if ix ~= 0 then vx = vx + ix * JUMP_H end
        elseif climbing then
            climbing, vy, varT, varSpd = false, JUMP_SPD, VAR_TIME, JUMP_SPD
            if ix ~= 0 and ix ~= onWall then vx, wallT = ix * WALL_H, WALL_TIME end
            stamina = stamina - 27.5
        elseif onWall ~= 0 and not grounded then
            vy, vx, varT, varSpd, wallT = JUMP_SPD, -onWall * WALL_H, VAR_TIME, JUMP_SPD, WALL_TIME
        end
    end
    
    -- Var jump
    if varT > 0 then
        if jh then vy = min(vy, varSpd) else varT = 0 end
    end
    
    -- Gravity
    if not grounded and not climbing then
        local mf = (onWall ~= 0 and vy > 0 and pushW) and WALL_SLIDE or MAX_FALL
        local gm = (abs(vy) < HALF_TH and jh) and 0.5 or 1
        vy = appr(vy, mf, GRAV * gm * dt)
    end
    
    moveX(vx * dt)
    moveY(vy * dt)
    depenetrate()
    grounded = solid(px, py + 1, pw, ph)
    
    if checkHazard() then dead = true return end
    checkTr()
    if not trActive then updateCam() end
end

function Game:draw()
    lg.setCanvas(canvas)
    lg.clear(0, 0, 0, 1)
    
    local r = Map.currentRoom
    if not r then lg.setCanvas() return canvas end
    
    -- Scissor to EXACTLY room size on screen (prevents seeing outside)
    local scrX, scrY = r.x - camX, r.y - camY
    local sW, sH = min(GW, r.w), min(GH, r.h)
    local sX, sY = max(0, scrX), max(0, scrY)
    sW, sH = min(sW, GW - sX), min(sH, GH - sY)
    
    lg.setScissor(sX, sY, sW, sH)
    lg.push()
    lg.translate(-camX, -camY)
    
    -- Background
    lg.setColor(0.1, 0.1, 0.15)
    lg.rectangle("fill", r.x, r.y, r.w, r.h)
    
    -- Tiles
    local tiles, rx, ry = r.tiles, r.x, r.y
    if tiles then
        for row = 1, #tiles do
            local tr = tiles[row]
            if tr then
                local ty = ry + (row - 1) * TILE
                for col = 1, #tr do
                    local v = tr[col]
                    if v and v > 0 then
                        local c = TC[v] or TC[1]
                        lg.setColor(c[1], c[2], c[3])
                        lg.rectangle("fill", rx + (col - 1) * TILE, ty, TILE, TILE)
                    end
                end
            end
        end
    end
    
    -- Hazards
    local hz = r.hazards or r.entities
    if hz then
        lg.setColor(1, 0.3, 0.3)
        for i = 1, #hz do
            local h = hz[i]
            local t = h.type
            if t and t:find("spike") then
                local x, y = rx + (h.x - 1) * TILE, ry + (h.y - 1) * TILE
                if t == "spike_up" then lg.polygon("fill", x+4,y+2, x+7,y+7, x+1,y+7)
                elseif t == "spike_down" then lg.polygon("fill", x+4,y+6, x+7,y+1, x+1,y+1)
                elseif t == "spike_left" then lg.polygon("fill", x+2,y+4, x+7,y+1, x+7,y+7)
                elseif t == "spike_right" then lg.polygon("fill", x+6,y+4, x+1,y+1, x+1,y+7) end
            end
        end
    end
    
    -- Player
    lg.setColor(climbing and 0.2 or ducking and 1 or 1, climbing and 0.8 or ducking and 0.5 or 0.2, climbing and 1 or ducking and 0.2 or 0.3)
    lg.rectangle("fill", px, py, pw, ph)
    
    -- Stamina
    if onWall ~= 0 and not grounded then
        local bx = px + pw/2 - 10
        lg.setColor(0.2, 0.2, 0.2, 0.8)
        lg.rectangle("fill", bx, py - 8, 20, 3)
        local p = stamina / STAMINA_MAX
        lg.setColor(p > 0.5 and 0.3 or p > 0.25 and 1 or 1, p > 0.5 and 1 or p > 0.25 and 1 or 0.3, p > 0.5 and 0.3 or 0.3)
        lg.rectangle("fill", bx, py - 8, 20 * p, 3)
    end
    
    lg.pop()
    lg.setScissor()
    lg.setCanvas()
    return canvas
end

function Game:drawTransition(x, y, w, h)
    if trAlpha > 0 then
        lg.setColor(0, 0, 0, trAlpha)
        lg.rectangle("fill", x, y, w, h)
    end
end

function Game:getCurrentRoom() return Map.currentRoom end
function Game:getPlayerState() return {x=px, y=py, speedX=vx, speedY=vy} end
function Game:getCanvasDimensions() return GW, GH end

return Game
