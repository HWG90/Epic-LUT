local api = dofile('vendor/menu/core.lua').new({
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
})
api.register({ id = 'test', name = 'Test', pages = { { id = 'p', name = 'Page', controls = {} } } })
local menu = dofile('vendor/menu/menu.lua').new(api)
menu.visible = true
menu.epic_typography = true
local saves, suppress = 0, 0
local function open(fail)
    menu.outfit_dialog = {
        phase = 'delete',
        title = 'Overwrite Row Preset?',
        preset_name = 'Row',
        description = 'Replace row?',
        action_label = 'Overwrite Row',
        on_save = function()
            if fail then
                error('write failed')
            end
            saves = saves + 1
            return 'Saved'
        end,
        on_suppress = function()
            suppress = suppress + 1
            return true
        end,
    }
end
local function label(name)
    for _, c in ipairs(menu.compose(1920, 1080)) do
        if c.text == name then
            return c
        end
    end
    error('Missing label ' .. name)
end
local function click(x, y)
    for _, down in ipairs({ true, false }) do
        menu.tick({
            down = function(k)
                return down and k == 1
            end,
            mouse = function()
                return x, y
            end,
            wheel = function()
                return 0
            end,
        })
    end
end
open()
local text = label("Don't show this again")
click(text.x - 20 * menu.window_bounds.scale, text.y + 2)
assert(menu.outfit_dialog.dont_show_again)
local button = label('Cancel')
click(button.x + 2, button.y + 2)
assert(not menu.outfit_dialog and saves == 0 and suppress == 0)
open(true)
text = label("Don't show this again")
click(text.x - 20 * menu.window_bounds.scale, text.y + 2)
button = label('Overwrite Row')
click(button.x + 2, button.y + 2)
assert(menu.outfit_dialog and suppress == 0 and saves == 0)
open()
text = label("Don't show this again")
click(text.x - 20 * menu.window_bounds.scale, text.y + 2)
button = label('Overwrite Row')
click(button.x + 2, button.y + 2)
assert(not menu.outfit_dialog and saves == 1 and suppress == 1)
print('PASS overwrite checkbox, cancellation, failed save and successful suppression')
