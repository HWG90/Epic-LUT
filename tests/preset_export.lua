local ffi = require('ffi')
local E = dofile('src/presets/preset_export.lua')
local D = dofile('src/core/dds.lua')
local O = dofile('src/presets/outfit_presets.lua')
local F = dofile('src/core/file_io.lua')
local L = dofile('src/presets/lut_files.lua')
local P = dofile('src/presets/patch_export.lua')
local Pair = dofile('src/presets/export_pairing.lua')
local document = { width = 23, height = 8, data = ffi.new('float[736]') }
local pattern = { width = 3, height = 1, data = ffi.new('float[12]') }
document.data[0], document.data[19], pattern.data[7] = 0.125, -2.5, 0.375
local function original(doc, resource)
    return {
        width = doc.width,
        height = doc.height,
        resource = resource,
        patch_source = '0123456789abcdef\n' .. string.rep('\0', 192) .. D.encode(doc.data, doc.width, doc.height)
            :sub(1, 148),
    }
end
local preset = {
    name = 'Saved Set',
    entries = {
        { kind = 'armor', key = '0:1:0:0', document = document, original = original(document, 'fedcba9876543210') },
        { kind = 'helmet', key = 'p:0:0:0:0', document = pattern, original = original(pattern, '000000000000002a') },
    },
}
local files = E.bundle({ dds = D }, preset)
assert(#files == 5 and files[5][1] == 'preset.tsv', 'Shared ZIP does not contain metadata/manifest')
for _, file in ipairs(files) do
    F.write('tests/tmp/presets/' .. file[1], file[2])
end
local modules = { file_io = F, dds = D, windows = {
    files = function()
        return {}
    end,
} }
local loaded = O.new(modules, 'tests/tmp/presets').import('tests/tmp/presets/preset.tsv', 'Shared Import')
assert(
    #loaded.entries == 2
        and loaded.entries[1].original.resource == 'fedcba9876543210'
        and ffi.string(loaded.entries[1].document.data, 2944) == ffi.string(document.data, 2944)
        and ffi.string(loaded.entries[2].document.data, 48) == ffi.string(pattern.data, 48),
    'Shareable preset round trip lost bytes or IDs'
)
local zip = P.zip_entries(files)
assert(zip:sub(1, 4) == 'PK\3\4' and zip:sub(-22, -19) == 'PK\5\6', 'Shared ZIP is invalid')
local Binding = dofile('src/presets/binding_provenance.lua')
local proof_entry = {
    kind = loaded.entries[1].kind,
    key = loaded.entries[1].key,
    document = loaded.entries[1].document,
    original = loaded.entries[1].original,
}
proof_entry.binding_provenance = {
    version = 1,
    kind = proof_entry.kind,
    key = proof_entry.key,
    texture_slot = Binding.LUT,
    original_texture = proof_entry.original.resource,
    section = 0xabc12345,
    kit_override = false,
    index_stamp = string.rep('a', 64),
    kit = { id = 21, body = 0, archive = '0123456789abcdef' },
    unit = {
        resource = 'abcdef0123456789',
        archive = '0123456789abcdef',
        main_sha256 = string.rep('1', 64),
        main = 'FAKE_PRIVATE_GAME_BYTES',
    },
    material = {
        resource = '1234567890abcdef',
        archive = '0123456789abcdef',
        main_sha256 = string.rep('2', 64),
        main = 'FAKE_PRIVATE_GAME_BYTES',
    },
    verified = true,
}
local certified_files = E.bundle(
    { dds = D, binding_provenance = Binding },
    { entries = { proof_entry, loaded.entries[2] } }
)
assert(
    #certified_files == 6 and certified_files[#certified_files][2]:match('^EPIC%-OUTFIT\t3\n'),
    'Shareable ZIP lost the v3 assignment references'
)
local assignment
for _, file in ipairs(certified_files) do
    assert(not file[2]:find('FAKE_PRIVATE_GAME_BYTES', 1, true), 'Shareable preset leaked hydrated game source bytes')
    if file[1]:match('%.assignment$') then
        assignment = file[2]
    end
    F.write('tests/tmp/presets/' .. file[1], file[2])
end
assert(assignment and not assignment:find('verified', 1, true), 'Shareable assignment sidecar persisted trusted status')
local certified_roundtrip = O.read(
    { dds = D, file_io = F, binding_provenance = Binding },
    'tests/tmp/presets/preset.tsv',
    'Certified Shared Import'
)
local refs = certified_roundtrip.entries[1].binding_provenance
assert(
    refs
        and refs.unit.resource == proof_entry.binding_provenance.unit.resource
        and refs.material.main_sha256 == proof_entry.binding_provenance.material.main_sha256
        and not refs.verified
        and not refs.unit.main
        and not certified_roundtrip.entries[2].binding_provenance,
    'Shareable v3 round trip lost references or trusted unhydrated game bytes'
)
assert(
    not pcall(E.bundle, { dds = D }, { entries = { proof_entry } }),
    'v3 metadata silently exported without its validator'
)
assert(not pcall(E.bundle, { dds = D, binding_provenance = Binding }, {
    entries = {
        {
            kind = proof_entry.kind,
            key = proof_entry.key,
            document = document,
            binding_provenance = proof_entry.binding_provenance,
        },
    },
}), 'Assignment references exported without certified original texture metadata')
-- Transmog can bind the same few LUTs to thousands of distinct material targets.
local many = { entries = {} }
for i = 1, E.MAX_BINDINGS do
    many.entries[i] = {
        kind = i % 2 == 0 and 'helmet' or 'armor',
        key = '0:0:' .. math.floor((i - 1) / 64) .. ':' .. (i - 1) % 64,
        document = document,
        original = original(document, string.format('%016x', i)),
    }
end
local compact = E.bundle({ dds = D }, many)
assert(#compact == 3, 'Exact aliases generated duplicate DDS or sidecar files')
assert(compact[1][2] == D.encode(document.data, document.width, document.height))
for _, file in ipairs(compact) do
    F.write('tests/tmp/presets/' .. file[1], file[2])
end
local many_loaded = O.read(modules, 'tests/tmp/presets/preset.tsv', 'Transmog Roundtrip')
assert(#many_loaded.entries == E.MAX_BINDINGS, 'Shareable preset discarded attached destinations')
for i, entry in ipairs(many_loaded.entries) do
    assert(entry.kind == many.entries[i].kind and entry.key == many.entries[i].key)
    assert(entry.original.resource == string.format('%016x', i), 'Alias substituted another destination ID')
    assert(ffi.string(entry.document.data, 2944) == ffi.string(document.data, 2944))
end
-- DDS and sidecar identities are independent of each destination's metadata.
local other_source = original(document, '1111111111111111')
other_source.patch_source = '1111111111111111' .. other_source.patch_source:sub(17)
other_source.height = 2
local other_pixels = { width = 23, height = 8, data = ffi.new('float[736]') }
ffi.copy(other_pixels.data, document.data, 2944)
other_pixels.data[0] = 0.875
local aliases = {
    entries = {
        many.entries[1],
        { kind = 'helmet', key = '0:2:0:0', document = document, original = other_source },
        {
            kind = 'cape',
            key = '0:3:0:0',
            document = other_pixels,
            original = original(document, many.entries[1].original.resource),
        },
    },
}
local alias_files = E.bundle({ dds = D }, aliases)
assert(#alias_files == 5, 'DDS or exact metadata deduplication discarded a distinct value')
for _, file in ipairs(alias_files) do
    F.write('tests/tmp/presets/' .. file[1], file[2])
end
local alias_roundtrip = O.read(modules, 'tests/tmp/presets/preset.tsv', 'Independent Aliases')
assert(alias_roundtrip.entries[2].original.height == 2)
assert(alias_roundtrip.entries[2].original.patch_source == other_source.patch_source)
assert(alias_roundtrip.entries[3].original.resource == alias_roundtrip.entries[1].original.resource)
assert(alias_roundtrip.entries[3].document.data[0] == 0.875, 'Shared hash discarded different DDS bytes')
local over_limit = { entries = {} }
for i = 1, E.MAX_BINDINGS + 1 do
    over_limit.entries[i] = many.entries[1]
end
assert(not pcall(E.bundle, { dds = D }, over_limit), 'Oversized binding collection exported')
local budget_source = many.entries[1].original.patch_source
local full_payload = string.rep('a', E.MAX_PAYLOAD_BYTES - #budget_source)
local boundary_codec = { dds = {
    encode = function()
        return full_payload
    end,
} }
assert(
    #E.bundle(boundary_codec, { entries = { many.entries[1], many.entries[2] } }) == 3,
    'Exact payload aliases consumed the serialized payload budget more than once'
)
local different_source = original(document, '2222222222222222')
different_source.patch_source = '2222222222222222' .. budget_source:sub(17)
local one_sidecar_too_many = {
    entries = {
        many.entries[1],
        { kind = 'armor', key = '0:1:0:0', document = document, original = different_source },
    },
}
assert(not pcall(E.bundle, boundary_codec, one_sidecar_too_many), 'Metadata bytes escaped payload budget')
local over_bytes = { dds = {
    encode = function()
        return full_payload .. 'b'
    end,
} }
assert(not pcall(E.bundle, over_bytes, { entries = { many.entries[1] } }), 'Oversized serialized payload exported')
local over_manifest = {
    entries = { { kind = 'armor', key = string.rep('1', E.MAX_MANIFEST_BYTES), document = document } },
}
assert(not pcall(E.bundle, { dds = D }, over_manifest), 'Oversized manifest exported')
local calls = {}
local bulk_entries, bulk_naming
local m = {
    dds = D,
    file_io = F,
    lut_files = L,
    export_pairing = Pair,
    bulk_dds_export = {
        new = function()
            return {
                save = function(name, entries, naming)
                    bulk_entries, bulk_naming = entries, naming
                    return 'tests/tmp/bulk-preset', #entries
                end,
            }
        end,
    },
    patch_export = {
        zip_entries = P.zip_entries,
        new = function()
            return {
                save = function(name, doc, orig)
                    calls[#calls + 1] = { name, doc, orig }
                    return 'output', 'resource', 'output.zip'
                end,
            }
        end,
    },
}
local export = E.new(m, {
    exports = 'tests/tmp/presets',
    directory_exists = function(path)
        local file = io.open(path, 'rb')
        if file then
            file:close()
            return true
        end
        return false
    end,
})
local actual_codec, actual_io, failed_writes = m.dds, m.file_io, 0
m.dds = over_bytes.dds
m.file_io = {
    write = function()
        failed_writes = failed_writes + 1
    end,
}
local oversized_ok, oversized_why = pcall(export.save, 'Oversized Payload', { entries = { many.entries[1] } }, 1, 1)
m.dds, m.file_io = actual_codec, actual_io
assert(
    not oversized_ok and tostring(oversized_why):find('payload budget', 1, true) and failed_writes == 0,
    'Payload budget failure wrote a partial shareable export'
)
export.save('Saved Set', loaded, 2, 2)
assert(
    calls[1][2] == loaded.entries[2].document and calls[1][3].resource == '000000000000002a',
    'Selected patch used wrong or worn LUT'
)
export.save('Saved Set', loaded, 3, 1)
assert(calls[2][2] == loaded.entries and calls[2][3] == nil, 'Entire preset patch omitted saved entries')
local paired_pattern = {
    kind = 'armor',
    key = 'p:' .. loaded.entries[1].key,
    document = loaded.entries[2].document,
    original = loaded.entries[2].original,
}
local wrong_gear = {
    kind = 'helmet',
    key = paired_pattern.key,
    document = pattern,
    original = original(pattern, '000000000000002b'),
}
local wrong_destination = {
    kind = 'armor',
    key = 'p:0:1:0:1',
    document = pattern,
    original = original(pattern, '000000000000002c'),
}
local paired_preset = { entries = { loaded.entries[1], paired_pattern, wrong_gear, wrong_destination } }
export.save('Selected Pair', paired_preset, 2, 1)
local patch_pair = calls[#calls]
assert(
    #patch_pair[2] == 2
        and patch_pair[2][1] == loaded.entries[1]
        and patch_pair[2][2] == paired_pattern
        and patch_pair[3] == nil,
    'Selected saved patch did not pair the exact material and Pattern destination'
)
assert(
    ffi.string(patch_pair[2][2].document.data, 48) == ffi.string(pattern.data, 48),
    'Selected saved patch changed Pattern float values'
)
local pair_folder, pair_description, pair_share = export.save('Selected Pair', paired_preset, 4, 1)
assert(
    pair_folder == 'tests/tmp/bulk-preset' and pair_share == pair_folder and pair_description == '2 saved LUT DDS files'
)
assert(
    #bulk_entries == 2
        and bulk_entries[1].document == loaded.entries[1].document
        and bulk_entries[2].document == paired_pattern.document
        and bulk_entries[1].kind == 'armor'
        and bulk_entries[2].kind == 'armor'
        and bulk_entries[1].ordinal == 1
        and bulk_entries[2].ordinal == 1
        and bulk_naming == 1,
    'Selected DDS pair mixed targets or did not use distinct material/Pattern naming'
)
export.save('Selected Pair', paired_preset, 4, 1, 5)
assert(bulk_naming == 5, 'Selected DDS pair ignored the requested naming format')
export.save('Selected Pattern', paired_preset, 2, 2)
assert(
    calls[#calls][2] == paired_pattern.document and calls[#calls][3] == paired_pattern.original,
    'Explicit selected Pattern patch exported another material'
)
local _, _, selected_pattern_raw = export.save('Selected Pattern', paired_preset, 4, 2)
local selected_pixels, selected_width, selected_height = D.decode(F.read(selected_pattern_raw, D.MAX_BYTES))
assert(
    selected_width == 3 and selected_height == 1 and ffi.string(selected_pixels, 48) == ffi.string(pattern.data, 48),
    'Explicit selected Pattern DDS did not remain standalone'
)
os.remove(selected_pattern_raw)
local no_metadata = {
    entries = {
        loaded.entries[1],
        { kind = paired_pattern.kind, key = paired_pattern.key, document = paired_pattern.document },
    },
}
local before_patch_calls = #calls
local metadata_ok, metadata_why = pcall(export.save, 'Missing Pattern Metadata', no_metadata, 2, 1)
assert(
    not metadata_ok and tostring(metadata_why):find('resave', 1, true) and #calls == before_patch_calls,
    'Incomplete paired patch metadata reached the writer'
)
-- Exercise the real transactional exporters: a malformed second member must
-- fail before a directory or file is created for the valid first material.
local created_outputs, written_outputs = 0, 0
local checked_export = E.new({
    dds = D,
    file_io = {
        write = function()
            written_outputs = written_outputs + 1
        end,
    },
    lut_files = L,
    export_pairing = Pair,
    bulk_dds_export = dofile('src/presets/bulk_dds_export.lua'),
    patch_export = P,
}, {
    exports = 'tests/tmp/presets',
    directory_exists = function()
        return false
    end,
    mkdir_new = function()
        created_outputs = created_outputs + 1
        error('Invalid export reached directory creation')
    end,
    rmdir = function() end,
})
local malformed_original = original(pattern, paired_pattern.original.resource)
malformed_original.patch_source = 'invalid'
local malformed_pair = {
    entries = {
        loaded.entries[1],
        {
            kind = paired_pattern.kind,
            key = paired_pattern.key,
            document = pattern,
            original = malformed_original,
        },
    },
}
local malformed_ok, malformed_why = pcall(checked_export.save, 'Malformed Pair', malformed_pair, 2, 1)
assert(not malformed_ok and tostring(malformed_why):find('Invalid original patch metadata', 1, true))
malformed_original.resource = 'invalid'
local bad_dds_ok, bad_dds_why = pcall(checked_export.save, 'Malformed Pair', malformed_pair, 4, 1)
assert(not bad_dds_ok and tostring(bad_dds_why):find('Invalid LUT resource ID', 1, true))
assert(created_outputs == 0 and written_outputs == 0, 'Invalid paired export left partial output')
local _, _, raw = export.save('Saved Set', loaded, 4, 1)
assert(raw:match('Saved Set%-%d%d%d%d%-%d%d%-%d%d_%d%d%-%d%d%-%d%d%.dds$'), 'Raw DDS lost timestamp naming')
local decoded = D.decode(F.read(raw, D.MAX_BYTES))
assert(ffi.string(decoded, 2944) == ffi.string(document.data, 2944), 'Raw DDS exported different pixels')
local output = export.save('Shared Set', loaded, 1, 1)
local output2 = export.save('Shared Set', loaded, 1, 1)
assert(output ~= output2 and F.read(output, 65536) == F.read(output2, 65536), 'Preset ZIP overwrote prior export')
local cape = { width = 23, height = 8, data = ffi.new('float[736]') }
ffi.copy(cape.data, document.data, 2944)
cape.data[0] = 0.875
local cape_entry = { kind = 'cape', key = '0:2:1:0', document = cape, original = original(cape, 'fedcba9876543210') }
local with_cape = { entries = { loaded.entries[1], loaded.entries[2], cape_entry } }
-- Saving a source palette on a shorter native Cape preserves both independent
-- shapes: the manifest certifies the original five rows, while the saved DDS
-- and replacement GPU record retain all eight applied rows without remapping.
local five_rows = { width = 23, height = 5, data = ffi.new('float[460]') }
local resized_cape = {
    kind = 'cape',
    key = '0:1:1:0',
    document = cape,
    original = original(five_rows, '13e2e070c0dcbd53'),
}
local resized_preset = { entries = { loaded.entries[1], loaded.entries[2], resized_cape } }
local resized_files = E.bundle(m, resized_preset)
for _, file in ipairs(resized_files) do
    F.write('tests/tmp/presets/' .. file[1], file[2])
end
local resized_roundtrip = O.read(modules, 'tests/tmp/presets/preset.tsv', 'Resized Cape Roundtrip')
assert(
    resized_roundtrip.entries[3].document.height == 8 and resized_roundtrip.entries[3].original.height == 5,
    'Preset bundle/read forced applied dimensions to match original metadata'
)
local resized_patch = P.encode_set(D, resized_roundtrip.entries)
assert(resized_patch.count == 3, 'Mixed material, Pattern and resized Cape patch omitted a texture')
local function uint(bytes, offset)
    local a, b, c, d = bytes:byte(offset + 1, offset + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end
local by_resource = {}
for _, entry in ipairs(resized_roundtrip.entries) do
    by_resource[entry.original.resource] = entry
end
for index = 1, resized_patch.count do
    local at = 104 + (index - 1) * 80
    local resource = ''
    for byte = 8, 1, -1 do
        resource = resource .. string.format('%02x', resized_patch.main:byte(at + byte))
    end
    local body, gpu, bytes =
        uint(resized_patch.main, at + 16), uint(resized_patch.main, at + 32), uint(resized_patch.main, at + 64)
    local source = assert(by_resource[resource]).document
    local pixels, width, height =
        D.decode(resized_patch.main:sub(body + 193, body + 340) .. resized_patch.gpu:sub(gpu + 1, gpu + bytes))
    assert(
        width == source.width
            and height == source.height
            and bytes == width * height * 16
            and ffi.string(pixels, bytes) == ffi.string(source.data, bytes),
        'Mixed saved-preset patch changed source float bytes or serialized dimensions'
    )
end
export.save('Resized Cape Pair', resized_roundtrip, 2, 3)
assert(
    calls[#calls][2] == resized_roundtrip.entries[3].document and calls[#calls][3].height == 5,
    'Selected resized Cape export discarded its exact destination metadata'
)
assert(
    #resized_preset.entries == 3 and cape.height == 8 and resized_cape.original.height == 5,
    'Resized export rewrote the stored preset or original snapshot'
)
assert(E.lut_choices(with_cape)[3]:find('Cape LUT 1', 1, true), 'Cape export choice mislabeled')
local cape_bundle = E.bundle(m, with_cape)
for _, file in ipairs(cape_bundle) do
    F.write('tests/tmp/presets/' .. file[1], file[2])
end
local cape_roundtrip = O.read(modules, 'tests/tmp/presets/preset.tsv', 'Cape Roundtrip')
assert(#cape_roundtrip.cape == 1 and #cape_roundtrip.armor == 1 and #cape_roundtrip.entries == 3)
assert(cape_roundtrip.entries[3].original.resource == cape_roundtrip.entries[1].original.resource)
assert(ffi.string(cape_roundtrip.cape[1].data, 2944) == ffi.string(cape.data, 2944), 'Shared-ID Cape bytes lost')
local include, include_patterns = false, true
local filtered = E.new(m, {
    exports = 'tests/tmp/presets',
    directory_exists = function(path)
        local f = io.open(path, 'rb')
        if f then
            f:close()
            return true
        end
        return false
    end,
}, {
    include_capes = function()
        return include
    end,
    include_patterns = function()
        return include_patterns
    end,
})
filtered.save('Without Cape', with_cape, 3, 1)
assert(#calls[#calls][2] == 2 and calls[#calls][2][1] == loaded.entries[1], 'Full patch exclusion removed wrong LUT')
filtered.save('Without Cape', with_cape, 5, 1, 1)
assert(#bulk_entries == 2 and #with_cape.entries == 3, 'Collection export mutated the saved Cape preset')
local filtered_bundle = E.bundle(m, with_cape, false)
assert(#filtered_bundle == 5 and not filtered_bundle[#filtered_bundle][2]:find('\ncape\t', 1, true))
local filtered_zip, filtered_label = filtered.save('Without Cape', with_cape, 1, 1)
assert(filtered_label == '2 saved LUTs' and not F.read(filtered_zip, 65536):find('\ncape\t', 1, true))
filtered.save('Selected Cape', with_cape, 2, 3)
assert(calls[#calls][2] == cape and calls[#calls][3].resource == 'fedcba9876543210', 'Selected Cape patch was filtered')
local _, _, cape_raw = filtered.save('Selected Cape', with_cape, 4, 3)
assert(
    ffi.string(D.decode(F.read(cape_raw, D.MAX_BYTES)), 2944) == ffi.string(cape.data, 2944),
    'Selected Cape DDS was filtered'
)
local cape_pattern = {
    kind = 'cape',
    key = 'p:' .. cape_entry.key,
    document = pattern,
    original = original(pattern, '000000000000002d'),
}
local paired_cape = { entries = { cape_entry, cape_pattern, loaded.entries[1], paired_pattern } }
filtered.save('Paired Cape Excluded', paired_cape, 3, 1)
assert(
    #calls[#calls][2] == 2 and calls[#calls][2][1].kind == 'armor' and calls[#calls][2][2].kind == 'armor',
    'Full export included excluded Cape or Cape Pattern'
)
filtered.save('Selected Cape Pair', paired_cape, 2, 1)
assert(
    #calls[#calls][2] == 2 and calls[#calls][2][1] == cape_entry and calls[#calls][2][2] == cape_pattern,
    'Explicit selected Cape patch did not keep its Pattern when Cape collection exports are excluded'
)
filtered.save('Selected Cape Pair', paired_cape, 4, 1)
assert(#bulk_entries == 2 and bulk_entries[1].kind == 'cape' and bulk_entries[2].kind == 'cape')
include_patterns = false
filtered.save('Material Only', paired_cape, 2, 3)
assert(
    calls[#calls][2] == loaded.entries[1].document and calls[#calls][3] == loaded.entries[1].original,
    'Disabled Pattern inclusion still paired a selected material patch'
)
local material_only, _, material_only_share = filtered.save('Material Only', paired_cape, 4, 3)
assert(
    material_only == material_only_share and material_only:match('%.dds$'),
    'Material-only selected DDS became a bundle'
)
assert(ffi.string(D.decode(F.read(material_only, D.MAX_BYTES)), 2944) == ffi.string(document.data, 2944))
filtered.save('No Patterns Or Capes', paired_cape, 3, 3)
assert(
    #calls[#calls][2] == 1 and calls[#calls][2][1] == loaded.entries[1],
    'Full patch Pattern/Cape exclusions did not combine independently'
)
filtered.save('No Patterns Or Capes', paired_cape, 5, 3)
assert(#bulk_entries == 1 and bulk_entries[1].document == loaded.entries[1].document)
local material_zip, material_label = filtered.save('No Patterns Or Capes', paired_cape, 1, 3)
local material_zip_bytes = F.read(material_zip, 65536)
assert(
    material_label == '1 saved LUTs'
        and not material_zip_bytes:find('\ncape\t', 1, true)
        and not material_zip_bytes:find('\tp:', 1, true),
    'Shareable preset included an excluded Pattern or Cape'
)
local no_patterns_bundle = E.bundle(m, paired_preset, nil, false)
assert(
    #no_patterns_bundle == 3 and not no_patterns_bundle[#no_patterns_bundle][2]:find('\tp:', 1, true),
    'Direct shareable bundle ignored its Pattern exclusion argument'
)
local fixed_excluded = E.new(m, { exports = 'tests/tmp/presets' }, { include_patterns = false })
fixed_excluded.save('Boolean Pattern Option', paired_cape, 2, 3)
assert(calls[#calls][2] == loaded.entries[1].document, 'Boolean Pattern exclusion still paired selected material')
fixed_excluded.save('Boolean Pattern Option', paired_cape, 5, 3)
assert(
    #bulk_entries == 2 and bulk_entries[1].kind == 'cape' and bulk_entries[2].kind == 'armor',
    'Pattern exclusion unexpectedly disabled Cape exports'
)
filtered.save('Explicit Cape Pattern', paired_cape, 2, 2)
assert(
    calls[#calls][2] == cape_pattern.document and calls[#calls][3] == cape_pattern.original,
    'Explicit selected Pattern patch was blocked by export inclusion settings'
)
local explicit_pattern, _, explicit_pattern_share = filtered.save('Explicit Cape Pattern', paired_cape, 4, 2)
local explicit_pixels, explicit_width, explicit_height = D.decode(F.read(explicit_pattern, D.MAX_BYTES))
assert(
    explicit_pattern == explicit_pattern_share
        and explicit_width == 3
        and explicit_height == 1
        and ffi.string(explicit_pixels, 48) == ffi.string(pattern.data, 48),
    'Explicit selected Pattern DDS was filtered or bundled'
)
local pattern_only = { entries = { paired_pattern } }
for _, format in ipairs({ 1, 3, 5 }) do
    local before_calls, before_bulk = #calls, bulk_entries
    local empty_ok, empty_why = pcall(filtered.save, 'Excluded Pattern Only', pattern_only, format, 1)
    assert(
        not empty_ok
            and tostring(empty_why):find('No LUTs remain', 1, true)
            and tostring(empty_why):find('Include Patterns', 1, true)
            and #calls == before_calls
            and bulk_entries == before_bulk,
        'Pattern-only collection exclusion did not fail clearly before export'
    )
end
include_patterns = true
filtered.save('Patterns Restored', paired_cape, 2, 3)
assert(
    #calls[#calls][2] == 2 and calls[#calls][2][2] == paired_pattern,
    'Live Pattern option change did not restore pairing'
)
filtered.save('Patterns Restored', paired_cape, 3, 3)
assert(#calls[#calls][2] == 2 and calls[#calls][2][1].kind == 'armor' and calls[#calls][2][2].kind == 'armor')
assert(
    #paired_cape.entries == 4 and paired_cape.entries[2] == cape_pattern and paired_cape.entries[4] == paired_pattern,
    'Export inclusion settings removed saved library entries'
)
os.remove(material_only)
os.remove(material_zip)
os.remove(explicit_pattern)
include = true
filtered.save('With Cape', with_cape, 5, 1, 1)
assert(#bulk_entries == 3 and bulk_entries[3].kind == 'cape', 'Enabling Cape export did not include stored Cape')
local ok_patch, patch_why = pcall(P.encode_set, D, with_cape.entries)
assert(
    not ok_patch and tostring(patch_why):find('Shared texture has conflicting applied palettes', 1, true),
    'Conflicting shared-ID patch chose one appearance silently'
)
include = false
local cape_only_ok, cape_only_why = pcall(filtered.save, 'Cape Only', { entries = { cape_entry } }, 1, 1)
assert(
    not cape_only_ok and tostring(cape_only_why):find('Enable Include Capes', 1, true),
    'Empty filtered preset export lacked guidance'
)
os.remove(filtered_zip)
os.remove(cape_raw)
local legacy = { entries = { { kind = 'armor', key = '0:1:0:0', document = document } } }
local bulk_output, bulk_description = export.save('Saved Set', loaded, 5, 1, 5)
assert(bulk_output == 'tests/tmp/bulk-preset' and bulk_description == '2 saved LUT DDS files')
assert(bulk_naming == 5 and #bulk_entries == 2)
assert(
    bulk_entries[1].document == loaded.entries[1].document and bulk_entries[2].document == loaded.entries[2].document
)
assert(bulk_entries[1].ordinal == 1 and bulk_entries[2].ordinal == 1)
assert(export.save('Legacy', legacy, 5, 1, 1), 'Legacy raw bulk export incorrectly required patch IDs')
local ok, why = pcall(export.save, 'Legacy', legacy, 2, 1)
assert(not ok and tostring(why):find('resave', 1, true), 'Legacy patch guessed a destination')
assert(not pcall(export.save, 'Bad', loaded, 2, 0), 'Invalid selected LUT index accepted')
assert(E.lut_choices(loaded)[2]:find('Helmet Pattern LUT 1', 1, true), 'Pattern export choice mislabeled')
os.remove(raw)
os.remove(output)
os.remove(output2)
print(
    'PASS preset export: 4096 destination compact round trip, exact Pattern pairing/options, independent metadata, exact full-float bytes, shared-ID conflicts, bounded manifests/payloads and legacy safety'
)
