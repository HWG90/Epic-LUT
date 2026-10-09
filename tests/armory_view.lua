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
local document = { width = 23, height = 8, data = ffi.new('float[736]') }
local state =
    { editor = document, status = 'Ready', raw = { outfit = { armor = { document }, helmet = { document } } } }
local view = dofile('src/editor/armory_view.lua').new(function()
    return state
end)
local saved
local exports = {}
local menu
local controls = {
    { id = 'armory_search', type = 'input', allow_empty = true, label = 'Search', default = '' },
    { id = 'armory_sort', type = 'choice', label = 'Sort', choices = { 'A-Z', 'Z-A' }, default = 1 },
    { id = 'basic_preset_name', type = 'input', label = 'Name', default = 'palette' },
    { id = 'basic_preset', type = 'choice', label = 'Palette', choices = { 'New preset' }, default = 1 },
    { id = 'outfit_preset', type = 'choice', label = 'Outfit', choices = { 'Choose outfit', 'Example' }, default = 1 },
    { id = 'armory_export_name', type = 'input', label = 'Export name', default = 'Saved Set' },
    {
        id = 'armory_export_format',
        type = 'choice',
        label = 'Export format',
        choices = {
            'Shareable Preset ZIP',
            'Selected LUT Patch ZIP',
            'Entire Preset Patch ZIP',
            'Raw DDS (selected LUT)',
            'Raw DDS (entire preset)',
        },
        default = 1,
        on_change = function(value)
            state.armory_export_format = value
        end,
    },
    {
        id = 'armory_dds_naming',
        type = 'choice',
        presentation = 'dropdown',
        label = 'DDS filenames',
        choices = { 'LUT# + HEX', 'LUT# + Decimal', 'LUT#', 'HEX', 'Decimal' },
        default = 1,
    },
    { id = 'armory_export_lut', type = 'choice', label = 'Saved LUT', choices = { 'Armor LUT 1' }, default = 1 },
    {
        id = 'outfit_name',
        type = 'input',
        label = 'Outfit name',
        default = 'my-outfit',
        on_change = function(name)
            saved = name
            menu.outfit_dialog = nil
        end,
    },
}
for _, id in ipairs({
    'outfit_rename',
    'outfit_delete',
    'save_setup',
    'outfit_apply_armor',
    'outfit_apply_helmet',
    'basic_save',
    'basic_export',
    'open_editor',
    'armory_export',
    'armory_import',
    'open_export',
}) do
    controls[#controls + 1] = {
        id = id,
        type = 'button',
        label = id,
        on_activate = function()
            if id == 'armory_export' then
                exports[#exports + 1] = {
                    format = api.mods.armory_test.handle.get('armory_export_format'),
                    naming = api.mods.armory_test.handle.get('armory_dds_naming'),
                }
            end
            return true
        end,
    }
end
local h = api.register({
    id = 'armory_test',
    name = 'Epic LUT',
    pages = { { id = 'armory', name = 'The Armory', controls = controls, require_confirmation = false } },
})
api.mods[h.id].pages[1].render_layout = view.draw
api.mods[h.id].tabs_top = true
menu = dofile('vendor/menu/menu.lua').new(api, function(t, size)
    return #t * size * 0.5
end)
menu.visible = true
local labels = {}
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text or c.text then
        labels[c.full_text or c.text] = c
    end
end
assert(
    labels.Armor and labels.Helmet and labels['Save Current Gear Preset'],
    'Armory lacks paired preview or save action'
)
assert(
    not labels['Save Current LUT as Preset'] and not labels['Export DDS to Share'] and not labels['Open LUT Editor'],
    'Removed single-LUT section still visible'
)
state.raw.outfit.armor = { document, document, document }
menu.compose(1920, 1080)
assert(view.maximum > 0, 'Multiple saved LUTs did not create a scrollable preview')
view.wheel(view.bounds.x + 2, view.bounds.y + 2, -1200)
local later = {}
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text then
        later[c.full_text] = true
    end
end
assert(later['LUT 3'], 'Later saved LUT missing from Armory preview')
-- A small viewport must retain access to export/import without controls escaping.
menu.compose(960, 720)
assert(view.sidebar_maximum > 0, 'Small Armory window did not scroll its controls')
view.wheel(view.sidebar_bounds.x + 2, view.sidebar_bounds.y + 2, -1200)
local bottom = {}
for _, c in ipairs(menu.compose(960, 720)) do
    if c.full_text then
        bottom[c.full_text] = true
    end
