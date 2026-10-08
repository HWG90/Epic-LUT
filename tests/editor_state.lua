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
