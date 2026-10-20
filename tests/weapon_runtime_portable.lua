-- Real weapon runtime/session controllers; the explicit host is a fixture,
-- not proof of current-game discovery, native writes or renderer lifetimes.
local B = require('src.core.float_buffer')
local Runtime = dofile('src/weapons/weapon_runtime.lua')
local Session = dofile('src/gear/binding_session.lua')
local function fixture()
    local f = { reads = 0, writes = 0, creates = 0, generation = {}, live = {}, originals = {} }
    local receipts, rows = {}, {}
    for slot = 1, 3 do
        f.generation[slot] = 1
        receipts[slot] = { unit = slot, weapon_slot = slot, weapon_resource64 = string.rep(tostring(slot), 16), generation = 1 }
        rows[slot] = { { mesh = 1, material = slot * 10 + 1 }, { mesh = 2, material = slot * 10 + 2 } }
        for _, kind in ipairs({ 'material', 'pattern' }) do
            local object = slot * 100 + (kind == 'material' and 1 or 2)
            local width = kind == 'material' and 23 or 3
            local data = B.new(width * 4)
            for index = 0, width * 4 - 1 do data[index] = (index - 40) / 8 end
            data[1], data[2] = -1 / math.huge, 2 ^ -149
            f.originals[object] = { width = width, height = 1, data = data, original = data,
                resource = string.format('%016x', object) }
            for _, row in ipairs(rows[slot]) do
                f.live[slot .. ':' .. row.mesh .. ':' .. kind] = object
            end
        end
    end
    local discovery = {}
    function discovery.capture(slot) f.reads = f.reads + 1; return receipts[slot] end
    function discovery.materials(receipt) return rows[receipt.weapon_slot] end
    function discovery.validate(receipt)
        f.reads = f.reads + 1
        return receipt.generation == f.generation[receipt.weapon_slot]
    end
    function discovery.descriptor(receipt, row, role)
        local kind = role == Runtime.MATERIAL and 'material' or 'pattern'
        local slot = receipt.weapon_slot
        local object = slot * 100 + (kind == 'material' and 1 or 2)
        return { unit = receipt.unit, mesh = row.mesh, material = row.material, slot = role,
            weapon_slot = slot, original = object, current = object, generation = receipt.generation,
            fixture_key = slot .. ':' .. row.mesh .. ':' .. kind, save_key = kind .. ':' .. row.mesh }
    end
    function discovery.present(binding)
        f.reads = f.reads + 1
        return binding.generation == f.generation[binding.weapon_slot]
    end
    function discovery.dead(binding) return not discovery.present(binding) end
    function discovery.binding(binding) f.reads = f.reads + 1; return f.live[binding.fixture_key] end
    function discovery.prove_private() f.reads = f.reads + 1; return not f.foreign, 'Foreign owner' end
    local retain, cohort = { records = {}, cache = {}, bytes = 0 }, {}
    f.runtime = Runtime.new({ discovery = discovery, binding_session = Session, retain = retain, cohort = cohort,
        document = function(object) return assert(f.originals[object]) end,
        create_texture = function(width, height, data)
            f.creates = f.creates + 1
            return { object = 1000 + f.creates, width = width, height = height, data = data }
        end,
        bind = function(binding, object)
            f.writes = f.writes + 1
            f.live[binding.fixture_key] = object
            if f.fail_write == f.writes then error('Explicit host rejection') end
        end,
    })
    function f.respawn(slot)
        f.generation[slot] = f.generation[slot] + 1
        receipts[slot] = { unit = slot + 10, weapon_slot = slot, weapon_resource64 = string.rep(tostring(slot), 16),
            generation = f.generation[slot] }
        for _, kind in ipairs({ 'material', 'pattern' }) do
            for _, row in ipairs(rows[slot]) do f.live[slot .. ':' .. row.mesh .. ':' .. kind] = slot * 100 + (kind == 'material' and 1 or 2) end
        end
    end
    return f
end

do
    local f = fixture()
    for slot = 1, 3 do
        assert(f.runtime.refresh(slot).available)
        for _, kind in ipairs({ 'material', 'pattern' }) do
            local document = f.runtime.load(slot, 1, kind)
            local count = document.width * document.height * 4
            local pristine = B.bytes(document.data, count)
            assert(document.data ~= document.original and B.bytes(document.original, count) == pristine)
            document.data[0] = slot / 8
            local expected = B.bytes(document.data, count)
            local affected, texture = f.runtime.apply(document, slot, 1, kind)
            assert(affected == 2 and B.bytes(texture.data, count) == expected)
            assert(1 / texture.data[1] == -math.huge and texture.data[2] == 2 ^ -149)
            document.data[0] = 12
            assert(B.bytes(texture.data, count) == expected, 'Upload backing followed the editable document')
            local loaded = f.runtime.load(slot, 1, kind)
            assert(B.bytes(loaded.data, count) == expected and B.bytes(loaded.original, count) == pristine)
            local creates, writes = f.creates, f.writes
            f.runtime.apply(loaded, slot, 1, kind)
            assert(f.creates == creates and f.writes == writes, 'Unchanged explicit apply allocated or rebound')
        end
    end
    local state = f.runtime.capture_state()
    assert(#state.entries == 6)
    state.entries[1].document.data[0] = 33
    assert(f.runtime.load(1, 1).data[0] == 1 / 8, 'History shares mutable document data')
    local reads, creates, writes = f.reads, f.creates, f.writes
    for _ = 1, 1000 do f.runtime.catalog(1); f.runtime.groups(2) end
    assert(f.reads == reads and f.creates == creates and f.writes == writes, 'Cached access touched the host')
    f.respawn(2)
    local catalog, recovered = f.runtime.recovery(2, true)
    assert(catalog.available and recovered == 2)
    assert(f.runtime.load(2, 1).data[0] == 2 / 8 and f.runtime.load(2, 1, 'pattern').data[0] == 2 / 8)
    assert(f.runtime.restore() and f.runtime.retirement_certificate())
end

do
    local f = fixture()
    f.runtime.refresh(1)
    local document, group = f.runtime.load(1, 1)
    local creates, writes = f.creates, f.writes
    local forged = { width = 23, height = 1, data = setmetatable({}, getmetatable(document.data)) }
    assert(not pcall(f.runtime.apply, forged, 1, 1) and f.creates == creates and f.writes == writes)
    forged.data, forged.original = document.data, {}
    assert(not pcall(f.runtime.apply, forged, 1, 1) and f.creates == creates and f.writes == writes)
    document.data[0] = 0.5
    f.foreign = true
    assert(not pcall(f.runtime.apply, document, 1, 1) and f.creates == creates and f.writes == writes)
    f.foreign, f.fail_write = false, 2
    assert(not pcall(f.runtime.apply, document, 1, 1))
    for _, binding in ipairs(group.bindings) do
        assert(f.live[binding.fixture_key] == binding.original and binding.current == binding.original)
    end
    assert(f.runtime.retirement_certificate(), 'Failed application retained live bindings')
end
print('PASS portable weapon runtime: three slots, exact immutable bytes, ownership, rollback, history and explicit respawn recovery')