end
assert(
    bottom['Export Selected Preset...'] and bottom['Import Shared Preset...'],
    'Armory export/import controls unreachable'
)
state.raw.outfit.helmet = { { width = 3, height = 1, data = ffi.new('float[12]') } }
view.scroll = 0
local pattern_labels = {}
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text then
        pattern_labels[c.full_text] = true
    end
end
assert(pattern_labels['Pattern LUT 1'], '3x1 Pattern preset missing safe preview')
state.raw.outfit.armor = {}
state.raw.outfit.cape = { document }
view.scroll, view.sidebar_scroll = 0, 0
local cape_labels = {}
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text then
        cape_labels[c.full_text] = true
    end
end
assert(cape_labels['Cape LUT 1'] and cape_labels['Armor / Cape'], 'Cape LUT missing from paired Armory preview')
assert(view.preview_columns[1][1].kind == 'cape' and view.preview_columns[1][1].document == document)
state.raw.outfit.armor, state.raw.outfit.cape = { document }, nil

local saved_kind
menu.outfit_dialog = {
    phase = 'scope',
    mod = api.mods[h.id],
    control = api.mods[h.id].controls.outfit_name,
    on_save = function(name, kind)
        saved = name
        saved_kind = kind
    end,
}
local armor_only
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text == 'Armor Only' then
        armor_only = c
    end
end
assert(armor_only, 'Save scope choice missing')
local ax, ay = armor_only.x + 2, armor_only.y + 2
menu.tick({
    down = function(k)
        return k == 1
    end,
    mouse = function()
        return ax, ay
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
        return ax, ay
    end,
    wheel = function()
        return 0
    end,
})
assert(menu.outfit_dialog.save_kind == 'armor' and menu.text_edit, 'Scope selection must precede typing')
menu.text_edit.text = 'Armor Only Test'
menu.key(13)
assert(saved_kind == 'armor' and not menu.outfit_dialog, 'Save lost the selected armor-only scope')
menu.outfit_dialog = { phase = 'confirm', mod = api.mods[h.id], control = api.mods[h.id].controls.outfit_name }
local yes
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text == 'Yes' then
        yes = c
    end
end
assert(yes, 'Keep preset confirmation missing')
local x, y = yes.x + 2, yes.y + 2
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
assert(menu.text_edit and menu.outfit_dialog.phase == 'name', 'Yes did not open naming box')
menu.text_edit.text = 'Mixed Set'
menu.key(13)
assert(saved == 'Mixed Set' and not menu.outfit_dialog, 'Named preset did not save/close')
local function composed(value)
    for _, c in ipairs(menu.compose(1920, 1080)) do
        if c.full_text == value then
            return c
        end
    end
end
local function tap_label(value)
    local c = assert(composed(value), 'Missing Armory export control: ' .. value)
    for _, down in ipairs({ true, false }) do
        menu.tick({
            down = function(key)
                return down and key == 1
            end,
            mouse = function()
                return c.x + 3, c.y + 3
            end,
            wheel = function()
                return 0
            end,
        })
    end
end
for format = 1, 4 do
    assert(h.set('armory_export_format', format))
    menu.compose(1920, 1080)
    view.sidebar_scroll = view.sidebar_maximum
    assert(not composed('LUT# + HEX'), 'Armory naming chooser leaked into an existing format')
    assert(
        (composed('Armor LUT 1') ~= nil) == (format == 2 or format == 4),
        'Armory selected-LUT chooser changed its original format eligibility'
    )
    tap_label('Export Selected Preset...')
    assert(exports[#exports].format == format, 'Armory old export format callback changed')
end
assert(h.set('armory_export_format', 5))
menu.compose(1920, 1080)
view.sidebar_scroll = view.sidebar_maximum
assert(not composed('Armor LUT 1'), 'Entire preset bulk DDS still asks for a single LUT')
tap_label('LUT# + HEX')
assert(menu.dropdown and menu.dropdown.control.id == 'armory_dds_naming', 'Armory bulk naming dropdown did not open')
for i = 1, 3 do
    menu.key(40)
end
menu.key(13)
tap_label('Export Selected Preset...')
assert(
    exports[#exports].format == 5 and exports[#exports].naming == 4,
    'Armory bulk export lost its HEX naming selection'
)
print('PASS Armory: split Armor/Helmet preview, keep-preset confirmation, editable naming popup')
