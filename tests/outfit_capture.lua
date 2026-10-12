local ffi = require('ffi')
local Capture = dofile('src/presets/outfit_capture.lua')
local gear = dofile('src/gear/gear_catalog.lua')
local function document(width, height, value)
    local d = {
        width = width,
        height = height,
        resource = width == 3 and '2222222222222222' or '1111111111111111',
        data = ffi.new('float[?]', width * height * 4),
    }
    d.data[0], d.data[3] = value, 0.6
    return d
end
local armor, body, pattern = document(23, 8, 0.1), document(23, 8, 0.8), document(3, 1, 0.4)
local g = { save_key = '0:1:0:0', armor = true, original = 100 }
local bindings, pattern_bindings = {}, {}
for mesh = 0, 4 do
    bindings[#bindings + 1] = {
        kind = 'weapon',
        weapon_slot = 1,
        weapon_resource = '5fecab819f96a3e8',
        save_key = '3:1:' .. mesh .. ':0',
        unit = 10,
        mesh = 1000 + mesh,
        material = 2000 + mesh,
        original = 3000,
        current = 4000,
    }
    local p = {}
    for key, value in pairs(bindings[#bindings]) do
        p[key] = value
    end
    p.original, p.current = 5000, 6000
    pattern_bindings[#pattern_bindings + 1] = p
end
local groups = { { family = 'main', bindings = bindings }, { family = 'pattern', bindings = pattern_bindings } }
local proof_valid, mutate, provenance_fail = true, false, false
local host = {
    stop_identification = function()
        return true
    end,
    stop_pattern_flash = function()
        return true
    end,
    refresh = function() end,
    ensure_provenance = function() end,
    provenance_state = function()
        return 'ready'
    end,
    validate_provenance_scope = function() end,
    groups = function()
        return { { bindings = { g } } }
    end,
    current_patterns = function()
        return {}
    end,
    original = function()
        return armor
    end,
    applied_document = function() end,
    weapon_groups = function()
        return groups
    end,
    weapon_original = function(b)
        return b.original == 5000 and pattern or body
    end,
    weapon_applied_document = function() end,
    weapon_proof = function(b)
        return {
            weapon_slot = b.weapon_slot,
            weapon_resource = b.weapon_resource,
            validate = function()
                return proof_valid
            end,
        }
    end,
    capture_weapon_provenance = function(b, context)
        assert(context.kind == 'weapon' and context.weapon_resource == '5fecab819f96a3e8' and context.weapon_slot == 1)
        if provenance_fail then
            error('source cache unavailable')
        end
        if mutate then
            b.current = b.current + 1
        end
        return {
            weapon_slot = 1,
            weapon_resource = context.weapon_resource,
            key = context.key,
            marker = 'full source receipt',
        }
    end,
}
local capture = Capture.new({ gear_catalog = gear }, host)
assert(
    Capture.save_options[1].default
        and Capture.save_options[4].kind == 'weapon'
        and Capture.save_options[4].default == false
)
local old, old_label = capture.capture('armor')
assert(
    #old == 1 and old[1].kind == 'armor' and old_label == 'Armor + Cape material',
    'Historical Armor/Cape mask changed'
)
local entries, label, summary = capture.capture({ armor = true, weapon = true, weapon_slots = { [1] = true } })
assert(#entries == 11 and label == 'Armor + Weapons' and summary.count == 10 and summary.available)
for index = 2, 11 do
    local entry = entries[index]
    assert(entry.kind == 'weapon' and entry.weapon_slot == 1 and entry.weapon_resource == '5fecab819f96a3e8')
    assert(entry.original and entry.binding_provenance.marker == 'full source receipt')
    assert(entry.document == (index <= 6 and body or pattern), 'Associated Pattern sourcing changed')
end
assert(
    entries[2].key == '3:1:0:0' and entries[6].key == '3:1:4:0' and entries[7].key == 'p:3:1:0:0',
    'LOD destinations were collapsed or patterns lost their keys'
)
provenance_fail = true
local without_refs, _, absent_summary = capture.capture({ weapon = true })
assert(#without_refs == 10 and absent_summary.error:find('source cache unavailable', 1, true))
assert(without_refs[1].binding_provenance == nil, 'Optional source failure forged provenance')
provenance_fail = false
proof_valid = false
assert(not pcall(capture.capture, { weapon = true }), 'Stale weapon proof was saved')
proof_valid = true
mutate = true
assert(not pcall(capture.capture, { weapon = true }), 'Changed weapon binding was saved')
mutate = false
bindings[1].current = 4000
assert(
    not pcall(capture.capture, { weapon = true, weapon_slots = { [2] = true } }),
    'Absent requested weapon slot was silently omitted'
)
assert(not pcall(capture.capture, { weapon = true, weapon_slots = { [4] = true } }))
local key = bindings[1].save_key
bindings[1].save_key = '3:1:64:0'
assert(not pcall(capture.capture, { weapon = true }), 'Out-of-range schema4 mesh was captured')
bindings[1].save_key = key
local wrong = bindings[1].weapon_resource
bindings[1].weapon_resource = 'bad'
assert(not pcall(capture.capture, { weapon = true }))
bindings[1].weapon_resource = wrong
local valid = capture.capture({ armor = true, weapon = true })
for _, entry in ipairs(valid) do
    entry.binding_provenance = nil
end
local modules = {
    dds = dofile('src/core/dds.lua'),
    file_io = dofile('src/core/file_io.lua'),
    windows = dofile('src/platform/windows.lua'),
}
local store = dofile('src/presets/outfit_presets.lua').new(modules, 'tests/tmp/presets')
store.save('Captured Mixed Weapons', valid)
local saved = store.load('Captured Mixed Weapons')
assert(
    #saved.armor == 1
        and #saved.weapon == 10
        and saved.entries[2].weapon_resource == wrong
        and saved.entries[7].key == 'p:3:1:0:0'
)
capture.mark_saved(valid)
assert(body.saved_pixels == ffi.string(body.data, 23 * 8 * 16) and pattern.saved_pixels == ffi.string(pattern.data, 48))
print(
    'PASS: Armory weapon capture full source/proof metadata, all LODs and Patterns, R5 masks, stale guards and real schema4 mixed save'
)
