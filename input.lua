-- input.lua (Multi-Key Support + Jump Buffer)
local Input = {}

-- Key bindings (multiple keys per action for WASD + Arrows)
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

-- Jump buffer (same as Celeste ~0.1 seconds)
Input.jumpBufferTimer = 0
local BUFFER_TIME = 0.1

function Input:update(dt)
    self.jumpBufferTimer = math.max(0, self.jumpBufferTimer - dt)
end

function Input:keypressed(key)
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

function Input:getKeyName(action)
    local bindings = self.keys[action]
    if bindings == nil then return "?" end
    if type(bindings) == "string" then return bindings end
    return bindings[1] or "?"
end

function Input:rebind(action, key)
    local bindings = self.keys[action]
    if bindings == nil then return end
    if type(bindings) == "string" then
        self.keys[action] = key
    else
        self.keys[action][1] = key
    end
end

return Input