-- Real catalog/Pattern/direct-editor discovery and Binding mutation paths.
local ffi = require('ffi')
local Engine = dofile('vendor/engine.lua')
local Catalog = dofile('src/gear/gear_catalog.lua')
local Pattern = dofile('src/editor/pattern_luts.lua')
local Binding = dofile('src/gear/binding_session.lua')
local f = assert(io.open('src/editor/direct_editor.lua', 'rb')); local source = f:read('*a'):gsub('\r\n', '\n'); f:close()
local function region(first, last)
    local a = assert(source:find(first, 1, true), 'Missing start: '..first); local b = assert(source:find(last, a, true), 'Missing end: '..last)
    return source:sub(a, b - 1)
end
local make = assert(loadstring('return function(m,read,small,big) local operations={}\n' .. region('local function binding(', 'local function present(')
    .. '\nreturn binding,operations.discovery_binding end'))()
local make_present = assert(loadstring('return function(m,native)\n' .. region('local function present(', 'local function material_key(')
    .. '\nreturn present end'))()
local discover_code = region('                discover = function(enumerate, observe)', '                export = function(name, document)')
    :gsub('^%s*discover = ', ''):gsub(',%s*$', '')
local make_discover = assert(loadstring('return function(m,native,memory,game,read,small,big,binding) return ' .. discover_code .. ' end'))()
local cape_code = region('        is_cape = function(b, observe)', '\n    })\n    bindings =')
    :gsub('^%s*is_cape = ', ''):gsub(',%s*$', '')
local make_cape = assert(loadstring('return function(m,read,small,big) return ' .. cape_code .. ' end'))()
local buffers, unit_materials, blocks, dead = {}, { {}, {} }, {}, {}
local calls = { read = 0, alive = 0, bind = 0, scopes = 0 }
local function number(bytes, offset, value, size)
    for i = 0, size - 1 do bytes[offset + i] = value % 256; value = math.floor(value / 256) end
end
local function seed(address)
    local header, slots = ffi.new('uint8_t[16]'), ffi.new('uint8_t[48]')
    number(header, 0, 3, 4); number(header, 8, address + 0x100000, 8)
    for i, row in ipairs({ { Engine.LUT_SLOT, 500 }, { Engine.PATTERN_SLOT, 600 }, { Engine.CAPE_LUT_SLOT, 0 } }) do
        number(slots, (i - 1) * 16, row[1], 4); number(slots, (i - 1) * 16 + 8, row[2], 8)
    end
    blocks[address + 24], blocks[address + 0x100000] = { header, 16 }, { slots, 48 }
    buffers[address] = slots
end
for unit = 1, 2 do for i = 1, 48 do local address = 0x20000 + ((unit - 1) * 48 + i) * 64
    seed(address); unit_materials[unit][i] = address end end
local function read(address, size, target)
    calls.read = calls.read + 1
    local value = blocks[address]; if not value or size > value[2] then return false end
    ffi.copy(target, value[1], size); return true
end
local native = {
    alive = function(unit) calls.alive = calls.alive + 1; return dead[unit] and 0 or 1 end,
    meshes = function() return 1 end, mesh = function(unit) return unit * 100 end,
    materials = function(mesh) return #unit_materials[mesh / 100] end,
    material = function(mesh, index) return unit_materials[mesh / 100][index + 1] end,
}
local modules = { engine = Engine, avatar = { resolve_live = function() return {} end,
    units = function() return { { unit = 1, type = 0, slot = 1 }, { unit = 2, type = 0, slot = 0 } } end } }
local small, big = ffi.new('uint8_t[96]'), ffi.new('uint8_t[1024]')
local fresh, create_reader = make(modules, read, small, big)
local function scoped() calls.scopes = calls.scopes + 1; return create_reader() end
local present = make_present(modules, native)
local function key(b) return b.unit .. ':' .. b.mesh .. ':' .. b.material end
local owned, pattern_owned = {}, {}
for unit = 1, 2 do for i, material in ipairs(unit_materials[unit]) do
    owned[#owned + 1] = { unit = unit, mesh = unit * 100, material = material, original = 100, current = 500 }
    if #pattern_owned < 92 then pattern_owned[#pattern_owned + 1] = { unit = unit, mesh = unit * 100,
        material = material, slot = Engine.PATTERN_SLOT, original = 200, current = 600 } end
end end
local catalog = Catalog.new({ identity = modules.avatar.resolve_live, units = modules.avatar.units,
    materials = function(unit) return Engine.unit_materials(native, unit) end, present = present,
    binding = fresh, discovery_binding = scoped, key = key, is_cape = make_cape(modules, read, small, big) })
local before = calls.read
local result = catalog.refresh(owned, 100)
assert(calls.read - before == 192 and #result.owned == 96 and #result.groups[1].bindings == 96,
    'Catalog must copy one full slot table per material while preserving originals')
local discover = make_discover(modules, native, {}, 1, read, small, big, fresh)
local session = Binding.new({ retain = { cache = {}, records = {}, bytes = 0 }, present = present, binding = fresh, key = key,
    create_texture = function() return { object = 900 } end,
    bind = function(b, value) calls.bind = calls.bind + 1; number(buffers[b.material], b.slot == Engine.PATTERN_SLOT and 24 or 8, value, 8) end })
session.owned = pattern_owned
local pattern = Pattern.new({ session = session, present = present,
    materials = function(unit) return Engine.unit_materials(native, unit) end,
    binding = fresh, discovery_binding = scoped, key = key, discover = discover, note = function(v) return v end })
before = calls.read
result = pattern.scan(true)
assert(calls.read - before == 192 and #session.owned == 92 and #result == 2 and calls.scopes == 2,
    'Pattern discovery/owned comparisons must share exactly one copied slot table per material')
-- Another operation sees a new live object; no slot map survives a scan.
local target = owned[1]; number(buffers[target.material], 8, 100, 8)
before = calls.read; result = catalog.refresh(owned, 100)
assert(calls.read - before == 192 and #result.owned == 95, 'Changed binding between scans reused an earlier ownership proof')
-- Mutation and restoration use actual, uncached Engine.binding even after discovery.
target.current = 100; session.owned = {}
local document = { width = 1, height = 1, data = ffi.new('float[4]') }
-- Prepare, commit revalidation, and write readback each use a fresh binding read.
before = calls.read; assert(session.apply(document, { target }) == 1 and calls.read - before == 6)
assert(fresh(target) == 900 and calls.bind == 1)
before = calls.read; assert(session.restore() and calls.read - before == 4 and fresh(target) == 100)
assert(calls.bind == 2, 'Uncached restoration did not read back its write')
catalog.refresh(owned, 100); number(buffers[target.material], 8, 777, 8)
before = calls.read
assert(not pcall(session.apply, document, { target }) and calls.read > before and calls.bind == 2,
    'Mutation trusted a discovery snapshot instead of detecting a later foreign writer')
-- Fresh per-destination alive checks are not replaced by a slot snapshot.
dead[1] = true; local alive = calls.alive; result = catalog.refresh(owned, 100)
assert(calls.alive - alive >= #owned and #result.owned == 48, 'Slot snapshots bypassed Unit lifetime checks')
print('PASS discovery slot snapshot: real catalog/Pattern/direct providers use96 copies/operation, preserve fresh scopes, Unit checks and uncached mutation/readback/restore')
