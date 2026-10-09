-- Production controller, discovery and ownership with a cape sharing Armor's original LUT.
local ffi = require('ffi')
local Core, DDS = dofile('vendor/menu/core.lua'), dofile('src/core/dds.lua')
local store = {
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
}
local api = Core.new(store)
local kits = { body = 7, armor = 11, helmet = 12, cape = 13 }
local units, materials, bound, originals, live = {}, {}, {}, {}, {}
local created, frontend, saved_outfit, bulk_entries, mirror_entries, shared_entries = 0
local stock = { width = 23, height = 8, data = ffi.new('float[736]'), resource = '1111111111111111' }
stock.data[0] = 0.125
local function actor(generation)
    units, materials, live = {}, {}, {}
    for i, slot in ipairs({ 2, 1, 0 }) do
        local unit, material = generation * 10 + i, generation * 100 + i
        units[i] = { unit = unit, type = 0, slot = slot }
        materials[unit] = { { mesh = material + 10, material = material, mesh_index = 0, material_index = 0 } }
        live[unit] = true
        local object = generation * 1000 + (i == 3 and 2 or 1)
        bound[material] = { [1] = object, [3] = i == 2 and 999 or 0 }
        originals[object] = stock
    end
end
actor(1)
local function current()
    return materials[units[1].unit][1].material,
        materials[units[2].unit][1].material,
        materials[units[3].unit][1].material
