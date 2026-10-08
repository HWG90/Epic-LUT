-- Optional read-only base-game integration; fixtures/output stay under dist.
local ffi = require('ffi')
local D = dofile('src/core/dds.lua')
local P = dofile('src/presets/patch_export.lua')
local root = assert(os.getenv('EPIC_LUT_PATCH_REVIEW'))
local function read(path)
    local f = assert(io.open(path, 'rb'))
    local bytes = f:read('*a')
    f:close()
    return bytes
end
local stamp = read(root .. '/snapshots/complete.txt'):match('^([%x]+)')
assert(stamp and #stamp == 64)
for _, id in ipairs({ '7b8293c071bde8b9', '33039c545e8d0669', 'cf0cc31b981786c9' }) do
    local base = root .. '/snapshots/' .. stamp .. '/game-' .. id .. '-original'
    local data, w, h = D.decode(read(base .. '.dds'))
    local original = { resource = id, width = w, height = h, patch_source = read(base .. '.patch-source') }
    data[0], data[1] = 1.25, -0.125 -- Observable, finite edits; retain every other channel.
    local patch = P.encode(D, { data = data, width = w, height = h }, original)
    local decoded, dw, dh = D.decode(patch.main:sub(377) .. patch.gpu)
    assert(dw == w and dh == h and decoded[0] == 1.25 and decoded[1] == -0.125)
    assert(ffi.string(decoded, #patch.gpu) == ffi.string(data, #patch.gpu))
    local destination = root .. '/exports/' .. id .. '/' .. patch.archive .. '.patch_0'
    for _, item in ipairs({
        { destination, patch.main },
        { destination .. '.gpu_resources', patch.gpu },
        { destination .. '.stream', patch.stream },
    }) do
        local f = assert(io.open(item[1], 'wb'))
        assert(f:write(item[2]))
        assert(f:close())
    end
    print('PASS base-game patch: ' .. id .. ' (' .. w .. 'x' .. h .. '), archive ' .. patch.archive)
end
