local actions = dofile('src/editor/editor_actions.lua')
local view_source = assert(io.open('src/editor/armory_view.lua', 'rb'))
local body = view_source:read('*a')
view_source:close()
assert(not body:find('save_new_preset', 1, true), 'Armory retains an unregistered new-preset action')
local selected = { name = 'Existing', entries = { { kind = 'armor' }, { kind = 'helmet' }, { kind = 'cape' } } }
local menu = {}
local saves = 0
local target
local deps = {
    frontend = function()
        return { menu = menu }
    end,
    outfits = function()
        return {
            names = function()
                return { 'Existing' }
            end,
        }
    end,
    armory_collection = function()
        return { selected = selected }
    end,
    stop_identification = function()
        return true
    end,
    mod = function()
        return { controls = { outfit_name = {} } }
    end,
    message = function(s)
        return s
    end,
    keep_outfit = function(name, scope)
        saves = saves + 1
        target = name
        assert(scope.armor and scope.helmet and scope.cape)
    end,
}
deps.weapon_enabled = true
local a = actions.new(deps)
local function select_default_scope()
    local dialog = menu.outfit_dialog
    assert(dialog.phase == 'scope' and dialog.weapon_options and not dialog.save_kind.weapon,
        'Existing presets must offer explicit weapon save selection')
    dialog.on_scope(dialog.save_kind)
end
a.save_setup_activate()
if selected then select_default_scope() end
assert(saves == 0 and menu.outfit_dialog.phase == 'delete' and menu.outfit_dialog.preset_name == 'Existing')
local confirm = menu.outfit_dialog
menu.outfit_dialog = nil
assert(saves == 0)
selected = { name = 'Other' }
confirm.on_save()
assert(saves == 1 and target == 'Existing')
selected = nil
a.save_setup_activate()
if selected then select_default_scope() end
assert(menu.outfit_dialog.phase == 'scope' and saves == 1)
print('PASS selected preset save: confirmation, cancellation, stable target, new preset fallback')

local warnings = true
deps.preferences = function()
    return {
        confirm_overwrites = function()
            return warnings
        end,
        save_confirm_overwrites = function(v)
            warnings = v
            return true
        end,
    }
end
selected = { name = 'Existing', entries = { { kind = 'armor' }, { kind = 'helmet' }, { kind = 'cape' } } }
a.save_setup_activate()
if selected then select_default_scope() end
assert(menu.outfit_dialog.on_suppress and saves == 1)
menu.outfit_dialog.on_suppress()
menu.outfit_dialog = nil
a.save_setup_activate()
if selected then select_default_scope() end
assert(saves == 2 and target == 'Existing' and not menu.outfit_dialog)
warnings = true
a.save_setup_activate()
if selected then select_default_scope() end
assert(menu.outfit_dialog and saves == 2)
print('PASS overwrite suppression and re-enabling preserve normal preset saving')

local saved_scope
selected = { name = 'Mixed', entries = { { kind = 'armor' }, { kind = 'weapon', weapon_slot = 1 } } }
deps.keep_outfit = function(name, scope) assert(name == selected.name); saved_scope = scope end
warnings = true
a.save_setup_activate()
local dialog = menu.outfit_dialog
assert(not dialog.save_kind.weapon and dialog.weapon_options)
dialog.on_scope(dialog.save_kind)
menu.outfit_dialog.on_save()
assert(saved_scope.armor and not saved_scope.weapon and saved_scope.weapon_slots == nil)
-- Even a garment-only preset can explicitly add its current primary weapon.
selected = {name = 'Garments', entries = {{kind = 'armor'}}}
a.save_setup_activate()
dialog = menu.outfit_dialog
dialog.save_kind.weapon, dialog.save_kind.weapon_slots[1] = true, true
dialog.on_scope(dialog.save_kind)
-- A pending confirmation owns a snapshot, not mutable checkbox state.
dialog.save_kind.weapon_slots[1] = false
menu.outfit_dialog.on_save()
assert(saved_scope.armor and saved_scope.weapon and saved_scope.weapon_slots[1])
selected = {name = 'Weapons', entries = {{kind = 'weapon', weapon_slot = 2}}}
a.save_setup_activate()
dialog = menu.outfit_dialog
assert(not dialog.save_kind.armor and not dialog.save_kind.weapon)
dialog.save_kind.weapon, dialog.save_kind.weapon_slots[2] = true, true
dialog.on_scope(dialog.save_kind)
menu.outfit_dialog.on_save()
assert(saved_scope.weapon and saved_scope.weapon_slots[2] and not saved_scope.armor)
print('PASS explicit overwrite scope: mixed, garment-only and weapon-only presets expose independent weapon slots')
