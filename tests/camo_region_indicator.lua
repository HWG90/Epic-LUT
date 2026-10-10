local ffi = require('ffi')
local Region = dofile('src/gear/region_indicator.lua')
local Session = dofile('src/gear/binding_session.lua')
local source = { width = 23, height = 3, data = ffi.new('float[?]', 23 * 3 * 4) }
for i = 0, 23 * 3 * 4 - 1 do
    source.data[i] = (i % 73 - 21) / 8
end
for row = 1, 3 do
    source.data[((row - 1) * 23 + 21) * 4 + 3] = row - 1 -- Active camo pattern selectors.
end
ffi.cast('uint32_t *', source.data)[((2 - 1) * 23 + 16) * 4 + 3] = 0x80000000
local original_bytes = ffi.string(source.data, 23 * 3 * 16)
local pattern = { width = 3, height = 1, data = ffi.new('float[12]') }
for i = 0, 11 do
    pattern.data[i] = (i - 4) / 3
end
local pattern_bytes = ffi.string(pattern.data, 48)
local b = { current = 10, original = 10, document = source }
local object, context, next_object, apply_calls = 10, 'editor', 100, 0
local fail_restore, alive = false, true
local session_deps = {
    retain = { records = {}, bytes = 0, cache = {} },
    present = function(target)
        return alive and target == b
    end,
    binding = function(target)
        assert(target == b)
        return object
    end,
    key = function()
        return 'material'
    end,
    bind = function(target, value)
        assert(target == b)
        if fail_restore then
            error('Restoration temporarily unavailable')
        end
        object = value
    end,
    create_texture = function(w, h, data)
        next_object = next_object + 1
        return { object = next_object, width = w, height = h, data = data }
    end,
}
local session = Session.new(session_deps)
local _, prior = session.apply(source, { b })
local prior_object = object
local indicator = Region.new({
    present = session_deps.present,
    binding = session_deps.binding,
    bind = session_deps.bind,
    context = function()
        return context
    end,
    apply = function(document, targets)
        apply_calls = apply_calls + 1
        return session.apply(document, targets)
    end,
})
local function item(document)
    return { binding = b, object = object, texture = b.texture, document = b.document, source = document or prior }
end
local function unchanged()
    assert(ffi.string(source.data, #original_bytes) == original_bytes, 'Flash changed editable material bytes')
    assert(ffi.string(prior.data, #original_bytes) == original_bytes, 'Flash changed immutable applied texture bytes')
    assert(ffi.string(pattern.data, 48) == pattern_bytes, 'Material flash changed separate Pattern data')
    assert(b.texture == prior and b.document == source, 'Flash leaked magenta into editor/export metadata')
end
indicator.start({ item() }, 2)
local highlight = object
local flashed = session_deps.retain.records[#session_deps.retain.records].data
local colors =
    { [1] = true, [3] = true, [6] = true, [7] = true, [13] = true, [17] = true, [18] = true, [19] = true, [20] = true }
local expected = ffi.new('float[?]', 23 * 3 * 4)
ffi.copy(expected, source.data, #original_bytes)
for column in pairs(colors) do
    local at = ((2 - 1) * 23 + column - 1) * 4
    expected[at], expected[at + 1], expected[at + 2] = 1, 0, 1
end
assert(
    ffi.string(flashed, #original_bytes) == ffi.string(expected, #original_bytes),
    'Camo flash missed a contributing color or changed alpha/material/tint/selector/other-row data'
)
unchanged()
indicator.tick(0.26, true)
assert(object == prior_object and b.current == prior_object)
unchanged()
indicator.tick(0.26, true)
assert(object == highlight)
context = 'armory'
indicator.tick(0, true)
assert(object == prior_object and not indicator.job, 'Tab change left a camo highlight stuck')
unchanged()
indicator.start({ item() }, 2)
indicator.tick(4.1, true)
assert(object == prior_object and not indicator.job)
indicator.start({ item() }, 2)
fail_restore = true
assert(not indicator.stop() and indicator.job, 'Failed restoration lost ownership')
unchanged()
fail_restore = false
assert(indicator.stop() and object == prior_object)
indicator.start({ item() }, 2)
object = 999
assert(indicator.stop() and object == 999, 'Camo flash overwrote a foreign texture')
unchanged()
object, b.current = prior_object, prior_object
-- Invalid later items are rejected before even the first target is applied.
local before = apply_calls
local invalid = { width = 23, height = 1, data = source.data }
assert(not pcall(indicator.start, { item(), item(invalid) }, 2))
assert(apply_calls == before and object == prior_object and not indicator.job)
for _, row in ipairs({ 0, 1.5, 4 }) do
    assert(not pcall(indicator.start, { item() }, row) and apply_calls == before)
end
assert(not pcall(indicator.start, { item({ width = 16, height = 1, data = source.data }) }, 1))
alive = false
assert(not pcall(indicator.start, { item() }, 2) and apply_calls == before)
alive = true
local foreign = item()
object = 999
assert(not pcall(indicator.start, { foreign }, 2) and object == 999 and apply_calls == before)
object, b.current = prior_object, prior_object
-- The existing Pattern-window flash is limited to the known first RGB cell.
indicator.start({ item(pattern) }, 1)
local pattern_flash = session_deps.retain.records[#session_deps.retain.records].data
local expected_pattern = ffi.new('float[12]')
ffi.copy(expected_pattern, pattern.data, 48)
expected_pattern[0], expected_pattern[1], expected_pattern[2] = 1, 0, 1
assert(ffi.string(pattern_flash, 48) == ffi.string(expected_pattern, 48))
assert(indicator.stop() and object == prior_object)
unchanged()
print(
    'PASS camo region flash: contributing RGB colors, exact alpha/selector/Pattern preservation, phases/tab/timeout/restoration/foreign/invalid-target guards'
)
