local ffi = require('ffi')
local D = dofile('src/core/dds.lua')
local F = dofile('src/core/file_io.lua')
local paths = { settings = 'tests/tmp/direct-state', presets = 'tests/tmp/presets' }
local m = {
    dds = D,
    native_import = dofile('src/platform/windows.lua'),
    file_io = F,
    windows = dofile('src/platform/windows.lua'),
    outfit_presets = dofile('src/presets/outfit_presets.lua'),
    binding_provenance = dofile('src/presets/binding_provenance.lua'),
}
local S = dofile('src/gear/direct_setup.lua').new(m, paths)
local document = { width = 23, height = 8, data = ffi.new('float[736]') }
local pattern = { width = 3, height = 1, data = ffi.new('float[12]') }
document.data[3], pattern.data[0], pattern.data[7], pattern.data[11] = -1.25, 0.375, 0.75, -2.125
local manifest = paths.settings .. '/direct-applied.tsv'
S.clear()
assert(S.save({ { save_key = '0:1:0:0', texture = document }, { save_key = 'p:0:1:0:0', texture = pattern } }, {}) == 2)
local plan = S.read()
assert(plan['0:1:0:0'] and plan['p:0:1:0:0'], 'Pattern and material destination keys collided')
local pixels, width, height = D.decode(F.read(paths.presets .. '/' .. plan['p:0:1:0:0'], D.MAX_BYTES))
assert(
    width == 3 and height == 1 and ffi.string(pixels, 48) == ffi.string(pattern.data, 48),
    'Pattern setup lost RGBA bits'
)
assert(S.save({ { save_key = 'p:0:0:0:0', texture = pattern } }, {}) == 1, 'Pattern-only setup could not save')
assert(S.read()['p:0:0:0:0'], 'Pattern-only setup could not load')
local previous = F.read(manifest, 524288)
assert(
    not pcall(S.save, { { save_key = 'p:0:0:0:0', texture = document } }, {}),
    'Material pixels accepted at Pattern destination'
)
assert(F.read(manifest, 524288) == previous, 'Failed save damaged previous setup')
for _, key in ipairs({ 'p:0:10:0:0', 'p:0:0:64:0', 'p:p:0:0:0:0', 'p:../outside', 'other:0:0:0:0' }) do
    F.write(manifest, 'setup-v1\n' .. key .. '\tsetup-1-1-1.dds\n')
    assert(not pcall(S.read), 'Invalid Pattern setup key accepted: ' .. key)
end
F.write(manifest, 'setup-v1\n0:1:0:0\tsetup-1-1-1.dds\n')
assert(S.read()['0:1:0:0'], 'Legacy material setup is no longer readable')
F.write(manifest, 'setup-v1\n0:2:0:0\tsetup-1-1-1.dds\n')
local legacy, legacy_capes = S.read()
assert(legacy['0:2:0:0'] and next(legacy_capes) == nil, 'Legacy slot invented a Cape identity proof')

assert(S.save({
    { save_key = '0:1:0:0', texture = document },
    { save_key = '0:2:0:0', texture = document, cape = true, cape_proof = '7:13', resource = 'FFFFFFFFFFFFFFFE' },
    { save_key = 'p:0:2:0:0', texture = pattern, cape = true, cape_proof = '7:13', resource = 'FFFFFFFFFFFFFFFF' },
}, {}) == 2, 'Cape material/Pattern setup lost texture deduplication')
previous = F.read(manifest, 524288)
assert(previous:sub(1, 9) == 'setup-v2\n', 'Cape proof was saved without versioned metadata')
local cape_plan, capes = S.read()
assert(cape_plan['0:1:0:0'] == cape_plan['0:2:0:0'] and cape_plan['p:0:2:0:0'])
assert(capes['0:1:0:0'] == nil, 'Cape proof attached to an ordinary Armor slot')
assert(capes['0:2:0:0'].proof == '7:13' and capes['0:2:0:0'].resource == 'fffffffffffffffe')
assert(
    capes['p:0:2:0:0'].proof == '7:13' and capes['p:0:2:0:0'].resource == 'ffffffffffffffff',
    'Cape Pattern metadata lost exact high 64-bit identity'
)
local cape_pixels, cape_width, cape_height =
    D.decode(F.read(paths.presets .. '/' .. cape_plan['p:0:2:0:0'], D.MAX_BYTES))
assert(cape_width == 3 and cape_height == 1 and ffi.string(cape_pixels, 48) == ffi.string(pattern.data, 48))
-- Existing metadata may use uppercase hex; reads normalize without truncation.
F.write(manifest, previous:gsub('fffffffffffffffe', 'FFFFFFFFFFFFFFFE'))
local _, uppercase_capes = S.read()
assert(uppercase_capes['0:2:0:0'].resource == 'fffffffffffffffe')
previous = F.read(manifest, 524288)
local function bad_cape(proof, resource)
    assert(not pcall(S.save, {
        { save_key = '0:2:0:0', texture = document, cape = true, cape_proof = proof, resource = resource },
    }, {}), 'Invalid Cape identity was saved')
    assert(F.read(manifest, 524288) == previous, 'Rejected Cape save damaged the existing setup')
