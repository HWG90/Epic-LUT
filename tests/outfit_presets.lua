local ffi = require('ffi')
local dds = dofile('src/core/dds.lua')
local module = dofile('src/presets/outfit_presets.lua')
local modules = { file_io = dofile('src/core/file_io.lua'), dds = dds, windows = dofile('src/platform/windows.lua') }
local store = module.new(modules, 'tests/tmp/presets')
local a = ffi.new('float[736]')
local h = ffi.new('float[736]')
for i = 0, 735 do
    a[i] = i / 7
    h[i] = -i / 13
end
store.save('Roundtrip Outfit', {
    { kind = 'armor', key = '0:1:0:0', document = { data = a, width = 23, height = 8 } },
    { kind = 'helmet', key = '0:0:0:0', document = { data = h, width = 23, height = 8 } },
})
local p = store.load('Roundtrip Outfit')
assert(
    #p.armor == 1
        and #p.helmet == 1
        and ffi.string(p.armor[1].data, 2944) == ffi.string(a, 2944)
        and ffi.string(p.helmet[1].data, 2944) == ffi.string(h, 2944),
    'Paired preset lost full-float data'
)
local saved_manifest = modules.file_io.read('tests/tmp/presets/outfit-Roundtrip Outfit.tsv', 65536)
local empty_ok, empty_error = pcall(store.save, 'Roundtrip Outfit', {})
assert(not empty_ok and tostring(empty_error):find('No loaded LUTs to save', 1, true), 'Empty preset error is unclear')
assert(
    modules.file_io.read('tests/tmp/presets/outfit-Roundtrip Outfit.tsv', 65536) == saved_manifest,
    'Empty save changed the existing preset'
)
local boundary_entries = {}
for i = 1, 128 do
    boundary_entries[i] = { kind = 'armor', key = i .. ':1:0:0', document = { data = a, width = 23, height = 1 } }
