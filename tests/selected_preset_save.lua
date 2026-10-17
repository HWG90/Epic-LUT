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
local a = actions.new(deps)
a.save_setup_activate()
assert(saves == 0 and menu.outfit_dialog.phase == 'delete' and menu.outfit_dialog.preset_name == 'Existing')
local confirm = menu.outfit_dialog
menu.outfit_dialog = nil
assert(saves == 0)
selected = { name = 'Other' }
confirm.on_save()
assert(saves == 1 and target == 'Existing')
selected = nil
a.save_setup_activate()
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
assert(menu.outfit_dialog.on_suppress and saves == 1)
menu.outfit_dialog.on_suppress()
menu.outfit_dialog = nil
a.save_setup_activate()
assert(saves == 2 and target == 'Existing' and not menu.outfit_dialog)
warnings = true
a.save_setup_activate()
assert(menu.outfit_dialog and saves == 2)
print('PASS overwrite suppression and re-enabling preserve normal preset saving')

local saved_scope
selected = { name = 'Mixed', entries = { { kind = 'armor' }, { kind = 'weapon', weapon_slot = 1 } } }
local weapons_checked = false
deps.handle = function() return {get = function(id) assert(id == 'outfit_target_weapon'); return weapons_checked end} end
deps.keep_outfit = function(name, scope) assert(name == 'Mixed'); saved_scope = scope end
warnings = true
a.save_setup_activate()
menu.outfit_dialog.on_save()
assert(saved_scope.armor and not saved_scope.weapon and saved_scope.weapon_slots == nil,
    'Unchecked Weapons were inherited from the existing preset during overwrite')
weapons_checked = true
a.save_setup_activate()
menu.outfit_dialog.on_save()
assert(saved_scope.armor and saved_scope.weapon and saved_scope.weapon_slots[1],
    'Explicit Weapons selection was not forwarded to preset capture')
print('PASS selected preset overwrite: existing weapon entries require explicit Weapons opt-in')
