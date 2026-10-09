-- Build-checked Application C API submission. The supplied owned viewport
-- selects the render layers; this wrapper does not replace native Armory
-- cameras, material parameters or its canvas. No game-owned object writes.
local Submit = {}
Submit.FLAGS, Submit.CONTEXT = 0x800f, 0x1a43b7a8
local UPDATE = '48895c2408574883ec30488bf9488b0d64816f01488b9938030000488b93101c'
local RENDER = '48895c240848896c2410488974241848897c242041564883ec604c8b9c249800'
local UI_CONTEXT = 'c7442438a8b7431a'
local UI_FLAGS = 'c74424300f800000'
local function unhex(value)
    return (value:gsub('..', function(pair)
        return string.char(tonumber(pair, 16))
    end))
end
function Submit.new(memory, game, exe, dependencies)
    dependencies = dependencies or {}
    local ffi = require('ffi')
    local function read(address, size)
        local value = memory.read(ffi.cast('const uint8_t *', address), size)
        assert(value and #value == size, 'Native preview submission memory unavailable')
        return value
    end
    local function pointer(address)
        local value = ffi.new('uint64_t[1]')
        ffi.copy(value, read(address, 8), 8)
        local result = tonumber(value[0])
        assert(result >= 65536 and result < 2 ^ 53, 'Native preview pointer invalid')
        return result
    end
    local api = pointer(game + 0x3326308)
    local app = pointer(api + 0x10)
    local update_at, render_at = pointer(app + 0x30), pointer(app + 0x28)
    assert(update_at == exe + 0x318090 and read(update_at, 32) == unhex(UPDATE), 'Native render-world update changed')
    assert(
        render_at == exe + 0x318150 and read(render_at, 32) == unhex(RENDER),
        'Native render-world submission changed'
    )
    assert(
        read(game + 0x1390778, 8) == unhex(UI_CONTEXT) and read(game + 0x139079f, 8) == unhex(UI_FLAGS),
        'Native Game Default submission contract changed'
    )
    local update = dependencies.update or ffi.cast('void (*)(void *)', update_at)
    local render = dependencies.render
        or ffi.cast(
            'void (*)(void *,const void *,const void *,const void *,const void *,const void *,uint32_t,uint32_t)',
            render_at
        )
    local address = dependencies.address
        or function(value)
            return tonumber(ffi.cast('uintptr_t', ffi.cast('void *', value)))
        end
    return function(world, camera, viewport, environment)
        assert(
            pointer(app + 0x30) == update_at and pointer(app + 0x28) == render_at,
            'Native submission dispatch changed'
        )
        local real_world = pointer(address(world))
        update(ffi.cast('void *', real_world))
        render(
            ffi.cast('void *', real_world),
            ffi.cast('void *', address(camera)),
            ffi.cast('void *', address(viewport)),
            nil,
            ffi.cast('void *', address(environment)),
            nil,
            Submit.FLAGS,
            Submit.CONTEXT
        )
    end
end
return Submit
