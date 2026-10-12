local ffi = require('ffi')
local fixture = dofile('tests/weapon_fixture.lua')
local D = dofile('src/weapons/weapon_discovery.lua')
local cases = 0
local function test(name, callback)
    callback()
    cases = cases + 1
    print('PASS ' .. name)
end
local function shape(document)
    return ffi.string(document.data, document.width * document.height * 16)
end
test('three local slots join the common cohort and absent support leaves other editors usable', function()
    local f = fixture()
    assert(#f.cohort.sessions == 6)
    assert(f.runtime.refresh(1).available and f.runtime.refresh(2).available)
    local missing = f.runtime.refresh(3)
    assert(not missing and not f.runtime.catalog(3).available and #f.runtime.groups(3) == 0)
    assert(#f.runtime.groups(1) == 2 and #f.runtime.groups(1, 'pattern') == 1 and #f.runtime.groups(2) == 2)
    assert(f.runtime.retirement_certificate())
end)
test('main and Pattern apply preserve exact float32 bytes across every LOD and stay local', function()
    local f = fixture()
    f.runtime.refresh(1)
    f.runtime.refresh(2)
    local doc, group = f.runtime.load(1, 1)
    local original = shape(doc)
    assert(#group.bindings == 5 and doc.width == 23 and doc.height == 8)
    assert(ffi.cast('uint32_t *', doc.data)[1] == 0x80000000 and doc.data[2] == 42.5 and doc.data[0] == -3.25)
    doc.data[0] = 1.25
    local count, texture = f.runtime.apply(doc, 1, 1)
    assert(count == 5 and f.allocations == 1 and #f.writes == 5 and shape(texture) == shape(doc))
    assert(shape(texture):sub(5) == original:sub(5), 'Unedited RGBA bytes changed')
    for _, b in ipairs(group.bindings) do
        assert(f.discovery.binding(b) == texture.object and b.slot == D.LUT)
    end
    local pattern, pattern_group = f.runtime.load(1, 1, 'pattern')
    pattern.data[11] = 0.875
    count, texture = f.runtime.apply(pattern, 1, 1, 'pattern')
    assert(count == 5 and #f.writes == 10 and pattern_group.bindings[1].slot == D.PATTERN)
    for _, model in pairs({ f.units[200], f.units[300] }) do
        for _, mesh in ipairs(model.meshes) do
            assert(f.textures[mesh.materials[1]][D.LUT] == f.A)
        end
    end
    assert(not f.runtime.retirement_certificate(), 'Active textures were declared detached')
    assert(f.runtime.restore(1) and f.runtime.retirement_certificate())
end)
test('partial native failure after a write rolls back only the attempted operation', function()
    local f = fixture()
    f.runtime.refresh(1)
    local doc, group = f.runtime.load(1, 1)
    doc.data[0] = 0.25
    f.fail_write = 3
    local ok, why = pcall(f.runtime.apply, doc, 1, 1)
    assert(not ok and tostring(why):find('native bind rejected after write', 1, true), why)
    for _, b in ipairs(group.bindings) do
        assert(f.discovery.binding(b) == f.A and b.current == f.A and b.previous == nil)
    end
    assert(f.runtime.restore(1) and f.runtime.retirement_certificate())
end)
test('private-material proof precedes allocation and current target proof precedes native writes', function()
    local f = fixture()
    f.runtime.refresh(1)
    local doc, group = f.runtime.load(1, 1)
    f.units[300].meshes[1].materials[1] = group.bindings[1].material
    local ok, why = pcall(f.runtime.apply, doc, 1, 1)
    assert(not ok and tostring(why):find('aliases another destination', 1, true))
    assert(f.allocations == 0 and #f.writes == 0)
    f = fixture()
    f.runtime.refresh(1)
    doc, group = f.runtime.load(1, 1)
    f.create_hook = function()
        f.snapshots[1].weapon_object = f.snapshots[1].weapon_object + 1
    end
    ok, why = pcall(f.runtime.apply, doc, 1, 1)
    assert(not ok and tostring(why):find('Weapon changed during native binding write', 1, true))
    assert(f.allocations == 1 and #f.writes == 0)
end)
test('foreign writes are never overwritten and prevent retirement certification', function()
    local f = fixture()
    f.runtime.refresh(1)
    local doc, group = f.runtime.load(1, 1)
    doc.data[0] = 0.25
    f.runtime.apply(doc, 1, 1)
    local b = group.bindings[1]
    f.textures[b.material][b.slot] = 0xdead00
    local count = #f.writes
    assert(#f.runtime.update() == 1 and not f.runtime.catalog(1).available)
    assert(not f.runtime.restore(1) and #f.writes == count + 4, 'Foreign target was restored or safe targets skipped')
    assert(f.textures[b.material][b.slot] == 0xdead00 and not f.runtime.retirement_certificate())
end)
test('drop and death invalidate stale editors without writing to a still-live dropped weapon', function()
    local f = fixture()
    f.runtime.refresh(1)
    local doc = f.runtime.load(1, 1)
    doc.data[0] = 0.5
    f.runtime.apply(doc, 1, 1)
    local count = #f.writes
    f.snapshots[1] = nil
    assert(#f.runtime.update() == 1 and not f.runtime.catalog(1).available)
    assert(not f.runtime.restore(1) and #f.writes == count and not f.runtime.retirement_certificate())
    f.units[100].alive = false
    assert(f.runtime.restore(1) and f.runtime.retirement_certificate())
end)
test('respawn recovery re-proves identity and only reapplies exact retained target resources', function()
    local f = fixture()
    f.runtime.refresh(1)
    local doc = f.runtime.load(1, 1)
    doc.data[0] = 0.625
    f.runtime.apply(doc, 1, 1)
    local count = #f.writes
    f.respawn(1, 101)
    assert(#f.runtime.update() == 1)
    local catalog, recovered = f.runtime.recovery(1, true)
    assert(catalog.available and recovered == 1 and #f.writes == count + 5)
    local loaded = f.runtime.load(1, 1)
    assert(loaded.data[0] == 0.625 and ffi.cast('uint32_t *', loaded.data)[1] == 0x80000000)
    f.respawn(1, 102, '9988776655443322')
    f.runtime.update()
    count = #f.writes
    catalog, recovered = f.runtime.recovery(1, true)
    assert(catalog.available and recovered == 0 and #f.writes == count, 'Draft crossed a different weapon resource')
end)
test('invalid dimensions, nonfinite pixels and closing cohorts cannot mutate bindings', function()
    local f = fixture()
    f.runtime.refresh(1)
    local doc = f.runtime.load(1, 1)
    doc.height = 1
    local ok = pcall(f.runtime.apply, doc, 1, 1)
    assert(not ok and #f.writes == 0)
    doc = f.runtime.load(1, 1)
    doc.data[0] = 0 / 0
    ok = pcall(f.runtime.apply, doc, 1, 1)
    assert(not ok and #f.writes == 0)
    f = fixture()
    f.runtime.refresh(1)
    doc = f.runtime.load(1, 1)
    f.cohort.closing = true
    ok = pcall(f.runtime.apply, doc, 1, 1)
    assert(not ok and #f.writes == 0 and f.allocations == 0)
end)
test('atomic main and Pattern plan failure restores the entire pre-operation state', function()
    local f = fixture()
    f.runtime.refresh(1)
    f.runtime.refresh(2)
    local main, main_group = f.runtime.load(1, 1)
    main.data[0] = 0.1875
    f.runtime.apply(main, 1, 1)
    local prior = f.runtime.capture_state()
    local prior_object = main_group.bindings[1].current
    local second = f.runtime.load(2, 1)
    local pattern, pattern_group = f.runtime.load(1, 1, 'pattern')
    second.data[0], pattern.data[0] = 0.75, 0.625
    f.fail_write = #f.writes + 2 + 3
    local ok, why = pcall(f.runtime.apply_plan, {
        { document = second, weapon_slot = 2, index = 1, family = 'material' },
        { document = pattern, weapon_slot = 1, index = 1, family = 'pattern' },
    })
    assert(not ok and tostring(why):find('native bind rejected after write', 1, true), why)
    for _, b in ipairs(main_group.bindings) do
        assert(f.discovery.binding(b) == prior_object)
    end
    for _, b in ipairs(pattern_group.bindings) do
        assert(f.discovery.binding(b) == f.P)
    end
    for _, b in ipairs(f.runtime.groups(2)[1].bindings) do
        assert(f.discovery.binding(b) == f.A)
    end
    assert(shape(f.runtime.load(1, 1)) == shape(prior.entries[1].document))
end)
test('checked accessors and exact history snapshots ignore mutable UI drafts', function()
    local f = fixture()
    f.runtime.refresh(1)
    local document, group = f.runtime.load(1, 1)
    local initial = f.runtime.capture_state()
    document.data[0] = 0.9375
    assert(#f.runtime.capture_state().entries == 0, 'UI draft changed the native history snapshot')
    f.runtime.apply(document, 1, 1)
    local applied = f.runtime.capture_state()
    assert(applied.entries[1].document.data[0] == 0.9375 and applied.entries[1].weapon_resource == '5fecab819f96a3e8')
    applied.entries[1].document.data[0] = 0.125
    assert(f.runtime.capture_state().entries[1].document.data[0] == 0.9375)
    assert(f.runtime.target(1, 1) == group and #f.runtime.sessions() == 6 and #f.runtime.all_owned() == 5)
    assert(group.index == 1 and group.bindings[1].group_index == 1)
    f.runtime.restore_state(initial)
    assert(f.runtime.load(1, 1).data[0] == -3.25)
    f.snapshots[1].weapon_resource64 = '1122334455667788'
    local ok = pcall(f.runtime.restore_state, applied)
    assert(not ok, 'History crossed a changed weapon identity')
end)
test('conflicting repeated plan assignments and source mismatches refuse before allocation', function()
    local f = fixture()
    f.runtime.refresh(1)
    local first = f.runtime.load(1, 1)
    local second = f.runtime.load(1, 1)
    second.data[0] = 0.125
    local ok, why = pcall(f.runtime.apply_plan, {
        { document = first, weapon_slot = 1, index = 1 },
        { document = second, weapon_slot = 1, index = 1 },
    })
    assert(not ok and tostring(why):find('Conflicting shared weapon material assignment', 1, true))
    assert(#f.writes == 0 and f.allocations == 0)
    ok = pcall(
        f.runtime.apply_plan,
        { { document = first, weapon_slot = 1, index = 1, source_resource = 'ffffffffffffffff' } }
    )
    assert(not ok and #f.writes == 0 and f.allocations == 0)
end)
test('disjoint LOD subsets retain different exact palettes and expose mixed assignments', function()
    local f = fixture()
    f.runtime.refresh(1)
    assert(f.runtime.supports_target_subsets == true)
    local left, group = f.runtime.load(1, 1)
    local before = f.runtime.capture_state()
    local right = f.runtime.load(1, 1)
    left.data[0], right.data[0] = 0.125, 0.875
    local results = f.runtime.apply_plan({
        { document = left, weapon_slot = 1, index = 1, targets = { group.bindings[1], group.bindings[2] } },
        {
            document = right,
            weapon_slot = 1,
            index = 1,
            targets = { group.bindings[3], group.bindings[4], group.bindings[5] },
        },
    })
    assert(#results == 2 and results[1].count == 2 and results[2].count == 3 and #f.writes == 5)
    assert(group.mixed and not group.document and not group.applied_document)
    local loaded = f.runtime.load(1, 1)
    assert(loaded.mixed and loaded.binding_documents[group.bindings[1].save_key].data[0] == 0.125)
    assert(loaded.binding_documents[group.bindings[5].save_key].data[0] == 0.875)
    local split = f.runtime.capture_state()
    assert(#split.entries == 2 and #split.entries[1].save_keys == 2 and #split.entries[2].save_keys == 3)
    f.runtime.restore_state(before)
    assert(not f.runtime.load(1, 1).mixed)
    f.runtime.restore_state(split)
    assert(f.runtime.load(1, 1).mixed)
    f.respawn(1, 101)
    f.runtime.update()
    local _, recovered = f.runtime.recovery(1, true)
    assert(recovered == 2 and f.runtime.load(1, 1).mixed, 'Recovery discarded split-LOD assignment intent')
end)
test('split-LOD plan failure rolls back every subset and preserves prior group state', function()
    local f = fixture()
    f.runtime.refresh(1)
    local left, group = f.runtime.load(1, 1)
    local right = f.runtime.load(1, 1)
    left.data[0], right.data[0] = 0.25, 0.75
    f.fail_write = 4
    local ok = pcall(f.runtime.apply_plan, {
        { document = left, weapon_slot = 1, index = 1, targets = { group.bindings[1], group.bindings[2] } },
        {
            document = right,
            weapon_slot = 1,
            index = 1,
            targets = { group.bindings[3], group.bindings[4], group.bindings[5] },
        },
    })
    assert(not ok)
    for _, b in ipairs(group.bindings) do
        assert(f.discovery.binding(b) == f.A and b.current == f.A)
    end
    assert(not f.runtime.load(1, 1).mixed and f.runtime.load(1, 1).data[0] == -3.25)
    assert(f.runtime.restore(1) and f.runtime.retirement_certificate())
end)
test('conflicting overlapping or physically aliased subsets refuse before native writes', function()
    local f = fixture()
    f.runtime.refresh(1)
    local first, group = f.runtime.load(1, 1)
    local second = f.runtime.load(1, 1)
    first.data[0], second.data[0] = 0.125, 0.875
    local ok = pcall(f.runtime.apply_plan, {
        { document = first, weapon_slot = 1, index = 1, targets = { group.bindings[1] } },
        { document = second, weapon_slot = 1, index = 1, targets = { group.bindings[1] } },
    })
    assert(not ok and f.allocations == 0 and #f.writes == 0)
    f = fixture()
    f.units[100].meshes[2].materials[1] = f.units[100].meshes[1].materials[1]
    f.runtime.refresh(1)
    first, group = f.runtime.load(1, 1)
    second = f.runtime.load(1, 1)
    first.data[0], second.data[0] = 0.125, 0.875
    ok = pcall(f.runtime.apply_plan, {
        { document = first, weapon_slot = 1, index = 1, targets = { group.bindings[1] } },
        { document = second, weapon_slot = 1, index = 1, targets = { group.bindings[2] } },
    })
    assert(not ok and f.allocations == 0 and #f.writes == 0)
end)
test('desired empty history restores actual originals and remains an empty captured frame', function()
    local f = fixture()
    f.runtime.refresh(1)
    local document, group = f.runtime.load(1, 1)
    assert(#f.runtime.capture_state().entries == 0)
    document.data[0] = 0.3125
    f.runtime.apply(document, 1, 1)
    f.runtime.restore_state({ version = 1, entries = {} })
    for _, b in ipairs(group.bindings) do
        assert(f.discovery.binding(b) == b.original and b.current == b.original)
    end
    assert(#f.runtime.capture_state().entries == 0 and f.runtime.retirement_certificate())
end)
test('desired partial history removes omitted LOD Pattern and other-slot assignments atomically', function()
    local f = fixture()
    f.runtime.refresh(1)
    f.runtime.refresh(2)
    local main, group = f.runtime.load(1, 1)
    main.data[0] = 0.375
    f.runtime.apply(main, 1, 1)
    local pattern = f.runtime.load(1, 1, 'pattern')
    pattern.data[0] = 0.5
    f.runtime.apply(pattern, 1, 1, 'pattern')
    local secondary = f.runtime.load(2, 1)
    secondary.data[0] = 0.75
    f.runtime.apply(secondary, 2, 1)
    f.runtime.restore_state({
        version = 1,
        entries = {
            {
                weapon_slot = 1,
                weapon_resource = group.weapon_resource,
                index = 1,
                family = 'material',
                source_resource = group.source_resource,
                document = main,
                save_keys = { group.bindings[1].save_key, group.bindings[2].save_key },
            },
        },
    })
    for index, b in ipairs(group.bindings) do
        assert(f.discovery.binding(b) == (index <= 2 and b.current or b.original))
        if index > 2 then
            assert(b.current == b.original)
        end
    end
    for _, b in ipairs(f.runtime.groups(1, 'pattern')[1].bindings) do
        assert(f.discovery.binding(b) == b.original)
    end
    for _, b in ipairs(f.runtime.groups(2)[1].bindings) do
        assert(f.discovery.binding(b) == b.original)
    end
    local frame = f.runtime.capture_state()
    assert(#frame.entries == 1 and #frame.entries[1].save_keys == 2)
end)
test('failed omitted-target restoration rolls the entire desired-frame operation back', function()
    local f = fixture()
    f.runtime.refresh(1)
    local main, group = f.runtime.load(1, 1)
    main.data[0] = 0.625
    f.runtime.apply(main, 1, 1)
    local before, objects = f.runtime.capture_state(), {}
    for index, b in ipairs(group.bindings) do
        objects[index] = b.current
    end
    f.fail_write = #f.writes + 3
    local ok = pcall(f.runtime.restore_state, { version = 1, entries = {} })
    assert(not ok)
    for index, b in ipairs(group.bindings) do
        assert(f.discovery.binding(b) == objects[index] and b.current == objects[index])
    end
    assert(shape(f.runtime.capture_state().entries[1].document) == shape(before.entries[1].document))
end)
print('PASS weapon runtime: ' .. cases .. ' focused contracts')
