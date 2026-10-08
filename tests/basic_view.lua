local ffi = require('ffi')
local core = dofile('vendor/menu/core.lua')
local api = core.new({
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
})
local data = ffi.new('float[?]', 23 * 8 * 4)
for i = 0, 23 * 8 * 4 - 1 do
    data[i] = 0.5
end
local state = {
    editor = { data = data, width = 23, height = 8 },
    palette_count = 1,
    status = 'Ready',
    armor_checked = true,
    helmet_checked = false,
}
state.raw = { basic = { armor = { document = state.editor }, helmet = { document = state.editor } } }
local selected
local view = dofile('src/basic_view.lua').new(function()
    return state
end, function(row)
    selected = row
end)
local controls = {
    { id = 'palette', type = 'choice', label = 'Imported LUT', choices = { 'Import first', 'LUT 2' }, default = 1 },
    {
        id = 'outfit_preset',
        type = 'choice',
        label = 'Saved outfit',
        choices = { 'Choose saved outfit...', 'Example' },
        default = 1,
    },
    { id = 'basic_target', type = 'choice', label = 'Worn gear', choices = { 'Armor', 'Helmet' }, default = 1 },
    { id = 'cell_color', type = 'color', label = 'Primary color', default = '#808080' },
    { id = 'basic_preset_name', type = 'input', label = 'Preset name', default = 'test' },
    { id = 'basic_preset', type = 'choice', label = 'Presets', choices = { 'New preset...', 'Saved' }, default = 1 },
}
for _, kind in ipairs({ 'armor', 'helmet' }) do
    controls[#controls + 1] =
        { id = 'basic_' .. kind .. '_lut', type = 'choice', label = kind .. ' LUT', choices = { 'LUT 1' }, default = 1 }
end
for _, kind in ipairs({ 'armor', 'helmet' }) do
    controls[#controls + 1] = {
        id = 'basic_apply_' .. kind,
        type = 'button',
        label = 'Apply ' .. kind,
        on_activate = function()
            return true
        end,
    }
end
for _, id in ipairs({
    'apply_import_armor',
    'apply_import_helmet',
    'apply_file_armor',
    'apply_file_helmet',
    'identify_region',
    'stop_identify',
    'apply_matching',
    'outfit_apply_armor',
    'outfit_apply_helmet',
    'save_setup',
}) do
    controls[#controls + 1] = {
        id = id,
        type = 'button',
        label = id,
        on_activate = function()
            return true
        end,
    }
end
for _, id in ipairs({ 'basic_advanced', 'basic_copy_helmet', 'basic_copy_helmet_all', 'basic_copy_armor' }) do
    controls[#controls + 1] = {
        id = id,
        type = 'button',
        label = id,
        on_activate = function()
            return true
        end,
    }
end
for _, id in ipairs({
    'browse',
    'populate_worn',
    'target_helmet',
    'target_armor',
    'apply_editor',
    'basic_save',
    'basic_export',
    'undo',
    'redo',
    'restore_imported',
    'restore',
}) do
    controls[#controls + 1] = {
        id = id,
        type = 'button',
        label = id,
        on_activate = function()
            return true
        end,
    }
end
api.register({
    id = 'basic_test',
    name = 'Epic LUT',
    pages = {
        {
            id = 'basic',
            name = 'Basic',
            min_width = 1100,
            min_height = 780,
            require_confirmation = false,
            controls = controls,
            render_layout = view.draw,
        },
    },
})
api.mods.basic_test.tabs_top = true
api.mods.basic_test.pages[1].render_layout = view.draw
api.mods.basic_test.pages[1].minimum_width = 1100
api.mods.basic_test.pages[1].minimum_height = 780
local menu = dofile('vendor/menu/menu.lua').new(api, function(t, size)
    return #t * size * 0.5
end)
menu.visible = true
menu.window_width = 1100
menu.window_height = 780
local commands = menu.compose(1920, 1080)
local regions = 0
local row8
for _, c in ipairs(commands) do
    if c.full_text and c.full_text:match('^Region %d+$') then
        regions = regions + 1
        if c.full_text == 'Region 8' then
            row8 = c
        end
    end
    assert(c.text ~= 'Value Editor - grouped by rows', 'Advanced editor leaked into Basic')
end
local apply_labels = {}
for _, c in ipairs(commands) do
    if c.full_text then
        apply_labels[c.full_text] = true
    end
end
assert(
    not apply_labels['Apply LUT 1 to All Armor']
        and not apply_labels['Restore Imported']
        and not apply_labels['Single LUT Import'],
    'Unused import controls should be hidden'
)
state.loaded = state.editor
local imported_labels = {}
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text then
        imported_labels[c.full_text] = true
    end
end
assert(
    imported_labels['Apply LUT 1 to All Armor']
        and imported_labels['Apply LUT 1 to All Helmet']
        and imported_labels['Single LUT Import'],
    'Loaded import controls missing'
)
assert(regions == 16 and row8, 'Basic did not fit both eight-region palettes: ' .. regions)
state.palette_count = 2
state.raw.matching = { matched = 1, unmatched = 1, unidentified = 0, ambiguous = 0 }
local matching = false
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text == 'Apply Matching LUTs' then
        matching = true
    end
end
assert(matching, 'Basic matching-import action missing')
local x, y = row8.x + 85, row8.y + 2
menu.tick({
    down = function(k)
        return k == 1
    end,
    mouse = function()
        return x, y
    end,
    wheel = function()
        return 0
    end,
})
menu.tick({
    down = function()
        return false
    end,
    mouse = function()
        return x, y
    end,
    wheel = function()
        return 0
    end,
})
assert(
    selected == 8 and menu.color_picker and menu.color_picker.control.id == 'cell_color',
    'Basic click did not open primary-color picker for the selected row'
)
print(
    'PASS Basic: eight primary regions at compact size, standard color picker, import/export/preset controls, no advanced fields'
)
