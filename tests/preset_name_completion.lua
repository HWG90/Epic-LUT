-- Real naming modal: autocomplete edits a draft, never a control/preset/native
-- transaction. Enter/Save retain the same explicit on_save ownership.
local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local Text = dofile('src/platform/text_editor.lua')
local api, writes, saves = Core.new(), 0, 0
local stored, saved_scope = { ['Armor Alpha'] = 'existing' }
local handle = api.register({
    id = 'name_completion',
    name = 'Epic LUT',
    pages = {
        {
            id = 'armory',
            name = 'The Armory',
            require_confirmation = false,
            controls = {
                {
                    id = 'outfit_name',
                    type = 'input',
                    label = 'Outfit name',
                    default = 'my-outfit',
                    on_change = function()
                        writes = writes + 1
                    end,
                },
            },
        },
    },
})
local mod, menu = api.mods[handle.id]
menu = Menu.new(api, function(value, size)
    return #value * size * 0.5
end, Text)
menu.visible, menu.epic_typography = true, true
menu.window_width, menu.window_height = 1100, 1000
local names = { 'Zebra', 'Arctic Gold', 'ARCTIC Blue', 'Armor Delta', 'Armor Alpha', 'Arctic', 'Alpha', 'Alpha Long' }
local inventory = table.concat(names, '|')
local function start(draft, complete)
    local dialog = {
        phase = 'name',
        mod = mod,
        control = mod.controls.outfit_name,
        names = complete ~= false and names or nil,
        save_kind = { armor = true, helmet = false, cape = true },
        on_save = function(name, scope)
            assert(name:match('^[%w _-]+$') and #name > 0 and #name <= 48, 'Invalid preset name')
            saves, stored[name], saved_scope = saves + 1, 'saved', scope
        end,
    }
    menu.outfit_dialog = dialog
    menu.text_edit =
        { mod = mod, control = dialog.control, text = draft or '', cursor = #(draft or ''), replace = false }
    return dialog, menu.text_edit
end
local function compose()
    local commands = menu.compose(1920, 1080)
    for _, command in ipairs(commands) do
        assert(not (command.text and command.text:find('attempt to ', 1, true)), command.text)
    end
    assert(table.concat(names, '|') == inventory, 'Completion reordered the storage inventory')
    return commands
end
local function label(value)
    for _, command in ipairs(compose()) do
        if command.full_text == value or command.text == value then
            return command
        end
    end
end
local function hint()
    for _, command in ipairs(compose()) do
        if (command.full_text or command.text or ''):match('^Tab: ') then
            return command
        end
    end
end
local function click(command)
    assert(command, 'Missing naming button')
    for _, down in ipairs({ true, false }) do
        menu.tick({
            down = function(key)
                return down and key == 1
            end,
            mouse = function()
                return command.x + 2, command.y + 2
            end,
        }, 0)
    end
end
local function unchanged(dialog, editor, text, before)
    assert(menu.visible and menu.outfit_dialog == dialog and menu.text_edit == editor and editor.text == text)
    assert(
        saves == before and writes == 0 and handle.get('outfit_name') == 'my-outfit',
        'Completion saved a preset or edited its backing control'
    )
end
for _, draft in ipairs({ '', 'Unknown', 'Alpha', 'Arctic' }) do
    local dialog, editor = start(draft)
    assert(not hint(), 'Empty, unmatched or already-complete name offered another preset')
    local before = saves
    menu.key(9)
    unchanged(dialog, editor, draft, before)
    click(label('Cancel'))
    assert(not menu.outfit_dialog and not menu.text_edit and saves == before and menu.visible)
end
local dialog, editor = start('armo')
local before = saves
assert(label('Tab: Armor Alpha'), 'Prefix match did not choose the alphabetically first case-insensitive name')
menu.key(9)
unchanged(dialog, editor, 'Armor Alpha', before)
assert(editor.cursor == #'Armor Alpha' and editor.anchor == editor.cursor and not editor.replace)
menu.key(90, true)
assert(editor.text == 'armo', 'Draft Undo did not restore the typed prefix')
menu.key(89, true)
assert(editor.text == 'Armor Alpha' and saves == before and writes == 0)
menu.key(13)
assert(saves == before + 1 and stored['Armor Alpha'] == 'saved' and not menu.outfit_dialog and not menu.text_edit)
assert(saved_scope.armor and not saved_scope.helmet and saved_scope.cape, 'Completion changed the save scope')
assert(writes == 0, 'Naming Enter bypassed the existing save callback')

dialog, editor = start('arctic ')
assert(label('Tab: ARCTIC Blue'))
menu.key(9, false, true)
assert(editor.text == 'arctic ', 'Shift-Tab unexpectedly accepted a completion')
menu.key(9, true)
assert(editor.text == 'arctic ', 'Ctrl-Tab unexpectedly accepted a completion')
menu.key(9)
assert(editor.text == 'ARCTIC Blue' and editor.cursor == #editor.text)
click(label('Save Preset'))
assert(stored['ARCTIC Blue'] == 'saved' and not menu.outfit_dialog and writes == 0)

-- A normal pasted lowercase draft also gets a suggestion; no file reads or
-- provider calls occur during key/compose or while the user cancels it.
dialog, editor = start()
menu.clipboard = {
    get = function()
        return 'aRmO'
    end,
}
menu.key(86, true)
assert(editor.text == 'aRmO' and label('Tab: Armor Alpha'))
menu.key(9)
before = saves
click(label('Cancel'))
assert(not menu.outfit_dialog and not menu.text_edit and saves == before)

-- Font scaling uses the existing gap between the name field and buttons.
-- Completion does not grow the modal or place hint ink over either surface.
for _, size in ipairs({ 12, 20, 24 }) do
    menu.font_size = size
    start('armo')
    local suggestion, field, panel = hint()
    for _, command in ipairs(compose()) do
        if
            command.type == 'rect'
            and command.c
            and command.c[1] == 24
            and command.c[2] == 39
            and command.c[3] == 52
        then
            field = command
        end
        if
            command.type == 'rect'
            and command.c
            and command.c[1] == 20
            and command.c[2] == 25
            and command.c[3] == 30
        then
            panel = command
        end
    end
    local save = assert(label('Save Preset'))
    assert(
        suggestion and field and suggestion.y + suggestion.size <= field.y and suggestion.y >= save.y + save.size,
        'Completion hint overlaps the name field or buttons'
    )
    local bounds = menu.window_bounds
    assert(
        field.h == 30 * bounds.scale
            and panel
            and panel.h == 190 * bounds.scale
            and panel.w == 440 * bounds.scale
            and menu.window_height == 1000,
        'Completion expanded the compact naming modal'
    )
    click(label('Cancel'))
end
menu.font_size = 12
dialog, editor = start('armo', false)
assert(not hint())
menu.key(9)
assert(editor.text == 'armo' and menu.outfit_dialog == dialog, 'A different name modal unexpectedly completed')
click(label('Cancel'))
menu.outfit_dialog, menu.text_edit, menu.focus = nil, nil, 'settings'
mod.tabs_top = false
compose()
menu.key(9)
assert(menu.focus == 'mods' and menu.visible, 'Normal menu Tab navigation changed')
menu.key(9)
assert(menu.focus == 'settings' and writes == 0)
print(
    'PASS preset name completion: case-insensitive sorted prefix hints, Tab/caret and draft Undo only, explicit Save/Enter overwrite, unchanged scope, empty/unmatched/Cancel and normal Tab, compact font-safe hint'
)
local confirmation_saves = 0
local pending = start('Armor Alpha')
pending.on_save = function()
    menu.outfit_dialog = {
        phase = 'confirm',
        title = 'Update Weapon Preset',
        description = 'Replace this weapon? Other saved gear is kept.',
        on_confirm = function()
            confirmation_saves = confirmation_saves + 1
            return true
        end,
    }
    menu.text_edit = nil
    return false
end
menu.key(13)
assert(menu.outfit_dialog and menu.outfit_dialog.phase == 'confirm' and confirmation_saves == 0)
click(label('No'))
assert(not menu.outfit_dialog and confirmation_saves == 0)
menu.outfit_dialog = {
    phase = 'confirm',
    title = 'Update Weapon Preset',
    on_confirm = function()
        confirmation_saves = confirmation_saves + 1
        return true
    end,
}
click(label('Yes'))
assert(not menu.outfit_dialog and confirmation_saves == 1)
