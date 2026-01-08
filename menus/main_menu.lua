-- menus/main_menu.lua
local UI = require("menus.ui_components")

local MainMenu = {}
MainMenu.__index = MainMenu

function MainMenu.new(game_ref)
    local self = setmetatable({}, MainMenu)
    self.game = game_ref
    self.selected_index = 1
    self.buttons = {}
    self:create_buttons()
    return self
end

function MainMenu:create_buttons()
    local w, h = love.graphics.getDimensions()
    local btn_w, btn_h = 200, 40
    local center_x = w/2 - btn_w/2
    local start_y = h/2
    
    self.buttons = {
        UI.Button.new(center_x, start_y, btn_w, btn_h, "Play"),
        UI.Button.new(center_x, start_y + 50, btn_w, btn_h, "Editor (WIP)"),
        UI.Button.new(center_x, start_y + 100, btn_w, btn_h, "Settings"),
        UI.Button.new(center_x, start_y + 150, btn_w, btn_h, "Quit")
    }
    self.buttons[self.selected_index].selected = true
end

function MainMenu:update(dt)
end

function MainMenu:keypressed(key)
    if key == "up" then
        self.buttons[self.selected_index].selected = false
        self.selected_index = self.selected_index - 1
        if self.selected_index < 1 then self.selected_index = #self.buttons end
        self.buttons[self.selected_index].selected = true
    elseif key == "down" then
        self.buttons[self.selected_index].selected = false
        self.selected_index = self.selected_index + 1
        if self.selected_index > #self.buttons then self.selected_index = 1 end
        self.buttons[self.selected_index].selected = true
    elseif key == "return" or key == "space" or key == "kpenter" then
        self:trigger_selection()
    end
end

function MainMenu:trigger_selection()
    local idx = self.selected_index
    if idx == 1 then
        self.game:start_game()
    elseif idx == 2 then
        -- Editor
        print("Editor not implemented yet")
    elseif idx == 3 then
        local SettingsMenu = require("menus.settings_menu")
        self.game.current_scn = SettingsMenu.new(self.game)
        self.game.state = "settings"
    elseif idx == 4 then
        love.event.quit()
    end
end

function MainMenu:draw()
    local w, h = love.graphics.getDimensions()
    
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("GRAVITY GRAPPLER", 0, h/4, w, "center")
    
    for _, btn in ipairs(self.buttons) do
        btn:draw()
    end
end

return MainMenu
