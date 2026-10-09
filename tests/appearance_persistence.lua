-- Appearance intent survives material/avatar churn; replay uses real binding
-- sessions and their immutable texture cache, without a game or native calls.
local ffi = require('ffi')
local State = dofile('src/gear/appearance_state.lua')
local Binding = dofile('src/gear/binding_session.lua')
local desired = State.new()
local retain = { records = {}, bytes = 0, cache = {} }
local creates, writes = 0, 0
local avatar, active, slots, targets
local hashes = {}
local transient = false
local function proof()
    return avatar and { armor = avatar.body .. ':' .. avatar.armor, helmet = tostring(avatar.helmet) }
end
local function current(b)
    return slots[b.material] and slots[b.material][b.slot]
end
local function present(b)
    return active[b.unit] == b.material
end
local function resource(b)
    return hashes[b.original]
end
local function session()
    return Binding.new({
        retain = retain,
        present = present,
        binding = current,
        key = function(b)
            return b.unit .. ':' .. b.material .. ':' .. b.slot
        end,
        create_texture = function()
            creates = creates + 1
            return { object = 900000 + creates }
        end,
        bind = function(b, object)
            assert(present(b), 'Stale material was written')
            slots[b.material][b.slot] = object
            writes = writes + 1
        end,
    })
end
local materials, patterns = session(), session()
local function prune()
    for _, s in ipairs({ materials, patterns }) do
        local kept = {}
        for _, b in ipairs(s.owned) do
            if present(b) and current(b) == b.current then
                kept[#kept + 1] = b
            end
        end
        s.owned = kept
    end
end
local function remember(s, pattern)
    -- The actual runtime skips Region/Pattern flash writes and cleanup replay.
    if transient then
        return 0
    end
    return desired.remember(s.owned, pattern, proof(), resource)
end
local function replay()
    if not avatar or transient then
        return 0
    end
    prune()
    local applied = 0
    for _, item in ipairs({ { false, materials }, { true, patterns } }) do
        for _, batch in ipairs(desired.batches(targets[item[1]], item[1], proof(), resource, current)) do
            applied = applied + item[2].apply(batch.document, batch.targets)
        end
    end
    return applied
end
local function scene(number, armor, helmet)
    avatar = { unit = number * 100, body = 10, armor = armor or 20, helmet = helmet or 30 }
    active, slots, targets = {}, {}, { [false] = {}, [true] = {} }
    local baseline = number * 1000
    local function make(unit, material, slot, original, kind, save_key, hash)
        active[unit] = material
        slots[material] = slots[material] or {}
        slots[material][slot] = original
        hashes[original] = hash
        return {
            unit = unit,
            mesh = material + 1,
            material = material,
            slot = slot,
            original = original,
            current = original,
            kind = kind,
            armor = kind == 'armor',
            helmet = kind == 'helmet',
            save_key = save_key,
        }
    end
    local a = make(number * 100 + 1, number * 100 + 11, 1, baseline + 1, 'armor', '0:1:0:0', 'aaaaaaaaaaaaaaaa')
    local h = make(number * 100 + 2, number * 100 + 12, 1, baseline + 2, 'helmet', '0:0:0:0', 'bbbbbbbbbbbbbbbb')
    local pa = make(a.unit, a.material, 2, baseline + 3, 'armor', '0:1:0:0', 'cccccccccccccccc')
    local ph = make(h.unit, h.material, 2, baseline + 4, 'helmet', '0:0:0:0', 'dddddddddddddddd')
    targets[false], targets[true] = { a, h }, { pa, ph }
    return a, h, pa, ph
end
local function document(width, height, seed)
    local d = { width = width, height = height, data = ffi.new('float[?]', width * height * 4) }
    for i = 0, width * height * 4 - 1 do
        d.data[i] = (i % 31 - 9) * seed
    end
    ffi.cast('uint32_t *', d.data)[3] = 0x80000000
    return d
end
local function bytes(d)
    return ffi.string(d.data, d.width * d.height * 16)
end
local armor_doc, helmet_doc = document(23, 8, 0.125), document(23, 8, 0.25)
local armor_pattern, helmet_pattern = document(3, 1, 0.5), document(3, 1, 0.75)
local expected = { bytes(armor_doc), bytes(helmet_doc), bytes(armor_pattern), bytes(helmet_pattern) }
local a, h, pa, ph = scene(1)
materials.apply(armor_doc, { a })
materials.apply(helmet_doc, { h })
patterns.apply(armor_pattern, { pa })
patterns.apply(helmet_pattern, { ph })
local count, pending = remember(materials, false)
assert(count == 2 and #pending == 0 and remember(patterns, true) == 2 and desired.count() == 4)
assert(#desired.entries() == 4)
local upload_count, applied_writes = creates, writes
assert(replay() == 0 and creates == upload_count and writes == applied_writes, 'Idle appearance was reapplied')
-- The editable CPU document can change without changing the applied intent.
armor_doc.data[0] = 99
assert(bytes(a.texture) == expected[1], 'Appearance retained a mutable editor document')
-- Temporary magenta must not become desired appearance or trigger replay.
local temp = document(23, 8, 0)
temp.data[0], temp.data[2] = 1, 1
local kept_texture = a.texture
transient = true
materials.apply(temp, { a })
assert(remember(materials, false) == 0 and replay() == 0)
materials.apply(kept_texture, { a })
transient = false
local after_flash = creates
-- Hellpod/level streaming can provide no local actor or material at all.
avatar, active, slots, targets = nil, {}, {}, { [false] = {}, [true] = {} }
for _ = 1, 20 do
    assert(replay() == 0)
end
prune()
assert(desired.count() == 4 and #materials.owned == 0 and #patterns.owned == 0)
-- New CPP objects and avatar IDs with the same gear receive all four tables.
a, h, pa, ph = scene(2)
assert(replay() == 4 and creates == after_flash, 'Same-gear transition uploaded duplicate textures or lost an override')
for i, b in ipairs({ a, h, pa, ph }) do
    assert(bytes(b.texture) == expected[i], 'Transition changed full RGBA/HDR bytes')
end
assert(
    current(a) ~= a.original and current(h) ~= h.original and current(pa) ~= pa.original and current(ph) ~= ph.original
)
applied_writes = writes
for _ = 1, 20 do
    assert(replay() == 0)
end
assert(writes == applied_writes and creates == after_flash)
-- Return to ship or joining another ship is another actor rebuild, not a new appearance.
a, h, pa, ph = scene(3)
assert(replay() == 4 and creates == after_flash)
-- The actor/material may survive while the game resets just its LUT slot.
-- Discovery must retire stale ownership and expose a fresh original binding.
local actor_unit, owned_object = avatar.unit, current(a)
slots[a.material][1] = a.original
local replacement = {}
for key, value in pairs(a) do
    replacement[key] = value
end
replacement.current, replacement.texture, replacement.document = replacement.original, nil, nil
targets[false][1], a = replacement, replacement
local writes_before_reset = writes
assert(replay() == 1 and avatar.unit == actor_unit and current(a) == owned_object)
assert(writes == writes_before_reset + 1 and creates == after_flash)
-- Changed Armor must not inherit old Armor/Pattern; the unchanged Helmet can resume independently.
a, h, pa, ph = scene(4, 21, 30)
assert(replay() == 2 and current(a) == a.original and current(pa) == pa.original)
assert(bytes(h.texture) == expected[2] and bytes(ph.texture) == expected[4])
a, h, pa, ph = scene(5, 21, 31)
assert(replay() == 0 and current(a) == a.original and current(h) == h.original)
-- A matching local slot with a different original resource is not a match.
a, h, pa, ph = scene(6)
hashes[a.original] = 'eeeeeeeeeeeeeeee'
assert(replay() == 3 and current(a) == a.original)
-- Foreign writes win even when the remembered gear, slot and resource match.
a, h, pa, ph = scene(7)
slots[a.material][1], slots[h.material][2] = 777001, 777002
assert(replay() == 2 and current(a) == 777001 and current(ph) == 777002, 'Foreign bindings were overwritten')
-- The game resetting a known original on the same still-live material is recoverable.
slots[a.material][1], slots[h.material][2] = a.original, ph.original
assert(replay() == 2 and bytes(a.texture) == expected[1] and bytes(ph.texture) == expected[4])
applied_writes = writes
assert(replay() == 0 and writes == applied_writes and creates == after_flash)
-- Restore Original must explicitly clear intent; ownership cleanup alone is not intent.
assert(materials.restore() and patterns.restore())
assert(desired.count() == 4)
assert(desired.clear() == 4 and desired.count() == 0)
a, h, pa, ph = scene(8)
assert(replay() == 0 and current(a) == a.original and current(pa) == pa.original)
assert(creates == after_flash)
-- Original metadata can arrive after an actor disappears or its gear changes.
-- Retry must use the captured proof/texture, never today's unrelated kit.
materials.apply(kept_texture, { a })
local delayed = State.new()
local remembered, waiting = delayed.remember({ a }, false, proof(), function()
    return nil
end)
assert(remembered == 0 and #waiting == 1 and delayed.count() == 0)
assert(waiting[1].proof == '10:20' and bytes(waiting[1].texture) == expected[1])
avatar.armor = 21
local ready = delayed.remember(waiting, false, { armor = waiting[1].proof }, resource)
assert(ready == 1 and delayed.count() == 1)
slots[a.material][1] = a.original
assert(#delayed.batches({ a }, false, proof(), resource, current) == 0, 'Metadata retry adopted the new gear proof')
avatar.armor = 20
local batch = delayed.batches({ a }, false, proof(), resource, current)
assert(#batch == 1 and bytes(batch[1].document) == expected[1])
assert(creates == after_flash)
print(
    'PASS appearance persistence with actual binding sessions: avatar/material transitions, downtime, exact RGBA/Pattern bytes, cached replay, gear/resource/foreign guards, flash exclusion and explicit Restore'
)
