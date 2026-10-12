-- Production editor/bridge/discovery/runtime/session code over bounded native
-- ports. Reuse the maintained garment fixture to exercise actual registration.
local ffi = require('ffi')
local f = dofile('tests/weapon_fixture.lua')()
local file = assert(io.open('tests/direct_editor.lua', 'rb'))
local text = file:read('*a')
file:close()
local marker = assert(text:find("local f = assert(io.open('src/editor/direct_editor.lua'", 1, true))
local base = assert(loadstring(text:sub(1, marker - 1) .. [[
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
print(
    'PASS production weapon editor integration: actual registered UI→bridge→discovery/runtime/sessions, main RGB/raw guards, roughness numeric/Alpha picker, all LOD writes, explicit gear isolation and cleanup'
)
