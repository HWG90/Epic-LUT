local ffi = require('ffi')
local D = dofile('src/core/dds.lua')
local F = dofile('src/core/file_io.lua')
local paths = { settings = 'tests/tmp/direct-state', presets = 'tests/tmp/presets' }
local S =
    dofile('src/gear/direct_setup.lua').new({ dds = D, native_import = dofile('src/platform/windows.lua') }, paths)
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
S.clear()
print(
    'PASS direct setup: material/Pattern and exact Cape identity round trip, legacy proof safety, high 64-bit resource normalization and rejected saves retain prior setup'
)
