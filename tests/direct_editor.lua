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
local m = {
    lut_files = dofile('src/presets/lut_files.lua'),
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
                cache = test_root .. '/tests/tmp/cache',
                settings = test_root .. '/tests/tmp/direct-state',
                presets = test_root .. '/tests/tmp/presets',
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
local ctx = { log = function() end, on_cleanup = function() end }
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
                return { data = stock, width = 23, height = 8, resource = 'ffffffffffffffff' }
            end,
        }
    end,
}
local stock_editor = assert(loadstring('local m=...\n' .. source))(m)
stock_editor.on_enable(ctx)
stock_editor.on_update(ctx, 0)
handle = api.mods.epic_direct_lut.handle
local armor_before, helmet_before = handle.get('target_armor'), handle.get('target_helmet')
activate('populate_worn')
assert(
    handle.get('target_armor') == armor_before and handle.get('target_helmet') == helmet_before,
    'Loading worn colors changed target choices'
)
assert(bound[3] == 100, 'Population wrote game bindings')
assert(handle.get('cell_r') == 0.25, 'Stock game pixels did not populate editor')
activate('editor_load_armor')
assert(
    handle.get('cell_r') == 0.25 and bound[3] == 100,
    'Editor Populate failed to load worn Armor before any custom application'
)
assert(handle.set('outfit_name', 'Stock Outfit'))
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
local remembered = m.direct_setup.new(m, m.paths.new()).read()
assert(next(remembered), 'Applying an Armory preset did not persist the active setup')
assert(handle.activate('outfit_apply_helmet'))
remembered = m.direct_setup.new(m, m.paths.new()).read()
assert(
    remembered['0:0:0:0'] and remembered['0:1:0:0'],
    'Mixed Armor and Helmet applications were not retained together'
)
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
activate('save_dds')
local shared = m.dds.read('tests/tmp/files/shared-palette.dds')
assert(shared[0] == 0.25, 'Shared preset did not retain full LUT data')
activate('refresh')
assert(bound[3] == armor_object and bound[8] == helmet_object, 'Refresh removed applied LUTs')
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
m.native_import.launch_worker = actual_launch
print(
    'PASS picker recovery: dead process, invalid heartbeat PID, cancellation and serialized retry; editor save is non-applying; checked targets and portable DDS export'
)
print(
    'PASS cumulative all-armor/helmet scopes, source and target switching, refresh without removal, saved defaults + individual overrides, restart restoration and Restore Original'
)
print(
    'PASS direct DDS: real registry, local binding groups, immutable reuse, foreign ownership, partial failure, stale membership and cleanup'
)
