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
local boundary_doc = { data = ffi.new('float[?]', 23 * 64 * 4), width = 23, height = 64 }
boundary_doc.data[0], boundary_doc.data[3], boundary_doc.data[63 * 23 * 4] = 8.75, -1.25, 0.375
for i = 1, module.MAX_BINDINGS do
    local slot = i - 1
    boundary_entries[i] = {
        kind = 'armor',
        key = '0:1:' .. math.floor(slot / 64) .. ':' .. slot % 64,
        document = boundary_doc,
    }
end
store.save('Binding Limit', boundary_entries)
local decodes = 0
local original_decode = dds.decode
dds.decode = function(...)
    decodes = decodes + 1
    return original_decode(...)
end
local boundary = store.load('Binding Limit')
dds.decode = original_decode
assert(#boundary.entries == module.MAX_BINDINGS, 'Preset rejected the supported binding limit')
assert(decodes == 1, 'Aliased destinations decoded the shared DDS more than once')
for i, entry in ipairs(boundary.entries) do
    assert(entry.key == boundary_entries[i].key, 'A Transmog destination was discarded')
    assert(entry.document == boundary.entries[1].document, 'An immutable aliased document was copied per binding')
end
assert(
    ffi.string(boundary.entries[1].document.data, 23 * 64 * 16) == ffi.string(boundary_doc.data, 23 * 64 * 16),
    'Shared Transmog payload changed HDR or alpha values'
)
local boundary_manifest = modules.file_io.read('tests/tmp/presets/outfit-Binding Limit.tsv', module.MAX_MANIFEST)
local unique_files = {}
for file in boundary_manifest:gmatch('\t([^\t\n]+%.dds)\t') do
    unique_files[file] = true
end
local file_count = 0
for _ in pairs(unique_files) do
    file_count = file_count + 1
end
assert(file_count == 1, 'Duplicate payloads wrote a DDS for every binding')
boundary_entries[module.MAX_BINDINGS + 1] = { kind = 'armor', key = '0:2:0:0', document = boundary_doc }
local oversized_ok, oversized_error = pcall(store.save, 'Binding Limit', boundary_entries)
assert(
    not oversized_ok and tostring(oversized_error):find('Preset has 4097 LUT bindings; the maximum is 4096.', 1, true),
    'Oversized preset reported the empty-preset error'
)
assert(
    modules.file_io.read('tests/tmp/presets/outfit-Binding Limit.tsv', module.MAX_MANIFEST) == boundary_manifest,
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
modules.file_io.write(
    'tests/tmp/presets/outfit-Legacy Keys.tsv',
    'EPIC-OUTFIT\t1\narmor\t0:1:0\toutfit-Roundtrip Outfit-armor-1.dds'
)
assert(store.load('Legacy Keys').entries[1].key == '0:1:0', 'Legacy numeric/colon target spelling was rejected')
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
-- Aliases share only exact bytes, retaining separate destinations and original
-- resource metadata even when the same resource has different custom values.
local positive = { width = 23, height = 8, data = ffi.new('float[736]') }
positive.data[0], positive.data[3] = 19.5, -2.75
local negative = { width = 23, height = 8, data = ffi.new('float[736]') }
ffi.copy(negative.data, positive.data, 2944)
ffi.cast('uint32_t *', negative.data)[1] = 0x80000000 -- Exact negative zero.
local function original_for(resource, height, bytes)
    return {
        width = 23,
        height = height,
        resource = resource,
        patch_source = bytes,
    }
end
local patch_a = '0123456789abcdef\n' .. string.rep('\0', 192) .. dds.encode(positive.data, 23, 8):sub(1, 148)
local patch_b = 'fedcba9876543210' .. patch_a:sub(17)
store.save('Exact Aliases', {
    {
        kind = 'armor',
        key = '0:1:0:0',
        document = positive,
        original = original_for('000000000000001a', 8, patch_a),
    },
    {
        kind = 'armor',
        key = '0:1:0:1',
        document = negative,
        original = original_for('000000000000001a', 8, patch_a),
    },
    {
        kind = 'cape',
        key = '0:2:0:0',
        document = positive,
        original = original_for('000000000000002b', 7, patch_a),
    },
    {
        kind = 'helmet',
        key = '0:0:0:0',
        document = positive,
        original = original_for('000000000000003c', 8, patch_b),
    },
})
local aliases = store.load('Exact Aliases').entries
assert(aliases[1].document == aliases[3].document and aliases[1].document == aliases[4].document)
assert(aliases[1].document ~= aliases[2].document, 'Different same-resource pixels were merged')
assert(ffi.cast('uint32_t *', aliases[1].document.data)[1] == 0)
assert(ffi.cast('uint32_t *', aliases[2].document.data)[1] == 0x80000000, 'Signed zero was normalized by deduplication')
assert(aliases[1].original.resource == aliases[2].original.resource)
assert(aliases[3].original.resource == '000000000000002b' and aliases[3].original.height == 7)
assert(aliases[4].original.resource == '000000000000003c' and aliases[4].original.patch_source == patch_b)
local alias_manifest = modules.file_io.read('tests/tmp/presets/outfit-Exact Aliases.tsv', module.MAX_MANIFEST)
local sidecar_names = {}
for file in alias_manifest:gmatch('\t([^\t\n]+%.patch%-source)') do
    sidecar_names[file] = true
end
local sidecar_count = 0
for _ in pairs(sidecar_names) do
    sidecar_count = sidecar_count + 1
end
assert(sidecar_count == 2, 'Sidecars were duplicated or different metadata was merged')
local writes, old_write = 0, modules.file_io.write
modules.file_io.write = function(...)
    writes = writes + 1
    return old_write(...)
end
local failures = {
    { aliases[1], aliases[1] }, -- Duplicate kind/key.
    { [1] = aliases[1], [3] = aliases[2] }, -- Sparse input.
    { aliases[1], { kind = 'armor', key = '::::', document = positive } },
    {
        aliases[1],
        {
            kind = 'cape',
            key = '0:2:0:1',
            document = positive,
            original = { resource = 'bad', patch_source = patch_a },
        },
    },
    {
        { kind = 'armor', key = string.rep('1', module.MAX_MANIFEST) .. ':1:0:0', document = positive },
    },
}
local nonfinite = { width = 23, height = 1, data = ffi.new('float[92]') }
nonfinite.data[0] = math.huge
failures[#failures + 1] = { aliases[1], { kind = 'armor', key = '0:1:0:1', document = nonfinite } }
local over_budget = {}
local canonical_size = #dds.encode(boundary_doc.data, 23, 64)
for i = 1, math.floor(module.MAX_PAYLOAD_BYTES / canonical_size) do
    local data = ffi.new('float[?]', 23 * 64 * 4)
    data[0] = i
    over_budget[i] = {
        kind = 'armor',
        key = '0:1:' .. math.floor((i - 1) / 64) .. ':' .. (i - 1) % 64,
        document = { width = 23, height = 64, data = data },
    }
end
local remaining = module.MAX_PAYLOAD_BYTES - #over_budget * canonical_size
local metadata_count = math.floor(remaining / 357) + 1
assert(metadata_count < #over_budget, 'Payload fixture has no metadata room to test')
for i = 1, metadata_count do
    over_budget[i].original = original_for(
        string.format('%016x', i),
        64,
        string.format('%016x', i) .. '\n' .. string.rep('\0', 192) .. dds.encode(boundary_doc.data, 23, 64):sub(1, 148)
    )
end
failures[#failures + 1] = over_budget
for _, entries in ipairs(failures) do
    assert(not pcall(store.save, 'Exact Aliases', entries), 'Malformed preset was written')
    assert(writes == 0, 'Validation failed after mutating payload files')
    assert(modules.file_io.read('tests/tmp/presets/outfit-Exact Aliases.tsv', module.MAX_MANIFEST) == alias_manifest)
end
modules.file_io.write = old_write
local changed = { width = 23, height = 8, data = ffi.new('float[736]') }
changed.data[0] = 0.625
local overwrite = { { kind = 'armor', key = aliases[1].key, document = changed } }
store.save('Exact Aliases', overwrite)
local updated = store.load('Exact Aliases').entries[1]
assert(updated.document.data[0] == 0.625, 'Replacing a saved preset retained old pixels')
-- Previously published manifests continue to reference their original payloads.
modules.file_io.write('tests/tmp/presets/previous-alias.tsv', alias_manifest)
local previous_aliases = module.read(modules, 'tests/tmp/presets/previous-alias.tsv', 'Previous').entries
assert(previous_aliases[1].document.data[0] == 19.5 and previous_aliases[2].original.resource == '000000000000001a')
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
    'PASS outfit presets: 4096 exact destinations, immutable DDS aliases, unique payload budget, per-entry metadata, signed zero and prevalidated saves'
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
