-- Game Default material constants for Epic-owned instances. The inner native
-- helper reads only these inline camera/light fields; the outer unit helper
-- instead ignores its scene argument and uses the game's global camera slots.
local UI = {}
UI.SIZE, UI.HELPER = 0x3c48, 0x138f250
local SIGNATURE = '4055535657415441564157488d6c24e14881ece0000000488b05a2cd2a014833'
local SELECTOR = '8b86900000004533c9428b942310c00000458bc789442420e8555cffff'
local function unhex(value)
    return (value:gsub('..', function(pair)
        return string.char(tonumber(pair, 16))
    end))
end
local function multiply(a, b)
    local out = {}
    for row = 0, 3 do
        for col = 0, 3 do
            local sum = 0
            for k = 0, 3 do
                sum = sum + a[row * 4 + k + 1] * b[k * 4 + col + 1]
            end
            out[row * 4 + col + 1] = sum
        end
    end
    return out
end
local function camera_matrices(camera, aspect)
    local position = camera.preview_position
    local fov, near, far = camera.preview_fov, camera.preview_near, camera.preview_far
    assert(type(position) == 'table' and #position == 3, 'UI preview camera position unavailable')
    assert(type(fov) == 'number' and fov > 0 and fov < 180, 'UI preview camera FOV unavailable')
    assert(
        type(near) == 'number' and type(far) == 'number' and near > 0 and far > near,
        'UI preview camera range unavailable'
    )
    -- The owned camera looks along -Y with +Z up; rotation turns the model.
    -- Native UI matrices use row vectors, Y-forward projection and reverse Z.
    local view = { -1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, position[1], position[2], -position[3], 1 }
    local y = 1 / math.tan(math.rad(fov) / 2)
    local range = near - far
    local projection = { y / aspect, 0, 0, 0, 0, 0, near / range, 1, 0, y, 0, 0, 0, 0, -near * far / range, 0 }
    return view, projection, multiply(view, projection)
end
function UI.new(E, memory, game, dependencies)
    dependencies = dependencies or {}
    local ffi = require('ffi')
    local function read(at, size)
        local bytes = memory.read(ffi.cast('const uint8_t *', at), size)
        assert(type(bytes) == 'string' and #bytes == size, 'UI preview constants unavailable')
        return bytes
    end
    local function verify()
        assert(read(game + UI.HELPER, 32) == unhex(SIGNATURE), 'Native UI material preparation changed')
        assert(read(game + 0x139949e, 29) == unhex(SELECTOR), 'Native UI lighting selection changed')
    end
    local function pointer(at)
        local pointer = ffi.new('uint64_t[1]')
        ffi.copy(pointer, read(at, 8), 8)
        local value = tonumber(pointer[0])
        assert(value >= 65536 and value < 2 ^ 53, 'UI preview scene unavailable')
        return value
    end
    local function scene()
        return pointer(game + 0x347cd90)
    end
    verify()
    local original_scene = scene()
    local actors = pointer(game + 0x347ce60)
    local preset_value = ffi.new('uint32_t[1]')
    ffi.copy(preset_value, read(actors + 0xc0a0, 4), 4)
    local preset = tonumber(preset_value[0])
    assert(preset < 10, 'Game Default lighting preset unavailable')
    local buffer = ffi.new('uint8_t[?]', UI.SIZE)
    -- This is one verified lighting-preset block, not a scene/world clone.
    -- World, actor, native camera, viewport and environment pointers stay zero.
    -- Native large actor slot 0 chooses this preset. Relocate its immutable
    -- constants into private preset 0; helper's last 0 selects our copy.
    ffi.copy(buffer + 0x1218, read(original_scene + 0x1218 + preset * 0x434, 0x434), 0x434)
    ffi.copy(buffer + 0x3c40, read(original_scene + 0x3c40, 8), 8)
    local prepare = dependencies.material
        or ffi.cast('void (*)(void *,void *,uint32_t,uint8_t,uint32_t)', game + UI.HELPER)
    local self = { buffer = buffer, source_preset = preset }
    local previous_camera, previous_revision
    function self.needs_update(camera)
        return camera ~= previous_camera or camera.preview_revision ~= previous_revision
    end
    local function write(at, values, count)
        assert(#values == count, 'UI camera constant shape changed')
        local floats = ffi.cast('float *', buffer + at)
        for i = 1, count do
            local value = values[i]
            assert(type(value) == 'number' and value == value and math.abs(value) < 1e12, 'Invalid UI camera constant')
            floats[i - 1] = value
        end
    end
    local shift = dependencies.origin_shift
    if shift then
        local translation = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -shift[1], -shift[2], -shift[3], 1 }
        -- The copied garments are isolated away from native Armory actors.
        -- Keep their lighting in the same coordinate space without touching
        -- the game's live lights or shadow-camera constants.
        for _, at in ipairs({ 0x122c, 0x1338, 0x1444, 0x1550 }) do
            local values = ffi.cast('float *', buffer + at)
            for i = 1, 3 do
                values[i - 1] = values[i - 1] + shift[i]
            end
        end
        for _, at in ipairs({ 0x12cc, 0x13d8, 0x14e4, 0x15f0 }) do
            local values, matrix = ffi.cast('float *', buffer + at), {}
            for i = 1, 16 do
                matrix[i] = values[i - 1]
            end
            write(at, multiply(translation, matrix), 16)
        end
    end
    function self.apply(camera, materials, width, height)
        assert(scene() == original_scene, 'UI preview scene changed')
        if not self.needs_update(camera) then
            return false
        end
        verify()
        assert(width > 0 and height > 0, 'UI portrait dimensions unavailable')
        local view, projection, matrix = camera_matrices(camera, width / height)
        write(0, { 0, 0, 1, 1 }, 4)
        write(0x10, camera.preview_position, 3)
        -- The native UI field points towards the eye, not camera-forward.
        write(0x1c, { 0, 1, 0 }, 3)
        write(0x28, { width, height }, 2)
        write(0x30, view, 16)
        write(0x70, projection, 16)
        write(0xb0, matrix, 16)
        for _, material in ipairs(materials) do
            assert(material.owned == true, 'Non-owned UI material refused')
        end
        for _, material in ipairs(materials) do
            prepare(buffer, ffi.cast('void *', material.material), 0, 0, 0)
        end
        previous_camera, previous_revision = camera, camera.preview_revision
        return true
    end
    return self
end
return UI
