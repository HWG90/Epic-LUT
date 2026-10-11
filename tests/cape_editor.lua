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
local include_capes, gear_ready, proof_ready, basic_select, basic_camo_row = true, true, true
local include_patterns = true
local basic_info, action_history
local outfit_save_calls, fail_outfit_save = 0, false
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
    basic_camo = dofile('src/editor/basic_camo.lua'),
    live_edit = dofile('src/editor/live_edit.lua'),
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
    import_picker = dofile('src/imports/import_picker.lua'),
    import_protocol = dofile('src/imports/import_protocol.lua'),
    file_io = dofile('src/core/file_io.lua'),
    action_history = {
        new = function(...)
            action_history = dofile('src/core/action_history.lua').new(...)
            return action_history
        end,
    },
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
                include_patterns_in_exports = function()
                    return include_patterns
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
        new = function(info, select, _, camo_row)
            basic_info = info
            basic_select = select
            basic_camo_row = camo_row
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
    outfit_targets = dofile('src/presets/outfit_targets.lua'),
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
                    outfit_save_calls = outfit_save_calls + 1
                    if fail_outfit_save then
                        return false, 'Simulated Armory manifest lock'
                    end
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
assert(
    h.get('outfit_target_armor') and h.get('outfit_target_helmet') and h.get('outfit_target_cape'),
    'Armory apply targets did not default to all three gear families'
)
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
    local defaults = frontend.menu.outfit_dialog.save_kind
    assert(defaults.armor and defaults.helmet and defaults.cape, 'Save popup did not default to the complete outfit')
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
do
    local native_before = { bound[armor][1], bound[cape][1], bound[helmet][1], bound[cape][3] }
    local texture_count, history_count = created, #action_history.undo
    for flags = 1, 7 do
        local scope = { armor = flags % 2 == 1, helmet = math.floor(flags / 2) % 2 == 1, cape = flags >= 4 }
        local subset = save(scope)
        for _, kind in ipairs({ 'armor', 'helmet', 'cape' }) do
            assert(#subset[kind] == (scope[kind] and #both[kind] or 0), 'Save mask included an unchecked gear family')
            for index, doc in ipairs(subset[kind]) do
                local original = both[kind][index]
                assert(
                    ffi.string(doc.data, doc.width * doc.height * 16)
                        == ffi.string(original.data, original.width * original.height * 16),
                    'Save mask altered a selected material LUT'
                )
            end
        end
        for _, entry in ipairs(subset.entries) do
            assert(scope[entry.kind] and entry.key:sub(1, 2) ~= 'p:', 'Material-only save invented Pattern data')
        end
    end
    assert(
        created == texture_count
            and #action_history.undo == history_count
            and bound[armor][1] == native_before[1]
            and bound[cape][1] == native_before[2]
            and bound[helmet][1] == native_before[3]
            and bound[cape][3] == native_before[4],
        'Saving independent gear subsets changed native bindings, textures or history'
    )
    for _, scope in ipairs({ {}, { armor = false, helmet = false, cape = false }, { armor = 1 }, { torso = true } }) do
        local previous, save_count = saved_outfit, outfit_save_calls
        activate('save_setup')
        assert(not pcall(frontend.menu.outfit_dialog.on_save, 'Cape fixture', scope))
        assert(saved_outfit == previous and outfit_save_calls == save_count and created == texture_count)
    end
    local previous, saved_pixels = saved_outfit, both.cape[1].saved_pixels
    activate('save_setup')
    local dialog = frontend.menu.outfit_dialog
    fail_outfit_save = true
    local accepted, reason = pcall(dialog.on_save, 'Cape fixture', { cape = true })
    fail_outfit_save = false
    assert(
        not accepted
            and reason:find('Simulated Armory manifest lock', 1, true)
            and saved_outfit == previous
            and both.cape[1].saved_pixels == saved_pixels
            and frontend.menu.outfit_dialog == dialog
            and created == texture_count
            and #action_history.undo == history_count,
        'Failed subset save committed a new preset, closed its dialog or changed native state'
    )
end
activate('restore')
activate('outfit_apply_cape')
assert(
    bound[cape][1] == custom and bound[armor][1] == 1001 and bound[helmet][1] == 1002 and bound[cape][3] == 999,
    'Armory Cape application changed same-resource Armor/Helmet or the Cape tint slot'
)
activate('global_undo')
assert(
    bound[cape][1] == 1001 and bound[armor][1] == 1001 and bound[helmet][1] == 1002,
    'Armory Cape Undo escaped its scope'
)
activate('global_redo')
assert(
    bound[cape][1] == custom and bound[armor][1] == 1001 and bound[helmet][1] == 1002,
    'Armory Cape Redo lost the isolated application'
)
activate('restore')
activate('outfit_apply_armor')
assert(
    bound[armor][1] ~= 1001 and bound[cape][1] == 1001 and bound[helmet][1] == 1002,
    'Armor preset action applied the separately controlled Cape/Helmet'
)
local armory_armor = bound[armor][1]
activate('outfit_apply_cape')
assert(bound[armor][1] == armory_armor and bound[cape][1] == custom and bound[helmet][1] == 1002)
local before = saved_outfit
gear_ready = false
activate('save_setup')
local saved, why = pcall(frontend.menu.outfit_dialog.on_save, 'Cape fixture', 'both')
assert(
    not saved and why:find('Armor/Cape LUTs', 1, true) and saved_outfit == before,
    'Loading Armor silently saved a partial Both preset'
)
do
    local saved_before, save_count, texture_count = saved_outfit, outfit_save_calls, created
    for _, scope in ipairs({ { armor = true }, { cape = true }, { helmet = true, cape = true } }) do
        activate('save_setup')
        local accepted, reason = pcall(frontend.menu.outfit_dialog.on_save, 'Cape fixture', scope)
        assert(
            not accepted
                and reason:find('material LUTs are unavailable', 1, true)
                and saved_outfit == saved_before
                and outfit_save_calls == save_count
                and created == texture_count,
            'Missing checked material family silently saved a partial preset'
        )
    end
    local helmet_only = save({ helmet = true })
    assert(#helmet_only.helmet > 0 and #helmet_only.armor == 0 and #helmet_only.cape == 0)
end
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
-- Imported palettes can target all Cape materials without selecting Cape in
-- the Armor dropdown or changing same-resource Armor/Helmet bindings.
actor(4)
kits.cape = 13
h = api.mods.epic_direct_lut.handle
activate('populate_worn')
assert(h.set('basic_armor_lut', 1))
local imported_pixels = ffi.new('float[736]')
imported_pixels[0] = 0.625
DDS.write(fixture .. '/cape-import.dds', imported_pixels, 23, 8)
assert(h.set('format', 1) and h.set('file', 'cape-import'))
activate('load')
armor, cape, helmet = current()
activate('apply_file_cape')
local imported_cape = bound[cape][1]
assert(
    imported_cape ~= 4001 and bound[armor][1] == 4001 and bound[helmet][1] == 4002,
    'Imported Cape action changed Armor/Helmet or failed to target Cape'
)
assert(bound[cape][3] == 999 and h.get('scope') == 5, 'Imported Cape action changed the tint slot or scope')
activate('global_undo')
assert(
    bound[cape][1] == 4001 and bound[armor][1] == 4001 and bound[helmet][1] == 4002,
    'Imported Cape Undo changed unrelated gear'
)
activate('global_redo')
assert(
    bound[cape][1] == imported_cape and bound[armor][1] == 4001,
    'Imported Cape Redo did not restore the isolated application'
)
os.remove(fixture .. '/cape-import.dds')
-- Armory compatibility uses exact current Cape destinations, never an arbitrary
-- Armor table. Typed Cape entries take priority over historical Armor labels.
do
    activate('restore')
    local cape_doc = { width = 23, height = 8, data = ffi.new('float[736]') }
    cape_doc.data[0], cape_doc.data[3] = 0.8125, 1.625
    local legacy_doc = { width = 23, height = 8, data = ffi.new('float[736]') }
    legacy_doc.data[0] = 0.25
    local function choose(entries)
        saved_outfit = { name = 'Cape fixture', entries = entries, armor = {}, helmet = {}, cape = {} }
        for _, entry in ipairs(entries) do
            saved_outfit[entry.kind][#saved_outfit[entry.kind] + 1] = entry.document
        end
        assert(h.set('outfit_preset', 1) and h.set('outfit_preset', 2))
    end
    -- V1 mesh families can gain one LOD destination. Expand only a uniform
    -- saved family; conflicting saved palettes cannot invent the fourth tint.
    do
        local armor_unit = units[1].unit
        local prior_materials, prior_log = materials[armor_unit], ctx.log
        local family, entries = {}, {}
        local family_doc = m.basic_state.clone(stock)
        family_doc.data[0] = 0.625
        materials[armor_unit] = {}
        for mesh = 1, 4 do
            local material = armor + 40 + mesh
            family[mesh] = material
            materials[armor_unit][mesh] = {
                mesh = material + 10,
                material = material,
                mesh_index = mesh,
                material_index = 0,
            }
            bound[material] = { [1] = 4001, [3] = 0 }
            entries[mesh] = { kind = 'armor', key = '0:2:' .. (mesh - 1) .. ':0', document = family_doc }
        end
        activate('populate_worn')
        local extra_logs = 0
        ctx.log = function(text)
            if text:find('ARMORY_APPLY', 1, true) and text:find('slot=0:2:4:0 ', 1, true) then
                assert(
                    bound[family[4]][1] ~= 4001 and text:find('match=mesh-family verified=true', 1, true),
                    'Extra-LOD success log preceded its verified native application'
                )
                extra_logs = extra_logs + 1
            end
        end
        choose(entries)
        activate('outfit_apply_armor')
        local family_object = bound[family[1]][1]
        for _, material in ipairs(family) do
            assert(
                bound[material][1] == family_object and family_object ~= 4001,
                'Uniform saved family missed a live LOD'
            )
        end
        assert(
            extra_logs == 1 and bound[cape][1] == 4001 and bound[helmet][1] == 4002,
            'LOD family expansion changed Cape/Helmet or lacked its verified match log'
        )
        activate('restore')
        local conflicting = m.basic_state.clone(family_doc)
        conflicting.data[0] = 0.875
        entries[4] = { kind = 'armor', key = '0:2:3:0', document = conflicting }
        choose(entries)
        activate('outfit_apply_armor')
        assert(
            bound[family[1]][1] ~= 4001
                and bound[family[3]][1] ~= 4001
                and bound[family[4]][1] == 4001
                and extra_logs == 1
                and bound[cape][1] == 4001
                and bound[helmet][1] == 4002,
            'Conflicting saved mesh colors expanded onto an unmatched LOD'
        )
        activate('restore')
        ctx.log, materials[armor_unit] = prior_log, prior_materials
        activate('populate_worn')
    end
    choose({
        { kind = 'armor', key = '0:1:0:0', document = legacy_doc },
        { kind = 'cape', key = '0:1:0:0', document = cape_doc },
    })
    activate('outfit_apply_cape')
    local typed = bound[cape][1]
    assert(
        typed ~= 4001 and bound[armor][1] == 4001 and bound[helmet][1] == 4002,
        'Typed Cape selection escaped current destination'
    )
    activate('restore')
    choose({ { kind = 'armor', key = '0:1:0:0', document = cape_doc } })
    assert(not api.mods[h.id].controls.outfit_apply_cape.disabled, 'Legacy same-destination Cape entry is unavailable')
    activate('outfit_apply_cape')
    assert(
        bound[cape][1] == typed and bound[armor][1] == 4001,
        'Legacy Cape adaptation chose another Armor destination'
    )
    activate('restore')
    choose({ { kind = 'armor', key = '0:2:0:0', document = cape_doc } })
    local count = created
    local accepted = pcall(h.activate, 'outfit_apply_cape')
    assert(
        not accepted and created == count and bound[cape][1] == 4001,
        'Unmatched Armor entry became a blanket Cape override'
    )
    choose({ { kind = 'cape', key = '0:1:0:0', document = cape_doc } })
    proof_ready = false
    local refused = api.mods[h.id].controls.outfit_apply_cape.on_activate()
    assert(
        refused:find('Current Cape identity unavailable', 1, true) and created == count and bound[cape][1] == 4001,
        'Armory Cape wrote without current identity'
    )
    proof_ready = true
    activate('populate_worn')
    bound[cape][1] = 777777
    refused = api.mods[h.id].controls.outfit_apply_cape.on_activate()
    assert(
        refused:find('Current Cape resource identity unavailable', 1, true)
            and created == count
            and bound[cape][1] == 777777,
        'Armory Cape adopted a foreign texture'
    )
    bound[cape][1] = 4001
    activate('populate_worn')
    local extra = cape + 20
    materials[units[2].unit][2] = { mesh = extra + 10, material = extra, mesh_index = 0, material_index = 1 }
    bound[extra] = { [1] = 4001, [3] = 998 }
    activate('populate_worn')
    choose({
        { kind = 'cape', key = '0:1:0:0', document = cape_doc },
        { kind = 'cape', key = '0:1:0:1', document = cape_doc },
    })
    activate('outfit_apply_cape')
    assert(
        bound[cape][1] == typed and bound[extra][1] == typed and bound[extra][3] == 998,
        'Armory Cape missed a matched second material'
    )
    activate('global_undo')
    assert(
        bound[cape][1] == 4001 and bound[extra][1] == 4001 and bound[armor][1] == 4001,
        'Multiple Cape targets were not one Undo action'
    )
    activate('global_redo')
    assert(bound[cape][1] == typed and bound[extra][1] == typed, 'Multiple Cape targets were not one Redo action')
    activate('restore')
    after_write = function(material)
        if material == cape then
            kits.cape = 99
        end
    end
    refused = api.mods[h.id].controls.outfit_apply_cape.on_activate()
    after_write = nil
    assert(
        refused:find('Cape kit changed', 1, true) and bound[extra][1] == 4001,
        'Armory Cape continued writing after a same-mount kit switch'
    )
    activate('populate_worn')
    assert(bound[cape][1] == 4001, 'Failed Armory Cape write lost the proof needed to retire its own prior color')
    kits.cape = 13
end
runtime.on_disable(ctx)
-- Cape Pattern entries use their dedicated owned session and slot. They never
-- reach the 23-column material upload or the separate tint/emblem binding.
do
    actor(5)
    armor, cape, helmet = current()
    local uploads = {}
    for index, material in ipairs({ armor, cape, helmet }) do
        local pattern =
            { width = 3, height = 1, data = ffi.new('float[12]'), resource = string.format('%016x', 5002 + index) }
        pattern.data[0] = index * 0.125
        bound[material][2], originals[5002 + index] = 5002 + index, pattern
    end
    m.engine.PATTERN_SLOT = 2
    m.pattern_luts = dofile('src/editor/pattern_luts.lua')
    local make_pattern, primed, pattern_model, prime_error = m.pattern_luts.new, {}, nil, false
    m.pattern_luts.new = function(...)
        pattern_model = make_pattern(...)
        local prime = pattern_model.prime
        pattern_model.prime = function(kind)
            primed[#primed + 1] = kind
            if prime_error then
                error('Simulated optional Pattern prime failure', 0)
            end
            return prime(kind)
        end
        return pattern_model
    end
    m.engine.create_texture = function(_, width, height, data)
        assert(width == 23 or width == 3 and height == 1, 'Wrong Cape DDS entered texture upload')
        created = created + 1
        local texture = { object = 90000 + created, width = width, height = height, data = data }
        uploads[texture.object] = ffi.string(data, width * height * 16)
        return texture
    end
    m.engine.bind = function(_, material, slot, object)
        assert(slot == 1 or slot == 2, 'Armory Cape touched tint/emblem slot')
        bound[material][slot] = object
    end
    m.direct_setup.new = function()
        return {
            read = function()
                return {}
            end,
            clear = function() end,
            save = function()
                return 1
            end,
        }
    end
    runtime.on_enable(ctx)
    runtime.on_update(ctx, 0)
    h = api.mods.epic_direct_lut.handle
    assert(#primed == 0, 'Startup populated Pattern values without an explicit Load Current Gear request')
    activate('populate_worn')
    assert(#primed == 1 and primed[1] == 'armor' and not pattern_model.is_open())
    do
        local time, now = os.time, os.time() + 10
        os.time = function()
            return now
        end
        for _ = 1, 3 do
            runtime.on_update(ctx, 0)
            basic_info()
        end
        assert(#primed == 1, 'Idle/render repeated a completed manual Pattern prime')
        assert(h.set('auto_populate_worn', true))
        runtime.on_update(ctx, 0)
        runtime.on_update(ctx, 1.1)
        assert(#primed == 1, 'Automatic populate/toggle primed the Pattern workspace')
        assert(h.set('auto_populate_worn', false))
        local helmet_source = originals[5002]
        originals[5002] = nil
        activate('populate_worn')
        assert(#primed == 1)
        now = now + 2
        runtime.on_update(ctx, 0)
        assert(#primed == 1, 'Pending manual material read primed Pattern too early')
        originals[5002] = helmet_source
        now = now + 2
        runtime.on_update(ctx, 0)
        assert(#primed == 2 and primed[2] == 'armor', 'Async manual material completion did not prime Pattern once')
        now = now + 2
        runtime.on_update(ctx, 0)
        assert(#primed == 2)
        originals[5002] = nil
        activate('populate_worn')
        now = now + 131
        runtime.on_update(ctx, 0)
        originals[5002] = helmet_source
        assert(h.set('auto_populate_worn', true))
        runtime.on_update(ctx, 0)
        assert(#primed == 2, 'Expired manual request primed a later automatic populate')
        assert(h.set('auto_populate_worn', false))
        prime_error = true
        activate('populate_worn')
        prime_error = false
        assert(#primed == 3 and basic_info().raw.basic.armor.document and not pattern_model.is_open())
        os.time = time
    end
    do
        local texture_count, history_count = created, #action_history.undo
        local native_before = {
            armor = { bound[armor][1], bound[armor][2] },
            helmet = { bound[helmet][1], bound[helmet][2] },
            cape = { bound[cape][1], bound[cape][2], bound[cape][3] },
        }
        for flags = 1, 7 do
            local scope = { armor = flags % 2 == 1, helmet = math.floor(flags / 2) % 2 == 1, cape = flags >= 4 }
            local subset = save(scope)
            local counts = { armor = { 0, 0 }, helmet = { 0, 0 }, cape = { 0, 0 } }
            for _, entry in ipairs(subset.entries) do
                assert(scope[entry.kind], 'Subset save leaked another gear family Pattern')
                local pattern = entry.key:sub(1, 2) == 'p:'
                assert(entry.document.width == (pattern and 3 or 23))
                counts[entry.kind][pattern and 2 or 1] = counts[entry.kind][pattern and 2 or 1] + 1
                assert(
                    ffi.string(entry.document.data, entry.document.width * entry.document.height * 16)
                        == ffi.string(entry.original.data, entry.original.width * entry.original.height * 16),
                    'Subset save altered original material/Pattern pixels'
                )
            end
            for _, kind in ipairs({ 'armor', 'helmet', 'cape' }) do
                local count = scope[kind] and 1 or 0
                assert(counts[kind][1] == count and counts[kind][2] == count)
            end
        end
        local original_pattern = originals[5005]
        originals[5005] = nil
        local helmet_only = save({ helmet = true })
        originals[5005] = original_pattern
        assert(
            #helmet_only.entries == 1
                and helmet_only.entries[1].kind == 'helmet'
                and helmet_only.entries[1].document.width == 23,
            'Unavailable optional Pattern prevented saving its checked material LUT'
        )
        assert(
            created == texture_count
                and #action_history.undo == history_count
                and bound[armor][1] == native_before.armor[1]
                and bound[armor][2] == native_before.armor[2]
                and bound[helmet][1] == native_before.helmet[1]
                and bound[helmet][2] == native_before.helmet[2]
                and bound[cape][1] == native_before.cape[1]
                and bound[cape][2] == native_before.cape[2]
                and bound[cape][3] == native_before.cape[3],
            'Subset material/Pattern saves changed native binding ownership or history'
        )
    end
    assert(h.set('outfit_preset', 1))
    local material = { width = 23, height = 8, data = ffi.new('float[736]') }
    local pattern = { width = 3, height = 1, data = ffi.new('float[12]') }
    material.data[0], pattern.data[0], pattern.data[3] = 0.6875, 0.9375, 1.875
    ffi.cast('uint32_t*', pattern.data)[7] = 0x80000000
    saved_outfit = {
        name = 'Cape fixture',
        armor = { stock },
        helmet = { stock },
        cape = { material, pattern },
        entries = {
            { kind = 'armor', key = '0:2:0:0', document = stock },
            { kind = 'helmet', key = '0:0:0:0', document = stock },
            { kind = 'cape', key = '0:1:0:0', document = material },
            { kind = 'cape', key = 'p:0:1:0:0', document = pattern },
        },
    }
    assert(h.set('outfit_preset', 2))
    local history_count = #action_history.undo
    activate('outfit_apply_cape')
    assert(
        uploads[bound[cape][1]] == ffi.string(material.data, 23 * 8 * 16)
            and uploads[bound[cape][2]] == ffi.string(pattern.data, 48),
        'Armory Cape material/Pattern upload did not preserve exact F32 bytes'
    )
    assert(
        bound[armor][1] == 5001
            and bound[armor][2] == 5003
            and bound[helmet][1] == 5002
            and bound[helmet][2] == 5005
            and bound[cape][3] == 999,
        'Armory Cape Pattern application changed unrelated material/Pattern/tint slots'
    )
    local material_object, pattern_object = bound[cape][1], bound[cape][2]
    assert(
        #action_history.undo == history_count + 1,
        'Mixed Cape material/Pattern application split its history action'
    )
    activate('global_undo')
    assert(bound[cape][1] == 5001 and bound[cape][2] == 5004, 'Mixed Cape Undo did not restore both exact slots')
    activate('global_redo')
    assert(
        bound[cape][1] == material_object and bound[cape][2] == pattern_object,
        'Mixed Cape Redo did not restore both owned textures'
    )
    history_count = #action_history.undo
    bound[cape][2] = 888888
    local accepted, refusal = h.activate('global_undo')
    assert(
        not accepted
            and refusal:find('Gear bindings changed', 1, true)
            and bound[cape][1] == material_object
            and bound[cape][2] == 888888
            and #action_history.undo == history_count,
        'Foreign Pattern rejection partially undid the Cape material or moved history'
    )
    bound[cape][2] = pattern_object
    local bind, fail_pattern = m.engine.bind, true
    m.engine.bind = function(native_arg, target, slot, object)
        if target == cape and slot == 2 and fail_pattern then
            fail_pattern = false
            error('simulated Pattern history write failure', 0)
        end
        return bind(native_arg, target, slot, object)
    end
    accepted = h.activate('global_undo')
    m.engine.bind = bind
    assert(
        not accepted
            and bound[cape][1] == material_object
            and bound[cape][2] == pattern_object
            and #action_history.undo == history_count,
        'Failed Pattern history write did not roll back the preceding material write'
    )
    activate('global_undo')
    assert(
        bound[cape][1] == 5001 and bound[cape][2] == 5004,
        'Mixed Cape history did not remain retryable after rollback'
    )
    activate('global_redo')
    -- A failed Redo rollback must retain only its still-owned forward write,
    -- including when the desired pool was empty before that Redo began.
    activate('global_undo')
    local redo_count = #action_history.redo
    m.engine.bind = function(native_arg, target, slot, object)
        if target == cape and (slot == 2 and object == pattern_object or slot == 1 and object == 5001) then
            error('simulated history rollback failure', 0)
        end
        return bind(native_arg, target, slot, object)
    end
    accepted = h.activate('global_redo')
    m.engine.bind = bind
    assert(
        not accepted
            and bound[cape][1] == material_object
            and bound[cape][2] == 5004
            and #action_history.redo == redo_count,
        'Failed history rollback lost the exact partial forward state or moved history'
    )
    activate('restore')
    assert(bound[cape][1] == 5001 and bound[cape][2] == 5004, 'Cape material/Pattern originals failed to restore')
    -- If a foreign writer wins during rollback, its third object is neither
    -- claimed as ours nor removed by the later Restore.
    activate('outfit_apply_cape')
    activate('global_undo')
    m.engine.bind = function(native_arg, target, slot, object)
        if target == cape and slot == 2 and object == pattern_object then
            error('simulated Pattern Redo failure', 0)
        elseif target == cape and slot == 1 and object == 5001 then
            bound[target][slot] = 999999
            error('foreign writer replaced rollback target', 0)
        end
        return bind(native_arg, target, slot, object)
    end
    accepted = h.activate('global_redo')
    m.engine.bind = bind
    assert(
        not accepted and bound[cape][1] == 999999 and bound[cape][2] == 5004,
        'History rollback overwrote a foreign third object'
    )
    activate('restore')
    assert(bound[cape][1] == 999999, 'Restore adopted a foreign object from failed history rollback')
    bound[cape][1] = 5001
    activate('refresh')
    saved_outfit.entries = { saved_outfit.entries[4] }
    saved_outfit.armor, saved_outfit.helmet, saved_outfit.cape = {}, {}, { pattern }
    assert(h.set('outfit_preset', 1) and h.set('outfit_preset', 2))
    assert(not api.mods[h.id].controls.outfit_apply_cape.disabled, 'Matched Pattern-only Cape preset cannot apply')
    activate('outfit_apply_cape')
    assert(
        bound[cape][1] == 5001 and uploads[bound[cape][2]] == ffi.string(pattern.data, 48),
        'Pattern-only Cape preset altered its material'
    )
    activate('restore')
    local count = created
    bound[cape][2] = 888888
    local refused = api.mods[h.id].controls.outfit_apply_cape.on_activate()
    assert(
        refused:find('Current Cape resource identity unavailable', 1, true)
            and created == count
            and bound[cape][2] == 888888,
        'Cape Pattern application adopted a foreign binding'
    )
    bound[cape][2] = 5004
    do
        local documents, destinations = {}, { armor = '0:2:0:0', helmet = '0:0:0:0', cape = '0:1:0:0' }
        local physical = { armor = armor, helmet = helmet, cape = cape }
        local pattern_objects = { armor = 5003, helmet = 5005, cape = 5004 }
        local entries = {}
        for index, kind in ipairs({ 'armor', 'helmet', 'cape' }) do
            local material = m.basic_state.clone(stock)
            local pattern = m.basic_state.clone(originals[pattern_objects[kind]])
            material.data[0], material.data[3], pattern.data[0], pattern.data[3] = index / 8, 1.875, index / 5, -0.75
            documents[kind] = { material, pattern }
            entries[#entries + 1] = { kind = kind, key = destinations[kind], document = material }
            entries[#entries + 1] = { kind = kind, key = 'p:' .. destinations[kind], document = pattern }
        end
        assert(h.set('outfit_preset', 1))
        saved_outfit = {
            name = 'Cape fixture',
            armor = documents.armor,
            helmet = documents.helmet,
            cape = documents.cape,
            entries = entries,
        }
        assert(h.set('outfit_preset', 2))
        local function select_targets(flags)
            local scope = { armor = flags % 2 == 1, helmet = math.floor(flags / 2) % 2 == 1, cape = flags >= 4 }
            local texture_count, history_count = created, #action_history.undo
            for _, kind in ipairs({ 'armor', 'helmet', 'cape' }) do
                assert(h.set('outfit_target_' .. kind, scope[kind]))
            end
            local raw = basic_info().armory_targets
            assert(raw.armor == scope.armor and raw.helmet == scope.helmet and raw.cape == scope.cape)
            assert(
                created == texture_count and #action_history.undo == history_count,
                'Armory targets edited live gear or history'
            )
            return scope
        end
        local function native_snapshot()
            local result = {}
            for kind, material in pairs(physical) do
                result[kind] = { bound[material][1], bound[material][2], bound[material][3] }
            end
            return result
        end
        local function same_native(expected)
            for kind, material in pairs(physical) do
                for slot = 1, 3 do
                    assert(
                        bound[material][slot] == expected[kind][slot],
                        'Grouped preset escaped its prior native state'
                    )
                end
            end
        end
        local function applied(scope, old)
            for kind, material in pairs(physical) do
                if scope[kind] then
                    for slot = 1, 2 do
                        local d = documents[kind][slot]
                        assert(
                            uploads[bound[material][slot]] == ffi.string(d.data, d.width * d.height * 16),
                            'Grouped preset missed a checked material/Pattern family or changed its F32 bytes'
                        )
                    end
                else
                    assert(bound[material][1] == old[kind][1] and bound[material][2] == old[kind][2])
                end
                assert(bound[material][3] == old[kind][3], 'Grouped preset changed the Cape tint/emblem slot')
            end
        end
        for flags = 1, 7 do
            activate('restore')
            local scope = select_targets(flags)
            local before, history_count = native_snapshot(), #action_history.undo
            activate('outfit_apply_selected')
            applied(scope, before)
            assert(#action_history.undo == history_count + 1, 'Grouped preset created more than one Undo action')
            local after = native_snapshot()
            activate('global_undo')
            same_native(before)
            activate('global_redo')
            same_native(after)
        end
        -- A malformed later family is rejected before any earlier family uploads.
        select_targets(3)
        local before, texture_count, history_count = native_snapshot(), created, #action_history.undo
        local bad = m.basic_state.clone(documents.helmet[1])
        bad.width = 16
        saved_outfit.helmet, entries[3].document = { bad, documents.helmet[2] }, bad
        local accepted, reason = h.activate('outfit_apply_selected')
        saved_outfit.helmet, entries[3].document = documents.helmet, documents.helmet[1]
        assert(
            accepted
                and reason:find('Invalid saved LUT target or dimensions', 1, true)
                and created == texture_count
                and #action_history.undo == history_count,
            'Grouped preflight wrote a partial outfit before rejecting a later saved family'
        )
        same_native(before)
        -- Fail the first Pattern write after all three materials have changed.
        select_targets(7)
        before, history_count = native_snapshot(), #action_history.undo
        local drafts = {}
        for _, container in ipairs({ 'armor', 'helmet' }) do
            local d = basic_info().raw.basic[container].document
            drafts[container] = ffi.string(d.data, d.width * d.height * 16)
        end
        local replacement = { name = 'Cape fixture', armor = {}, helmet = {}, cape = {}, entries = {} }
        for _, entry in ipairs(entries) do
            local changed = m.basic_state.clone(entry.document)
            changed.data[0] = changed.data[0] + 0.0375
            replacement.entries[#replacement.entries + 1] = { kind = entry.kind, key = entry.key, document = changed }
            replacement[entry.kind][#replacement[entry.kind] + 1] = changed
        end
        assert(h.set('outfit_preset', 1))
        saved_outfit = replacement
        assert(h.set('outfit_preset', 2))
        local native_bind, failed, material_writes = m.engine.bind, false, 0
        m.engine.bind = function(_, target, slot, object)
            if not failed and object >= 90000 then
                if slot == 1 then
                    material_writes = material_writes + 1
                elseif slot == 2 then
                    failed = true
                    error('Simulated grouped Pattern failure', 0)
                end
            end
            return native_bind(_, target, slot, object)
        end
        accepted, reason = h.activate('outfit_apply_selected')
        m.engine.bind = native_bind
        assert(
            accepted
                and failed
                and material_writes == 3
                and reason:find('Simulated grouped Pattern failure', 1, true)
                and not reason:find('rollback failed', 1, true)
                and #action_history.undo == history_count,
            'Failed grouped apply did not roll prior custom material/Pattern state back atomically'
        )
        same_native(before)
        for _, container in ipairs({ 'armor', 'helmet' }) do
            local d = basic_info().raw.basic[container].document
            assert(
                ffi.string(d.data, d.width * d.height * 16) == drafts[container],
                'Failed grouped apply retained a partial Basic draft'
            )
        end
        runtime.on_update(ctx, 0.5)
        same_native(before)
        select_targets(0)
        texture_count = created
        accepted, reason = h.activate('outfit_apply_selected')
        assert(
            accepted
                and reason:find('Check at least one available gear type', 1, true)
                and created == texture_count
                and #action_history.undo == history_count,
            'Empty preset target scope issued native writes or added history'
        )
        same_native(before)
        -- Default checked targets omit families absent from this saved preset.
        local helmet_only = { name = 'Cape fixture', armor = {}, helmet = replacement.helmet, cape = {}, entries = {} }
        for _, entry in ipairs(replacement.entries) do
            if entry.kind == 'helmet' then
                helmet_only.entries[#helmet_only.entries + 1] = entry
            end
        end
        assert(h.set('outfit_preset', 1))
        saved_outfit = helmet_only
        assert(h.set('outfit_preset', 2))
        select_targets(7)
        activate('outfit_apply_selected')
        assert(
            #action_history.undo == history_count + 1
                and bound[armor][1] == before.armor[1]
                and bound[armor][2] == before.armor[2]
                and bound[cape][1] == before.cape[1]
                and bound[cape][2] == before.cape[2],
            'Default checked targets applied gear families absent from the saved preset'
        )
        for slot = 1, 2 do
            local d = helmet_only.helmet[slot]
            assert(uploads[bound[helmet][slot]] == ffi.string(d.data, d.width * d.height * 16))
        end
        activate('global_undo')
        same_native(before)
        -- Basic's per-LUT chooser separates two Armor resources and always
        -- brings the Pattern at each selected physical destination with it.
        local other = armor + 20
        materials[units[1].unit][2] = { mesh = other + 10, material = other, mesh_index = 1, material_index = 1 }
        bound[other] = { [1] = 5010, [2] = 5011, [3] = 0 }
        originals[5010] = m.basic_state.clone(stock)
        originals[5010].resource = '4444444444444444'
        originals[5011] = m.basic_state.clone(originals[5003])
        originals[5011].resource = '5555555555555555'
        local extra_material, extra_pattern = m.basic_state.clone(stock), m.basic_state.clone(originals[5011])
        extra_material.data[0], extra_material.data[3], extra_pattern.data[0] = 0.8125, 2.25, 0.9375
        local chooser_preset = { name = 'Cape fixture', armor = {}, helmet = {}, cape = {}, entries = {} }
        for _, entry in ipairs(entries) do
            chooser_preset.entries[#chooser_preset.entries + 1] = entry
            chooser_preset[entry.kind][#chooser_preset[entry.kind] + 1] = entry.document
        end
        chooser_preset.entries[#chooser_preset.entries + 1] =
            { kind = 'armor', key = '0:2:1:1', document = extra_material }
        chooser_preset.entries[#chooser_preset.entries + 1] =
            { kind = 'armor', key = 'p:0:2:1:1', document = extra_pattern }
        chooser_preset.armor[#chooser_preset.armor + 1] = extra_material
        chooser_preset.armor[#chooser_preset.armor + 1] = extra_pattern
        assert(h.set('outfit_preset', 1))
        saved_outfit = chooser_preset
        assert(h.set('outfit_preset', 2))
        activate('restore')
        local function chooser()
            local texture_count, history_count = created, #action_history.undo
            activate('outfit_choose_luts')
            local dialog = assert(frontend.menu.lut_apply_dialog)
            assert(dialog.title == 'Apply Preset' and #dialog.columns == 2)
            assert(dialog.columns[1].title == 'Armor / Cape' and dialog.columns[2].title == 'Helmet')
            assert(#dialog.columns[1].items == 3 and #dialog.columns[2].items == 1)
            assert(
                created == texture_count and #action_history.undo == history_count,
                'Opening LUT chooser changed native gear/history'
            )
            local map, all = {}, {}
            for _, column in ipairs(dialog.columns) do
                for _, item in ipairs(column.items) do
                    assert(not map[item.label] and type(item.id) == 'string')
                    map[item.label] = item
                    all[item.id] = item.enabled == true
                    assert(item.checked == item.enabled, 'Chooser did not initially check all enabled LUTs')
                end
            end
            return dialog, map, all
        end
        local dialog, items = chooser()
        local extra = assert(items['Armor LUT 2'])
        assert(items['Armor LUT 1'] and items['Cape LUT 1'] and items['Helmet LUT 1'])
        for _, item in pairs(items) do
            assert(item.enabled and item.detail == 'Pattern included')
        end
        before, history_count = native_snapshot(), #action_history.undo
        local extra_before = { bound[other][1], bound[other][2] }
        include_patterns = false
        assert(dialog.on_apply({ [extra.id] = true }))
        assert(
            uploads[bound[other][1]] == ffi.string(extra_material.data, 23 * 8 * 16)
                and uploads[bound[other][2]] == ffi.string(extra_pattern.data, 48)
                and #action_history.undo == history_count + 1
                and frontend.menu.lut_apply_dialog == nil,
            'Selected Armor LUT failed to include its mandatory Pattern in one Undo action'
        )
        same_native(before)
        local extra_after = { bound[other][1], bound[other][2] }
        activate('global_undo')
        assert(bound[other][1] == extra_before[1] and bound[other][2] == extra_before[2])
        same_native(before)
        activate('global_redo')
        assert(bound[other][1] == extra_after[1] and bound[other][2] == extra_after[2])
        include_patterns = true
        activate('restore')
        local all
        dialog, items, all = chooser()
        history_count = #action_history.undo
        local previous_action = action_history.undo[history_count]
        before, extra_before = native_snapshot(), { bound[other][1], bound[other][2] }
        assert(dialog.on_apply(all))
        applied({ armor = true, helmet = true, cape = true }, native_snapshot())
        assert(uploads[bound[other][1]] == ffi.string(extra_material.data, 23 * 8 * 16))
        assert(uploads[bound[other][2]] == ffi.string(extra_pattern.data, 48))
        assert(
            #action_history.undo <= history_count + 1 and action_history.undo[#action_history.undo] ~= previous_action,
            'Select All split its material/Pattern application history'
        )
        activate('global_undo')
        same_native(before)
        assert(bound[other][1] == extra_before[1] and bound[other][2] == extra_before[2])
        activate('restore')
        local function refused(dialog, selected, text)
            local texture_count, history_count = created, #action_history.undo
            local native_before, extra_before = native_snapshot(), { bound[other][1], bound[other][2] }
            local accepted, reason = pcall(dialog.on_apply, selected)
            assert(not accepted and reason:find(text, 1, true), 'Chooser did not explain its rejected target')
            assert(created == texture_count and #action_history.undo == history_count)
            assert(
                frontend.menu.lut_apply_dialog == dialog,
                'Rejected chooser closed instead of retaining its selection'
            )
            same_native(native_before)
            assert(bound[other][1] == extra_before[1] and bound[other][2] == extra_before[2])
        end
        dialog, items = chooser()
        extra = items['Armor LUT 2']
        refused(dialog, {}, 'Select at least one current LUT')
        refused(dialog, { unknown = true }, 'Preset LUT choices changed')
        local old = chooser_preset.entries[1].document.data[0]
        chooser_preset.entries[1].document.data[0] = old + 0.125
        refused(dialog, { [extra.id] = true }, 'Saved preset changed')
        chooser_preset.entries[1].document.data[0] = old
        kits.armor = 99
        refused(dialog, { [extra.id] = true }, 'Worn gear changed')
        kits.armor = 11
        old = bound[other][1]
        bound[other][1] = 888777
        refused(dialog, { [extra.id] = true }, 'Current LUT target changed')
        bound[other][1] = old
        local pattern_original = originals[5011]
        originals[5011] = nil
        refused(dialog, { [extra.id] = true }, 'Current LUT resource changed')
        local disabled
        dialog, items = chooser()
        disabled = items['Armor LUT 2']
        assert(not disabled.enabled and not disabled.checked)
        refused(dialog, { [disabled.id] = true }, 'This current LUT cannot use')
        originals[5011] = pattern_original
        dialog, items = chooser()
        extra = items['Armor LUT 2']
        local extra_member = armor + 30
        materials[units[1].unit][3] =
            { mesh = extra_member + 10, material = extra_member, mesh_index = 2, material_index = 1 }
        bound[extra_member] = { [1] = 5010, [2] = 5011, [3] = 0 }
        refused(dialog, { [extra.id] = true }, 'Current LUT members changed')
        materials[units[1].unit][3] = nil
        dialog, items = chooser()
        extra = items['Armor LUT 2']
        local old_bind, failed = m.engine.bind, false
        m.engine.bind = function(_, material, slot, object)
            if not failed and material == other and slot == 2 and object >= 90000 then
                failed = true
                error('Simulated chooser Pattern failure', 0)
            end
            return old_bind(_, material, slot, object)
        end
        before, history_count = native_snapshot(), #action_history.undo
        extra_before = { bound[other][1], bound[other][2] }
        local accepted, reason = pcall(dialog.on_apply, { [extra.id] = true })
        m.engine.bind = old_bind
        assert(
            not accepted
                and failed
                and reason:find('Simulated chooser Pattern failure', 1, true)
                and not reason:find('rollback failed', 1, true)
                and #action_history.undo == history_count,
            'Chooser Pattern failure left a partial material application/history'
        )
        same_native(before)
        assert(bound[other][1] == extra_before[1] and bound[other][2] == extra_before[2])
        assert(frontend.menu.lut_apply_dialog == dialog)
        -- Legacy material-only presets have no companion to invent or opt out.
        local saved_pattern_entry = table.remove(chooser_preset.entries)
        local saved_pattern_document = table.remove(chooser_preset.armor)
        dialog, items = chooser()
        extra = items['Armor LUT 2']
        assert(
            extra.enabled and extra.checked and extra.detail == nil,
            'Material-only chooser displayed a fake Pattern detail'
        )
        local previous_pattern = bound[other][2]
        assert(dialog.on_apply({ [extra.id] = true }))
        assert(bound[other][2] == previous_pattern, 'Material-only preset changed an unsaved Pattern')
        chooser_preset.entries[#chooser_preset.entries + 1] = saved_pattern_entry
        chooser_preset.armor[#chooser_preset.armor + 1] = saved_pattern_document
    end
    runtime.on_disable(ctx)
end
-- Basic camo edits only the explicitly checked regions of one resource/kind.
-- Its transient row scope stays independent of document history.
do
    actor(6)
    armor, cape, helmet = current()
    local helmet_stock = m.basic_state.clone(stock)
    for column = 17, 20 do
        local at = (7 * 23 + column - 1) * 4
        helmet_stock.data[at], helmet_stock.data[at + 1] = 1.625, -0.875
        helmet_stock.data[at + 2], helmet_stock.data[at + 3] = 2.25, 3.75
    end
    helmet_stock.data[(7 * 23 + 21) * 4 + 3] = 3
    originals[6002] = helmet_stock
    local other, same = armor + 20, armor + 30
    materials[units[1].unit][2] = { mesh = other + 10, material = other, mesh_index = 0, material_index = 1 }
    materials[units[1].unit][3] = { mesh = same + 10, material = same, mesh_index = 0, material_index = 2 }
    bound[other], bound[same] = { [1] = 6003, [3] = 0 }, { [1] = 6001, [3] = 0 }
    local other_doc = m.basic_state.clone(stock)
    other_doc.resource = '2222222222222222'
    originals[6003] = other_doc
    local uploads, fail_next, fail_material = {}, false, armor
    m.engine.create_texture = function(_, width, height, data)
        assert(width == 23 or width == 3 and height == 1)
        created = created + 1
        local texture = { object = 90000 + created, width = width, height = height, data = data }
        uploads[texture.object] = ffi.string(data, width * height * 16)
        return texture
    end
    m.engine.bind = function(_, material, slot, object)
        if fail_next and material == fail_material then
            fail_next = false
            error('simulated camo bind failure', 0)
        end
        bound[material][slot] = object
        if after_write then
            after_write(material)
        end
    end
    local source, close_ready, starts = nil, false, 0
    m.camo_patterns = {
        new = function()
            starts = starts + 1
            source = {
                state = 'ready',
                start = function() end,
                tick = function() end,
                get = function()
                    return nil
                end,
                close = function()
                    source.closes = (source.closes or 0) + 1
                    return close_ready
                end,
            }
            return source
        end,
    }
    runtime.on_enable(ctx)
    runtime.on_update(ctx, 0)
    h = api.mods.epic_direct_lut.handle
    activate('populate_worn')
    frontend.basic_mode = true
    api.focus_page(h.id, 'basic')
    assert(h.set('basic_armor_lut', 1) and h.set('edit_row', 7))
    local initial = basic_info().raw.basic.armor.document
    local before, initial_revision = ffi.string(initial.data, initial.width * initial.height * 16), initial.revision
    local armor_rows, helmet_rows = { [1] = true, [3] = true }, {}
    for row = 1, 7 do
        helmet_rows[row] = true
    end
    local function choose_rows(kind, rows)
        local panel = basic_info().raw.basic[kind]
        for row = 1, panel.document.height do
            assert(basic_camo_row(row, kind, rows[row] == true, panel.camo_rows))
        end
        return basic_info().raw.basic[kind]
    end
    local function assert_scope(panel, expected)
        local count = 0
        for row = 1, panel.document.height do
            assert(panel.camo_rows[row] == (expected[row] == true), 'Camo scope contains an unexpected region')
            count = count + (expected[row] and 1 or 0)
        end
        assert(panel.camo_count == count, 'Camo checked-region count is stale')
    end
    local function recipe_bytes(source, index, mask, rows, keep_colors)
        local palette = m.basic_camo.COLORWAYS[index]
        local values = ffi.new('float[736]')
        ffi.copy(values, source, #source)
        for row = 1, 8 do
            local offset = (row - 1) * 23 * 4
            if rows[row] then
                for color, hex in ipairs(palette.colors) do
                    if not keep_colors then
                        for channel = 0, 2 do
                            values[offset + (15 + color) * 4 + channel] = tonumber(
                                hex:sub(channel * 2 + 1, channel * 2 + 2),
                                16
                            ) / 255
                        end
                    end
                    values[offset + (15 + color) * 4 + 3] = ({ 0.52978515625, 2, -1, 4 })[color]
                end
                values[offset + 20 * 4 + 3] = 0.8896484375
                for channel = 0, 2 do
                    values[offset + 21 * 4 + channel] = palette.mask[channel + 1]
                end
                values[offset + 21 * 4 + 3] = mask
                values[offset + 22 * 4 + 3] = palette.blend
            end
        end
        return ffi.string(values, #source)
    end
    do
        local raw = basic_info().raw.basic
        local history_count, redo_count, texture_count = #action_history.undo, #action_history.redo, created
        for _, kind in ipairs({ 'armor', 'helmet' }) do
            assert_scope(raw[kind], {})
            local prefix = 'basic_' .. kind .. '_camo'
            local controls = api.mods[h.id].controls
            assert(controls[prefix].disabled and controls[prefix .. '_colorway'].disabled)
            for color = 1, 4 do
                local field = controls[prefix .. '_color_' .. color]
                assert(field.disabled and field.can_open_picker() == false)
            end
            assert(not pcall(h.set, prefix, 7), 'Unchecked Camo pattern control remains enabled')
            local refusal = controls[prefix].on_change(7)
            assert(refusal:find('Select at least one Camo region', 1, true))
            refusal = controls[prefix .. '_colorway'].on_change(3)
            assert(refusal:find('Select at least one Camo region', 1, true))
            assert(controls[prefix .. '_color_1'].picker_commit('#123456') == false)
        end
        assert(
            created == texture_count
                and #action_history.undo == history_count
                and #action_history.redo == redo_count
                and basic_info().raw.basic.armor.document == initial
                and ffi.string(initial.data, #before) == before
                and bound[armor][1] == 6001
                and bound[same][1] == 6001
                and bound[helmet][1] == 6002,
            'Unchecked Camo actions changed a document, history or native texture'
        )
        assert(not basic_camo_row(0, 'armor', true) and not basic_camo_row(9, 'armor', true))
        assert(not basic_camo_row(1.5, 'armor', true) and not basic_camo_row(1, 'armor', 1))
        assert(not basic_camo_row(1, 'invalid', true))
        local panel = choose_rows('armor', armor_rows)
        assert_scope(panel, armor_rows)
        assert(
            created == texture_count
                and #action_history.undo == history_count
                and #action_history.redo == redo_count
                and panel.document == initial
                and panel.document.revision == initial_revision
                and ffi.string(initial.data, #before) == before
                and not api.mods[h.id].controls.basic_armor_camo.disabled,
            'Camo checkbox toggles allocated textures, edited pixels or entered history'
        )
    end
    local count = #action_history.undo
    assert(h.set('basic_armor_camo', 7))
    local applied = basic_info().raw.basic.armor.document
    local bytes = recipe_bytes(before, 1, 4, armor_rows)
    local armor_camo = bound[armor][1]
    assert(
        applied ~= initial
            and ffi.string(initial.data, #before) == before
            and ffi.string(applied.data, #before) == bytes
            and uploads[armor_camo] == bytes,
        'Basic camo changed unchecked rows, missed its complete upload or changed the old draft'
    )
    assert(
        bound[same][1] == armor_camo
            and bound[other][1] == 6003
            and bound[cape][1] == 6001
            and bound[cape][3] == 999
            and bound[helmet][1] == 6002,
        'Selected Armor camo escaped its exact resource/kind bindings'
    )
    assert(#action_history.undo == count + 1, 'Checked-region camo was not one history action')
    activate('global_undo')
    assert(
        bound[armor][1] == 6001
            and bound[same][1] == 6001
            and ffi.string(basic_info().raw.basic.armor.document.data, #before) == before,
        'Basic camo Undo lost the original live/local table'
    )
    assert_scope(basic_info().raw.basic.armor, armor_rows)
    activate('global_redo')
    assert(
        bound[armor][1] == armor_camo
            and bound[same][1] == armor_camo
            and ffi.string(basic_info().raw.basic.armor.document.data, #before) == bytes,
        'Basic camo Redo lost the full table'
    )
    assert_scope(basic_info().raw.basic.armor, armor_rows)
    local helmet_before = ffi.string(basic_info().raw.basic.helmet.document.data, #before)
    choose_rows('helmet', helmet_rows)
    assert(h.set('basic_helmet_camo', 4))
    local helmet_doc = basic_info().raw.basic.helmet.document
    local helmet_pattern_bytes = recipe_bytes(helmet_before, 1, 1, helmet_rows)
    local helmet_pattern_object = bound[helmet][1]
    assert(uploads[helmet_pattern_object] == helmet_pattern_bytes, 'Helmet pattern did not isolate visor Region 8')
    assert(
        bound[armor][1] == armor_camo and bound[cape][1] == 6001 and bound[other][1] == 6003,
        'Helmet camo changed Armor/Cape/other resource'
    )
    activate('global_undo')
    assert(
        bound[helmet][1] == 6002 and ffi.string(basic_info().raw.basic.helmet.document.data, #before) == helmet_before,
        'Helmet pattern Undo lost original visor HDR fields'
    )
    activate('global_redo')
    assert(bound[helmet][1] == helmet_pattern_object and uploads[bound[helmet][1]] == helmet_pattern_bytes)
    local function tinted(source, palette, rows)
        local values = ffi.new('float[736]')
        ffi.copy(values, source, #source)
        for color, hex in pairs(palette) do
            for row = 1, 8 do
                if rows[row] then
                    for channel = 0, 2 do
                        values[((row - 1) * 23 + 15 + color) * 4 + channel] = tonumber(
                            hex:sub(channel * 2 + 1, channel * 2 + 2),
                            16
                        ) / 255
                    end
                end
            end
        end
        return ffi.string(values, #source)
    end
    do
        local color_count = #action_history.undo
        assert(h.set('basic_helmet_camo_colorway', 4))
        local colorway_bytes = recipe_bytes(helmet_pattern_bytes, 3, 1, helmet_rows)
        local colorway_object = bound[helmet][1]
        basic_info()
        assert(
            uploads[colorway_object] == colorway_bytes
                and #action_history.undo == color_count + 1
                and h.get('basic_helmet_camo_colorway') == 4
                and bound[armor][1] == armor_camo,
            'Helmet colorway changed visor RGB/alpha, Armor or selector recognition'
        )
        activate('global_undo')
        assert(bound[helmet][1] == helmet_pattern_object)
        activate('global_redo')
        assert(bound[helmet][1] == colorway_object)
        assert(h.set('basic_helmet_camo_color_2', '#40A020'))
        assert(
            uploads[bound[helmet][1]] == tinted(colorway_bytes, { [2] = '40A020' }, helmet_rows)
                and bound[armor][1] == armor_camo
                and bound[cape][1] == 6001,
            'Helmet tint changed Region 8 visor bytes or another gear kind'
        )
    end
    do
        local old = basic_info().raw.basic.helmet.document
        local old_bytes, old_object = ffi.string(old.data, #before), bound[helmet][1]
        local history_count, texture_count = #action_history.undo, created
        local visor_rows = { [8] = true }
        assert_scope(choose_rows('helmet', visor_rows), visor_rows)
        assert(created == texture_count and #action_history.undo == history_count)
        assert(h.set('basic_helmet_camo', 5), 'Helmet Region 8 cannot explicitly opt into Camo')
        local visor_bytes = recipe_bytes(old_bytes, 1, 2, visor_rows, true)
        local visor_object = bound[helmet][1]
        assert(
            uploads[visor_object] == visor_bytes
                and #action_history.undo == history_count + 1
                and bound[armor][1] == armor_camo
                and bound[cape][1] == 6001,
            'Explicit Helmet Region 8 Camo changed an unchecked row or another gear kind'
        )
        activate('global_undo')
        assert(
            bound[helmet][1] == old_object
                and ffi.string(basic_info().raw.basic.helmet.document.data, #before) == old_bytes
        )
        assert_scope(basic_info().raw.basic.helmet, visor_rows)
        activate('global_redo')
        assert(bound[helmet][1] == visor_object and uploads[visor_object] == visor_bytes)
        assert_scope(basic_info().raw.basic.helmet, visor_rows)
        activate('global_undo')
        choose_rows('helmet', helmet_rows)
    end
    local helmet_object, color_history = bound[helmet][1], #action_history.undo
    assert(h.set('basic_armor_camo_colorway', 3))
    local colorway_object = bound[armor][1]
    local colorway_bytes = recipe_bytes(bytes, 2, 4, armor_rows)
    assert(
        uploads[colorway_object] == colorway_bytes
            and ffi.string(basic_info().raw.basic.armor.document.data, #before) == colorway_bytes
            and ffi.string(applied.data, #before) == bytes
            and bound[same][1] == colorway_object
            and bound[other][1] == 6003
            and bound[cape][1] == 6001
            and bound[helmet][1] == helmet_object,
        'Basic colorway escaped its selected resource/kind or missed its complete camo recipe'
    )
    assert(#action_history.undo == color_history + 1, 'Checked-region colorway split its history action')
    activate('global_undo')
    assert(
        bound[armor][1] == armor_camo
            and bound[same][1] == armor_camo
            and ffi.string(basic_info().raw.basic.armor.document.data, #before) == bytes,
        'Colorway Undo did not restore its exact previous table'
    )
    activate('global_redo')
    assert(bound[armor][1] == colorway_object and uploads[bound[same][1]] == colorway_bytes)
    color_history = #action_history.undo
    assert(h.set('basic_armor_camo_color_1', '#0A80FF'))
    local c1_bytes = tinted(colorway_bytes, { [1] = '0A80FF' }, armor_rows)
    local c1_object = bound[armor][1]
    assert(
        uploads[bound[armor][1]] == c1_bytes
            and bound[same][1] == bound[armor][1]
            and bound[other][1] == 6003
            and bound[cape][1] == 6001
            and bound[helmet][1] == helmet_object
            and #action_history.undo == color_history + 1,
        'C1 edit changed unchecked bytes or another gear resource, or split its history action'
    )
    activate('global_undo')
    assert(bound[armor][1] == colorway_object and uploads[bound[same][1]] == colorway_bytes)
    assert_scope(basic_info().raw.basic.armor, armor_rows)
    activate('global_redo')
    assert(bound[armor][1] == c1_object and uploads[bound[same][1]] == c1_bytes)
    assert_scope(basic_info().raw.basic.armor, armor_rows)
    local mixed = basic_info().raw.basic.armor.document
    mixed.data[((3 - 1) * 23 + 16) * 4] = 0.25
    mixed.revision = mixed.revision + 1
    basic_info()
    assert(h.get('basic_armor_camo_color_1') == '#0A80FF')
    local c1 = api.mods[h.id].controls.basic_armor_camo_color_1
    assert(c1.can_open_picker())
    frontend.menu.color_picker = { control = c1 }
    color_history = #action_history.undo
    local committed = c1.picker_commit('#0A80FF')
    assert(
        committed
            and uploads[bound[armor][1]] == c1_bytes
            and ffi.string(basic_info().raw.basic.armor.document.data, #before) == c1_bytes
            and #action_history.undo == color_history + 1,
        'Unchanged first-row picker value did not unify checked lower rows in one action'
    )
    local old_color = basic_info().raw.basic.armor.document
    local old_color_object = bound[armor][1]
    color_history = #action_history.undo
    fail_next, fail_material = true, same
    assert(c1.picker_commit('#010203') == false)
    fail_material = armor
    assert(
        basic_info().raw.basic.armor.document == old_color
            and ffi.string(old_color.data, #before) == c1_bytes
            and bound[armor][1] == old_color_object
            and bound[same][1] == old_color_object
            and #action_history.undo == color_history,
        'Failed camo color write published a new draft/history or lost its live table'
    )
    assert_scope(basic_info().raw.basic.armor, armor_rows)
    local other_choice
    for index, target in ipairs(api.mods[h.id].controls.basic_armor_lut.choice_targets) do
        if target.binding.original == 6003 then
            other_choice = index
        end
    end
    local count_before_switch = created
    assert(h.set('basic_armor_lut', assert(other_choice)))
    local other_scope = basic_info().raw.basic.armor.camo_rows
    assert_scope(basic_info().raw.basic.armor, {})
    assert(basic_camo_row(2, 'armor', true, other_scope))
    assert_scope(basic_info().raw.basic.armor, { [2] = true })
    local allowed, reason = c1.can_open_picker()
    assert(
        not allowed and reason:find('selected LUT changed', 1, true) and created == count_before_switch,
        'Open camo picker followed a changed selected resource'
    )
    frontend.menu.color_picker = nil
    assert(h.set('basic_armor_lut', 1))
    assert_scope(basic_info().raw.basic.armor, armor_rows)
    assert(not basic_camo_row(2, 'armor', true, other_scope), 'A stale LUT checkbox changed the current row scope')
    assert_scope(basic_info().raw.basic.armor, armor_rows)
    local shared_cape_choice
    for index, target in ipairs(api.mods[h.id].controls.basic_armor_lut.choice_targets) do
        if target.kind == 'cape' and target.binding.original == 6001 then
            shared_cape_choice = index
        end
    end
    assert(h.set('basic_armor_lut', assert(shared_cape_choice)))
    assert_scope(basic_info().raw.basic.armor, {})
    choose_rows('armor', { [4] = true })
    assert(h.set('basic_armor_lut', 1))
    assert_scope(basic_info().raw.basic.armor, armor_rows)
    assert(h.set('basic_armor_lut', shared_cape_choice))
    assert_scope(basic_info().raw.basic.armor, { [4] = true })
    assert(h.set('basic_armor_lut', other_choice))
    assert_scope(basic_info().raw.basic.armor, { [2] = true })
    assert(h.set('basic_armor_lut', 1) and created == count_before_switch)
    assert(basic_select(1, 'helmet'))
    helmet_doc = basic_info().raw.basic.helmet.document
    local interacting, was_interacting = true, frontend.menu.is_interacting
    frontend.menu.is_interacting = function()
        return interacting
    end
    local drag_start = created
    for frame = 1, 120 do
        helmet_doc.data[0] = frame / 256
        helmet_doc.revision = (helmet_doc.revision or 0) + 1
        runtime.on_update(ctx, 1 / 60)
    end
    assert(created - drag_start <= 31, 'Continuous Basic edits still allocate one texture per frame')
    helmet_doc.data[0] = 0.98765
    helmet_doc.revision = helmet_doc.revision + 1
    interacting = false
    runtime.on_update(ctx, 0)
    assert(
        uploads[bound[helmet][1]] == ffi.string(helmet_doc.data, helmet_doc.width * helmet_doc.height * 16),
        'Drag release did not apply the latest complete LUT immediately'
    )
    local quiet_count = created
    for _ = 1, 10 do
        runtime.on_update(ctx, 0)
    end
    assert(created == quiet_count, 'Idle editor continues allocating textures')
    frontend.menu.is_interacting = was_interacting
    local old = basic_info().raw.basic.armor.document
    local old_bytes, old_object, old_history = ffi.string(old.data, #before), bound[armor][1], #action_history.undo
    fail_next = true
    assert(h.set('basic_armor_camo_colorway', 5))
    assert(
        basic_info().raw.basic.armor.document == old
            and ffi.string(old.data, #before) == old_bytes
            and bound[armor][1] == old_object
            and bound[same][1] == old_object
            and #action_history.undo == old_history,
        'Failed complete colorway recipe committed a changed local draft/history/live table'
    )
    assert_scope(basic_info().raw.basic.armor, armor_rows)
    do
        local old_scope = basic_info().raw.basic.armor.camo_rows
        local history_count, texture_count = #action_history.undo, created
        kits.armor = 99
        local changed = basic_info().raw.basic.armor
        assert_scope(changed, {})
        assert(changed.camo_rows ~= old_scope and not basic_camo_row(1, 'armor', true, old_scope))
        kits.armor = 11
        assert_scope(basic_info().raw.basic.armor, {})
        assert(
            created == texture_count and #action_history.undo == history_count and bound[armor][1] == old_object,
            'New-kit Camo scope reset changed data, history or native bindings'
        )
    end
    runtime.on_disable(ctx)
    actor(7)
    armor, cape, helmet = current()
    same = armor + 30
    materials[units[1].unit][2] = { mesh = same + 10, material = same, mesh_index = 0, material_index = 1 }
    bound[same] = { [1] = 7001, [3] = 0 }
    runtime.on_enable(ctx)
    runtime.on_update(ctx, 0)
    h = api.mods.epic_direct_lut.handle
    activate('populate_worn')
    frontend.basic_mode = true
    api.focus_page(h.id, 'basic')
    assert(h.set('basic_armor_lut', 1))
    assert_scope(basic_info().raw.basic.armor, {})
    choose_rows('armor', { [1] = true })
    after_write = function(material)
        if material == armor then
            kits.armor = 99
        end
    end
    assert(h.set('basic_armor_camo', 8))
    after_write, kits.armor = nil, 11
    assert(
        bound[armor][1] == 7001 and bound[same][1] == 7001,
        'Camo forward writes continued across a same-mount kit switch'
    )
    bound[cape][1] = 6104
    originals[6104] = { width = 16, height = 5, data = ffi.new('float[320]'), resource = '3333333333333333' }
    activate('refresh')
    basic_info()
    local cape_choice
    for index, target in ipairs(api.mods[h.id].controls.basic_armor_lut.choice_targets) do
        if target.kind == 'cape' then
            cape_choice = index
        end
    end
    assert(h.set('basic_armor_lut', assert(cape_choice)))
    local unsupported = basic_info().raw.basic.armor.document
    assert(
        unsupported.width == 16 and api.mods[h.id].controls.basic_armor_camo.disabled,
        'Unsupported Cape layout leaves Basic camo active'
    )
    count = created
    assert(
        not pcall(h.set, 'basic_armor_camo', 4) and created == count and bound[cape][1] == 6104,
        'Disabled Cape camo issued a GPU edit'
    )
    frontend.menu.visible = true
    runtime.on_update(ctx, 0)
    assert(starts == 1 and source, 'Basic camo preview source did not start on its page')
    local registered = api.mods[h.id]
    assert(
        runtime.on_disable(ctx) == false and source.closes == 1 and api.mods[h.id] == registered,
        'Pending camo source cleanup released its activation early'
    )
    assert(
        not pcall(runtime.on_enable, ctx) and starts == 1 and api.mods[h.id] == registered,
        'Pending camo source was replaced by a new activation'
    )
    close_ready = true
    assert(
        runtime.on_disable(ctx) ~= false and not api.mods[h.id],
        'Completed camo source cleanup did not release the activation'
    )
end
-- Complete cleanup reclaims only the current certified cohort after the preview
-- acknowledges closure and render fences drain both detachment and disposal.
do
    m.texture_lifetime = dofile('src/gear/texture_lifetime.lua')
    actor(8)
    armor, cape, helmet = current()
    local events, lut_handle = {}, nil
    local frontend_closed, render_allowed, dismissed = false, false, false
    local retire = package.loaded['epic.direct_lut.retained.v1']
    local previous_records, previous_bytes = #retire.records, retire.bytes
    m.engine.create_texture = function(_, width, height, data)
        created = created + 1
        local texture =
            { handle = 100000 + created, object = 200000 + created, data = data, width = width, height = height }
        if width == 1 then
            assert(bound[armor][1] == 8001, 'Render drain preceded original binding restoration')
            assert(not frontend_closed, 'Frontend closed before its texture retirement fence')
            events[#events + 1] = 'fence'
        else
            assert(width == 23 and height == 8)
            lut_handle = texture.handle
        end
        return texture
    end
    native.destroy = function(handle)
        events[#events + 1] = handle == lut_handle and 'destroy LUT' or 'destroy fence'
    end
    runtime.on_enable(ctx)
    runtime.on_update(ctx, 0)
    h = api.mods.epic_direct_lut.handle
    frontend.render_ready = function()
        return not frontend_closed and render_allowed
    end
    frontend.dismiss = function()
        dismissed, frontend.menu.visible = true, false
        return true
    end
    frontend.close = function()
        frontend_closed = true
        events[#events + 1] = 'close frontend'
        return true
    end
    activate('populate_worn')
    frontend.basic_mode = true
    api.focus_page(h.id, 'basic')
    assert(h.set('basic_armor_lut', 1))
    basic_info().raw.basic.armor.document.data[0] = 1.23456
    assert(basic_camo_row(1, 'armor', true))
    basic_info()
    assert(h.set('basic_armor_camo', 8) and lut_handle)
    assert(#retire.records == previous_records + 1)
    local preview_closed = false
    package.loaded['epic.player_preview.v1'] = {
        before_editor_close = function()
            return preview_closed
        end,
    }
    frontend.menu.visible = true
    local registered = api.mods[h.id]
    assert(runtime.on_disable(ctx) == false and #events == 0, 'Texture disposal ran while preview cleanup was pending')
    assert(
        dismissed and not frontend.menu.visible and not frontend_closed and api.mods[h.id] == registered,
        'Pending cleanup closed/unregistered the frontend instead of dismissing it'
    )
    preview_closed = true
    assert(
        runtime.on_disable(ctx) == false and #events == 0 and not frontend_closed and api.mods[h.id] == registered,
        'Waiting for render readiness closed the probe required to drain queued textures'
    )
    render_allowed = true
    assert(runtime.on_disable(ctx) ~= false)
    package.loaded['epic.player_preview.v1'] = nil
    assert(
        table.concat(events, ',') == 'fence,destroy fence,destroy LUT,fence,destroy fence,close frontend'
            and frontend_closed
            and not api.mods[h.id],
        'Complete cleanup omitted or reordered a texture retirement fence'
    )
    assert(
        #retire.records == previous_records and retire.bytes == previous_bytes and not retire.cohort,
        'Certified texture cleanup freed legacy buffers or retained its own completed cohort'
    )
end
-- Imported mapping uses ready sources, exact current LUT groups and one atomic
-- transaction, including only metadata-proven Pattern companions.
do
    m.texture_lifetime = nil
    actor(9)
    armor, cape, helmet = current()
    local armor_targets = { armor }
    for index = 1, 4 do
        local material, object = armor + 10 + index * 10, 9000 + index * 10
        materials[units[1].unit][index + 1] =
            { mesh = material + 10, material = material, mesh_index = index, material_index = index }
        bound[material] = { [1] = object, [3] = 0 }
        originals[object] = m.basic_state.clone(stock)
        originals[object].resource = tostring(index + 1):rep(16)
        armor_targets[#armor_targets + 1] = material
    end
    local physical, pattern_objects = { armor, cape, helmet }, {}
    for index = 2, #armor_targets do
        physical[#physical + 1] = armor_targets[index]
    end
    for index, material in ipairs(physical) do
        local object = 9200 + index
        local d = {
            width = 3,
            height = 1,
            data = ffi.new('float[12]'),
            resource = index == 1 and '8888888888888888' or string.format('%016x', object),
        }
        d.data[0], d.data[3] = index / 7, -0.875
        originals[object], bound[material][2], pattern_objects[material] = d, object, object
    end
    local uploads = {}
    m.engine.create_texture = function(_, width, height, data)
        created = created + 1
        local texture = { object = 90000 + created, width = width, height = height, data = data }
        uploads[texture.object] = ffi.string(data, width * height * 16)
        return texture
    end
    m.engine.bind = function(_, material, slot, object)
        assert(slot == 1 or slot == 2, 'Imported mapping wrote the tint/emblem slot')
        bound[material][slot] = object
    end
    m.original_luts.preserve = dofile('src/gear/original_luts.lua').preserve
    m.import_matches = dofile('src/imports/import_matches.lua')
    local make_picker, accept = m.import_picker.new
    m.import_picker.new = function(deps)
        accept = deps.accept
        return make_picker(deps)
    end
    runtime.on_enable(ctx)
    runtime.on_update(ctx, 0)
    h = api.mods.epic_direct_lut.handle
    activate('populate_worn')
    local zero, one = m.basic_state.clone(stock), m.basic_state.clone(stock)
    zero.data[0], one.data[0], zero.data[3], one.data[3] = 0.11875, 0.68125, 3.25, 2.75
    for i = 52, 55 do
        zero.data[i], one.data[i] = 1.625, 2.125
    end
    local pattern = { width = 3, height = 1, data = ffi.new('float[12]') }
    pattern.data[0], pattern.data[3] = 0.64375, 1.875
    DDS.write(fixture .. '/lut000.dds', zero.data, 23, 8)
    DDS.write(fixture .. '/lut001.dds', one.data, 23, 8)
    DDS.write(fixture .. '/lut002.dds', pattern.data, 3, 1)
    local metadata = assert(io.open(fixture .. '/resources.tsv', 'wb'))
    metadata:write('lut000.dds\t1111111111111111\nlut001.dds\t2222222222222222\nlut002.dds\t8888888888888888\n')
    metadata:close()
    local function imported()
        assert(accept('ok\nlut001.dds\nlut000.dds\nlut002.dds\n', { base = fixture }))
    end
    imported()
    local count_before = created
    activate('imported_map_armor')
    assert(not frontend.menu.lut_apply_dialog, 'Mapping opened before asynchronous imported tables were ready')
    for _ = 1, 5 do
        runtime.on_update(ctx, 0)
    end
    assert(created == count_before, 'Asynchronous mapping preparation uploaded a texture')
    local dialog = assert(frontend.menu.lut_apply_dialog)
    local function inspect(kind)
        local dialog = assert(frontend.menu.lut_apply_dialog)
        assert(dialog.mode == 'mapping' and dialog.title == 'Map LUTs to ' .. kind)
        local sources = {}
        for _, item in ipairs(dialog.columns[1].items) do
            sources[item.label:match('(lut%d%d%d%.dds)$')] = item
        end
        assert(sources['lut000.dds'].enabled and sources['lut001.dds'].enabled and not sources['lut002.dds'].enabled)
        return dialog, sources, dialog.columns[2].items
    end
    local sources, target_items
    dialog, sources, target_items = inspect('Armor')
    assert(#target_items == 5)
    local function snapshot()
        local result = {}
        for _, material in ipairs(physical) do
            result[material] = { bound[material][1], bound[material][2], bound[material][3] }
        end
        return result
    end
    local function same(expected)
        for _, material in ipairs(physical) do
            for slot = 1, 3 do
                assert(bound[material][slot] == expected[material][slot], 'Mapping changed an unselected native group')
            end
        end
    end
    local before, history_count = snapshot(), #action_history.undo
    dialog.source_id = sources['lut000.dds'].id
    assert(created == count_before and #action_history.undo == history_count)
    assert(dialog.on_map(dialog.source_id, target_items[2].id))
    assert(uploads[bound[armor_targets[2]][1]] == ffi.string(zero.data, 23 * 8 * 16))
    assert(
        bound[armor_targets[2]][2] == before[armor_targets[2]][2],
        'Arbitrary mapping guessed a Pattern relationship'
    )
    for _, material in ipairs(physical) do
        if material ~= armor_targets[2] then
            assert(bound[material][1] == before[material][1] and bound[material][2] == before[material][2])
        end
    end
    assert(frontend.menu.lut_apply_dialog == dialog and target_items[2].mapped_source == sources['lut000.dds'].id)
    local mapped = snapshot()
    assert(dialog.on_map(sources['lut001.dds'].id, target_items[2].id))
    assert(uploads[bound[armor_targets[2]][1]] == ffi.string(one.data, 23 * 8 * 16))
    local remapped = snapshot()
    activate('global_undo')
    same(mapped)
    activate('global_undo')
    same(before)
    activate('global_redo')
    same(mapped)
    activate('global_redo')
    same(remapped)
    activate('restore')
    activate('imported_map_armor')
    dialog, sources, target_items = inspect('Armor')
    before, history_count = snapshot(), #action_history.undo
    local previous_action = action_history.undo[history_count]
    assert(dialog.on_auto_map())
    for index, material in ipairs(armor_targets) do
        local source = index % 2 == 1 and zero or one
        assert(
            uploads[bound[material][1]] == ffi.string(source.data, 23 * 8 * 16),
            'Auto-map lost zero-based numeric order or source cycling'
        )
        assert(target_items[index].mapped_source == sources[index % 2 == 1 and 'lut000.dds' or 'lut001.dds'].id)
        if index > 1 then
            assert(bound[material][2] == before[material][2], 'Auto-map guessed an unrelated Pattern companion')
        end
    end
    assert(
        uploads[bound[armor][2]] == ffi.string(pattern.data, 48),
        'Verified imported resource pair lost its associated Pattern'
    )
    assert(bound[cape][1] == before[cape][1] and bound[helmet][1] == before[helmet][1])
    assert(#action_history.undo <= history_count + 1 and action_history.undo[#action_history.undo] ~= previous_action)
    activate('global_undo')
    same(before)
    activate('restore')
    activate('imported_map_armor')
    dialog, sources, target_items = inspect('Armor')
    before, history_count = snapshot(), #action_history.undo
    local bind, forward = m.engine.bind, 0
    m.engine.bind = function(_, material, slot, object)
        if slot == 1 and object >= 90000 then
            forward = forward + 1
            if forward == 3 then
                error('Simulated auto-map batch failure', 0)
            end
        end
        return bind(_, material, slot, object)
    end
    local accepted, why = pcall(dialog.on_auto_map)
    m.engine.bind = bind
    assert(
        not accepted
            and forward >= 3
            and why:find('Simulated auto-map batch failure', 1, true)
            and not why:find('rollback failed', 1, true)
    )
    assert(#action_history.undo == history_count and frontend.menu.lut_apply_dialog == dialog)
    same(before)
    local function refused(call, text)
        local native_before, count, history_count = snapshot(), created, #action_history.undo
        local accepted, why = pcall(call)
        assert(not accepted and why:find(text, 1, true), 'Mapping did not reject stale/unready data')
        assert(created == count and #action_history.undo == history_count)
        same(native_before)
    end
    kits.armor = 99
    refused(dialog.on_auto_map, 'Worn gear changed')
    kits.armor = 11
    local original = originals[9020]
    originals[9020] = nil
    refused(dialog.on_auto_map, 'Original mapping target changed')
    originals[9020] = original
    original = originals[pattern_objects[armor]]
    originals[pattern_objects[armor]] = nil
    refused(dialog.on_auto_map, 'Original mapping target changed')
    originals[pattern_objects[armor]] = original
    local loaded, old_source = basic_info().raw.tables[1]
    old_source = loaded.data[0]
    loaded.data[0] = old_source + 0.125
    refused(dialog.on_auto_map, 'Imported LUT data changed')
    loaded.data[0] = old_source
    local old = bound[armor_targets[4]][1]
    bound[armor_targets[4]][1] = 888777
    refused(dialog.on_auto_map, 'Current mapping target changed')
    bound[armor_targets[4]][1] = old
    imported()
    for _ = 1, 5 do
        runtime.on_update(ctx, 0)
    end
    refused(dialog.on_auto_map, 'Imported palette changed')
    activate('imported_map_armor')
    dialog, sources, target_items = inspect('Armor')
    assert(h.set('preserve_emissives', true))
    local expected = m.original_luts.preserve(one, originals[9001])
    assert(dialog.on_map(sources['lut001.dds'].id, target_items[1].id))
    assert(
        uploads[bound[armor][1]] == ffi.string(expected.data, 23 * 8 * 16),
        'Mapping did not preserve exact original emissive/zero values'
    )
    assert(h.set('preserve_emissives', false))
    for _, kind in ipairs({ 'helmet', 'cape' }) do
        activate('imported_map_' .. kind)
        local name = kind == 'helmet' and 'Helmet' or 'Cape'
        local d, source_items, targets = inspect(name)
        local before = snapshot()
        assert(#targets == 1 and d.on_map(source_items['lut001.dds'].id, targets[1].id))
        local material = kind == 'helmet' and helmet or cape
        assert(uploads[bound[material][1]] == ffi.string(one.data, 23 * 8 * 16))
        for _, other in ipairs(physical) do
            if other ~= material then
                assert(bound[other][1] == before[other][1] and bound[other][2] == before[other][2])
            end
        end
    end
    original = originals[9030]
    originals[9030] = nil
    activate('imported_map_armor')
    dialog = frontend.menu.lut_apply_dialog
    assert(not dialog.columns[2].items[4].enabled)
    refused(dialog.on_auto_map, 'current mapping target is not ready')
    originals[9030] = original
    metadata = assert(io.open(fixture .. '/resources.tsv', 'wb'))
    metadata:write('lut002.dds\t8888888888888888\n')
    metadata:close()
    assert(accept('ok\nlut002.dds\n', { base = fixture }))
    for _ = 1, 3 do
        runtime.on_update(ctx, 0)
    end
    activate('imported_map_armor')
    dialog = assert(frontend.menu.lut_apply_dialog)
    assert(#dialog.columns[1].items == 1 and not dialog.columns[1].items[1].enabled)
    refused(dialog.on_auto_map, 'No material LUTs available to auto-map')
    runtime.on_disable(ctx)
    m.import_picker.new = make_picker
    for _, name in ipairs({ 'lut000.dds', 'lut001.dds', 'lut002.dds', 'resources.tsv' }) do
        os.remove(fixture .. '/' .. name)
    end
end
os.remove(fixture .. '/' .. armor_file)
os.remove(fixture .. '/' .. filename)
print(
    'PASS folded Cape controller: same-hash selector/single editor, scoped edits/reset/history/recovery, Basic kit guards, three local save scopes/loading rejection, export flag, alias modal/raw IDs and legacy/new startup proof'
)
