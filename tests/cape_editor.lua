-- Production controller, discovery and ownership with a cape sharing Armor's original LUT.
local ffi = require('ffi')
local Core, DDS = dofile('vendor/menu/core.lua'), dofile('src/core/dds.lua')
local saved_settings = {}
local store = {
    load = function(id)
        return saved_settings[id] or {}
    end,
    save = function(id, values)
        saved_settings[id] = values
        return true
    end,
}
local api = Core.new(store)
local kits = { body = 7, armor = 11, helmet = 12, cape = 13 }
local units, materials, bound, originals, live = {}, {}, {}, {}, {}
local created, frontend, saved_outfit, bulk_entries, mirror_entries, shared_entries = 0
local include_capes, gear_ready, proof_ready, basic_select = true, true, true
local after_write
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
            return proof_ready and kits or nil
        end,
        reader = function()
            return function()
                return false
            end
        end,
        units = function()
            if gear_ready then
                return units
            end
            return { units[3] }
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
            if after_write then
                after_write(material)
            end
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
            return {
                close = function() end,
                include_capes_in_armor_exports = function()
                    return include_capes
                end,
            }
        end,
    },
    provider_menu = {
        disable_matching = function()
            return true, false
        end,
    },
    basic_view = {
        new = function(info, select)
            basic_select = select
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
                    saved_outfit = { name = 'Cape fixture', entries = entries, armor = {}, helmet = {}, cape = {} }
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
api.focus_page = function(id, page_id)
    for index, page in ipairs(api.mods[id].pages) do
        if page.id == page_id then
            frontend.menu.page = index
            return true
        end
    end
    return false
end
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
api.focus_page(h.id, 'colors')
local control = api.mods[h.id].controls.basic_armor_lut
assert(
    #control.choices == 2 and control.choices[1] == 'LUT 1' and control.choices[2] == 'Cape LUT 1',
    'Armor/Cape shared resource did not yield separate named choices'
)
assert(
    control.choice_targets[1].kind == 'armor' and control.choice_targets[2].kind == 'cape',
    'Combined choice lost actual native kind'
)
assert(not api.mods[h.id].controls.basic_cape_lut and #models == 1, 'Separate Cape controls/editor still registered')
assert(h.set('cell_r', 0.375))
runtime.on_update(ctx, 0)
local armor, cape, helmet = current()
local armor_custom = bound[armor][1]
assert(h.set('basic_armor_lut', 2))
assert(h.get('cell_r') == 0.125 and models[1].gear == 'armor', 'Cape choice does not use the shared Armor grid')
assert(h.set('cell_r', 0.75))
runtime.on_update(ctx, 0)
local custom = bound[cape][1]
assert(
    custom ~= 1001 and bound[armor][1] == armor_custom and bound[helmet][1] == 1002,
    'Cape edit spilled into shared-hash Armor/Helmet'
)
assert(bound[cape][3] == 999, 'Cape material edit overwrote its separate tint/emblem slot')
activate('global_undo')
assert(bound[cape][1] == 1001 and bound[armor][1] == armor_custom, 'Shared Undo did not isolate Cape')
activate('global_redo')
assert(bound[cape][1] == custom and bound[armor][1] == armor_custom, 'Shared Redo did not restore Cape intent')
activate('reset_custom')
runtime.on_update(ctx, 0)
assert(bound[armor][1] == armor_custom, 'Selected Cape Reset repainted Armor')
assert(h.set('cell_r', 0.75))
runtime.on_update(ctx, 0)
custom = bound[cape][1]
activate('editor_all_armor')
activate('editor_all_both')
assert(bound[cape][1] == custom, 'Armor/Both wide application includes Cape')
runtime.on_update(ctx, 0)
assert(not mirror_entries['0:1:0:0'], 'Cape escaped into Armory mirror')
for _, entry in ipairs(shared_entries) do
    assert(entry.key ~= '0:1:0:0', 'Cape escaped into lobby payload')
end
-- The include flag filters outgoing exports, never local named presets.
assert(h.set('export_format', 4))
include_capes = false
activate('export_selected')
for _, entry in ipairs(bulk_entries) do
    assert(entry.kind ~= 'cape', 'Outgoing exclude flag leaked Cape')
end
include_capes = true
activate('export_selected')
local exported_cape = false
for _, entry in ipairs(bulk_entries) do
    exported_cape = exported_cape or entry.kind == 'cape'
end
assert(exported_cape, 'Outgoing include flag discarded Cape')
local function save(scope)
    activate('save_setup')
    assert(frontend.menu.outfit_dialog)
    frontend.menu.outfit_dialog.on_save('Cape fixture', scope)
    return saved_outfit
end
include_capes = false
local local_armor = save('armor')
assert(
    #local_armor.armor > 0 and #local_armor.cape > 0 and #local_armor.helmet == 0,
    'Armor Only save lost Cape or included Helmet'
)
local local_helmet = save('helmet')
assert(
    #local_helmet.helmet > 0 and #local_helmet.armor == 0 and #local_helmet.cape == 0,
    'Helmet Only save includes Armor/Cape'
)
local both = save('both')
assert(#both.armor > 0 and #both.cape > 0 and #both.helmet > 0, 'Both save omitted a gear kind')
activate('restore')
activate('outfit_apply_armor')
assert(
    bound[armor][1] ~= 1001 and bound[cape][1] == custom and bound[helmet][1] == 1002,
    'Saved Armor+Cape preset did not apply separate same-hash destinations'
)
local before = saved_outfit
gear_ready = false
activate('save_setup')
local saved, why = pcall(frontend.menu.outfit_dialog.on_save, 'Cape fixture', 'both')
assert(
    not saved and why:find('Armor/Cape LUTs', 1, true) and saved_outfit == before,
    'Loading Armor silently saved a partial Both preset'
)
gear_ready = true
-- Alias writes retain raw texture IDs and the modal refocus seed.
activate('populate_worn')
assert(h.set('basic_armor_lut', 2))
activate('editor_load_armor')
activate('rename_lut')
assert(frontend.menu.outfit_dialog.initial_text == '' and frontend.menu.outfit_dialog.action_label == 'Save Name')
frontend.menu.outfit_dialog.on_save('Cape Pink')
assert(
    control.choice_details[2] == 'Cape Pink'
        and control.choice_hashes[2] == '1111111111111111'
        and control.choice_help[2]:find('1111111111111111', 1, true),
    'Alias replaced raw hash metadata'
)
activate('rename_lut')
assert(frontend.menu.outfit_dialog.initial_text == 'Cape Pink', 'Rename refocus lost existing label')
frontend.menu.outfit_dialog.on_save('   ')
assert(control.choice_details[2] ~= 'Cape Pink', 'Whitespace clear did not restore texture ID')
activate('restore')
activate('editor_load_armor')
assert(h.set('cell_r', 0.75))
runtime.on_update(ctx, 0)
custom = bound[cape][1]
actor(2)
runtime.on_update(ctx, 0.5)
armor, cape, helmet = current()
assert(bound[cape][1] == custom and bound[armor][1] == 2001, 'Same Cape actor recovery repainted Armor or lost colors')
assert(h.set('cell_r', 0.625))
runtime.on_update(ctx, 0)
custom = bound[cape][1]
assert(custom ~= 2001 and bound[armor][1] == 2001, 'Loaded Cape draft could not resolve its rebuilt actor')
activate('global_undo')
kits.cape = 99
runtime.on_update(ctx, 0.5)
local redone, refusal = h.activate('global_redo')
assert(
    not redone and refusal:find('Cape kit changed', 1, true) and bound[cape][1] == 2001,
    'Old Cape Redo painted a different kit on the same mount'
)
activate('editor_load_armor')
assert(h.get('cell_r') == 0.125, 'Cape swap retained stale editor cache')
-- Basic swatch/copy/picker targets also require captured kit+resource proof.
frontend.basic_mode = true
api.focus_page(h.id, 'basic')
assert(basic_select(1, 'armor'))
assert(h.set('cell_color', '#FF0000'))
kits.cape = 98
runtime.on_update(ctx, 0)
assert(bound[cape][1] == 2001, 'Basic Cape edit repainted a changed kit while refresh was deferred')
runtime.on_update(ctx, 0.5)
proof_ready = false
assert(not pcall(basic_select, 1, 'armor'), 'Basic Cape selection accepted unavailable identity')
proof_ready = true
frontend.basic_mode = false
api.focus_page(h.id, 'colors')
activate('restore')
bound[cape][1] = 777777
kits.cape = 97
runtime.on_update(ctx, 0.5)
assert(bound[cape][1] == 777777, 'Cape kit swap overwrote a foreign writer')
activate('restore')
assert(bound[cape][1] == 777777, 'Restore overwrote a foreign Cape writer')
runtime.on_disable(ctx)
-- Cross-launch restoration requires Cape proof and checks it at each write.
local filename = 'setup-1-1-1.dds'
local pixels = ffi.new('float[736]')
pixels[0] = 0.875
DDS.write(fixture .. '/' .. filename, pixels, 23, 8)
local function startup(plan, proof, kit)
    kits.cape = kit
    actor(3)
    m.direct_setup.new = function()
        return {
            read = function()
                return plan, proof
            end,
            clear = function() end,
            save = function()
                return 1
            end,
        }
    end
    runtime.on_enable(ctx)
    for _ = 1, 14 do
        runtime.on_update(ctx, 0.25)
    end
    armor, cape, helmet = current()
end
startup({ ['0:1:0:0'] = filename }, nil, 13)
assert(bound[cape][1] == 3001, 'Legacy unproved Cape slot resumed onto current kit')
runtime.on_disable(ctx)
startup({ ['0:1:0:0'] = filename }, { ['0:1:0:0'] = { proof = '7:13', resource = '1111111111111111' } }, 99)
assert(bound[cape][1] == 3001, 'Saved old Cape proof resumed onto another kit')
runtime.on_disable(ctx)
startup({ ['0:1:0:0'] = filename }, { ['0:1:0:0'] = { proof = '7:13', resource = '1111111111111111' } }, 13)
assert(bound[cape][1] ~= 3001, 'Exact saved Cape proof failed to resume')
runtime.on_disable(ctx)
-- A same-mount kit switch after scan but before the later Cape batch cannot adopt old colors.
local armor_file = 'setup-1-1-2.dds'
DDS.write(fixture .. '/' .. armor_file, pixels, 23, 8)
local original_pairs = pairs
pairs = function(value)
    if
        type(value) == 'table'
        and type(value[filename]) == 'table'
        and value[filename][1]
        and value[filename][1].cape
        and value[armor_file]
    then
        local keys, index = { armor_file, filename }, 0
        return function()
            index = index + 1
            local key = keys[index]
            if key then
                return key, value[key]
            end
        end
    end
    return original_pairs(value)
end
after_write = function(material)
    if material == 301 then
        kits.cape = 99
    end
end
startup(
    { ['0:2:0:0'] = armor_file, ['0:1:0:0'] = filename },
    { ['0:1:0:0'] = { proof = '7:13', resource = '1111111111111111' } },
    13
)
pairs, after_write = original_pairs, nil
assert(
    bound[armor][1] ~= 3001 and bound[cape][1] == 3001,
    'Cape startup batch applied after the kit changed following scan'
)
runtime.on_disable(ctx)
os.remove(fixture .. '/' .. armor_file)
os.remove(fixture .. '/' .. filename)
print(
    'PASS folded Cape controller: same-hash selector/single editor, scoped edits/reset/history/recovery, Basic kit guards, three local save scopes/loading rejection, export flag, alias modal/raw IDs and legacy/new startup proof'
)