end
bad_cape(nil, 'fffffffffffffffe')
for _, proof in ipairs({ '', '7', '7:13:1', '-7:13', 'body:cape', string.rep('1', 33) .. ':13' }) do
    bad_cape(proof, 'fffffffffffffffe')
end
bad_cape('7:13', nil)
for _, resource in ipairs({ '', 'fffffffffffffff', 'fffffffffffffffff', 'zzzzzzzzzzzzzzzz' }) do
    bad_cape('7:13', resource)
end
for _, row in ipairs({
    '0:2:0:0\tsetup-1-1-1.dds\tcape\t7:13',
    '0:2:0:0\tsetup-1-1-1.dds\tcape\t7:13\tnot-an-exact-id',
    '0:2:0:0\tsetup-1-1-1.dds\tcape\t7\tfffffffffffffffe',
    'armor-all\tsetup-1-1-1.dds\tcape\t7:13\tfffffffffffffffe',
}) do
    F.write(manifest, 'setup-v2\n' .. row .. '\n')
    assert(not pcall(S.read), 'Malformed Cape metadata was loaded')
end
F.write(manifest, previous)
assert(S.read()['p:0:2:0:0'], 'Rejected metadata checks lost the valid saved setup')

local function weapon(key, doc, resource)
    local slot = tonumber(key:match('^p?:?3:(%d+):')) or tonumber(key:match('^3:(%d+):'))
    local original = {
        width = doc.width,
        height = doc.height,
        resource = resource,
        patch_source = '0123456789abcdef\n' .. ('\0'):rep(192) .. D.encode(doc.data, doc.width, doc.height):sub(1, 148),
    }
    return {
        kind = 'weapon',
        key = key,
        weapon_slot = slot,
        weapon_resource = '5fecab819f96a3e8',
        document = doc,
        original = original,
        binding_provenance = {
            version = 4,
            kind = 'weapon',
            key = key,
            weapon_slot = slot,
            weapon_resource = '5fecab819f96a3e8',
            texture_slot = key:sub(1, 2) == 'p:' and m.binding_provenance.PATTERN or m.binding_provenance.LUT,
            original_texture = resource,
            material_texture = resource,
            unit_override = false,
            section = 101,
            mesh_id = 99,
            material_slot = 0,
            index_stamp = ('a'):rep(64),
            unit = { resource = '5fecab819f96a3e8', archive = '0123456789abcdef', main_sha256 = ('b'):rep(64) },
            material = { resource = '2222222222222222', archive = '0123456789abcdef', main_sha256 = ('c'):rep(64) },
        },
    }
