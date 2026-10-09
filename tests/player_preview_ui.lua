local ffi = require('ffi')
local UI = dofile('src/preview/player_preview_ui.lua')
local game, scene, actors = 0x10000000, 0x30000000, 0x50000000
local function unhex(value)
    return (value:gsub('..', function(pair)
        return string.char(tonumber(pair, 16))
    end))
end
local pointer = ffi.new('uint64_t[1]', scene)
local actor_pointer = ffi.new('uint64_t[1]', actors)
local preset = ffi.new('uint32_t[1]', 2)
local signature = unhex('4055535657415441564157488d6c24e14881ece0000000488b05a2cd2a014833')
local light = string.rep('\x5a', 0x434)
local blocks = {
    [game + UI.HELPER] = signature,
    [game + 0x139949e] = unhex('8b86900000004533c9428b942310c00000458bc789442420e8555cffff'),
    [game + 0x347cd90] = ffi.string(pointer, 8),
    [game + 0x347ce60] = ffi.string(actor_pointer, 8),
    [actors + 0xc0a0] = ffi.string(preset, 4),
    [scene + 0x1218 + 2 * 0x434] = light,
    [scene + 0x3c40] = string.rep('\x2a', 8),
}
local reads = {}
local memory = {
    read = function(at, size)
        local address = tonumber(ffi.cast('uintptr_t', at))
        local value = blocks[address]
        assert(value and #value == size, 'Unexpected scene data read')
        reads[#reads + 1] = { address, size }
        return value
    end,
}
-- Intentionally no engine camera or matrix getters: this game's API omits them.
local E = {}
local calls = 0
local state = UI.new(E, memory, game, {
    material = function(buffer, material, slot, scenario, preset)
        assert(tonumber(ffi.cast('uintptr_t', material)) == 0x40000000)
        assert(slot == 0 and scenario == 0 and preset == 0)
        assert(ffi.sizeof(buffer) == UI.SIZE and ffi.string(buffer + 0x1218, 0x434) == light)
        assert(ffi.string(buffer + 0x3c48 - 8, 8) == blocks[scene + 0x3c40])
        assert(ffi.string(buffer + 0x3c28, 16) == string.rep('\0', 16), 'Private record contains game pointers')
        local matrix = ffi.cast('float *', buffer + 0xb0)
        local scale = 1 / math.tan(math.rad(45) / 2)
        assert(math.abs(matrix[0] + scale / (16 / 9)) < 0.00001)
        assert(math.abs(matrix[9] - scale) < 0.00001 and matrix[7] == -1)
        assert(math.abs(matrix[12] - 100 * scale / (16 / 9)) < 0.0001)
        assert(math.abs(matrix[13] + scale) < 0.00001 and matrix[15] == 5)
        local direction = ffi.cast('float *', buffer + 0x1c)
        assert(direction[0] == 0 and direction[1] == 1 and direction[2] == 0)
        local position = ffi.cast('float *', buffer + 0x10)
        assert(position[0] == 100 and position[1] == 5 and position[2] == 1)
        local rect = ffi.cast('float *', buffer)
        assert(rect[0] == 0 and rect[1] == 0 and rect[2] == 1 and rect[3] == 1)
        calls = calls + 1
    end,
})
local camera = {
    camera = 'owned camera',
    preview_revision = 1,
    preview_position = { 100, 5, 1 },
    preview_fov = 45,
    preview_near = 0.05,
    preview_far = 20,
}
local materials = { { material = 0x40000000, owned = true } }
assert(state.source_preset == 2, 'Native lighting selection was replaced with an assumed preset')
assert(state.needs_update(camera) and state.apply(camera, materials, 1920, 1080) and calls == 1)
local function project(buffer, x, y, z)
    local matrix, point, out = ffi.cast('float *', buffer + 0xb0), { x, y, z, 1 }, {}
    for col = 0, 3 do
        local sum = 0
        for row = 0, 3 do
            sum = sum + point[row + 1] * matrix[row * 4 + col]
        end
        out[col + 1] = sum
    end
    return out
end
local center = project(state.buffer, 100, 0, 1)
assert(math.abs(center[1]) < 0.00001 and math.abs(center[2]) < 0.00001 and center[4] == 5)
local near = project(state.buffer, 100, 5 - camera.preview_near, 1)
local far = project(state.buffer, 100, 5 - camera.preview_far, 1)
assert(math.abs(near[3] / near[4] - 1) < 0.00001, 'Projection does not map near to reverse-Z one')
assert(math.abs(far[3] / far[4]) < 0.00001, 'Projection does not map far to reverse-Z zero')
local half = 5 * math.tan(math.rad(camera.preview_fov) / 2)
local top = project(state.buffer, 100, 0, 1 + half)
local right = project(state.buffer, 100 - half * 16 / 9, 0, 1)
assert(math.abs(top[2] / top[4] - 1) < 0.00001 and math.abs(right[1] / right[4] - 1) < 0.00001)
assert(project(state.buffer, 100, 6, 1)[4] < 0, 'A point behind the camera is treated as visible')
assert(not state.needs_update(camera) and not state.apply(camera, materials, 1920, 1080) and calls == 1)
camera.preview_revision = 2
assert(state.apply(camera, materials, 1920, 1080) and calls == 2)
camera.preview_revision = 3
assert(not pcall(state.apply, camera, { materials[1], { material = 0x40000004, owned = false } }, 1920, 1080))
assert(calls == 2, 'A partial material preparation happened before ownership validation')
local lighting = ffi.new('uint8_t[0x434]')
for _, at in ipairs({ 0x122c, 0x1338, 0x1444, 0x1550 }) do
    local values = ffi.cast('float *', lighting + at - 0x1218)
    values[0], values[1], values[2] = 1, 2, 3
end
for _, at in ipairs({ 0x12cc, 0x13d8, 0x14e4, 0x15f0 }) do
    local values = ffi.cast('float *', lighting + at - 0x1218)
    values[0], values[5], values[10], values[15] = 1, 1, 1, 1
end
blocks[scene + 0x1218 + 2 * 0x434] = ffi.string(lighting, 0x434)
local rebased = UI.new(E, memory, game, {
    origin_shift = { 100, 0, 0 },
    material = function(buffer)
        for _, at in ipairs({ 0x122c, 0x1338, 0x1444, 0x1550 }) do
            local values = ffi.cast('float *', buffer + at)
            assert(values[0] == 101 and values[1] == 2 and values[2] == 3)
        end
        for _, at in ipairs({ 0x12cc, 0x13d8, 0x14e4, 0x15f0 }) do
            local values = ffi.cast('float *', buffer + at)
            assert(values[0] == 1 and values[12] == -100 and values[15] == 1)
        end
        calls = calls + 1
    end,
})
assert(rebased.apply(camera, materials, 1920, 1080) and calls == 3, 'Lighting stayed at the game actor origin')
local before_scale = tonumber(ffi.cast('float *', rebased.buffer + 0xb0)[9])
camera.preview_fov, camera.preview_position[1], camera.preview_revision = 60, 101, 4
assert(rebased.apply(camera, materials, 1920, 1080) and calls == 4)
assert(ffi.cast('float *', rebased.buffer + 0xb0)[9] < before_scale, 'Zoom did not change projection')
assert(ffi.cast('float *', rebased.buffer + 0x10)[0] == 101, 'Pan did not change camera position')
camera.preview_revision = 5
local saved_near = camera.preview_near
camera.preview_near = nil
assert(not pcall(rebased.apply, camera, materials, 1920, 1080) and calls == 4, 'Missing range metadata accepted')
camera.preview_near = saved_near
blocks[game + UI.HELPER] = string.rep('\0', 32)
assert(not pcall(state.apply, camera, materials, 1920, 1080) and calls == 4)
assert(not pcall(UI.new, E, memory, game), 'Changed helper code accepted')
blocks[game + UI.HELPER] = signature
pointer[0] = scene + 0x1000
blocks[game + 0x347cd90] = ffi.string(pointer, 8)
assert(not pcall(state.apply, camera, materials, 1920, 1080) and calls == 4, 'Changed scene accepted')
print(
    'PASS private Game Default camera constants, exact helper args, bounded lighting reads, ownership and drift refusal'
)
