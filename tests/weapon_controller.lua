local ffi = require('ffi')
local Controller = dofile('src/editor/weapon_controller.lua')
local function document(width, height)
    local data = ffi.new('float[?]', width * height * 4)
    for i = 0, width * height * 4 - 1 do
        data[i] = (i % 4 == 3) and 0.6 or 0.25
    end
    return { width = width, height = height, data = data }
end
local function fixture()
    local resource = '5fecab819f96a3e8'
    local body, rail, pattern = document(23, 8), document(23, 8), document(3, 1)
    local function targets(slot, material)
        local result = {}
        for mesh = 0, 4 do
            result[#result + 1] = {
                kind = 'weapon',
                weapon_slot = slot,
                weapon_resource = resource,
                save_key = '3:' .. slot .. ':' .. mesh .. ':' .. material,
                mesh_index = mesh,
                material_index = material,
            }
        end
        return result
    end
    local weapons = {
        {
            status = 'ready',
            name = 'BR-14 Adjudicator',
            resource = resource,
            main = {
                { id = 'body', label = 'Body LUT 1', document = body, verified_shape = true, targets = targets(1, 0) },
                { id = 'rail', label = 'Rail LUT 2', document = rail, verified_shape = true, targets = targets(1, 1) },
            },
            pattern = {
                {
                    id = 'pattern',
                    label = 'Pattern LUT 1',
                    document = pattern,
                    verified_shape = true,
                    targets = targets(1, 0),
                },
            },
        },
        { status = 'absent', name = 'No secondary equipped' },
        { status = 'loading', name = 'Support weapon' },
    }
    local source = { weapons = weapons, status = 'Loaded weapons', imports = { 'lut000.dds', 'lut001.dds' } }
    local hits, errors, order = {}, {}, {}
    local host = {
        snapshot = function()
            return source
        end,
        message = function(reason)
            errors[#errors + 1] = reason
        end,
    }
    for _, name in ipairs({
        'load_current',
        'load_editor',
        'open_editor',
        'edit_rgb',
        'edit_camo',
        'edit_pattern',
        'open_pattern',
        'apply',
        'restore',
        'import',
        'map_imports',
        'save_preset',
        'export',
        'share',
    }) do
        local action = name
        host[action] = function(...)
            hits[action] = { ... }
            order[#order + 1] = action
            return true
        end
    end
    local controller = Controller.new(host)
    return {
        controller = controller,
        source = source,
        host = host,
        hits = hits,
        errors = errors,
        order = order,
        body = body,
        rail = rail,
        pattern = pattern,
        targets = targets,
    }
end
local f = fixture()
local c, state = f.controller, f.controller.state()
assert(state.weapon_slot == 1 and state.family == 'main' and state.document == f.body)
assert(state.quick_ready and state.pattern_ready and #state.target.bindings == 5)
assert(
    state.target.kind == 'weapon'
        and state.target.save_key == '3:1:0:0'
        and state.target.weapon_resource == '5fecab819f96a3e8'
)
assert(c.load_current() and f.hits.load_current)
assert(c.open_editor(2, 3, state.target))
assert(f.order[#f.order - 1] == 'load_editor' and f.order[#f.order] == 'open_editor')
assert(f.hits.load_editor[1] == f.body and #f.hits.load_editor[2].bindings == 5)
assert(f.hits.open_editor[1].row == 2 and f.hits.open_editor[1].column == 3)
assert(c.edit_rgb(4, state.target) and f.hits.edit_rgb[1] == 4 and f.hits.edit_rgb[3] == f.body)
assert(c.edit_camo(8, 4, state.target) and f.hits.edit_camo[1] == 8 and f.hits.edit_camo[2] == 4)
assert(c.edit_pattern(3, state.pattern_target))
assert(f.hits.edit_pattern[4].alpha_only == true and f.hits.edit_pattern[3] == f.pattern)
assert(c.edit_pattern(1, state.pattern_target) and f.hits.edit_pattern[4].alpha_only == false)
assert(c.open_pattern(state.pattern_target) and f.hits.open_pattern[1] == f.pattern)
assert(c.apply(state.target) and f.hits.apply[2] == f.body and #f.hits.apply[1].bindings == 5)
assert(c.restore(state.target) and f.hits.restore[1].save_key == '3:1:0:0')
assert(c.import() and f.hits.import)
assert(c.map_imports(false))
assert(#f.hits.map_imports[1] == 3 and f.hits.map_imports[2].auto == false)
assert(f.hits.map_imports[1][3].family == 'pattern', 'Pattern LUT omitted from mapping targets')
assert(c.map_imports(true) and f.hits.map_imports[2].auto == true and f.hits.map_imports[2].rollover == true)
for _, action in ipairs({ 'save_preset', 'export', 'share' }) do
    assert(c[action]() and #f.hits[action][1] == 3 and f.hits[action][1][3].document == f.pattern)
end
assert(c.choose_group(2))
local rail = c.state()
assert(rail.document == f.rail and rail.pattern_target == nil, 'Rail inherited an unrelated Body Pattern LUT')
local before = #f.order
local ok, why = c.edit_rgb(1, state.target)
assert(ok == false and why:find('Weapon selection changed', 1, true) and #f.order == before)
assert(c.choose_family('pattern') and c.state().family == 'pattern')
assert(c.open_editor() and f.hits.open_pattern[1] == f.pattern)
assert(c.choose_slot(2) and c.state().weapon.status == 'absent' and c.state().target == nil)
before = #f.order
assert(c.apply() == false and #f.order == before and #f.errors > 0)
assert(c.choose_slot(3) and c.state().weapon.status == 'loading' and c.state().target == nil)
assert(c.choose_slot(1) and c.choose_family('main') and c.choose_group(1))
local shared = fixture()
local shared_pattern = shared.source.weapons[1].pattern[1]
for _, binding in ipairs(shared.targets(1, 1)) do
    shared_pattern.targets[#shared_pattern.targets + 1] = binding
end
local body_scope = shared.controller.state().pattern_target
assert(#body_scope.bindings == 5 and #body_scope.group_bindings == 10)
assert(shared.controller.choose_group(2))
local rail_scope = shared.controller.state().pattern_target
assert(#rail_scope.bindings == 5 and #rail_scope.group_bindings == 10)
assert(rail_scope.material_index == 1 and rail_scope.save_key == '3:1:0:1')
assert(shared.controller.edit_pattern(3, body_scope) == false, 'A stale sibling subset reused the shared Pattern group')
assert(shared.controller.edit_pattern(3, rail_scope) and shared.hits.edit_pattern[2].scope_id == rail_scope.scope_id)
local second_pattern = {
    id = 'pattern-second',
    label = 'Pattern LUT 2',
    document = document(3, 1),
    verified_shape = true,
    targets = shared.targets(1, 1),
}
shared.source.weapons[1].pattern[2] = second_pattern
assert(shared.controller.choose_family('pattern') and shared.controller.choose_group(2))
assert(shared.controller.open_editor(1, 3))
assert(shared.hits.open_pattern[3].row == 1 and shared.hits.open_pattern[3].column == 3)
assert(shared.controller.open_editor(2, 3) == false and shared.controller.open_editor(1, 4) == false)
assert(shared.controller.choose_family('main'))
assert(shared.controller.state().pattern_group == second_pattern, 'Remembered companion Pattern choice was lost')
for _, height in ipairs({ 1, 16, 32, 64 }) do
    local tall = fixture()
    tall.source.weapons[1].main[1].document = document(23, height)
    assert(tall.controller.state().quick_ready, 'Verified material rows were restricted to eight')
    assert(tall.controller.edit_rgb(height) and tall.hits.edit_rgb[1] == height)
    assert(tall.controller.edit_camo(height, 4) and tall.hits.edit_camo[1] == height)
    assert(tall.controller.edit_rgb(height + 1) == false, 'Quick RGB exceeded its verified table height')
end
f.source.busy = true
assert(c.edit_rgb(1) == false and c.map_imports(true) == false)
f.source.busy = false
f.source.weapons[1].main[1].verified_shape = false
assert(not c.state().quick_ready and c.edit_rgb(1) == false and c.edit_camo(1, 1) == false)
f.source.weapons[1].main[1].verified_shape = true
f.body.width = 22
assert(not c.state().quick_ready and c.edit_rgb(1) == false)
f.body.width = 23
f.body.read_only = true
assert(not c.state().quick_ready and c.edit_rgb(1) == false)
f.body.read_only = nil
assert(c.edit_rgb(9) == false and c.edit_camo(1, 5) == false and c.edit_pattern(4) == false)
assert(c.toggle_weapon(1, false))
assert(c.save_preset() == false)
assert(c.toggle_weapon(1, true))
local source_target = f.source.weapons[1].main[1].targets[1]
source_target.save_key = '0:1:0:0'
assert(c.apply() == false, 'Non-weapon destination reached Apply')
source_target.save_key = '3:1:0:0'
local second = f.source.weapons[2]
second.status, second.resource, second.main, second.pattern =
    'ready', f.source.weapons[1].resource, {
        {
            id = 'sidearm',
            label = 'Secondary Body',
            document = document(23, 8),
            verified_shape = true,
            targets = f.targets(2, 0),
        },
    }, {}
assert(c.toggle_weapon(2, true) and #c.targets() == 4)
assert(c.toggle_weapon(3, true) == false, 'Loading support weapon was selected as a mapping target')
local controls, stored = {}, {}
for _, control in ipairs(c.controls()) do
    controls[control.id] = control
end
c.attach({
    set = function(id, value)
        stored[id] = value
        if controls[id].on_change then
            controls[id].on_change(value)
        end
    end,
}, controls)
assert(controls.weapon_lut.choices[1] == 'Body LUT 1' and stored.weapon_slot == 1)
controls.weapon_slot.on_change(2)
assert(c.state().weapon_slot == 2 and controls.weapon_lut.choices[1] == 'Secondary Body')
local fail = fixture()
fail.host.load_editor = function()
    return false, 'Editor target unavailable'
end
assert(
    fail.controller.open_editor() == false and fail.hits.open_editor == nil,
    'Failed editor load still opened a stale editor'
)
local real = fixture()
local core = dofile('vendor/menu/core.lua').new({
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
})
local mounted = core.register({ id = 'weapon_workspace_test', name = 'Weapons', pages = { real.controller.page() } })
real.controller.attach(mounted, core.mods.weapon_workspace_test.controls)
assert(real.controller.choose_group(2) and mounted.get('weapon_lut') == 2)
assert(
    real.controller.choose_slot(2),
    'Absent weapon selection tried writing a disabled choice through the real provider'
)
assert(core.mods.weapon_workspace_test.controls.weapon_lut.disabled and mounted.get('weapon_lut') == 1)
real.controller.sync()
assert(real.controller.choose_slot(1) and mounted.get('weapon_lut') == 2)
print(
    'PASS: weapon controller real editor/actions, all-LOD targets, Pattern association, mapping, presets, sharing and guards'
)
return fixture
