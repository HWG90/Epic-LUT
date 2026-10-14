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
