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
S.clear()
print(
    'PASS direct setup: Pattern-only and mixed round trip, exact float bits, separate slots, legacy compatibility and safe rejection'
)
