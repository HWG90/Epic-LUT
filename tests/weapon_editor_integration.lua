-- Production editor/bridge/discovery/runtime/session code over bounded native
-- ports. Reuse the maintained garment fixture to exercise actual registration.
local ffi = require('ffi')
local f = dofile('tests/weapon_fixture.lua')()
local file = assert(io.open('tests/direct_editor.lua', 'rb'))
local text = file:read('*a')
file:close()
local marker = assert(text:find("local f = assert(io.open('src/editor/direct_editor.lua'", 1, true))
-- This focused fixture already resolves dofile paths from the repository root.
-- verify.py supplies an absolute root; a direct LuaRunner invocation need not.
local fixture_source, replacements = text:sub(1, marker - 1):gsub(
    "local test_root = assert%(os%.getenv%('EPIC_LUT_TEST_ROOT'%)%)",
    "local test_root = os.getenv('EPIC_LUT_TEST_ROOT') or '.'"
)
assert(replacements == 1, 'Garment fixture test-root contract changed')
local base = assert(loadstring(fixture_source .. [[
return {m=m,api=api,memory=memory,native=native,bound=bound,frontend=function()return test_frontend end,info=function()return quick_info()end}
]], '@weapon-editor-garment-fixture'))()
local m = base.m
local palette_new = m.lut_editor.new
m.lut_editor.new = function(...)
    local palette = palette_new(...)
    base.palette = palette
    return palette
end
m.weapon_runtime = dofile('src/weapons/weapon_runtime.lua')
m.weapon_discovery = dofile('src/weapons/weapon_discovery.lua')
m.weapon_controller = dofile('src/editor/weapon_controller.lua')
m.weapon_view = dofile('src/editor/weapon_view.lua')
m.weapon_bridge = dofile('src/editor/weapon_bridge.lua')
m.weapon_pattern_quick = dofile('src/editor/weapon_pattern_quick.lua')
m.weapon_mapping = dofile('src/editor/weapon_mapping.lua')
m.primary_identity = {
    new = function()
        return f.identity
    end,
}
_G.stingray = f.E
base.api.focus_page = function(id, page)
    assert(id == 'epic_direct_lut')
    base.focused_page = page
end
local native = {}
for key, value in pairs(f.native) do
    native[key] = value
end
native.alive = function(unit)
    return f.units[unit] and f.native.alive(unit) or base.native.alive(unit)
end
native.commit = function() end
m.engine.open = function()
    return native
end
local old_binding, old_bind, old_create = m.engine.binding, m.engine.bind, m.engine.create_texture
m.engine.binding = function(read, material, slot, small, big)
    if f.textures[material] then
        return f.textures[material][slot]
    end
    return old_binding(read, material, slot, small, big)
