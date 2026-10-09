local ffi = require('ffi')
local E = dofile('src/presets/preset_export.lua')
local D = dofile('src/core/dds.lua')
local O = dofile('src/presets/outfit_presets.lua')
local F = dofile('src/core/file_io.lua')
local L = dofile('src/presets/lut_files.lua')
local P = dofile('src/presets/patch_export.lua')
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
local calls = {}
local bulk_entries, bulk_naming
local m = {
    dds = D,
    file_io = F,
    lut_files = L,
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
export.save('Saved Set', loaded, 2, 2)
assert(
    calls[1][2] == loaded.entries[2].document and calls[1][3].resource == '000000000000002a',
    'Selected patch used wrong or worn LUT'
)
export.save('Saved Set', loaded, 3, 1)
assert(calls[2][2] == loaded.entries and calls[2][3] == nil, 'Entire preset patch omitted saved entries')
local _, _, raw = export.save('Saved Set', loaded, 4, 1)
assert(raw:match('Saved Set%-%d%d%d%d%-%d%d%-%d%d_%d%d%-%d%d%-%d%d%.dds$'), 'Raw DDS lost timestamp naming')
local decoded = D.decode(F.read(raw, D.MAX_BYTES))
assert(ffi.string(decoded, 2944) == ffi.string(document.data, 2944), 'Raw DDS exported different pixels')
local output = export.save('Shared Set', loaded, 1, 1)
local output2 = export.save('Shared Set', loaded, 1, 1)
assert(output ~= output2 and F.read(output, 65536) == F.read(output2, 65536), 'Preset ZIP overwrote prior export')
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
    'PASS preset export: stored full-float/Pattern bytes, shareable round trip, exact destinations, legacy safety, timestamp collisions'
)
