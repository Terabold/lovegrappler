-- src/core/input.lua
-- Multi-Key Input with Jump Buffer

local Input = {}

-- Key bindings (multiple keys per action)
Input.keys = {
    jump = {"z", "space"},
    dash = {"x", "lshift"},
    grab = {"c", "lctrl"},
    crouch = {"down", "s"},
    left = {"left", "a"},
    right = {"right", "d"},
    up = {"up", "w"},
    down = {"down", "s"},
    confirm = {"z", "return", "space"},
    back = {"x", "escape"},
    menu_up = {"up", "w"},
    menu_down = {"down", "s"},
    menu_left = {"left", "a"},
    menu_right = {"right", "d"}
}

-- Buffered input
Input.jumpBufferTimer = 0
local BUFFER_TIME = 0.1

-- Just-pressed tracking
local keysPressed = {}

function Input:update(dt)
    self.jumpBufferTimer = math.max(0, self.jumpBufferTimer - dt)
    keysPressed = {}  -- Clear just-pressed
end

function Input:keypressed(key)
    keysPressed[key] = true
    if self:isKeyInAction(key, "jump") then
        self.jumpBufferTimer = BUFFER_TIME
    end
end

function Input:isKeyInAction(key, action)
    local bindings = self.keys[action]
    if bindings == nil then return false end
    if type(bindings) == "string" then 
        return key == bindings 
    end
    for _, k in ipairs(bindings) do
        if key == k then return true end
    end
    return false
end

function Input:down(action)
    local bindings = self.keys[action]
    if bindings == nil then return false end
    if type(bindings) == "string" then 
        return love.keyboard.isDown(bindings) 
    end
    for _, k in ipairs(bindings) do
        if love.keyboard.isDown(k) then return true end
    end
    return false
end

function Input:pressed(action)
    local bindings = self.keys[action]
    if bindings == nil then return false end
    if type(bindings) == "string" then 
        return keysPressed[bindings] or false
    end
    for _, k in ipairs(bindings) do
        if keysPressed[k] then return true end
    end
    return false
end

function Input:consumeJump()
    if self.jumpBufferTimer > 0 then
        self.jumpBufferTimer = 0
        return true
    end
    return false
end

function Input:getAxis()
    local x, y = 0, 0
    if self:down("left") then x = x - 1 end
    if self:down("right") then x = x + 1 end
    if self:down("up") then y = y - 1 end
    if self:down("down") then y = y + 1 end
    return x, y
end

return Input
