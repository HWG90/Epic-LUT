local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local api = Core.new()
local applied, removed, reject = 0, {}, false
local h = api.register({
    id = 'remove_test',
    name = 'Remove',
    pages = {
        {
            id = 'main',
            name = 'Main',
            require_confirmation = false,
            controls = {
                {
                    id = 'preset',
                    type = 'choice',
                    label = 'Presets',
                    presentation = 'dropdown',
                    choices = { 'Choose saved preset...', 'Alpha', 'Beta' },
                    default = 2,
                    on_change = function(index)
                        if index > 1 then
                            applied = applied + 1
                        end
                    end,
                },
            },
        },
    },
})
local mod = api.mods[h.id]
mod.tabs_top = true
mod.pages[1].render_layout = function(ui)
    ui.choice('preset', ui.x + 20, ui.y + 200, 420)
end
local control = mod.controls.preset
control.choice_details = { [2] = 'Armor + Helmet', [3] = 'Helmet Only' }
control.choice_previews = { [2] = { armor = { { 255, 0, 0 } }, helmet = { { 0, 0, 255 } } } }
control.on_delete_choice = function(index, label)
    assert(index > 1 and control.choices[index] == label, 'Stale deletion target')
    if reject then
        error('Deletion refused')
    end
    removed[#removed + 1] = label
    table.remove(control.choices, index)
    table.remove(control.choice_details, index)
    table.remove(control.choice_previews, index)
    if h.get('preset') == index then
        assert(h.set('preset', 1))
    end
    return true, 'Removed ' .. label
end
local menu = Menu.new(api, function(value, size)
    return #value * size * 0.5
end)
menu.visible, menu.window_width, menu.window_height = true, 1200, 850
local function compose()
    return menu.compose(1920, 1080)
end
local function click(x, y)
    for _, down in ipairs({ true, false }) do
        menu.tick({
            down = function(key)
                return down and key == 1
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
local function label(commands, value, popup)
    for _, c in ipairs(commands) do
        if c.type == 'text' and (c.full_text or c.text) == value and ((c.paint_plane or 0) >= 300) == popup then
            return c
        end
    end
    error('Label missing: ' .. value)
end
local function remove_button(commands, value)
    local item = label(commands, value, true)
    local best, difference
    for _, c in ipairs(commands) do
        if c.type == 'text' and c.text == 'X' and (c.paint_plane or 0) >= 300 then
            local dy = math.abs(c.y - item.y)
            if not difference or dy < difference then
                best, difference = c, dy
            end
        end
    end
    assert(best and difference < 16, 'Saved item lost its removal button')
    return best
end
local chosen = label(compose(), 'Alpha', false)
click(chosen.x + 3, chosen.y + 3)
assert(menu.dropdown)
local commands = compose()
local buttons = 0
for _, c in ipairs(commands) do
    if c.text == 'X' and (c.paint_plane or 0) >= 300 then
        buttons = buttons + 1
    end
end
assert(buttons == 2, 'Placeholder received a removal button, or a saved item lost it')
local delete = remove_button(commands, 'Beta')
click(delete.x + 3, delete.y + 2)
assert(menu.outfit_dialog and #removed == 0 and applied == 0, 'X deleted before confirmation')
local function dialog_click(value)
    for _, c in ipairs(compose()) do
        if c.type == 'text' and c.text == value then
            click(c.x + 3, c.y + 2)
            return
        end
    end
    error('Missing dialog action ' .. value)
end
dialog_click('Cancel')
assert(not menu.outfit_dialog and #removed == 0)
chosen = label(compose(), 'Alpha', false)
click(chosen.x + 3, chosen.y + 3)
delete = remove_button(compose(), 'Beta')
click(delete.x + 3, delete.y + 2)
reject = true
dialog_click('Delete Preset')
assert(menu.outfit_dialog and #removed == 0 and h.get('preset') == 2 and applied == 0)
reject = false
dialog_click('Delete Preset')
assert(not menu.outfit_dialog and removed[1] == 'Beta' and #control.choices == 2 and applied == 0)
chosen = label(compose(), 'Alpha', false)
click(chosen.x + 3, chosen.y + 3)
commands = compose()
delete = remove_button(commands, 'Alpha')
local preview_end
for _, c in ipairs(commands) do
    if c.type == 'rect' and c.ui_role == 'swatch_fill' and (c.paint_plane or 0) >= 300 then
        preview_end = math.max(preview_end or 0, c.x + c.w)
    end
end
assert(preview_end and preview_end < delete.x - 8, 'Removal overlaps swatches')
click(delete.x + 3, delete.y + 2)
control.choices[2] = 'Changed'
dialog_click('Delete Preset')
assert(menu.outfit_dialog and #removed == 1, 'Stale confirmation deleted another preset')
control.choices[2] = 'Alpha'
dialog_click('Delete Preset')
assert(removed[2] == 'Alpha' and h.get('preset') == 1 and applied == 0)
print('PASS dropdown deletion confirmation: cancellation, failure, stale identity, correct target, no apply')