end
m.engine.bind = function(_, material, slot, object)
    if f.textures[material] then
        f.writes[#f.writes + 1] = { material = material, slot = slot, object = object }
        f.textures[material][slot] = object
    else
        return old_bind(native, material, slot, object)
    end
end
m.engine.create_texture = function(_, width, height, data)
    f.allocations = f.allocations + 1
    local object = f.next_texture
    f.next_texture = f.next_texture + 0x1000
    return { object = object, data = data, width = width, height = height }
end
base.memory.read = function(pointer, size)
    return f.read(tonumber(ffi.cast('uintptr_t', pointer)), size)
end
m.original_luts = {
    new = function()
        return {
            loaded = true,
            start = function() end,
            tick = function() end,
            close = function() end,
            get = function(object)
                return f.documents[object]
            end,
            request_object = function(object)
                return f.documents[object]
            end,
        }
    end,
}
local editor_file = assert(io.open('src/editor/direct_editor.lua', 'rb'))
local source = editor_file:read('*a')
editor_file:close()
local editor = assert(loadstring('local m=...\n' .. source, '@production-weapon-editor'))(m)
local logs = {}
local ctx = {
    log = function(value)
        logs[#logs + 1] = value
    end,
    on_cleanup = function() end,
}
editor.on_enable(ctx)
editor.on_update(ctx, 0)
local mod, handle = base.api.mods.epic_direct_lut, base.api.mods.epic_direct_lut.handle
assert(
    mod.controls.weapon_slot and mod.controls.weapon_family and mod.controls.editor_apply_weapon,
    'Production registration omitted the weapon modules'
)
local page
for _, candidate in ipairs(mod.pages) do
    if candidate.id == 'weapons' then
        page = candidate
    end
end
assert(page and page.render_layout and page.on_wheel)
assert(handle.activate('editor_load_weapon'))
assert(base.info().editor and base.info().editor.kind == 'weapon',
    'Weapon header did not load its table like Armor and Helmet')
local function buttons()
    local result = {}
    page.render_layout({
        x = 0,
        y = 0,
        w = 1800,
        h = 1300,
        theme = { white = { 255, 255, 255 }, muted = { 100, 100, 100 }, line = { 50, 50, 50 }, panel = { 30, 30, 30 } },
        spacing = function(n)
            return n
        end,
        control_height = function(_, _, minimum)
            return minimum
        end,
        text_width = function(value)
            return #value * 8
        end,
        text_y = function(y)
            return y + 2
        end,
        rect = function() end,
        bounded = function() end,
        choice = function() end,
        hit = function() end,
        checkbox = function() end,
        viewport = function(_, draw)
            draw()
        end,
        scrollbar = function() end,
        button = function(_, _, _, _, _, callback, options)
            if options.action then
                result[options.action] = callback
            end
        end,
    })
    return result
end
assert(buttons().weapon_editor())
local selected_page = base.frontend().menu.page
for index, candidate in ipairs(mod.pages) do
    if candidate.id == 'colors' then base.frontend().menu.page = index end
end
local selection_writes = #f.writes
assert(handle.set('weapon_lut', 2))
assert(base.info().editor.kind == 'weapon' and base.info().editor.data[0] == f.documents[f.B].data[0],
    'Weapon LUT dropdown did not load its selected group into the shared table')
assert(#f.writes == selection_writes, 'Selecting a weapon LUT applied it to live bindings')
assert(handle.set('weapon_lut', 1))
assert(handle.set('weapon_slot', 2))
assert(base.info().editor.weapon_slot == 2, 'Shared weapon slot selector retained the primary draft')
assert(handle.set('weapon_slot', 3))
assert(base.info().editor == nil, 'Unavailable support slot retained an applicable primary/secondary draft')
assert(handle.set('weapon_slot', 1))
assert(base.info().editor.weapon_slot == 1 and #f.writes == selection_writes,
    'Selecting a weapon slot wrote live bindings')
base.frontend().menu.page = selected_page
local loaded = base.info().editor
assert(loaded.kind == 'weapon' and loaded.family == 'material' and loaded.weapon_slot == 1 and loaded.width == 23)
assert(
    mod.controls.cell_a.disabled and not mod.controls.cell_r.disabled,
    'Main raw Alpha lock or primary RGB permission changed'
)
assert(handle.set('unlock', true) and not mod.controls.cell_a.disabled,
    'Advanced mode did not provide the same raw Alpha access as garments')
assert(handle.set('unlock', false) and mod.controls.cell_a.disabled)
local rendered_menu = dofile('vendor/menu/menu.lua').new(base.api, function(value, size)
    return #value * size * 0.5
end)
rendered_menu.visible, rendered_menu.compact_fonts, rendered_menu.epic_typography = true, true, true
rendered_menu.window_width, rendered_menu.window_height = 1800, 1200
for index, candidate in ipairs(mod.pages) do
    if candidate.id == 'colors' then
        rendered_menu.page = index
    end
end
local copied_weapon_id
rendered_menu.clipboard = {
    set = function(text)
        copied_weapon_id = text
        return true
    end,
}
local function weapon_footer()
    local commands = rendered_menu.compose(2400, 1600)
    local found, header = false, {}
    for _, command in ipairs(commands) do
        assert(not (command.text and command.text:find('Editor control missing:', 1, true)), command.text)
        found = found or command.text == 'Apply weapon'
        if command.text == 'Helmet LUT' or command.text == 'Armor LUT' or command.text == 'Weapon LUT' then
            header[command.text] = command
        end
    end
    assert(found, 'Rendered weapon editor changed the Apply footer back to garment scope')
    if base.info().editor.width == 23 then
        local quick, roughness = false, false
        for _, command in ipairs(commands) do
            quick = quick or command.text == 'Quick Editor: Pattern LUT'
            roughness = roughness or command.text == 'Roughness'
        end
        assert(quick and roughness, 'Shared weapon table omitted its Pattern quick controls')
    end
    assert(
        header['Helmet LUT'] and header['Armor LUT'] and header['Weapon LUT'],
        'Shared LUT header omitted Weapon LUT'
    )
    assert(
        header['Helmet LUT'].x < header['Armor LUT'].x
            and header['Armor LUT'].x < header['Weapon LUT'].x
            and header['Helmet LUT'].y == header['Weapon LUT'].y,
        'Weapon LUT is not beside Armor and Helmet'
    )
    return commands
end
weapon_footer()
local header_commands = weapon_footer() -- Repeated layout must retain its weapon context.
local weapon_id_text
for _, command in ipairs(header_commands) do
    if (command.full_text or command.text) == '[0x' .. loaded.resource .. ']' then
        weapon_id_text = command
    end
end
assert(weapon_id_text, 'Weapon header omitted its raw texture ID')
local before_copy_writes = #f.writes
assert(handle.set('resource_format', 2))
for _, down in ipairs({ true, false }) do
    rendered_menu.tick({
        down = function(key)
            return down and key == 2
        end,
        mouse = function()
            return weapon_id_text.x + 2, weapon_id_text.y + 2
        end,
        wheel = function()
            return 0
        end,
    })
end
assert(
    copied_weapon_id == m.resource_ids.format(loaded.resource, true):sub(2, -2),
    'Weapon ID copy used the garment naming resolver or ignored the format preference: ' .. tostring(copied_weapon_id)
)
assert(#f.writes == before_copy_writes and rendered_menu.visible, 'Weapon ID copy changed native LUT bindings')
assert(handle.set('resource_format', 1))
local gear = {}
for material, value in pairs(base.bound) do
    gear[material] = value
end
assert(handle.set('cell_r', 0.625))
editor.on_update(ctx, 0.1)
assert(#f.writes == 5, 'Live main edit did not write every primary LOD')
for material, value in pairs(gear) do
    assert(base.bound[material] == value, 'Weapon live edit contaminated garment scope')
end
assert(handle.set('weapon_family', 2))
assert(buttons().weapon_editor())
loaded = base.info().editor
assert(loaded.kind == 'weapon' and loaded.family == 'pattern' and loaded.width == 3 and loaded.height == 1)
assert(handle.set('edit_column', 3))
weapon_footer()
weapon_footer()
assert(
    not mod.controls.cell_a.disabled
        and mod.controls.cell_r.disabled
        and mod.controls.cell_g.disabled
        and mod.controls.cell_b.disabled,
    'Known roughness Alpha numeric permission differs from RGB/raw guards'
)
local pattern_before = ffi.string(loaded.data, 48)
assert(handle.set('cell_a', 0.875))
editor.on_update(ctx, 0.1)
assert(
    #f.writes == 10 and ffi.string(loaded.data, 48):sub(1, 44) == pattern_before:sub(1, 44),
    'Pattern Alpha touched RGB/other channels or missed LODs'
)
local control = mod.controls.cell_color
assert(control.can_open_picker(6) and control.picker_channel_enabled(4, 6) and not control.picker_channel_enabled(1, 6))
control.picker_begin(6)
control.picker_preview({ 255, 0, 255 }, 0.3125)
control.picker_end(true)
editor.on_update(ctx, 0.1)
assert(
    #f.writes == 15
        and loaded.data[11] == 0.3125
        and ffi.string(loaded.data, 48):sub(1, 44) == pattern_before:sub(1, 44)
)
assert(handle.set('weapon_family', 1) and buttons().weapon_editor())
local weapon_writes = #f.writes
assert(handle.activate('apply_armor'))
assert(#f.writes == weapon_writes, 'Explicit Apply Armor from a weapon draft was routed into the weapon runtime')
assert(base.bound[3] ~= gear[3], 'Explicit Apply Armor did not reach its garment scope')
-- Import and Send must retain the selected weapon destination, including Pattern DDS.
for _, sample in ipairs({{name='weapon-import', object=f.A, width=23, height=8}, {name='weapon-pattern-import', object=f.P, width=3, height=1}}) do
    assert(buttons().weapon_editor())
    local before = #f.writes
    m.dds.write('tests/tmp/files/' .. sample.name .. '.dds', f.documents[sample.object].data, sample.width, sample.height)
    assert(handle.set('format', 1) and handle.set('file', sample.name))
    assert(handle.activate('load'))
    assert(#f.writes == before, 'Import wrote to live weapons')
    assert(handle.activate('save_palette'))
    local imported = base.info().editor
    assert(imported.kind == 'weapon' and imported.width == sample.width, 'Send lost weapon import context')
    assert(handle.activate('editor_apply_weapon'))
    assert(#f.writes > before, 'Apply imported weapon document did not bind its destination')
    before = #f.writes
    assert(handle.activate('apply_checked'))
    assert(base.info().editor.kind == 'weapon', 'Apply imported file lost weapon scope')
end
assert(handle.set('weapon_family', 1) and buttons().weapon_editor())
local reset_document = base.info().editor
assert(handle.set('auto_populate_worn', true))
editor.on_update(ctx, 1.1)
assert(base.info().editor == reset_document and reset_document.kind == 'weapon', 'Automatic worn gear replaced the weapon table')
assert(handle.set('edit_row', 1) and handle.set('edit_column', 1))
local original_red = reset_document.data[0]
assert(handle.set('cell_r', 0.19375))
editor.on_update(ctx, 0.1)
assert(reset_document.data[0] ~= original_red, 'Weapon numeric edit did not change its draft')
assert(handle.activate('reset_cell'))
editor.on_update(ctx, 0.1)
assert(reset_document.data[0] == original_red, 'Weapon Reset cell did not restore loaded values')
-- Exercise the real grid clipboard and keyboard path on a weapon draft.
weapon_footer()
local palette = assert(base.palette)
local clipboard_before = ffi.string(reset_document.data, 23 * 8 * 16)
palette.selection = {r1=1,r2=2,c1=1,c2=2}
assert(palette.key(67, true, false, {}))
palette.set_paste_anchor(3, 17)
assert(palette.key(86, true, false, {}))
local clipboard_after = ffi.string(reset_document.data, 23 * 8 * 16)
assert(clipboard_after ~= clipboard_before, 'Weapon clipboard test did not change destination cells')
for row=0,1 do
    local source_at = row * 23 * 16
    local destination_at = ((row+2)*23+16)*16
    assert(clipboard_after:sub(destination_at+1,destination_at+32) == clipboard_before:sub(source_at+1,source_at+32),
        'Weapon clipboard lost HDR, signed-zero or Alpha bytes')
end
local pasted_writes = #f.writes
editor.on_update(ctx, 0.1)
assert(#f.writes == pasted_writes + 5, 'Weapon paste did not apply to exactly its five selected LODs')
assert(not palette.key(46, false, false, {control='cell_r'}), 'Delete in a numeric input reset the grid')
assert(ffi.string(reset_document.data, 23*8*16) == clipboard_after)
assert(palette.key(46, false, false, {}))
assert(ffi.string(reset_document.data, 23*8*16) == clipboard_before,
    'Weapon Delete did not reset only selected cells to their loaded float32 bytes')
local deleted_writes = #f.writes
editor.on_update(ctx, 0.1)
assert(#f.writes == deleted_writes + 5, 'Weapon Delete did not update exactly its five LODs')
for _, mesh in ipairs(f.units[200].meshes) do
    assert(f.textures[mesh.materials[1]][0x7e662968] == f.A, 'Weapon grid edits changed the secondary')
end
local flash_before = {}
for _, mesh in ipairs(f.units[100].meshes) do
    for _, material in ipairs(mesh.materials) do
        flash_before[material] = f.textures[material][0x7e662968]
    end
end
local flash_pixels = ffi.string(reset_document.data, reset_document.width * reset_document.height * 16)
assert(handle.activate('identify_region'))
for _, mesh in ipairs(f.units[100].meshes) do
    assert(f.textures[mesh.materials[1]][0x7e662968] ~= flash_before[mesh.materials[1]], 'Identify missed primary LOD')
    assert(f.textures[mesh.materials[2]][0x7e662968] == flash_before[mesh.materials[2]], 'Identify changed sibling material')
end
assert(ffi.string(base.info().editor.data, #flash_pixels) == flash_pixels, 'Highlight leaked into editor pixels')
editor.on_update(ctx, 0.3)
for _, mesh in ipairs(f.units[100].meshes) do
    assert(f.textures[mesh.materials[1]][0x7e662968] == flash_before[mesh.materials[1]], 'Weapon blink off did not restore exact binding')
end
assert(handle.activate('stop_identify'))
assert(handle.activate('identify_region'))
editor.on_update(ctx, 4.1)
for _, mesh in ipairs(f.units[100].meshes) do
    assert(f.textures[mesh.materials[1]][0x7e662968] == flash_before[mesh.materials[1]], 'Weapon highlight timeout did not restore')
end
assert(editor.on_disable(ctx))
for material, value in pairs(gear) do
    assert(base.bound[material] == value, 'Cleanup left modified garment bindings')
end
for _, unit in ipairs({ 100, 200 }) do
    for _, mesh in ipairs(f.units[unit].meshes) do
        for index, material in ipairs(mesh.materials) do
            assert(f.textures[material][0x7e662968] == (index == 1 and f.A or f.B), 'Cleanup left a weapon LUT bound')
            if index == 1 then
                assert(f.textures[material][0x81d4c49d] == f.P, 'Cleanup left a Pattern LUT bound')
            end
        end
    end
end

-- Complete-addon cleanup must restore known garment/weapon bindings even if a
-- weapon session cannot certify retirement. The actual lifetime service then
-- quarantines its backing buffers without guessing ownership or destroying GPU
-- handles. Use separate activations so the cohorts cannot certify each other.
m.texture_lifetime = dofile('src/gear/texture_lifetime.lua')
local runtime_new = m.weapon_runtime.new
local creates = m.engine.create_texture
local destroyed = 0
native.destroy = function()
    destroyed = destroyed + 1
end
m.engine.create_texture = function(...)
    local texture = creates(...)
    texture.handle = texture.object
    return texture
end
for _, fault in ipairs({ 'foreign', 'throw' }) do
    m.weapon_runtime.new = function(deps)
        local runtime = runtime_new(deps)
        if fault == 'throw' then
            runtime.restore = function()
                error('Uncertain weapon restoration read', 0)
            end
        end
        return runtime
    end
    local closing_editor = assert(loadstring('local m=...\n' .. source, '@weapon-editor-cleanup-' .. fault))(m)
    closing_editor.on_enable(ctx)
    closing_editor.on_update(ctx, 0)
    mod, handle = base.api.mods.epic_direct_lut, base.api.mods.epic_direct_lut.handle
    for _, candidate in ipairs(mod.pages) do
        if candidate.id == 'weapons' then
            page = candidate
        end
    end
    assert(handle.activate('editor_load_weapon') and buttons().weapon_editor())
    assert(handle.set('cell_r', fault == 'foreign' and 0.4375 or 0.5625))
    closing_editor.on_update(ctx, 0.1)
    assert(handle.activate('apply_armor') and base.bound[3] ~= gear[3])
    local foreign_material = f.units[100].meshes[1].materials[1]
    if fault == 'foreign' then
        f.textures[foreign_material][0x7e662968] = 0xdead00
    end
    local retained = assert(package.loaded['epic.direct_lut.retained.v1'])
    local cohort, count, bytes, destroyed_before = retained.cohort, #retained.records, retained.bytes, destroyed
    assert(closing_editor.on_disable(ctx), 'Weapon cleanup failure prevented completed quarantine: ' .. fault)
    for material, value in pairs(gear) do
        assert(base.bound[material] == value, 'Weapon cleanup failure skipped garment restoration: ' .. fault)
    end
    assert(
        #retained.records == count
            and retained.bytes == bytes
            and destroyed == destroyed_before
            and cohort.sessions == nil
            and retained.cohort == nil,
        'Uncertified cleanup freed textures, skipped quarantine, or retained addon closures: ' .. fault
    )
    if fault == 'foreign' then
        assert(f.textures[foreign_material][0x7e662968] == 0xdead00, 'Cleanup overwrote a foreign weapon writer')
        for _, mesh in ipairs(f.units[100].meshes) do
            if mesh.materials[1] ~= foreign_material then
                assert(f.textures[mesh.materials[1]][0x7e662968] == f.A, 'Known weapon LOD was not restored')
            end
        end
    end
    local quarantined = false
    for _, value in ipairs(logs) do
        quarantined = quarantined or value:find('texture retirement: quarantined', 1, true) ~= nil
    end
    assert(quarantined, 'Production cleanup never reached the lifetime quarantine service')
    assert(closing_editor.on_disable(ctx) and destroyed == destroyed_before, 'Completed quarantine retried disposal')
    -- The next synthetic activation starts from pristine test inputs; actual
    -- runtime cleanup must retain these unsafe buffers and never do this reset.
    for _, mesh in ipairs(f.units[100].meshes) do
        f.textures[mesh.materials[1]][0x7e662968] = f.A
    end
end
m.weapon_runtime.new = runtime_new

-- Exercise the real provenance pending sentinel through the production update
-- poll. Reuse only the provenance fixture factory, before its test cases run.
local provenance_file = assert(io.open('tests/weapon_provenance.lua', 'rb'))
local provenance_text = provenance_file:read('*a')
provenance_file:close()
local provenance_marker = assert(provenance_text:find("test('weapon source worker paths", 1, true))
local provenance_setup = assert(loadstring(provenance_text:sub(1, provenance_marker - 1) .. 'return setup'))()
local pending_sources = provenance_setup()
local pending_binding = pending_sources.runtime.groups(1, 'material')[1].bindings[1]
local ready, pending_status = pcall(pending_sources.sources.capture, pending_binding)
assert(not ready and pending_status == dofile('src/weapons/weapon_provenance.lua').PENDING)
local pending_source, hooks = source:gsub("(return {[%s]+name = 'Epic LUT')", function(value)
    return 'm.weapon_fixture_access=function()return operations,function(value)status=value end end\n' .. value
end)
assert(hooks == 1, 'Production pending fixture did not find the addon return')
local pending_editor = assert(loadstring('local m=...\n' .. pending_source, '@weapon-editor-source-pending'))(m)
local source_factories = 0
m.weapon_provenance = {
    PENDING = dofile('src/weapons/weapon_provenance.lua').PENDING,
    new = function(_, host)
        source_factories = source_factories + 1
        assert(host.discovery and host.groups and host.original and host.paths and host.lua_engine)
        return pending_sources.sources
    end,
}
pending_editor.on_enable(ctx)
local pending_operations, set_status = m.weapon_fixture_access()
assert(pending_operations.weapon_sources() == pending_sources.sources and source_factories == 1)
set_status(pending_status)
local notes = #logs
pending_editor.on_update(ctx, 0)
assert(
    #logs > notes and logs[notes + 1] == 'Epic LUT: Exact weapon binding sources ready',
    'A prefixed pending exception prevented the production source-ready notification'
)
assert(pending_editor.on_disable(ctx))
m.weapon_fixture_access = nil

-- Preserve the lazy factories across activation resets and run the registered
-- controller callbacks through actual mapping, storage, export and local sharing
-- services. Only imported-file inputs and the lobby transport boundary are fake.
m.weapon_provenance = dofile('src/weapons/weapon_provenance.lua')
m.weapon_presets = dofile('src/presets/weapon_presets.lua')
m.outfit_targets = dofile('src/presets/outfit_targets.lua')
m.outfit_presets = dofile('src/presets/outfit_presets.lua')
m.preset_export = dofile('src/presets/preset_export.lua')
m.patch_export = dofile('src/presets/patch_export.lua')
m.weapon_shared = dofile('src/weapons/weapon_shared.lua')
local Workflow = dofile('src/editor/weapon_workflow.lua')
local imported_paths = { 'lut000.dds', 'PatternLUT000.dds' }
local imported = {
    ['lut000.dds'] = m.weapon_mapping.copy(f.documents[f.A]),
    ['PatternLUT000.dds'] = m.weapon_mapping.copy(f.documents[f.P]),
}
imported['lut000.dds'].data[0], imported['PatternLUT000.dds'].data[11] = 0.78125, 0.8125
local workflow_factories, shared_entries = 0, {}
m.weapon_workflow = {
    new = function(modules, host)
        workflow_factories = workflow_factories + 1
        host.imports.palettes = function()
            return imported_paths
        end
        host.imports.document = function(path)
            return imported[path]
        end
        host.imports.resource = function(_, document)
            return document.resource
        end
        return Workflow.new(modules, host)
    end,
}
m.avatar.reader = function()
    return function() end
end
m.avatar.resolve = function()
    return { body = 1, armor = 2, helmet = 3 }
end
m.shared_lut_codec = {
    new = function()
        return {}
    end,
}
m.shared_appearance = {
    new = function(deps)
        return {
            tick = function(_, enabled)
                if enabled then
                    local identity = assert(deps.identity())
                    shared_entries = deps.entries()
                    for _, entry in ipairs(shared_entries) do
                        if entry.kind == 'weapon' then
                            assert(identity.weapons[entry.weapon_slot] == entry.weapon_resource)
                        end
                    end
                end
            end,
            authorized = function()
                return false
            end,
            close = function()
                return true
            end,
        }
    end,
}
local history_new, workflow_history = m.action_history.new
m.action_history.new = function(...)
    workflow_history = history_new(...)
    return workflow_history
end
local workflow_editor = assert(loadstring('local m=...\n' .. source, '@weapon-editor-registered-workflows'))(m)
for activation = 1, 2 do
    workflow_editor.on_enable(ctx)
    workflow_editor.on_update(ctx, 0)
    mod, handle = base.api.mods.epic_direct_lut, base.api.mods.epic_direct_lut.handle
    for _, candidate in ipairs(mod.pages) do
        if candidate.id == 'weapons' then
            page = candidate
        end
    end
    assert(handle.activate('editor_load_weapon'))
    local before = #workflow_history.undo
    local applied, texture = buttons().weapon_apply()
    assert(applied == 5 and texture.object, 'Weapon mutation lost its native count/texture return values')
    assert(#workflow_history.undo == before + 1, 'Weapons Apply omitted global Undo history')
    assert(handle.activate('global_undo'))
    assert(f.textures[f.units[100].meshes[1].materials[1]][0x7e662968] == f.A)
    assert(handle.activate('global_redo'))
    before = #workflow_history.undo
    assert(buttons().weapon_restore())
    assert(#workflow_history.undo == before + 1, 'Weapons Restore omitted global Undo history')
    assert(handle.activate('global_undo'))
    assert(f.textures[f.units[100].meshes[1].materials[1]][0x7e662968] ~= f.A, 'Undo Restore lost its catalog')
    assert(handle.activate('global_redo'))
    assert(f.textures[f.units[100].meshes[1].materials[1]][0x7e662968] == f.A)
    assert(handle.activate('editor_load_weapon'))
    assert(buttons().weapon_map())
    local mapping = assert(base.frontend().menu.lut_apply_dialog)
    before = #workflow_history.undo
    assert(mapping.on_map('source:1', 'weapon:1:material:1'))
    assert(#workflow_history.undo == before + 1, 'Manual weapon mapping omitted global Undo history')
    assert(handle.activate('global_undo'))
    assert(f.textures[f.units[100].meshes[1].materials[1]][0x7e662968] == f.A)
    assert(handle.activate('global_redo'))
    assert(buttons().weapon_auto_map())
    assert(workflow_factories == activation, 'Workflow service was recreated or erased during activation')
    assert(buttons().weapon_preset())
    local naming = assert(base.frontend().menu.outfit_dialog)
    assert(naming.on_save('weapon-factory-fixture'))
    local preset = m.outfit_presets.new(m, m.paths.new().presets).load('weapon-factory-fixture')
    assert(#preset.weapon == 15 and preset.weapon[1].data[0] == 0.78125)
    local preset_index
    for index, name in ipairs(mod.controls.outfit_preset.choices) do
        if name == 'weapon-factory-fixture' then preset_index = index end
    end
    assert(preset_index and handle.set('outfit_preset', preset_index))
    assert(buttons().weapon_apply_preset(), 'Registered weapon preset action failed')
    assert(buttons().weapon_export():find('Exported weapons', 1, true))
    assert(buttons().weapon_share())
    workflow_editor.on_update(ctx, 0)
    assert(#shared_entries == 15 and shared_entries[1].kind == 'weapon', 'Weapon sharing factory lost local entries')
    assert(workflow_editor.on_disable(ctx))
end
m.action_history.new = history_new

-- Exercise the actual registered startup/save/history/close wiring. Only the
-- persisted-file and completed source-cache boundaries are stubbed; the bridge,
-- discovery, native ports, runtime writes and global history remain production.
local storage = {
    reads = 0,
    saves = {},
    clears = 0,
    snapshot = {
        entries = {
            {
                kind = 'weapon',
                key = '3:1:0:0',
                weapon_slot = 1,
                weapon_resource = f.snapshots[1].weapon_resource64,
                document = f.documents[f.A],
            },
        },
    },
}
local startup_services, startup_factories, events = {}, 0, {}
m.direct_setup = {
    new = function()
        return {
            read = function()
                storage.reads = storage.reads + 1
                return {}, {}, storage.snapshot
            end,
            save = function(gear_bindings, defaults, entries)
                assert(
                    #gear_bindings == 0 and next(defaults) == nil and #entries > 0,
                    'Weapon-only history save lost its snapshot or entered garment scope'
                )
                storage.saves[#storage.saves + 1] = entries
                storage.snapshot = { entries = entries }
                events[#events + 1] = 'storage-save'
                return #entries
            end,
            clear = function()
                storage.clears = storage.clears + 1
                storage.snapshot = nil
                events[#events + 1] = 'storage-clear'
            end,
        }
    end,
}
m.weapon_provenance = {
    PENDING = 'Fixture source pending',
    new = function()
        local sources = { closed = false }
        sources.poll = function() end
        sources.close = function()
            sources.closed = true
            events[#events + 1] = 'source-close'
            return true
        end
        return sources
    end,
}
m.weapon_setup = {
    new = function(_, host)
        startup_factories = startup_factories + 1
        local service = { queued = false, starts = 0, explicit_cancels = 0 }
        startup_services[startup_factories] = service
        service.start = function(preset)
            assert(preset == storage.snapshot and #preset.entries > 0)
            assert(host.bridge().runtime() and host.bridge().discovery(), 'Startup factory lost the actual bridge')
            service.starts, service.queued = service.starts + 1, true
        end
        service.tick = function() end -- Leave cooperative startup queued for manual cancellation.
        service.cancel = function(discard)
            service.queued = false
            service.explicit_cancels = service.explicit_cancels + (discard and 1 or 0)
        end
        service.pending = function()
            return service.queued
        end
        service.capture = function()
            assert(not service.queued, 'Pending startup was persisted as an empty weapon snapshot')
            assert(not host.sources().closed, 'Weapon snapshot capture occurred after source cache close')
            events[#events + 1] = 'weapon-capture'
            local entries = {}
            for _, binding in ipairs(host.bridge().runtime().all_owned()) do
                if binding.texture and binding.current == binding.texture.object then
                    entries[#entries + 1] = {
                        kind = 'weapon',
                        key = binding.save_key,
                        weapon_slot = binding.weapon_slot,
                        weapon_resource = binding.weapon_resource,
                        document = m.weapon_mapping.copy(binding.texture),
                    }
                end
            end
            return entries
        end
        return service
    end,
}
local persistence_history
m.action_history.new = function(...)
    persistence_history = history_new(...)
    return persistence_history
end
local persistence_editor = assert(loadstring('local m=...\n' .. source, '@weapon-editor-startup-persistence'))(m)
local function activate_persistence()
    persistence_editor.on_enable(ctx)
    persistence_editor.on_update(ctx, 0)
    mod, handle = base.api.mods.epic_direct_lut, base.api.mods.epic_direct_lut.handle
    for _, candidate in ipairs(mod.pages) do
        if candidate.id == 'weapons' then
            page = candidate
        end
    end
    local service = startup_services[startup_factories]
    assert(
        service and service.starts == 1 and service.pending(),
        'Empty gear plan prevented the third-result weapon startup snapshot from loading'
    )
    assert(handle.activate('editor_load_weapon'))
    local writes = #f.writes
    assert(buttons().weapon_apply())
    assert(
        #f.writes == writes + 5 and not service.pending() and service.explicit_cancels > 0,
        'Manual registered weapon apply did not cancel queued startup before native writes'
    )
    assert(
        persistence_history.undo[#persistence_history.undo].after.remember_application == true,
        'Weapon-only application did not enter remembered state in global history'
    )
    return service
end
local startup_service = activate_persistence()
assert(buttons().weapon_editor())
assert(handle.set('cell_r', 0.4375))
persistence_editor.on_update(ctx, 0.1)
local clears = storage.clears
assert(
    handle.activate('global_undo') and #storage.saves > 0 and storage.clears == clears,
    'Weapon-only Undo cleared the saved snapshot instead of persisting applied weapon bindings'
)
local saves = #storage.saves
assert(
    handle.activate('global_redo') and #storage.saves == saves + 1 and storage.clears == clears,
    'Weapon-only Redo cleared the saved snapshot'
)
events = {}
assert(persistence_editor.on_disable(ctx))
local captured_at, closed_at
for index, event in ipairs(events) do
    if event == 'weapon-capture' then
        captured_at = index
    end
    if event == 'source-close' then
        closed_at = index
    end
end
assert(
    captured_at and closed_at and captured_at < closed_at,
    'Complete-addon close shut down source certification before capturing weapon persistence'
)
assert(startup_factories == 1 and storage.snapshot)
startup_service = activate_persistence()
assert(startup_factories == 2, 'Weapon startup factory did not survive repeated activation')
clears = storage.clears
assert(
    handle.activate('restore') and storage.clears == clears + 1 and storage.snapshot == nil,
    'Explicit global Restore retained the weapon startup pointer'
)
assert(not startup_service.pending())
assert(persistence_editor.on_disable(ctx))
m.action_history.new = history_new
print(
    'PASS registered weapon persistence: third-result startup, manual cancellation, remembered history, weapon-only Undo/Redo, global Restore and save-before-source-close across repeated activation'
)
print(
    'PASS production weapon editor integration: registered UI→runtime, raw/roughness guards, LOD writes, scope isolation, quarantine, exact source pending→ready, repeated mapping/Auto-map/save/export/sharing activation and global Undo/Redo'
)
