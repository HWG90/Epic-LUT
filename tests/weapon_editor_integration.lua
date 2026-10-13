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
m.weapon_runtime = dofile('src/weapons/weapon_runtime.lua')
m.weapon_discovery = dofile('src/weapons/weapon_discovery.lua')
m.weapon_controller = dofile('src/editor/weapon_controller.lua')
m.weapon_view = dofile('src/editor/weapon_view.lua')
m.weapon_bridge = dofile('src/editor/weapon_bridge.lua')
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
local loaded = base.info().editor
assert(loaded.kind == 'weapon' and loaded.family == 'material' and loaded.weapon_slot == 1 and loaded.width == 23)
assert(
    mod.controls.cell_a.disabled and not mod.controls.cell_r.disabled,
    'Main raw Alpha lock or primary RGB permission changed'
)
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
end
weapon_footer()
weapon_footer() -- Repeated layout must retain its weapon context.
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
pending_editor.on_enable(ctx)
local pending_operations, set_status = m.weapon_fixture_access()
pending_operations.weapon_sources_service = pending_sources.sources
m.weapon_provenance = dofile('src/weapons/weapon_provenance.lua')
set_status(pending_status)
local notes = #logs
pending_editor.on_update(ctx, 0)
assert(
    #logs > notes and logs[notes + 1] == 'Epic LUT: Exact weapon binding sources ready',
    'A prefixed pending exception prevented the production source-ready notification'
)
assert(pending_editor.on_disable(ctx))
m.weapon_fixture_access = nil
print(
    'PASS production weapon editor integration: actual registered UI→bridge→discovery/runtime/sessions, main RGB/raw guards, roughness numeric/Alpha picker, all LOD writes, explicit gear isolation, independent garment cleanup, foreign/exception texture quarantine and exact provenance pending→ready notification'
)
