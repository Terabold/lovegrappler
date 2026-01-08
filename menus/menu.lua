-- menu.lua
local Menu = {}

local options = {
    { text = "Start Game", action = "start" },
    { text = "Settings", action = "settings" },
    { text = "Quit", action = "quit" }
}

-- Removed Scale option as per requirement to auto-scale without window resize
local settingsOptions = {
    { text = "Back", action = "back" },
    { text = "Fullscreen", type = "toggle", key = "fullscreen" },
    { text = "VSync", type = "toggle", key = "vsync" }
}

local state = "Main"
local selection = 1

-- Config Management
Menu.config = {
    fullscreen = false,
    vsync = true
}

function Menu:draw()
    love.graphics.setColor(1, 1, 1, 1)
    
    if state == "Main" then
        self:printCentered("Celeste Base", 20)
        
        for i, opt in ipairs(options) do
            local prefix = (i == selection) and "> " or "  "
            self:printCentered(prefix .. opt.text, 60 + i * 20)
        end
        
        love.graphics.setColor(0.5, 0.5, 0.5)
        self:printCentered("Control: Arrows + Z/Space", 150)
        
    elseif state == "Settings" then
        self:printCentered("Settings", 20)
        
        for i, opt in ipairs(settingsOptions) do
            local prefix = (i == selection) and "> " or "  "
            local valueStr = ""
            
            if opt.type == "toggle" then
                valueStr = ": " .. (Menu.config[opt.key] and "On" or "Off")
            end
            
            self:printCentered(prefix .. opt.text .. valueStr, 50 + i * 20)
        end
        
        love.graphics.setColor(0.5, 0.5, 0.5)
        self:printCentered("Auto-Scaling Enabled", 160)
    end
end

function Menu:keypressed(key)
    if key == "up" then
        selection = selection - 1
        local max = (state == "Main") and #options or #settingsOptions
        if selection < 1 then selection = max end
    elseif key == "down" then
        selection = selection + 1
        local max = (state == "Main") and #options or #settingsOptions
        if selection > max then selection = 1 end
    end
    
    if key == "return" or key == "z" or key == "space" or key == "right" or key == "left" then
        if state == "Main" then
            local action = options[selection].action
            if action == "start" then return "play"
            elseif action == "settings" then 
                state = "Settings"
                selection = 1
            elseif action == "quit" then love.event.quit() end
            
        elseif state == "Settings" then
            local opt = settingsOptions[selection]
            if opt.action == "back" then
                state = "Main"
                selection = 1
            elseif opt.type == "toggle" then
                Menu.config[opt.key] = not Menu.config[opt.key]
                self:applyConfig()
            end
        end
    end
end

function Menu:printCentered(text, y)
    local font = love.graphics.getFont()
    local width = font:getWidth(text)
    love.graphics.print(text, 160 - width/2, y)
end

function Menu:applyConfig()
    love.window.setVSync(Menu.config.vsync and 1 or 0)
    love.window.setFullscreen(Menu.config.fullscreen, "desktop")
end

return Menu