end
local memory = {
    verify_build = function()
        return true
    end,
    address = function()
        return 1
    end,
    module = function()
        return 1
    end,
    read_into = function()
        return true
    end,
}
local native = {
    alive = function(unit)
        return live[unit] and 1 or 0
    end,
    commit = function() end,
}
local fixture = assert(os.getenv('EPIC_LUT_TEST_ROOT')) .. '/tests/tmp/presets'
local m = {
    cape_panel = dofile('src/editor/cape_panel.lua'),
    appearance_state = dofile('src/gear/appearance_state.lua'),
    binding_session = dofile('src/gear/binding_session.lua'),
    gear_catalog = dofile('src/gear/gear_catalog.lua'),
    basic_state = dofile('src/core/basic_state.lua'),
    region_indicator = dofile('src/gear/region_indicator.lua'),
    editor_registry = dofile('src/editor/editor_registry.lua'),
    lut_editor = dofile('src/editor/lut_editor.lua'),
    lut_editor_controls = dofile('src/editor/lut_editor_controls.lua'),
    lut_editor_view = dofile('src/editor/lut_editor_view.lua'),
    configuration = dofile('src/editor/configuration.lua'),
    semantics = dofile('src/core/semantics.lua'),
    palette = dofile('src/core/palette.lua'),
    resource_ids = dofile('src/core/resource_ids.lua'),
    lut_files = dofile('src/presets/lut_files.lua'),
    dds = DDS,
    ui_core = Core,
    table_index = dofile('src/imports/table_index.lua'),
    import_job = dofile('src/imports/import_job.lua'),
    import_protocol = dofile('src/imports/import_protocol.lua'),
    file_io = dofile('src/core/file_io.lua'),
    action_history = dofile('src/core/action_history.lua'),
    windows = {
        row_presets = function()
            return {}
        end,
        files = function()
            return {}
        end,
    },
    native_import = {},
    paths = {
        new = function()
            return {
                files = fixture,
                presets = fixture,
                cache = fixture,
                exports = fixture,
                settings = fixture,
                storage = store,
            }
        end,
    },
    bingus_memory = {
        new = function()
            return memory
        end,
    },
    avatar = {
        resolve_live = function()
            return { units_at = 1 }
        end,
        resolve = function()
            return kits
        end,
        reader = function()
            return function()
                return false
            end
        end,
        units = function()
            return units
        end,
    },
    engine = {
        LUT_SLOT = 1,
        CAPE_LUT_SLOT = 3,
        open = function()
            return native
        end,
        unit_materials = function(_, unit)
            return materials[unit] or {}
        end,
        binding = function(_, material, slot)
            return bound[material] and bound[material][slot]
        end,
        create_texture = function(_, width, height, data)
            assert(width == 23, 'Cape editor invented support for a separate cape tint layout')
            created = created + 1
            return { object = 90000 + created, width = width, height = height, data = data }
        end,
        bind = function(_, material, slot, object)
            assert(slot == 1, 'Cape tint/emblem binding was overwritten')
            bound[material][slot] = object
        end,
    },
    original_luts = {
        new = function()
            return {
                loaded = true,
                status = 'Ready',
                start = function() end,
                tick = function() end,
                scan = function() end,
                close = function() end,
                get = function(object)
                    return originals[object]
                end,
            }
        end,
    },
    preferences = {
        new = function()
            return { close = function() end }
        end,
    },
    provider_menu = {
        disable_matching = function()
            return true, false
        end,
    },
    basic_view = {
        new = function()
            return { draw = function() end, wheel = function() end }
        end,
    },
    frontend = {
        new = function()
            frontend = {
                menu = {
                    visible = false,
                    page = 1,
                    is_interacting = function()
                        return false
                    end,
                },
                tick = function() end,
                resolve = function()
                    return api
                end,
                close = function()
                    return true
                end,
            }
            return frontend
        end,
    },
    direct_setup = {
        new = function()
            return {
                read = function()
                    return {}
                end,
                clear = function() end,
                save = function()
                    return 1
                end,
            }
        end,
    },
    armory_collection = dofile('src/presets/armory_collection.lua'),
    outfit_presets = {
        new = function()
            return {
                names = function()
                    return saved_outfit and { 'Cape fixture' } or {}
                end,
                load = function()
                    return saved_outfit
                end,
                save = function(_, entries)
                    saved_outfit = { name = 'Cape fixture', entries = entries, armor = {}, helmet = {} }
                    for _, entry in ipairs(entries) do
                        saved_outfit[entry.kind][#saved_outfit[entry.kind] + 1] = entry.document
                    end
                    return true
                end,
            }
        end,
    },
    bulk_dds_export = {
        new = function()
            return {
                save = function(_, entries)
                    bulk_entries = entries
                    return 'output', #entries
                end,
            }
        end,
    },
    armory_mirror = {
        new = function(deps)
            return {
                tick = function()
                    mirror_entries = deps.entries()
                end,
                close = function()
                    return true
                end,
            }
        end,
    },
    lobby_sync = {},
    shared_lut_codec = {
        new = function()
            return {}
        end,
    },
    shared_appearance = {
        new = function(deps)
            return {
                tick = function()
                    shared_entries = deps.entries()
                end,
                close = function()
                    return true
                end,
            }
        end,
    },
}
local models = {}
local make_editor = m.lut_editor.new
m.lut_editor = {
    new = function(...)
        local model = make_editor(...)
        models[#models + 1] = model
        return model
    end,
}
local f = assert(io.open('src/editor/direct_editor.lua', 'rb'))
local source = f:read('*a')
f:close()
local runtime = assert(loadstring('local m=...\n' .. source))(m)
local ctx = { log = function() end, on_cleanup = function() end }
runtime.on_enable(ctx)
runtime.on_update(ctx, 0)
local h = api.mods.epic_direct_lut.handle
local function activate(id)
    local ok, value = h.activate(id)
    assert(ok, id .. ': ' .. tostring(value))
    assert(not (type(value) == 'string' and value:find('%.lua:%d+:')), value)
    return value
end
assert(h.set('preserve_emissives', false))
activate('populate_worn')
assert(h.set('cell_r', 0.375))
runtime.on_update(ctx, 0)
local armor, cape, helmet = current()
local armor_custom = bound[armor][1]
local main = models[1]
main.focus_cell(2, 3)
local main_pixels = ffi.string(main.document.data, main.document.width * main.document.height * 16)
local main_selection, main_undo = main.selection, #main.undo
assert(activate('editor_load_cape'):find('Cape material loaded', 1, true), 'Cape cannot be loaded into its own section')
assert(h.get('cape_cell_r') == 0.125, 'Cape current load missed the original snapshot')
assert(
    ffi.string(main.document.data, #main_pixels) == main_pixels
        and main.selection == main_selection
        and #main.undo == main_undo,
    'Cape load replaced main document/selection/history'
)
assert(h.set('cape_cell_r', 0.75))
runtime.on_update(ctx, 0)
local custom = bound[cape][1]
assert(
    custom ~= 1001 and bound[armor][1] == armor_custom and bound[helmet][1] == 1002,
    'Cape edit repainted shared Armor/Helmet'
)
assert(bound[cape][3] == 999, 'Material edit affected separate cape tint/emblem LUT')
assert(
    ffi.string(main.document.data, #main_pixels) == main_pixels
        and main.selection == main_selection
        and #main.undo == main_undo,
    'Cape edit replaced main document/selection/history'
)
activate('editor_apply_cape')
-- Main action Undo/Redo preserves current independently edited Cape bindings and intent.
activate('global_undo')
assert(bound[armor][1] == 1001 and bound[cape][1] == custom, 'Main Undo also changed Cape')
activate('global_redo')
assert(bound[armor][1] == armor_custom and bound[cape][1] == custom, 'Main Redo also changed Cape')
local allocated = created
activate('editor_all_armor')
activate('editor_all_both')
assert(bound[cape][1] == custom, 'Armor/Both wide action includes Cape')
runtime.on_update(ctx, 0)
assert(not mirror_entries['0:1:0:0'], 'Cape escaped into Armor Armory mirror entries')
for _, entry in ipairs(shared_entries) do
    assert(entry.key ~= '0:1:0:0', 'Cape escaped into lobby packet')
end
assert(h.set('export_format', 4))
activate('export_selected')
for _, entry in ipairs(bulk_entries) do
    assert(entry.kind ~= 'cape', 'Armor/Helmet bulk export includes Cape')
end
activate('save_setup')
assert(frontend.menu.outfit_dialog and frontend.menu.outfit_dialog.on_save('Cape fixture', 'both'))
for _, entry in ipairs(saved_outfit.entries) do
    assert(entry.key ~= '0:1:0:0', 'Cape was saved inside Armor preset')
end
activate('editor_restore_cape')
assert(bound[cape][1] == 1001 and bound[armor][1] ~= 1001, 'Cape Restore affected Armor')
assert(h.set('cape_cell_r', 0.75))
runtime.on_update(ctx, 0)
activate('restore')
assert(bound[cape][1] == 1001 and bound[armor][1] == 1001 and bound[helmet][1] == 1002, 'Main Restore missed Cape')
activate('editor_load_cape')
assert(h.set('cape_cell_r', 0.75))
runtime.on_update(ctx, 0)
custom = bound[cape][1]
actor(2)
runtime.on_update(ctx, 0.5)
armor, cape, helmet = current()
assert(bound[cape][1] == custom and bound[armor][1] == 2001, 'Matching Cape did not recover or repainted Armor')
-- Cape's own model Undo/Redo changes only its captured kit and history.
activate('cape_undo')
runtime.on_update(ctx, 0)
local undone = bound[cape][1]
assert(undone ~= custom and bound[armor][1] == 2001, 'Cape Undo changed Armor or failed to apply')
kits.cape = 97
activate('cape_redo')
runtime.on_update(ctx, 0)
assert(bound[cape][1] == undone, 'Cape Redo repainted a different kit on the same mount')
runtime.on_update(ctx, 0.5)
assert(bound[cape][1] == 2001, 'Changed Cape retained the previous kit appearance')
kits.cape = 13
runtime.on_update(ctx, 0.5)
activate('editor_load_cape')
assert(h.set('cape_cell_r', 0.75))
runtime.on_update(ctx, 0)
custom = bound[cape][1]
-- Changing cape kit can reuse every native unit/material/resource pointer.
kits.cape = 99
runtime.on_update(ctx, 0.5)
assert(bound[cape][1] == 2001, 'Previous Cape colors stayed on a changed kit with the same mount')
activate('editor_load_cape')
assert(h.get('cape_cell_r') == 0.125, 'Cape editor retained stale custom cache after kit changed')
runtime.on_update(ctx, 0.5)
assert(bound[cape][1] == 2001, 'Old Cape intent was replayed onto a new Cape kit')
kits.cape = 13
runtime.on_update(ctx, 0.5)
assert(bound[cape][1] == custom, 'Returning to the exact prior Cape lost its intent')
bound[cape][1] = 777777
kits.cape = 98
runtime.on_update(ctx, 0.5)
assert(bound[cape][1] == 777777, 'Cape-kit change overwrote a foreign writer')
activate('restore')
assert(bound[cape][1] == 777777, 'Main Restore overwrote a foreign Cape writer')
runtime.on_disable(ctx)
-- The legacy manifest's Helmet blanket default must not fall through to a Cape destination.
local filename = 'cape-fixture-helmet.dds'
DDS.write(fixture .. '/' .. filename, stock.data, stock.width, stock.height)
m.direct_setup.new = function()
    return {
        read = function()
            return { ['helmet-all'] = filename }
        end,
        clear = function() end,
        save = function()
            return 1
        end,
    }
end
actor(3)
runtime.on_enable(ctx)
for _ = 1, 14 do
    runtime.on_update(ctx, 0.25)
end
armor, cape, helmet = current()
assert(bound[cape][1] == 3001 and bound[helmet][1] ~= 3002, 'Helmet startup default fell through into Cape')
runtime.on_disable(ctx)
os.remove(fixture .. '/' .. filename)
print(
    'PASS independent Cape material section: scoped model/current load/edit/picker/history/Restore, narrow native targets, main document/selection/history preservation, exact kit recovery and unchanged-mount kit/foreign/startup isolation'
)