end
local weapons = { weapon('3:1:4:0', document, 'babd338977faa2ff'), weapon('p:3:1:4:0', pattern, 'cf0cc31b981786c9') }
assert(S.save({}, {}, weapons) == 2, 'Weapon-only setup could not save')
previous = F.read(manifest, 524288)
assert(previous:sub(1, 9) == 'setup-v3\n')
local weapon_plan, weapon_capes, saved = S.read()
assert(next(weapon_plan) == nil and next(weapon_capes) == nil and #saved.entries == 2)
local weapon_filename = assert(previous:match('weapons\t([^\n]+)'))
assert(weapon_filename:match('^outfit%-setup%-%d+%-%d+%-weapons%.tsv$'))
local private_manifest = F.read(paths.settings .. '/' .. weapon_filename, m.outfit_presets.MAX_MANIFEST)
assert(private_manifest:sub(1, 13) == 'EPIC-OUTFIT\t4', 'Private setup lost schema4 assignments')
for i, entry in ipairs(saved.entries) do
    local expected = weapons[i]
    assert(entry.key == expected.key and entry.weapon_slot == 1 and entry.weapon_resource == expected.weapon_resource)
    assert(
        ffi.string(entry.document.data, entry.document.width * entry.document.height * 16)
            == ffi.string(expected.document.data, expected.document.width * expected.document.height * 16),
        'Weapon setup lost exact alpha/HDR bytes'
    )
    assert(
        entry.binding_provenance.version == 4
            and m.binding_provenance.encode(entry.binding_provenance, 'weapon', entry.key, entry.original)
                == m.binding_provenance.encode(expected.binding_provenance, 'weapon', expected.key, expected.original)
    )
end
assert(
    S.save(
        {
            {
                save_key = '0:2:0:0',
                texture = document,
                cape = true,
                cape_proof = '7:13',
                resource = 'fffffffffffffffe',
            },
        },
        {},
        weapons
    ) == 3
)
local combined, combined_capes, combined_weapons = S.read()
assert(combined['0:2:0:0'] and combined_capes['0:2:0:0'].proof == '7:13' and #combined_weapons.entries == 2)
assert(
    F.read(paths.settings .. '/' .. weapon_filename, m.outfit_presets.MAX_MANIFEST) == private_manifest,
    'New setup overwrote an old referenced weapon manifest'
)
previous = F.read(manifest, 524288)
local function refuses(entries)
    assert(not pcall(S.save, {}, {}, entries), 'Invalid or cold weapon setup was saved')
    assert(F.read(manifest, 524288) == previous, 'Failed weapon save damaged prior main pointer')
end
local cold = weapon('3:1:4:0', document, 'babd338977faa2ff')
cold.binding_provenance = nil
refuses({ cold })
local invalid = weapon('3:1:4:0', document, 'babd338977faa2ff')
invalid.binding_provenance.unit.main_sha256 = 'native-pointer'
refuses({ invalid })
invalid = weapon('3:1:4:0', document, 'babd338977faa2ff')
invalid.binding_provenance.mesh_id = nil
refuses({ invalid })
refuses({ weapons[1], weapons[1] })
refuses({ [1] = weapons[1], [3] = weapons[2] })
invalid = weapon('3:1:04:0', document, 'babd338977faa2ff')
refuses({ invalid })
refuses({ { kind = 'armor', key = '0:1:0:0', document = document } })
local storage = m.file_io
m.file_io = {
    read = storage.read,
    write = function(path, bytes)
        assert(not path:match('%.assignment$'), 'Injected assignment publication failure')
        return storage.write(path, bytes)
    end,
}
refuses(weapons)
m.file_io = storage
local native_import = m.native_import
m.native_import = {
    verify_interface = function()
        local user, kernel = native_import.verify_interface()
        return user,
            {
                epic_native_wide = kernel.epic_native_wide,
                epic_native_move = function()
                    return 0
                end,
            }
    end,
}
refuses(weapons)
m.native_import = native_import
assert(#S.read() > -1, 'Failed main-pointer publication damaged a readable prior setup')
for _, pointer in ipairs({
    'weapons\t../outside.tsv',
    'weapons\tC:/outside.tsv',
    'weapons\toutfit-Armory.tsv',
    'weapons\toutfit-setup-1-1-weapons.tsv\tother',
    'weapons\toutfit-setup-1-1-weapons.tsv\nweapons\toutfit-setup-1-1-weapons.tsv',
    '0:1:0:0\tsetup-1-1-1.dds',
}) do
    F.write(manifest, 'setup-v3\n' .. pointer .. '\n')
    assert(not pcall(S.read), 'Malformed weapon manifest pointer accepted')
end
local label = 'setup-1-1-weapons'
m.outfit_presets.new(m, paths.settings).save(label, { cold })
F.write(manifest, 'setup-v3\nweapons\toutfit-' .. label .. '.tsv\n')
assert(not pcall(S.read), 'An incomplete assignment proof was accepted from a disk preset')
F.write(manifest, previous)
local too_many = {}
for i = 1, 4096 do
    too_many[i] = { save_key = '0:1:0:0', texture = document }
end
assert(not pcall(S.save, too_many, {}, weapons) and F.read(manifest, 524288) == previous)
local oversized = {}
for i = 1, 400 do
    local doc = { width = 23, height = 64, data = ffi.new('float[?]', 23 * 64 * 4) }
    doc.data[0] = i
    oversized[i] = weapon('3:1:' .. math.floor((i - 1) / 64) .. ':' .. ((i - 1) % 64), doc, 'babd338977faa2ff')
end
refuses(oversized)
local current_weapon_manifest = assert(previous:match('weapons\t([^\n]+)'))
local oversized_rows = { 'setup-v3', 'weapons\t' .. current_weapon_manifest }
for i, entry in ipairs(oversized) do
    local filename = 'setup-0-0-' .. i .. '.dds'
    D.write(paths.presets .. '/' .. filename, entry.document.data, entry.document.width, entry.document.height)
    oversized_rows[#oversized_rows + 1] = '0:1:'
        .. math.floor((i - 1) / 64)
        .. ':'
        .. ((i - 1) % 64)
        .. '\t'
        .. filename
end
F.write(manifest, table.concat(oversized_rows, '\n') .. '\n')
assert(not pcall(S.read), 'Combined gear+weapon payload budget was bypassed by a modified main pointer')
F.write(manifest, previous)
S.clear()
assert(
    F.read(paths.settings .. '/' .. current_weapon_manifest, m.outfit_presets.MAX_MANIFEST),
    'Clear deleted a recoverable private weapon snapshot'
)
print(
    'PASS direct setup: material/Pattern and exact Cape identity round trip, legacy proof safety, high 64-bit resource normalization and rejected saves retain prior setup'
)
print(
    'PASS setup-v3: private weapon-only/mixed schema4 snapshots, complete exact assignments, cold/invalid proof refusal, payload limits and atomic pointer retention'
)
