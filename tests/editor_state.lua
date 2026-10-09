local ffi = require('ffi')
local B = dofile('src/core/basic_state.lua')
local R = dofile('src/gear/region_indicator.lua')
local source = { width = 23, height = 1, data = ffi.new('float[92]') }
source.data[0] = 0.25
local state = B.new()
local clone = state.get('helmet', source)
clone.data[0] = 0.75
assert(source.data[0] == 0.25 and state.get('helmet', source) == clone, 'Editor copy aliases source or loses edits')
local target = { width = 23, height = 2, data = ffi.new('float[184]') }
target.data[92] = 0.5
assert(
    B.copy(target, clone) == 1 and target.data[0] == 0.75 and target.data[92] == 0.5,
    'Copy lost unmatched target rows'
)
state.clear()
assert(not next(state.documents), 'Restore did not discard cached edits')
source.original = ffi.new('float[92]')
source.original[0] = 0.125
source.resource = 'resource'
source.revision = 7
local copier = B.copier()
local saved = copier.copy(source)
assert(
    saved == copier.copy(source) and copier.bytes == 736,
    'History copy must deduplicate aliases and account for original buffers'
)
assert(saved.original[0] == 0.125 and saved.resource == 'resource' and saved.revision == 7, 'History metadata lost')
saved.data[0] = 0.9
saved.original[0] = 0.8
assert(source.data[0] == 0.25 and source.original[0] == 0.125, 'History snapshot aliases live pixels')

local b = { current = 10, document = source }
local object = 10
local fail = false
local r = R.new({
    present = function()
        return true
    end,
    binding = function()
        return object
    end,
    bind = function(_, value)
        if fail then
            error('temporary bind failure')
        end
        object = value
    end,
    apply = function(document)
        assert(document.data[0] == 1 and document.data[3] == source.data[3])
        object = 20
        b.current = 20
        return 1, { object = 20 }
    end,
})
local function start()
    r.start({ { binding = b, object = 10, document = source, source = source } }, 1)
end
start()
fail = true
assert(not r.stop(), 'Failed restoration was forgotten')
fail = false
assert(r.stop() and object == 10, 'Restoration retry failed')
start()
object = 99
assert(r.stop() and object == 99, 'Highlight overwrote a competing binding')
print('PASS editor state: independent copies, unequal row counts, cache reset, restoration retry, foreign ownership')

local tall = { width = 23, height = 12, data = ffi.new('float[?]', 23 * 12 * 4) }
tall.data[(11 * 23) * 4 + 3] = 0.625
local current = 10
local tall_binding = { current = 10 }
local tall_indicator = R.new({
    present = function()
        return true
    end,
    binding = function()
        return current
    end,
    bind = function(_, object)
        current = object
    end,
    apply = function(document)
        local at = 11 * 23 * 4
        assert(
            document.height == 12
                and document.data[at] == 1
                and document.data[at + 1] == 0
                and document.data[at + 2] == 1
                and document.data[at + 3] == 0.625
                and document.data[0] == 0,
            'Wrong custom region highlighted'
        )
        current = 20
        tall_binding.current = 20
        return 1, { object = 20 }
    end,
})
tall_indicator.start({ { binding = tall_binding, object = 10, source = tall, document = tall } }, 12)
assert(tall.data[11 * 23 * 4] == 0, 'Region flash mutated custom LUT')
assert(tall_indicator.stop() and current == 10)

-- The real binding session publishes documents on Apply. Identification must
-- retain the prior document and immutable applied texture through both phases,
-- reloads and retries, so an editor/export/save reader cannot capture magenta.
local Session = dofile('src/gear/binding_session.lua')
local custom = B.clone(tall)
custom.data[0], custom.data[3] = -0.25, 2.5
local material = { current = 10, original = 10 }
local native_object, next_object = 10, 10
local context, fail_restore = 'import', false
local session_deps = {
    retain = { records = {}, bytes = 0, cache = {} },
    present = function()
        return true
    end,
    binding = function()
        return native_object
    end,
    key = function()
        return 'material'
    end,
    bind = function(_, object)
        if fail_restore then
            error('temporary restoration failure')
        end
        native_object = object
    end,
    create_texture = function(width, height, data)
        next_object = next_object + 1
        return { object = next_object, width = width, height = height, data = data }
    end,
}
local session = Session.new(session_deps)
local _, applied = session.apply(custom, { material })
local before_pixels = ffi.string(applied.data, applied.width * applied.height * 16)
local indicator = R.new({
    present = session_deps.present,
    binding = session_deps.binding,
    bind = session_deps.bind,
    apply = session.apply,
    context = function()
        return context
    end,
})
local function flash()
    assert(indicator.stop())
    indicator.start({
        {
            binding = material,
            object = material.current,
            texture = material.texture,
            document = material.document,
            source = material.texture,
        },
    }, 1)
end
local function unchanged()
    assert(material.texture == applied and material.document == custom, 'Flash leaked temporary document metadata')
    local editor_copy = B.clone(material.document)
    assert(
        ffi.string(editor_copy.data, editor_copy.width * editor_copy.height * 16) == before_pixels,
        'Loading/exporting the current LUT captured magenta'
    )
end
flash()
local flash_object = native_object
assert(flash_object ~= applied.object)
unchanged()
indicator.tick(0.26, true)
assert(native_object == applied.object and material.current == applied.object)
unchanged()
indicator.tick(0.26, true)
assert(native_object == flash_object)
unchanged()
context = 'editor'
indicator.tick(0, true)
assert(not indicator.job and native_object == applied.object, 'Changing tabs retained a native flash')
unchanged()
flash()
flash()
assert(native_object == flash_object, 'Repeated Flash lost immutable texture reuse')
indicator.tick(4.1, true)
assert(not indicator.job and native_object == applied.object, 'Timeout retained a native flash')
unchanged()
flash()
fail_restore = true
assert(not indicator.stop() and indicator.job, 'Retryable native restoration was discarded')
unchanged()
fail_restore = false
assert(indicator.stop() and native_object == applied.object)
flash()
native_object = 99
assert(indicator.stop() and native_object == 99, 'Flash restoration overwrote a foreign texture')
unchanged()
assert(
    ffi.string(custom.data, custom.width * custom.height * 16) == before_pixels,
    'Flash modified editable or exported float bits'
)
print(
    'PASS real binding-session identification: ON/OFF isolation, tab changes, repeated flashes, timeout, retries and foreign ownership'
)
