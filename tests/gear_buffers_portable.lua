-- Real detached buffers through production preservation, snapshot, and mirror code.
local Buffer = require('src.core.float_buffer')
local Original = dofile('src/gear/original_luts.lua')
local Mirror = dofile('src/gear/armory_mirror.lua')
local DDS = dofile('src/core/dds.lua')
local function document(height, offset)
    local data = Buffer.new(23 * height * 4)
    for i = 0, 23 * height * 4 - 1 do data[i] = (i - 57) / 29 + (offset or 0) end
    data[0], data[1], data[2], data[3] = 2 ^ -149, -1 / math.huge, 1000000, 2
    return { data = data, width = 23, height = height, source = 'owned-import.dds' }
end
local imported, original = document(8, 3), document(5)
original.data[13 * 4 + 3] = -1 / math.huge
local imported_bytes = Buffer.bytes(imported.data, 23 * 8 * 4)
local original_bytes = Buffer.bytes(original.data, 23 * 5 * 4)
local trimmed = Original.preserve(imported, original)
assert(trimmed.width == 23 and trimmed.height == 5 and Buffer.count(trimmed.data) == 23 * 5 * 4,
    'Trimming copied beyond the owned output allocation')
assert(trimmed.source == imported.source and trimmed.data ~= imported.data and trimmed.data ~= original.data)
for row = 0, 4 do
    for column = 0, 22 do
        for channel = 0, 3 do
            local at = (row * 23 + column) * 4 + channel
            local expected = imported.data[at]
            if column == 13 or column == 0 and channel == 3 then expected = original.data[at] end
            assert(Buffer.value_to_word(trimmed.data[at]) == Buffer.value_to_word(expected),
                'Protected or imported float bytes changed')
        end
    end
end
assert(1 / trimmed.data[13 * 4 + 3] == -math.huge, 'Protected signed zero was lost')
local retained = Original.preserve(imported, original, true)
assert(retained.height == 8 and Buffer.count(retained.data) == 23 * 8 * 4)
assert(Buffer.bytes(retained.data, 23 * 3 * 4, 23 * 5 * 4)
    == Buffer.bytes(imported.data, 23 * 3 * 4, 23 * 5 * 4), 'Custom rows were truncated or rewritten')
assert(Buffer.bytes(imported.data, 23 * 8 * 4) == imported_bytes
    and Buffer.bytes(original.data, 23 * 5 * 4) == original_bytes, 'Preservation mutated its source')
retained.data[0] = 0.5
assert(imported.data[0] == 2 ^ -149 and trimmed.data[0] == 2 ^ -149, 'Output aliases an input or another output')
assert(not pcall(Original.preserve, imported, nil))
assert(not pcall(Original.preserve, original, imported), 'Invented missing import rows')
assert(not pcall(Original.preserve, { width = 23, height = 8, data = Buffer.new(4) }, original),
    'Accepted an undersized owned import buffer')

-- Snapshot loading uses the actual portable DDS decoder and exact live-object mapping.
local hash = '0123456789abcdef'
local filename = 'armor-00000001-0-' .. hash .. '-original.dds'
local files = { ['originals/' .. filename] = DDS.encode(original.data, 23, 5) }
local opens, closes, listings = 0, 0, 0
local service = {
    open = function(path)
        local bytes = files[path]
        if not bytes then return nil, 'missing fixture file' end
        opens = opens + 1
        local at, closed = 1, false
        return {
            read = function(_, size)
                assert(not closed)
                if at > #bytes then return nil end
                local result = bytes:sub(at, at + size - 1)
                at = at + #result
                return result
            end,
            close = function() assert(not closed); closed = true; closes = closes + 1; return true end,
        }
    end,
}
local reader = Original.new({
    dds = DDS,
    file_io = service,
    windows = { files = function(folder, filter)
        assert(folder == 'originals' and filter == '*-original.dds')
        listings = listings + 1
        return { filename }
    end },
    engine = { texture_object = function(_, resource) return resource == hash and 100000 or nil end },
}, { originals = 'originals' }, {})
local loaded = assert(reader.get_resource(hash))
assert(loaded.resource == hash and loaded.width == 23 and loaded.height == 5
    and Buffer.bytes(loaded.data, 23 * 5 * 4) == original_bytes, 'Snapshot pixels or identity changed')
for _ = 1, 1000 do assert(reader.get(100000) == loaded and reader.get(200000) == nil) end
assert(listings == 1 and opens == closes, 'Cached snapshot reads reopened or leaked streams')

local applied, restored, units_calls = 0, 0, 0
local hovered, present, cape, allow_restore = 999, true, false, true
local targets_seen, binding = {}, 100
local active_document = document(1)
local mirror = Mirror.new({
    identity = function() return { ui_slot = 0, body = 1, armor = 2, helmet = 3 } end,
    locate = function(slot) assert(slot == 0); return {} end,
    watch = function() return {
        poll = function() return present and 'kits' or 'absent' end,
        kits = function() return hovered, 2, 1 end,
    } end,
    units = function()
        units_calls = units_calls + 1
        return { { unit = 11, type = 0, slot = 1 }, { unit = 12, type = 0, slot = 0 } }
    end,
    materials = function(unit)
        return { { mesh = unit, material = unit, mesh_index = 0, material_index = 0 } }
    end,
    is_cape = function() return cape end,
    slot = function(pattern) return pattern and 2 or 1 end,
    binding = function() return binding end,
    entries = function() return {
        ['0:1:0:0'] = { document = active_document },
        ['0:0:0:0'] = { document = active_document, helmet = true },
    } end,
    session = function() return {
        restore = function() restored = restored + 1; return allow_restore end,
        apply = function(doc, targets)
            assert(doc == active_document)
            applied = applied + 1
            targets_seen = targets
            for _, target in ipairs(targets) do
                assert(target.unit == 11 or hovered == 3, 'Recolored an unrelated hovered helmet')
                assert(target.original == binding and target.current == binding)
            end
        end,
    } end,
})
mirror.tick(0.05)
assert(units_calls == 0 and applied == 0, 'Changed the existing mirror cadence')
mirror.tick(0.05)
assert(applied == 1 and #targets_seen == 1 and targets_seen[1].unit == 11)
for _ = 1, 100 do mirror.tick(0.1) end
assert(applied == 1, 'Unchanged exact pixels were rebound')
active_document.data[1] = 0 -- Binary signature preserves the existing signed-zero distinction.
mirror.tick(0.1)
assert(applied == 2, 'Changed detached bytes failed to invalidate the mirror')
hovered = 3
mirror.tick(0.1)
assert(applied == 3 and #targets_seen == 2)
allow_restore = false
active_document.data[5] = 12.5
mirror.tick(0.1)
assert(applied == 3, 'Applied over a pending owned restoration')
allow_restore = true
mirror.tick(0.1)
assert(applied == 4)
cape = true
active_document.data[6] = 8
mirror.tick(0.1)
assert(applied == 4, 'Mirror changed a Cape material')
present = false
mirror.tick(0.1)
assert(mirror.close() and restored >= 4)
print('PASS portable gear buffers: bounded trimmed preservation, exact protected floats/custom rows, immutable copies, cached DDS snapshots, matching Armory ownership and unchanged no-op')
