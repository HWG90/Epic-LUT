local ffi = require('ffi')
local core = dofile('vendor/menu/core.lua')
local store = {
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
}
local api = core.new(store)
local alive = true
local membership = true
local fail = false
local bound = { [3] = 100, [4] = 100, [6] = 300, [8] = 400, [9] = 999 }
local creates = 0
local gpu_data
local gpu_object
local units = { { unit = 1, type = 0, slot = 1 }, { unit = 2, type = 0, slot = 2 }, { unit = 3, type = 0, slot = 0 } }
local native = {
    alive = function()
        return alive and 1 or 0
    end,
    commit = function() end,
}
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
local test_root = assert(os.getenv('EPIC_LUT_TEST_ROOT'))
os.remove(test_root .. '/tests/tmp/direct-state/direct-applied.tsv')
local quick_select, quick_info
local test_frontend
local pattern_deps
local bulk_entries, bulk_naming
local Pattern = dofile('src/editor/pattern_luts.lua')
local m = {
    pattern_luts = {
        new = function(deps)
            pattern_deps = deps
            return Pattern.new(deps)
        end,
    },
    lut_files = dofile('src/presets/lut_files.lua'),
    editor_tools = dofile('src/editor/editor_tools.lua'),
    table_index = dofile('src/imports/table_index.lua'),
    file_io = dofile('src/core/file_io.lua'),
    editor_registry = dofile('src/editor/editor_registry.lua'),
    gear_catalog = dofile('src/gear/gear_catalog.lua'),
    lut_editor_controls = dofile('src/editor/lut_editor_controls.lua'),
    lut_editor_view = dofile('src/editor/lut_editor_view.lua'),
    import_job = dofile('src/imports/import_job.lua'),
    armory_collection = dofile('src/presets/armory_collection.lua'),
    configuration = dofile('src/editor/configuration.lua'),
    binding_session = dofile('src/gear/binding_session.lua'),
    import_protocol = dofile('src/imports/import_protocol.lua'),
    control_help = dofile('src/editor/control_help.lua'),
    resource_ids = dofile('src/core/resource_ids.lua'),
    bulk_dds_export = {
        new = function()
            return {
                save = function(name, entries, naming)
                    bulk_entries, bulk_naming = entries, naming
                    return 'tests/tmp/bulk-export', #entries
                end,
            }
        end,
    },
    action_history = dofile('src/core/action_history.lua'),
    basic_state = dofile('src/core/basic_state.lua'),
    region_indicator = dofile('src/gear/region_indicator.lua'),
    windows = dofile('src/platform/windows.lua'),
    ui_core = core,
    import_view = {
        new = function(info, tables, select)
            quick_info = info
            quick_select = select
            return { draw = function() end }
        end,
    },
    dds = dofile('src/core/dds.lua'),
    provider_menu = {
        disable_matching = function()
            return true, false
        end,
    },
    direct_setup = dofile('src/gear/direct_setup.lua'),
    native_import = dofile('src/platform/windows.lua'),
    palette = dofile('src/core/palette.lua'),
    semantics = dofile('src/core/semantics.lua'),
    lut_editor = dofile('src/editor/lut_editor.lua'),
    paths = {
        new = function()
            return {
                files = test_root .. '/tests/tmp/files',
                exports = test_root .. '/tests/tmp/files',
                cache = test_root .. '/tests/tmp/cache',
                settings = test_root .. '/tests/tmp/direct-state',
                presets = test_root .. '/tests/tmp/presets',
                directory_exists = function(path)
                    local file = io.open(path, 'rb')
                    if file then
                        file:close()
                        return true
                    end
                    return false
                end,
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
        units = function()
            return units
        end,
    },
    engine = {
        LUT_SLOT = 1,
        open = function()
            return native
        end,
        unit_materials = function(_, unit)
            assert(unit >= 1 and unit <= 3, 'Non-local unit inspected')
            if not membership then
                return {}
            end
            if unit == 1 then
                return { { mesh = 2, material = 3 }, { mesh = 2, material = 4 } }
            end
            return unit == 2 and { { mesh = 5, material = 6 } } or { { mesh = 7, material = 8 } }
        end,
        binding = function(_, material)
            return bound[material]
        end,
        create_texture = function(_, w, h, data)
            assert(w == 23 and h == 8)
            creates = creates + 1
            gpu_data = data
            gpu_object = 199 + creates
            return { object = gpu_object, data = data, width = w, height = h }
        end,
        bind = function(_, material, slot, object)
            bound[material] = object
            if fail then
                fail = false
                error('failure after native mutation')
            end
        end,
    },
    preferences = {
        new = function()
            return { close = function() end }
        end,
    },
    frontend = {
        new = function()
            test_frontend = {
                resolve = function()
                    return api
                end,
                tick = function() end,
                close = function()
                    return true
                end,
            }
            return test_frontend
        end,
    },
}
local f = assert(io.open('src/editor/direct_editor.lua', 'rb'))
local source = f:read('*a')
f:close()
local editor = assert(loadstring('local m=...\n' .. source))(m)
local cleanups = {}
local ctx = {
    log = function() end,
    on_cleanup = function(fn)
        cleanups[#cleanups + 1] = fn
    end,
}
editor.on_enable(ctx)
editor.on_update(ctx, 0)
local handle = api.mods.epic_direct_lut.handle
local function activate(key)
    local ok, value = handle.activate(key)
    assert(ok, value)
    return value
end
-- Stock equipped colors work before any import, without writing bindings.
editor.on_disable(ctx)
local stock = ffi.new('float[?]', 23 * 8 * 4)
stock[0] = 0.25
local basic_select
m.basic_view = {
    new = function(_, select)
        basic_select = select
        return { draw = function() end, wheel = function() end }
    end,
}
m.outfit_presets = dofile('src/presets/outfit_presets.lua')
m.original_luts = {
    new = function()
        return {
            loaded = true,
            status = 'Ready',
            start = function() end,
            tick = function() end,
            close = function() end,
            get = function()
                return {
                    data = stock,
                    width = 23,
                    height = 8,
                    resource = 'ffffffffffffffff',
                    patch_source = '0123456789abcdef\n' .. string.rep('\0', 192) .. m.dds
                        .encode(stock, 23, 8)
                        :sub(1, 148),
                }
            end,
        }
    end,
}
local stock_editor = assert(loadstring('local m=...\n' .. source))(m)
local patch_saved
m.patch_export = {
    zip_entries = dofile('src/presets/patch_export.lua').zip_entries,
    new = function(folder, deps)
        assert(folder == test_root .. '/tests/tmp/files' and deps.dds == m.dds)
        return {
            save = function(name, document, original)
                patch_saved = { name = name, document = document, original = original }
                return folder .. '/' .. name, original.resource
            end,
        }
    end,
}
m.preset_export = dofile('src/presets/preset_export.lua')
stock_editor.on_enable(ctx)
stock_editor.on_update(ctx, 0)
handle = api.mods.epic_direct_lut.handle
assert(not api.mods.epic_direct_lut.controls.export_material_report, 'Removed inspector export still registered')
local armor_before, helmet_before = handle.get('target_armor'), handle.get('target_helmet')
activate('populate_worn')
assert(
    handle.get('target_armor') == armor_before and handle.get('target_helmet') == helmet_before,
    'Loading worn colors changed target choices'
)
assert(bound[3] == 100, 'Population wrote game bindings')
assert(handle.get('cell_r') == 0.25, 'Stock game pixels did not populate editor')
assert(
    activate('editor_load_armor'):find('Editor populated from Armor LUT', 1, true),
    'Worn LUT load returned an error after populating'
)
assert(
    handle.get('cell_r') == 0.25 and bound[3] == 100,
    'Editor Populate failed to load worn Armor before any custom application'
)
assert(handle.set('save_name', 'native-patch'))
assert(activate('save_patch'):find('Exported patch ZIP for ffffffffffffffff', 1, true))
assert(
    patch_saved
        and patch_saved.name == 'native-patch'
        and patch_saved.document.data[0] == 0.25
        and patch_saved.original.resource == 'ffffffffffffffff'
        and bound[3] == 100,
    'Patch export changed bindings or used an imported identity'
)
patch_saved = nil
bound[3], bound[4] = 777, 777
assert(
    activate('save_patch'):find('Gear changed', 1, true) and not patch_saved,
    'Changed gear exported against a stale destination'
)
bound[3], bound[4] = 100, 100
activate('editor_load_armor')
assert(handle.set('outfit_name', 'Stock Outfit'))
test_frontend.menu = {}
assert(handle.activate('save_setup'))
assert(test_frontend.menu.outfit_dialog.on_save('Stock Outfit', 'both'))
test_frontend.menu = nil
local outfit_choices = api.mods[handle.id].controls.outfit_preset.choices
local found_outfit = false
for _, label in ipairs(outfit_choices) do
    if label == 'Stock Outfit' then
        found_outfit = true
    end
end
assert(found_outfit, 'Saving original gear without a custom application failed to refresh Armory')
for index, label in ipairs(outfit_choices) do
    if label == 'Stock Outfit' then
        assert(handle.set('outfit_preset', index))
        break
    end
end
assert(handle.activate('outfit_apply_armor'))
local preset = quick_info().raw.outfit
local bad_entry
for _, entry in ipairs(preset.entries) do
    if entry.kind == 'armor' and entry.key == '0:1:0:0' then
        bad_entry = entry
        break
    end
end
assert(bad_entry)
assert(
    handle.get('armory_export_name') == 'Stock Outfit' and not api.mods[handle.id].controls.armory_export.disabled,
    'Selected preset did not unlock named Armory export'
)
assert(handle.set('armory_export_format', 2))
assert(not api.mods[handle.id].controls.armory_export_lut.disabled)
patch_saved = nil
assert(activate('armory_export'):find('Exported Stock Outfit', 1, true))
assert(
    patch_saved
        and patch_saved.document == preset.entries[1].document
        and patch_saved.original.resource == preset.entries[1].original.resource,
    'Armory patch exported editor/worn bytes instead of selected stored preset'
)
local original_key, original_value = bad_entry.key, bad_entry.document.data[0]
bad_entry.key = '2:9:63:63'
bad_entry.document.data[0] = 0.77 -- A wrong fallback would visibly repaint the unmatched first material.
local untouched_object = bound[3]
assert(handle.activate('outfit_apply_armor'))
assert(bound[3] == untouched_object, 'Preset fallback repainted an unmatched binding')
bad_entry.key = original_key
-- This CPU document is still different from its already-applied GPU data.
assert(handle.set('outfit_name', 'Applied Snapshot Test'))
test_frontend.menu = {}
assert(handle.activate('save_setup'))
assert(test_frontend.menu.outfit_dialog.on_save('Applied Snapshot Test', 'both'))
test_frontend.menu = nil
local saved_snapshot = quick_info().raw.outfit
for _, entry in ipairs(saved_snapshot.entries) do
    if entry.kind == 'armor' and entry.key == original_key then
        assert(entry.document.data[0] == original_value, 'Preset saved mutable editor values instead of applied pixels')
    end
end
bad_entry.document.data[0] = original_value
local remembered = m.direct_setup.new(m, m.paths.new()).read()
assert(next(remembered), 'Applying an Armory preset did not persist the active setup')
assert(handle.activate('outfit_apply_helmet'))
remembered = m.direct_setup.new(m, m.paths.new()).read()
assert(
    remembered['0:0:0:0'] and remembered['0:1:0:0'],
    'Mixed Armor and Helmet applications were not retained together'
)
local shared_fixture = io.open('tests/tmp/files/armorytest.zip', 'rb')
if shared_fixture then
    shared_fixture:close()
    local old_native_import = m.native_import
    m.native_import = dofile('src/platform/windows.lua')
    local script = assert(io.open('tools/import_zip.ps1', 'rb'))
    m.zip_import_script = script:read('*a'):gsub('.', function(c)
        return string.format('%02x', c:byte())
    end)
    script:close()
    local before_armor, before_helmet = bound[3], bound[8]
    assert(handle.set('format', 2) and handle.set('file', 'armorytest'))
    activate('load')
    ffi.cdef('void epic_armory_import_test_sleep(uint32_t) __asm__("Sleep");')
    local kernel, completed = ffi.load('kernel32'), false
    for _ = 1, 200 do
        stock_editor.on_update(ctx, 0.05)
        local selected = quick_info().raw.outfit
        if selected and selected.name:match('^armorytest') then
            completed = true
            break
        end
        kernel.epic_armory_import_test_sleep(50)
    end
    assert(completed, 'Actual shared preset worker was not accepted into Armory')
    assert(bound[3] == before_armor and bound[8] == before_helmet, 'Importing a shared preset applied it to worn gear')
    local shared = quick_info().raw.outfit
    assert(
        #shared.entries == 2
            and shared.entries[1].original.resource == '0000000000000001'
            and shared.entries[2].document.width == 3,
        'Shared preset import lost destination or Pattern data'
    )
    m.native_import = old_native_import
end
assert(handle.activate('restore'))
assert(not next(m.direct_setup.new(m, m.paths.new()).read()), 'Restore Original retained a startup preset')

local stock_preview = quick_info()
assert(stock_preview.raw.basic.armor.resource == '[0xffffffffffffffff]', 'Hex resource ID missing')
assert(stock_preview.armor[1].resource == '[0xffffffffffffffff]', 'Grouped display dropped the resource ID')
assert(handle.set('resource_format', 2))
assert(quick_info().raw.basic.armor.resource == '[18446744073709551615]', 'Decimal resource ID lost 64-bit precision')
assert(
    api.mods[handle.id].controls.basic_armor_lut.choices[1] == 'LUT 1',
    'Selector should remain separate from the resource ID'
)
assert(handle.set('resource_format', 1))
assert(
    api.mods[handle.id].controls.basic_armor_lut.choice_details[1] == '[0xffffffffffffffff]',
    'Dropdown resource details missing'
)
assert(
    #stock_preview.raw.armor == 2 and #stock_preview.raw.helmet == 1,
    'Show All omitted stock snapshots before any palette was applied'
)
local old_object = bound[3]
for _, off_phase in ipairs({ false, true }) do
    activate('identify_region')
    if off_phase then
        stock_editor.on_update(ctx, 0.26)
    end
    activate('editor_load_armor')
    assert(
        bound[3] == old_object and handle.get('cell_r') == 0.25,
        'Loading the editor during a flash captured magenta or failed to restore its native binding'
    )
    assert(handle.set('save_name', 'flash-clean'))
    activate('save_patch')
    assert(
        patch_saved and ffi.string(patch_saved.document.data, 23 * 8 * 16) == ffi.string(stock, 23 * 8 * 16),
        'Exporting after a region flash retained transient identification pixels'
    )
    stock_editor.on_update(ctx, 4.1)
    assert(bound[3] == old_object, 'Ending a flash reapplied transient editor pixels')
end
test_frontend.menu = { page = 1, visible = true }
activate('identify_region')
test_frontend.menu.page = 2
stock_editor.on_update(ctx, 0)
assert(
    bound[3] == old_object and handle.get('cell_r') == 0.25,
    'Switching tabs retained a region flash or changed editor colors'
)
test_frontend.menu = nil
activate('identify_region')
assert(
    bound[3] ~= old_object and gpu_data[0] == 1 and gpu_data[1] == 0 and gpu_data[2] == 1,
    'Region highlight did not apply magenta'
)
assert(stock[0] == 0.25 and handle.get('cell_r') == 0.25, 'Highlight modified editor/source pixels')
local highlight_object = bound[3]
local highlighted_creates = creates
stock_editor.on_update(ctx, 0.26)
assert(bound[3] == old_object, 'Flash off phase did not restore appearance')
stock_editor.on_update(ctx, 0.26)
assert(
    bound[3] == highlight_object and creates == highlighted_creates,
    'Flash allocated another texture or failed to alternate'
)
stock_editor.on_update(ctx, 4.1)
assert(bound[3] == old_object, 'Timed highlight failed to restore exact original binding')
test_frontend.basic_mode = true
basic_select(1, 'helmet')
-- Basic uses its own scoped target; hidden F10 checkboxes must not override it.
assert(handle.set('cell_color', '#FF0000'))
stock_editor.on_update(ctx, 0.1)
assert(bound[8] ~= 400 and bound[3] == old_object, 'Basic color edit did not auto-apply only to Helmet')
local edited_helmet = bound[8]
activate('basic_copy_helmet_all')
assert(
    bound[3] ~= old_object and bound[6] ~= 300 and bound[8] == edited_helmet,
    'Copy Helmet to All changed Helmet or skipped Armor'
)
assert(
    gpu_data[0] == 1 and gpu_data[1] == 0 and stock[0] == 0.25,
    'Copy-to-all failed to use edited Helmet or mutated originals'
)
activate('restore')
assert(bound[3] == 100 and bound[6] == 300 and bound[8] == 400, 'Restore Original failed after copy-to-all')
assert(handle.get('cell_r') == 0.25, 'Restore Original left edited pixels in editor')
stock_editor.on_disable(ctx)
m.original_luts = nil
m.basic_view = nil
m.outfit_presets = nil
creates = 0
package.loaded['epic.direct_lut.retained.v1'] = nil
editor = assert(loadstring('local m=...\n' .. source))(m)
editor.on_enable(ctx)
editor.on_update(ctx, 0)
handle = api.mods.epic_direct_lut.handle
assert(activate('apply'):find('Load a DDS first', 1, true))
local data = ffi.new('float[?]', 23 * 8 * 4)
for i = 0, 23 * 8 * 4 - 1 do
    data[i] = (i - 100) / 9
end
m.dds.write('tests/tmp/files/palette.dds', data, 23, 8)
activate('load')
assert(quick_info().loaded, 'Import did not establish a palette')
activate('global_undo')
assert(not quick_info().loaded and bound[3] == 100, 'Global undo failed to remove import or changed gear')
activate('global_redo')
assert(quick_info().loaded, 'Global redo failed to restore import')
activate('apply_checked')
assert(
    bound[3] == 200 and bound[4] == 200 and bound[6] == 200 and bound[8] == 200,
    'File LUT did not apply immediately without saving it to the editor'
)
activate('global_undo')
assert(bound[3] == 100 and bound[6] == 300 and bound[8] == 400, 'Undo Apply did not restore exact prior bindings')
activate('global_redo')
assert(bound[3] == 200 and bound[6] == 200 and bound[8] == 200, 'Redo Apply did not restore retained textures')
local before_populate = creates
activate('populate_applied')
assert(creates == before_populate and bound[3] == 200, 'Populate editor wrote to game bindings')
assert(#api.mods.epic_direct_lut.controls.edit_row.choices == 8, 'Applied LUT did not populate editor rows')
activate('restore')
activate('save_palette')
activate('refresh')
assert(bound[3] == 100 and bound[8] == 400, 'Saving an import to the editor applied it to gear')
assert(handle.set('basic_preset_name', 'basic-roundtrip'))
activate('basic_save')
local preset_index
for index, name in ipairs(api.mods.epic_direct_lut.controls.basic_preset.choices) do
    if name == 'basic-roundtrip' then
        preset_index = index
    end
end
assert(preset_index, 'Basic palette preset did not appear')
assert(handle.set('cell_color', '#FF0000'))
assert(handle.set('basic_preset', preset_index))
assert(handle.get('edit_row') == 1, 'Basic preset changed editor row unexpectedly')
assert(handle.set('edit_column', 1))
assert(handle.set('color_field', 1))
activate('save_palette')

local quick_path = test_root .. '/tests/tmp/files/palette.dds'
quick_select({ width = 23, height = 8, data = data, source = quick_path, name = 'Table 1' }, 3, 6)
local before_quick = creates
assert(handle.set('target_armor', false))
assert(handle.set('target_helmet', false))
assert(handle.set('quick_color', '#123456'))
assert(
    handle.get('edit_row') == 3 and handle.get('edit_column') == 6,
    'Import selection did not focus exact editor cell'
)
assert(math.abs(handle.get('cell_r') - 0x12 / 255) < 0.0006, 'Scratch edit did not sync editor table')
activate('undo')
assert(creates == before_quick, 'Unchecked quick edit changed live bindings')
assert(handle.set('basic_preset', 1) and handle.set('basic_preset', preset_index))
local changed_preset = assert(quick_info().editor)
local preset_bytes = ffi.string(changed_preset.data, changed_preset.width * changed_preset.height * 16)
assert(
    not api.mods.epic_direct_lut.controls.quick_color.can_open_picker(),
    'Stale quick selection opened on a new preset'
)
assert(handle.set('quick_color', '#654321'))
assert(
    ffi.string(changed_preset.data, changed_preset.width * changed_preset.height * 16) == preset_bytes,
    'Stale quick selection painted into a replacement preset'
)
activate('save_palette')
assert(handle.set('edit_row', 1))
assert(handle.set('edit_column', 1))
assert(handle.set('color_field', 1))
assert(handle.set('target_armor', true))
assert(handle.set('target_helmet', true))
assert(handle.set('scope', 1))
assert(handle.get('preserve_emissives') == false, 'Emissive preservation did not default Off')
assert(handle.set('preserve_emissives', true))
assert(activate('apply'):find('Original game LUT reader', 1, true) and bound[3] == 100)
assert(handle.set('preserve_emissives', false))
assert(handle.set('edit_row', 2))
assert(handle.set('cell_color', '#FF0080'))
-- Saving the same source again must overwrite previous edits, without live writes.
local before_save = creates
activate('save_palette')
assert(creates == before_save and bound[3] == 100, 'Send to LUT Editor applied to gear')
assert(
    math.abs(handle.get('cell_r') - tonumber(data[23 * 4])) < 0.0001,
    'Send to LUT Editor reused stale edits instead of imported values'
)
assert(handle.set('cell_color', '#FF0080'))
local edited_index = 23 * 4
assert(api.mods.epic_direct_lut.controls.cell_a.disabled, 'Shader alpha was writable without unlocking')
activate('undo')
activate('redo')
activate('undo')
assert(#api.mods.epic_direct_lut.controls.lut.choices == 3)
activate('apply')
assert(bound[3] == 200 and bound[4] == 200 and bound[9] == 999 and creates == 1)
local retained_value = gpu_data[23 * 4]
assert(handle.set('cell_color', '#010203'))
assert(gpu_data[23 * 4] == retained_value, 'Editing changed an already queued GPU buffer')
activate('undo')
activate('restore')
assert(bound[3] == 100 and bound[4] == 100)
activate('apply')
assert(creates == 1, 'Identical import allocated another texture')
bound[3] = 300
activate('restore')
assert(bound[3] == 300 and bound[4] == 100, 'Restoration overwrote foreign ownership')
bound[3] = 100
activate('refresh')
fail = true
assert(activate('apply'):find('failure after native mutation', 1, true))
assert(bound[3] == 100 and bound[4] == 100, 'Partial failure was not restored')
activate('refresh')
bound[3] = 555
assert(activate('apply'):find('Live LUT changed', 1, true) and bound[3] == 555)
bound[3] = 100
activate('refresh')
activate('apply')
membership = false
activate('restore')
assert(bound[3] == 200, 'Stale material was mutated')
membership = true
bound[3] = 100
bound[4] = 100
local fixture = io.open('tests/tmp/files/importtest.zip', 'rb')
if fixture then
    fixture:close()
    m.native_import = dofile('src/platform/windows.lua')
    local script = assert(io.open('tools/import_zip.ps1', 'rb'))
    m.zip_import_script = script:read('*a'):gsub('.', function(c)
        return string.format('%02x', c:byte())
    end)
    script:close()
    assert(handle.set('format', 2))
    assert(handle.set('file', 'importtest'))
    assert(activate('load'):find('Extracting ZIP', 1, true))
    ffi.cdef('void epic_direct_test_sleep(uint32_t) __asm__("Sleep");')
    local kernel = ffi.load('kernel32')
    local complete = false
    for i = 1, 200 do
        editor.on_update(ctx, 0.05)
        for _, c in ipairs(api.mods.epic_direct_lut.pages[1].controls) do
            if c.id == 'status' and c.label:find('DDS imported', 1, true) then
                complete = true
            end
        end
        if complete then
            break
        end
        kernel.epic_direct_test_sleep(50)
    end
    assert(complete, 'Asynchronous ZIP import did not finish in Lua')
    activate('save_palette')
    activate('refresh')
    activate('apply')
    assert(bound[3] == gpu_object and bound[4] == gpu_object)
    activate('restore')
    assert(bound[3] == 100 and bound[4] == 100)
    print(
        'PASS direct ZIP: real Windows background launch, patch extraction, Lua polling, selected palette load, Apply and Restore'
    )
end
-- Separate all-armor and helmet applications are cumulative, including source changes and refresh.
assert(handle.set('format', 1))
assert(handle.set('file', 'palette'))
activate('load')
activate('save_palette')
activate('refresh')
activate('apply_armor')
local armor_object = bound[3]
assert(bound[4] == armor_object and bound[6] == armor_object and bound[8] == 400)
local helmet = ffi.new('float[?]', 23 * 8 * 4)
for i = 0, 23 * 8 * 4 - 1 do
    helmet[i] = 0.25
end
m.dds.write('tests/tmp/files/helmet.dds', helmet, 23, 8)
assert(handle.set('file', 'helmet'))
activate('load')
activate('save_palette')
activate('apply_helmet')
local helmet_object = bound[8]
assert(
    helmet_object ~= armor_object and bound[3] == armor_object and bound[6] == armor_object,
    'Helmet application removed armor'
)
local bulk_uploads = creates
assert(handle.set('export_format', 4) and handle.set('dds_naming', 2))
activate('export_selected')
assert(bulk_naming == 2 and #bulk_entries == 4, 'Bulk export did not collect all custom gear bindings')
local armor_ordinals, helmets = {}, 0
for _, entry in ipairs(bulk_entries) do
    if entry.kind == 'armor' then
        armor_ordinals[entry.ordinal] = true
    else
        helmets = helmets + 1
    end
end
assert(armor_ordinals[1] and armor_ordinals[2] and helmets == 1)
assert(creates == bulk_uploads and bound[3] == armor_object and bound[8] == helmet_object, 'DDS export changed gear')
assert(handle.set('export_format', 1))
assert(handle.set('target_armor', false))
assert(handle.set('target_helmet', false))
assert(activate('apply_checked'):find('Check Armor', 1, true) and bound[3] == armor_object)
assert(handle.set('target_helmet', true))
activate('apply_checked')
assert(bound[3] == armor_object and bound[8] == helmet_object)
assert(handle.set('cell_color', '#FF0000'))
activate('apply_checked')
assert(bound[8] == helmet_object, 'File Apply LUT incorrectly applied the unsaved editor changes')
activate('apply_editor')
assert(bound[8] ~= helmet_object, 'Editor apply did not use the edited table')
activate('undo')
activate('apply_editor')
assert(bound[8] == helmet_object)
assert(handle.set('save_name', 'shared-palette'))
local actual_date = os.date
os.date = function()
    return '2026-10-08_21-15-30'
end
local export_base = 'tests/tmp/files/shared-palette-2026-10-08_21-15-30'
for _, suffix in ipairs({ '', '-01', '-02' }) do
    os.remove(export_base .. suffix .. '.dds')
end
activate('save_dds')
local shared = m.dds.read(export_base .. '.dds')
assert(shared[0] == 0.25, 'Shared preset did not retain full LUT data')
local f = assert(io.open(export_base .. '.dds', 'rb'))
local existing = f:read('*a')
f:close()
test_frontend.menu = {}
activate('save_dds')
assert(not test_frontend.menu.outfit_dialog, 'Timestamp export asked to overwrite')
assert(m.dds.read(export_base .. '-01.dds')[0] == 0.25)
f = assert(io.open(export_base .. '.dds', 'rb'))
assert(f:read('*a') == existing, 'Timestamp export overwrote earlier file')
f:close()
for _, suffix in ipairs({ '', '-01' }) do
    os.remove(export_base .. suffix .. '.dds')
end
os.date = actual_date
test_frontend.menu = nil

activate('refresh')
assert(bound[3] == armor_object and bound[8] == helmet_object, 'Refresh removed applied LUTs')
-- Completed startup restoration must not clone every LUT/history frame while idle.
editor.on_update(ctx, 0.01)
editor.on_update(ctx, 0.01)
local actual_copier = m.basic_state.copier
local idle_copies = 0
m.basic_state.copier = function()
    idle_copies = idle_copies + 1
    return actual_copier()
end
for i = 1, 10 do
    editor.on_update(ctx, 0.01)
end
m.basic_state.copier = actual_copier
assert(idle_copies == 0, 'Completed setup restoration still captures full snapshots every idle frame')

assert(handle.set('scope', 1))
assert(handle.set('lut', 2))
activate('apply')
assert(
    bound[3] == armor_object and bound[6] == armor_object and bound[8] == helmet_object,
    'Switching selected Armor LUT failed to load its palette or changed unrelated targets'
)
activate('save_setup')
local setup = m.direct_setup.new(m, m.paths.new())
local saved = setup.read()
assert(saved['armor-all'] and saved['helmet-all'] and saved['0:1:0:0'] and saved['0:2:0:0'] and saved['0:0:0:0'])
activate('refresh')
local selected_entry = assert(quick_info().armor[1])
local original_pixels = ffi.string(selected_entry.data, selected_entry.width * selected_entry.height * 16)
local old_helmet = bound[8]
quick_select(selected_entry, 1, 1, false, 'armor')
assert(handle.set('quick_color', '#234567'))
assert(bound[8] == old_helmet, 'Right-click paint spilled into Helmet')
local painted = quick_info().armor[1]
assert(
    ffi.string(painted.data + selected_entry.width * 4, (selected_entry.height - 1) * selected_entry.width * 16)
        == original_pixels:sub(selected_entry.width * 16 + 1),
    'Right-click paint changed other rows'
)
activate('global_undo')
local undone = quick_info().armor[1]
assert(
    ffi.string(undone.data, undone.width * undone.height * 16) == original_pixels,
    'Right-click paint could not be undone'
)
assert(editor.on_disable(ctx))
assert(bound[3] == 100 and bound[6] == 300 and bound[8] == 400)
-- Simulate another mod instance/launch: only stable local slots and persisted DDS data are used.
local restarted = assert(loadstring('local m=...\n' .. source))(m)
restarted.on_enable(ctx)
for i = 1, 20 do
    restarted.on_update(ctx, 0.1)
end
assert(
    bound[3] == armor_object and bound[6] == armor_object and bound[8] == helmet_object,
    'Saved multi-target setup did not resume'
)
local restart_handle = api.mods.epic_direct_lut.handle
assert(restart_handle.activate('restore'))
assert(bound[3] == 100 and bound[6] == 300 and bound[8] == 400)
assert(not next(setup.read()), 'Restore Original left automatic saved application enabled')
-- Shared source objects do not force Apply Armor to overwrite separate helmet materials.
bound[8] = 100
assert(restart_handle.set('format', 1))
assert(restart_handle.set('file', 'palette'))
assert(restart_handle.activate('load'))
assert(restart_handle.activate('save_palette'))
assert(restart_handle.activate('refresh'))
assert(restart_handle.activate('apply_armor'))
assert(bound[8] == 100 and bound[3] == armor_object, 'Shared resource group overwrote helmet during Apply Armor')
fail = true
assert(restart_handle.set('file', 'helmet'))
assert(restart_handle.activate('load'))
assert(restart_handle.activate('save_palette'))
assert(restart_handle.activate('apply_helmet'))
assert(bound[8] == 100 and bound[3] == armor_object, 'Failed helmet application undid armor or failed to roll back')
assert(restart_handle.activate('restore'))
bound[8] = 400
assert(restarted.on_disable(ctx))
local actual_launch = m.native_import.launch_worker
local workers = {}
m.native_import.launch_worker = function(args)
    local base = assert(args:match('%-Result "([^"]+)%.txt"'))
    local worker = { pid = 12345, alive = true, base = base, closed = false }
    function worker.running()
        return worker.alive
    end
    function worker.stop()
        worker.alive = false
    end
    function worker.close()
        worker.closed = true
    end
    workers[#workers + 1] = worker
    return worker
end
local recovery = assert(loadstring('local m=...\n' .. source))(m)
recovery.on_enable(ctx)
recovery.on_update(ctx, 0.1)
local rh = api.mods.epic_direct_lut.handle
assert(rh.activate('browse'))
workers[1].alive = false
recovery.on_update(ctx, 0.1)
assert(workers[1].closed, 'Dead worker handle leaked')
assert(rh.activate('browse'))
local w = workers[2]
local progress = assert(io.open(w.base .. '.txt.progress', 'wb'))
progress:write('99999\tpicker\t', tostring(os.time()))
progress:close()
recovery.on_update(ctx, 0.1)
assert(w.closed and not w.alive, 'Invalid picker state did not release the queue')
assert(rh.activate('browse'))
w = workers[3]
assert(rh.activate('cancel_import'))
w.alive = false
recovery.on_update(ctx, 0.1)
assert(w.closed)
assert(rh.activate('browse'))
assert(#workers == 4, 'Picker could not reopen after recovery')
assert(rh.activate('retry_import'))
workers[4].alive = false
recovery.on_update(ctx, 0.1)
assert(workers[4].closed and #workers == 5, 'Retry launched a second picker before closing the old one')
workers[5].alive = false
recovery.on_update(ctx, 0.1)
assert(recovery.on_disable(ctx))
-- Reusing the same addon object must not carry old documents or worker results
-- into the next activation, and cleanup must finish before state is discarded.
recovery.on_enable(ctx)
recovery.on_update(ctx, 0.1)
rh = api.mods.epic_direct_lut.handle
assert(rh.set('format', 1) and rh.set('file', 'palette'))
assert(rh.activate('load') and rh.activate('save_palette'))
quick_select({ width = 23, height = 8, data = data, source = quick_path, name = 'Table 1' }, 3, 6)
local old_document = assert(quick_info().editor)
local old_cleanup = cleanups[#cleanups]
m.import_description = 'Old imported archive'
local retained = package.loaded['epic.direct_lut.retained.v1']
local retained_records, retained_bytes = #retained.records, retained.bytes
assert(rh.activate('browse'))
local old_worker = workers[#workers]
local counter = package.loaded['epic.import.counter.v1'].value
local ready, why = pcall(recovery.on_enable, ctx)
assert(not ready and tostring(why):find('cleanup is still pending', 1, true))
assert(quick_info().editor == old_document and quick_info().busy, 'Pending cleanup discarded active state')
old_worker.alive = false
recovery.on_enable(ctx)
recovery.on_update(ctx, 0.1)
assert(old_worker.closed, 'Reinitialize leaked the old import worker')
local clean = quick_info()
assert(not clean.loaded and not clean.editor and not clean.busy and #clean.raw.tables == 0)
assert(m.quick_source == nil and m.import_description == nil, 'Old import metadata survived initialization')
assert(not api.mods.epic_direct_lut.controls.quick_color.can_open_picker(), 'Stale region opened a picker')
assert(old_cleanup() and api.mods.epic_direct_lut, 'Old cleanup callback closed the new activation')
assert(package.loaded['epic.direct_lut.retained.v1'] == retained)
assert(
    #retained.records == retained_records and retained.bytes == retained_bytes,
    'Initialization released GPU buffers'
)
assert(package.loaded['epic.import.counter.v1'].value == counter, 'Initialization reused an import job name')
assert(recovery.on_disable(ctx))
m.native_import.launch_worker = actual_launch
print(
    'PASS same-instance initialization: clean documents, selections and imports after worker cleanup; GPU buffers retained'
)
print(
    'PASS picker recovery: dead process, invalid heartbeat PID, cancellation and serialized retry; editor save is non-applying; checked targets and portable DDS export'
)
print(
    'PASS cumulative all-armor/helmet scopes, source and target switching, refresh without removal, saved defaults + individual overrides, restart restoration and Restore Original'
)
print(
    'PASS direct DDS: real registry, local binding groups, immutable reuse, foreign ownership, partial failure, stale membership and cleanup'
)

-- Exercise the real registry path for the new sharing controls, with native networking substituted.
m.avatar.reader = function()
    return function() end
end
m.shared_lut_codec = {
    new = function()
        return {}
    end,
}
m.lobby_sync = {}
local sharing_ticked = false
m.shared_appearance = {
    new = function()
        return {
            status = 'ready',
            tick = function(dt, enabled)
                assert(enabled == true)
                sharing_ticked = true
            end,
            close = function()
                return true
            end,
        }
    end,
}
local sharing_editor = assert(loadstring('local m=...\n' .. source))(m)
sharing_editor.on_enable(ctx)
sharing_editor.on_update(ctx, 0.1)
assert(api.mods.epic_direct_lut.controls.share_appearance)
for _, page in ipairs(api.mods.epic_direct_lut.pages) do
    assert(page.id ~= 'advanced', 'Duplicate Material / camo tab remains')
end
assert(
    api.mods.epic_direct_lut.controls.shader_mode and api.mods.epic_direct_lut.controls.camo_pattern,
    'Material controls removed from registry'
)
assert(sharing_ticked, 'Sharing was not enabled through Configuration')
assert(sharing_editor.on_disable(ctx))

-- The real binding-only avatar contract has no body/armor/helmet kit fields.
assert(
    pattern_deps and type(pattern_deps.gear_signature()) == 'string',
    'Partial avatar identity broke Pattern refresh'
)
local gear_before = pattern_deps.gear_signature()
local unit_before = units[1].unit
units[1].unit = unit_before + 100
assert(pattern_deps.gear_signature() ~= gear_before, 'Garment replacement did not change Pattern refresh identity')
units[1].unit = unit_before

-- Startup restores Pattern slots separately, waits for them, and saves before cleanup.
m.shared_appearance = nil
m.outfit_presets = nil
local old_binding, old_bind, old_create, old_originals =
    m.engine.binding, m.engine.bind, m.engine.create_texture, m.original_luts
local old_pattern_slot, old_time = m.engine.PATTERN_SLOT, memory.time
local pattern_bound = { [3] = 900, [4] = 900, [6] = 901, [8] = 902 }
local pattern_available, clock = false, 0
local pattern = { width = 3, height = 1, data = ffi.new('float[12]') }
pattern.data[0], pattern.data[3], pattern.data[7], pattern.data[11] = 0.3125, -0.125, 0.75, 13.25
m.engine.PATTERN_SLOT = 2
memory.time = function()
    return clock
end
m.engine.binding = function(_, material, slot)
    if slot == 2 then
        return pattern_available and pattern_bound[material] or nil
    end
    return bound[material]
end
m.engine.bind = function(_, material, slot, object)
    if slot == 2 then
        pattern_bound[material] = object
    else
        bound[material] = object
    end
end
local pattern_upload
m.engine.create_texture = function(_, w, h, data)
    if w == 3 then
        assert(h == 1)
        pattern_upload = ffi.string(data, 48)
        return { object = 5000, data = data, width = w, height = h }
    end
    return old_create(nil, w, h, data)
end
m.original_luts = {
    new = function()
        return {
            loaded = true,
            status = 'Ready',
            start = function() end,
            tick = function() end,
            close = function() end,
            get = function(object)
                if object >= 900 and object <= 902 then
                    return pattern
                end
                return { data = stock, width = 23, height = 8, resource = 'ffffffffffffffff' }
            end,
        }
    end,
}
local state_paths = m.paths.new()
local combined_setup = m.direct_setup.new(m, state_paths)
combined_setup.clear()
bound[3], bound[4], bound[6], bound[8] = 100, 100, 300, 400
combined_setup.save({
    { save_key = '0:1:0:0', texture = { data = stock, width = 23, height = 8 } },
    { save_key = 'p:0:1:0:0', texture = pattern },
}, {})
local combined_editor = assert(loadstring('local m=...\n' .. source))(m)
combined_editor.on_enable(ctx)
for _ = 1, 5 do
    clock = clock + 0.3
    combined_editor.on_update(ctx, 0.3)
end
assert(pattern_bound[3] == 900 and bound[3] == 100, 'Saved setup applied before Pattern slots became ready')
pattern_available = true
for _ = 1, 20 do
    clock = clock + 0.3
    combined_editor.on_update(ctx, 0.3)
end
assert(
    pattern_bound[3] == 5000 and bound[3] ~= 100 and pattern_upload == ffi.string(pattern.data, 48),
    'Mixed setup failed exact Pattern/material resume'
)
local mixed_handle = api.mods.epic_direct_lut.handle
assert(mixed_handle.set('export_format', 4) and mixed_handle.activate('export_selected'))
local exported_pattern = false
for _, entry in ipairs(bulk_entries) do
    if entry.document.width == 3 then
        assert(ffi.string(entry.document.data, 48) == pattern_upload, 'Bulk export changed Pattern bits')
        exported_pattern = true
    end
end
assert(exported_pattern, 'Bulk DDS omitted applied Pattern LUTs')
assert(quick_info().editor and quick_info().editor.width == 23, 'Pattern setup was loaded into the material editor')
assert(combined_editor.on_disable(ctx))
assert(bound[3] == 100 and pattern_bound[3] == 900, 'Owned Pattern/material cleanup did not restore source bindings')
assert(combined_setup.read()['p:0:1:0:0'], 'Closing Pattern editor erased its persisted setup')

combined_setup.save({ { save_key = 'p:0:1:0:0', texture = pattern } }, {})
local pattern_only = assert(loadstring('local m=...\n' .. source))(m)
pattern_only.on_enable(ctx)
for _ = 1, 20 do
    clock = clock + 0.3
    pattern_only.on_update(ctx, 0.3)
end
assert(
    pattern_bound[3] == 5000 and bound[3] == 100 and quick_info().editor == nil,
    'Pattern-only startup altered material slots/editor'
)
assert(pattern_only.on_disable(ctx) and pattern_bound[3] == 900)
assert(combined_setup.read()['p:0:1:0:0'], 'Pattern-only close could not remember its applied preset')
local restored_pattern = assert(loadstring('local m=...\n' .. source))(m)
restored_pattern.on_enable(ctx)
for _ = 1, 20 do
    clock = clock + 0.3
    restored_pattern.on_update(ctx, 0.3)
end
assert(api.mods.epic_direct_lut.handle.activate('restore'))
assert(
    pattern_bound[3] == 900 and not next(combined_setup.read()),
    'Global Restore Original left Pattern or persisted bindings applied'
)
assert(restored_pattern.on_disable(ctx))
combined_setup.save({ { save_key = 'p:0:1:0:0', texture = pattern } }, {})
local foreign_pattern = assert(loadstring('local m=...\n' .. source))(m)
foreign_pattern.on_enable(ctx)
for _ = 1, 20 do
    clock = clock + 0.3
    foreign_pattern.on_update(ctx, 0.3)
end
pattern_bound[3] = 7777
assert(foreign_pattern.on_disable(ctx) and pattern_bound[3] == 7777, 'Pattern cleanup overwrote foreign ownership')
assert(not next(combined_setup.read()), 'Foreign-overridden Pattern was retained for startup')
m.engine.binding, m.engine.bind, m.engine.create_texture, m.original_luts =
    old_binding, old_bind, old_create, old_originals
m.engine.PATTERN_SLOT, memory.time = old_pattern_slot, old_time
print(
    'PASS Pattern startup: deferred discovery, exact mixed and Pattern-only resume, save-before-cleanup and foreign ownership'
)

-- Built-in table: exact float bits, a fresh editable copy and no live upload.
local debug_file = assert(io.open('assets/debug-lut.dds', 'rb'))
local debug_bytes = debug_file:read('*a')
debug_file:close()
m.debug_lut_dds_hex = debug_bytes:gsub('.', function(byte)
    return string.format('%02x', byte:byte())
end)
local expected_debug, debug_width, debug_height = m.dds.decode(debug_bytes)
local debug_pixels = ffi.string(expected_debug, debug_width * debug_height * 16)
local debug_editor = assert(loadstring('local m=...\n' .. source))(m)
debug_editor.on_enable(ctx)
debug_editor.on_update(ctx, 0.1)
local debug_handle = api.mods.epic_direct_lut.handle
local debug_uploads, debug_armor, debug_helmet = creates, bound[3], bound[8]
assert(debug_handle.activate('load_debug_lut'))
local debug_document = assert(quick_info().editor)
assert(debug_document.width == 23 and debug_document.height == 8)
assert(ffi.string(debug_document.data, #debug_pixels) == debug_pixels)
assert(quick_info().loaded.data ~= debug_document.data, 'Debug editor aliases its imported original')
assert(creates == debug_uploads and bound[3] == debug_armor and bound[8] == debug_helmet, 'Debug load applied to gear')
debug_document.data[0] = 123
assert(debug_handle.activate('load_debug_lut'))
assert(quick_info().editor ~= debug_document and ffi.string(quick_info().editor.data, #debug_pixels) == debug_pixels)
assert(debug_handle.set('palette', 1) and debug_handle.activate('save_palette'))
assert(
    ffi.string(quick_info().editor.data, #debug_pixels) == debug_pixels,
    'Built-in palette path tried to open a file'
)
assert(debug_editor.on_disable(ctx))
print('PASS built-in Debug LUT: exact supplied DDS, fresh editable reloads and no live application')
