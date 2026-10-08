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
local menu
local controls = {
    { id = 'basic_preset_name', type = 'input', label = 'Name', default = 'palette' },
    { id = 'basic_preset', type = 'choice', label = 'Palette', choices = { 'New preset' }, default = 1 },
    { id = 'outfit_preset', type = 'choice', label = 'Outfit', choices = { 'Choose outfit', 'Example' }, default = 1 },
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
print('PASS Armory: split Armor/Helmet preview, keep-preset confirmation, editable naming popup')
