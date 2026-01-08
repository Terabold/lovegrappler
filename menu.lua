-- menu.lua
local Input = require("input")

local Menu = {}

local options = {
    { text = "Start Game", action = "start" },
    { text = "Settings", action = "settings" },
    { text = "Quit", action = "quit" }
}

-- Rebind State
local isRebinding = false
local rebindAction = nil

local settingsOptions = {
    { text = "Back", action = "back" },
    { text = "Fullscreen", type = "toggle", key = "fullscreen" },
    { text = "VSync", type = "toggle", key = "vsync" },
    { text = "Jump Bind: ", type = "bind", action = "jump" },
    { text = "Dash Bind: ", type = "bind", action = "dash" }
}

local state = "Main"
local selection = 1

-- Config
Menu.config = {
    fullscreen = false,
    vsync = true
}

function Menu:draw()
    love.graphics.setColor(1, 1, 1, 1)
    local W = 1280
    local H = 720
    
    if isRebinding then
        self:printCentered("Press any key to bind " .. rebindAction, H/2 - 20)
        return
    end
    
    if state == "Main" then
        self:printCentered("CELESTE ENGINE", H/3)
        for i, opt in ipairs(options) do
            local prefix = (i == selection) and "> " or "  "
            self:printCentered(prefix .. opt.text, H/2 + i * 30)
        end
    elseif state == "Settings" then
        self:printCentered("SETTINGS", H/5)
        for i, opt in ipairs(settingsOptions) do
            local prefix = (i == selection) and "> " or "  "
            local str = prefix .. opt.text
            
            if opt.type == "toggle" then
                str = str .. (Menu.config[opt.key] and "On" or "Off")
            elseif opt.type == "bind" then
                str = str .. string.upper(Input.keys[opt.action])
            end
            
            self:printCentered(str, H/3 + i * 30)
        end
        self:printCentered("Arrow Keys to Navigate, " .. string.upper(Input.keys.confirm) .. " to Select", H - 50)
    end
end

function Menu:keypressed(key)
    if isRebinding then
        Input:setBind(rebindAction, key)
        isRebinding = false
        rebindAction = nil
        return
    end

    if key == Input.keys.up then
        selection = selection - 1
        local max = (state == "Main") and #options or #settingsOptions
        if selection < 1 then selection = max end
    elseif key == Input.keys.down then
        selection = selection + 1
        local max = (state == "Main") and #options or #settingsOptions
        if selection > max then selection = 1 end
    end
    
    if key == Input.keys.confirm or key == "return" then
        if state == "Main" then
            local act = options[selection].action
            if act == "start" then return "play"
            elseif act == "settings" then state = "Settings"; selection = 1
            elseif act == "quit" then love.event.quit() end
        elseif state == "Settings" then
            local opt = settingsOptions[selection]
            if opt.action == "back" then state = "Main"; selection = 1
            elseif opt.type == "toggle" then
                Menu.config[opt.key] = not Menu.config[opt.key]
                self:applyConfig()
            elseif opt.type == "bind" then
                isRebinding = true
                rebindAction = opt.action
            end
        end
    end
end

function Menu:printCentered(text, y)
    local font = love.graphics.getFont()
    local width = font:getWidth(text)
    -- We assume drawing to screen here
    love.graphics.print(text, 1280/2 - width/2, y)
end

function Menu:applyConfig()
    love.window.setVSync(Menu.config.vsync and 1 or 0)
    love.window.setFullscreen(Menu.config.fullscreen, "desktop")
end

return Menu
