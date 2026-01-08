-- menus/ui_components.lua
local UI = {}

-- Basic Button
UI.Button = {}
UI.Button.__index = UI.Button

function UI.Button.new(x, y, w, h, text)
    local self = setmetatable({}, UI.Button)
    self.x = x
    self.y = y
    self.w = w
    self.h = h
    self.text = text
    self.selected = false
    self.hovered = false
    return self
end

function UI.Button:update(dt, mouse_x, mouse_y, clicked)
    self.hovered = (mouse_x >= self.x and mouse_x <= self.x + self.w and
                    mouse_y >= self.y and mouse_y <= self.y + self.h)
    
    if self.hovered and clicked then
        return true
    end
    return false
end

function UI.Button:draw()
    local color = {0.2, 0.2, 0.2}
    local border = {0.5, 0.5, 0.5}
    
    if self.selected or self.hovered then
        color = {0.3, 0.3, 0.3}
        border = {1, 0.8, 0} -- Gold/Yellow accent
    end
    
    love.graphics.setColor(unpack(color))
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h, 5, 5) -- Rounded corners
    
    love.graphics.setColor(unpack(border))
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", self.x, self.y, self.w, self.h, 5, 5)
    
    love.graphics.setColor(1, 1, 1)
    local font = love.graphics.getFont()
    local text_w = font:getWidth(self.text)
    local text_h = font:getHeight()
    love.graphics.print(self.text, self.x + self.w/2 - text_w/2, self.y + self.h/2 - text_h/2)
end

return UI