end
store.save('Binding Limit', boundary_entries)
assert(#store.load('Binding Limit').entries == 128, 'Preset rejected the supported binding limit')
local boundary_manifest = modules.file_io.read('tests/tmp/presets/outfit-Binding Limit.tsv', 65536)
boundary_entries[129] = boundary_entries[128]
local oversized_ok, oversized_error = pcall(store.save, 'Binding Limit', boundary_entries)
assert(
    not oversized_ok and tostring(oversized_error):find('Preset has 129 LUT bindings; the maximum is 128.', 1, true),
    'Oversized preset reported the empty-preset error'
)
assert(
    modules.file_io.read('tests/tmp/presets/outfit-Binding Limit.tsv', 65536) == boundary_manifest,
    'Oversized save changed the existing preset'
)
store.delete('Binding Limit')
store.save('Rename Source', p.entries)
pcall(store.delete, 'Rename Destination')
store.rename('Rename Source', 'Rename Destination')
assert(
    not pcall(store.load, 'Rename Source') and #store.load('Rename Destination').entries == 2,
    'Rename lost data or retained old active name'
)
store.delete('Rename Destination')
assert(not pcall(store.load, 'Rename Destination'), 'Deleted preset remains active')
assert(not pcall(store.load, '../outside'), 'Preset path traversal accepted')
-- Legacy presets remain loadable; patch metadata is never inferred from live gear.
modules.file_io.write(
    'tests/tmp/presets/outfit-Legacy.tsv',
    'EPIC-OUTFIT\t1\narmor\t0:1:0:0\toutfit-Roundtrip Outfit-armor-1.dds'
)
local legacy = store.load('Legacy')
assert(#legacy.entries == 1 and legacy.entries[1].original == nil, 'Legacy preset changed destination metadata')
local pattern = ffi.new('float[12]')
pattern[0], pattern[3], pattern[7] = 0.125, 0.375, -1.25
local original = {
    width = 3,
    height = 1,
    resource = '000000000000002a',
    patch_source = '0123456789abcdef\n' .. string.rep('\0', 192) .. dds.encode(pattern, 3, 1):sub(1, 148),
}
store.save('Pattern Metadata', {
    {
        kind = 'helmet',
        key = 'p:0:0:0:0',
        document = { width = 3, height = 1, data = pattern },
        original = original,
    },
})
local saved_pattern = store.load('Pattern Metadata').entries[1]
assert(
    saved_pattern.original.resource == original.resource
        and saved_pattern.original.patch_source == original.patch_source
        and ffi.string(saved_pattern.document.data, 48) == ffi.string(pattern, 48),
    'Pattern metadata or channels lost'
)
local cape_original = {
    width = 23,
    height = 8,
    resource = '000000000000002a',
    patch_source = '0123456789abcdef\n' .. string.rep('\0', 192) .. dds.encode(h, 23, 8):sub(1, 148),
}
store.save('Cape Metadata', {
    { kind = 'cape', key = '0:2:1:0', document = { width = 23, height = 8, data = h }, original = cape_original },
    { kind = 'armor', key = '0:2:1:0', document = { width = 23, height = 8, data = a } },
})
local cape_preset = store.load('Cape Metadata')
assert(#cape_preset.cape == 1 and #cape_preset.armor == 1 and #cape_preset.helmet == 0)
assert(cape_preset.entries[1].kind == 'cape' and cape_preset.entries[1].key == '0:2:1:0')
assert(cape_preset.entries[1].original.resource == cape_original.resource)
assert(
    ffi.string(cape_preset.cape[1].data, 2944) == ffi.string(h, 2944),
    'Cape preset lost its kind, pixels or metadata'
)
store.delete('Cape Metadata')
modules.file_io.write(
    'tests/tmp/presets/unsafe-preset.tsv',
    'EPIC-OUTFIT\t2\nhelmet\tp:0:0:0:0\t../outside.dds\t-\t-\t-\t-'
)
assert(
    not pcall(module.read, modules, 'tests/tmp/presets/unsafe-preset.tsv', 'Unsafe'),
    'Shared preset traversal accepted'
)
modules.file_io.write(
    'tests/tmp/presets/duplicate-preset.tsv',
    'EPIC-OUTFIT\t1\narmor\t0:1:0:0\toutfit-Roundtrip Outfit-armor-1.dds\narmor\t0:1:0:0\toutfit-Roundtrip Outfit-armor-1.dds'
)
assert(
    not pcall(module.read, modules, 'tests/tmp/presets/duplicate-preset.tsv', 'Duplicate'),
    'Duplicate preset destination accepted'
)
local history = dofile('src/core/action_history.lua').new(function() end, function()
    error('foreign binding')
end)
history.record({ signature = 'before', bytes = 10 }, { signature = 'after', bytes = 10 })
assert(
    not pcall(history.undo_action) and #history.undo == 1 and #history.redo == 0 and not history.busy,
    'Failed history restore destroyed the undo frame'
)
print(
    'PASS outfit presets: named full-float Armor/Helmet round trip, path rejection, failed history restoration retained'
)

local tall = { width = 23, height = 64, data = ffi.new('float[?]', 23 * 64 * 4) }
tall.data[63 * 23 * 4], tall.data[63 * 23 * 4 + 3] = 32.5, -2.75
local tall_original = {
    width = 23,
    height = 64,
    resource = '0123456789abcdef',
    patch_source = '0123456789abcdef\n' .. string.rep('\0', 192) .. dds.encode(tall.data, 23, 64):sub(1, 148),
}
store.save('Tall Metadata', { { kind = 'armor', key = '0:1:0:0', document = tall, original = tall_original } })
local saved_tall = store.load('Tall Metadata').entries[1]
assert(saved_tall.original.height == 64 and saved_tall.original.patch_source == tall_original.patch_source)
assert(
    ffi.string(saved_tall.document.data, 23 * 64 * 16) == ffi.string(tall.data, 23 * 64 * 16),
    'Preset truncated row 64'
)
tall_original.height = 65
assert(
    not pcall(
        store.save,
        'Too Tall Metadata',
        { { kind = 'armor', key = '0:1:0:0', document = tall, original = tall_original } }
    ),
    'Preset accepted row-65 original metadata'
)
store.delete('Tall Metadata')
