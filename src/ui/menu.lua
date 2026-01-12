-- src/ui/menu.lua
-- Settings Menu

local Input = require("core.input")

local UI = {}

local mainOptions = {
    { text = "Start Game", action = "play" },
    { text = "Level Editor", action = "editor" },
    { text = "Settings", action = "settings" },
    { text = "Quit", action = "quit" }
}

local settingsOptions = {
    { text = "Back", action = "back" },
    { text = "Resolution", type = "resolution" },
    { text = "Fullscreen", type = "toggle", key = "fullscreen" },
    { text = "VSync", type = "toggle", key = "vsync" },
    { text = "Show FPS", type = "toggle", key = "showFPS" },
}

local state = "main"
local selection = 1

local resolutions = {
    { w = 960,  h = 540,  name = "960x540 (3x)" },
    { w = 1280, h = 720,  name = "1280x720 (4x)" },
    { w = 1600, h = 900,  name = "1600x900 (5x)" },
    { w = 1920, h = 1080, name = "1920x1080 (6x)" },
}

UI.config = {
    resIndex = 2,
    fullscreen = false,
    vsync = true,
    showFPS = true,
}

local SETTINGS_FILE = "settings.dat"

function UI:loadSettings()
    if love.filesystem.getInfo(SETTINGS_FILE) then
        local contents = love.filesystem.read(SETTINGS_FILE)
        if contents then
            for line in contents:gmatch("[^\r\n]+") do
                local key, value = line:match("^([%w_]+)=(.+)$")
                if key and value then
                    if key == "resIndex" then
                        local idx = tonumber(value)
                        if idx and idx >= 1 and idx <= #resolutions then
                            UI.config.resIndex = idx
                        end
                    elseif key == "fullscreen" then
                        UI.config.fullscreen = (value == "true")
                    elseif key == "vsync" then
                        UI.config.vsync = (value == "true")
                    elseif key == "showFPS" then
                        UI.config.showFPS = (value == "true")
                    end
                end
            end
        end
    end
end

function UI:saveSettings()
    local data = string.format(
        "resIndex=%d\nfullscreen=%s\nvsync=%s\nshowFPS=%s\n",
        UI.config.resIndex,
        tostring(UI.config.fullscreen),
        tostring(UI.config.vsync),
        tostring(UI.config.showFPS)
    )
    love.filesystem.write(SETTINGS_FILE, data)
end

function UI:applySettings()
    local res = resolutions[UI.config.resIndex] or resolutions[2]
    
    local flags = {
        vsync = UI.config.vsync and 1 or 0,
        resizable = true,
        highdpi = true,
        minwidth = 320,
        minheight = 180
    }
    
    if UI.config.fullscreen then
        love.window.setMode(0, 0, flags)
        love.window.setFullscreen(true, "desktop")
    else
        love.window.setFullscreen(false)
        love.window.setMode(res.w, res.h, flags)
    end
end

function UI:draw()
    local W, H = love.graphics.getDimensions()
    local font = love.graphics.getFont()
    
    love.graphics.clear(0.08, 0.08, 0.12, 1)
    
    local title = (state == "main") and "CELESTE ENGINE" or "SETTINGS"
    love.graphics.setColor(1, 1, 1, 1)
    local titleWidth = font:getWidth(title)
    love.graphics.print(title, math.floor((W - titleWidth) / 2), math.floor(H * 0.2))
    
    local options = (state == "main") and mainOptions or settingsOptions
    local menuStartY = math.floor(H * 0.35)
    local itemSpacing = 40
    
    for i, opt in ipairs(options) do
        local y = menuStartY + (i - 1) * itemSpacing
        local isSelected = (i == selection)
        
        local lineText = opt.text
        local valueText = ""
        
        if opt.type == "toggle" then
            valueText = UI.config[opt.key] and "ON" or "OFF"
        elseif opt.type == "resolution" then
            valueText = resolutions[UI.config.resIndex].name
        end
        
        local fullText = lineText .. (valueText ~= "" and ": " .. valueText or "")
        local textWidth = font:getWidth(fullText)
        local textX = math.floor((W - textWidth) / 2)
        
        if isSelected then
            love.graphics.setColor(1, 0.8, 0.2, 1)
            love.graphics.print("> ", textX - font:getWidth("> "), y)
            love.graphics.print(" <", textX + textWidth, y)
        end
        
        if isSelected then
            love.graphics.setColor(1, 1, 1, 1)
        else
            love.graphics.setColor(0.6, 0.6, 0.6, 1)
        end
        love.graphics.print(lineText, textX, y)
        
        if valueText ~= "" then
            local colonX = textX + font:getWidth(lineText)
            love.graphics.print(": ", colonX, y)
            
            if isSelected then
                love.graphics.setColor(0.4, 0.9, 1, 1)
            else
                love.graphics.setColor(0.4, 0.5, 0.6, 1)
            end
            love.graphics.print(valueText, colonX + font:getWidth(": "), y)
        end
    end
    
    love.graphics.setColor(0.4, 0.4, 0.5, 1)
    local hint = state == "main" and "Arrow Keys: Navigate | Z/Space/Enter: Select" or "Up/Down: Navigate | Left/Right: Change | Escape: Back"
    local hintWidth = font:getWidth(hint)
    love.graphics.print(hint, math.floor((W - hintWidth) / 2), H - 50)
end

function UI:keypressed(key)
    local options = (state == "main") and mainOptions or settingsOptions
    
    if Input:isKeyInAction(key, "menu_up") then
        selection = selection - 1
        if selection < 1 then selection = #options end
    elseif Input:isKeyInAction(key, "menu_down") then
        selection = selection + 1
        if selection > #options then selection = 1 end
    end
    
    if state == "settings" then
        local opt = options[selection]
        
        if Input:isKeyInAction(key, "menu_left") or Input:isKeyInAction(key, "menu_right") then
            if opt.type == "resolution" then
                if Input:isKeyInAction(key, "menu_left") then
                    UI.config.resIndex = UI.config.resIndex - 1
                    if UI.config.resIndex < 1 then UI.config.resIndex = #resolutions end
                else
                    UI.config.resIndex = UI.config.resIndex + 1
                    if UI.config.resIndex > #resolutions then UI.config.resIndex = 1 end
                end
                self:applySettings()
                self:saveSettings()
            elseif opt.type == "toggle" then
                UI.config[opt.key] = not UI.config[opt.key]
                self:applySettings()
                self:saveSettings()
            end
        end
    end
    
    if Input:isKeyInAction(key, "confirm") then
        local opt = options[selection]
        
        if state == "main" then
            if opt.action == "play" then return "play"
            elseif opt.action == "editor" then return "editor"
            elseif opt.action == "settings" then state = "settings"; selection = 1
            elseif opt.action == "quit" then love.event.quit() end
        elseif state == "settings" then
            if opt.action == "back" then state = "main"; selection = 1; self:saveSettings()
            elseif opt.type == "toggle" then
                UI.config[opt.key] = not UI.config[opt.key]
                self:applySettings()
                self:saveSettings()
            end
        end
    end
    
    if Input:isKeyInAction(key, "back") and state == "settings" then
        state = "main"
        selection = 1
        self:saveSettings()
    end
    
    return nil
end

return UI
