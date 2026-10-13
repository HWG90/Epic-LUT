local F = dofile('tests/weapon_services_fixture.lua')
local M = dofile('src/editor/weapon_mapping.lua')
do
    local ffi = require('ffi')
    local chunk = assert(loadfile('src/editor/weapon_mapping.lua'))
    setfenv(
        chunk,
        setmetatable({
            tostring = function(value)
                return type(value) == 'cdata' and '[cdata (deleted)]' or tostring(value)
            end,
        }, { __index = _G })
    )
    local mapping = chunk()
    local document = F.document(23, 8, 0.625)
    document.original = document.data
    local copied = mapping.copy(document)
    assert(mapping.bytes(copied) == mapping.bytes(document))
    assert(ffi.string(copied.original, 23 * 8 * 16) == ffi.string(document.original, 23 * 8 * 16))
    assert(copied.data ~= document.data and copied.original ~= document.original)
    local data = document.data
    document.data = ffi.cast('float *', data)
    assert(not pcall(mapping.copy, document), 'Mapping accepted a float pointer')
    document.data, document.original = data, ffi.cast('float *', data)
    assert(not pcall(mapping.copy, document), 'Mapping accepted an original float pointer')
    document.original = ffi.new('float[?]', 1)
    assert(not pcall(mapping.copy, document), 'Mapping accepted an undersized original array')
    document.original, document.data = data, ffi.new('uint8_t[?]', 23 * 8 * 16)
    assert(not pcall(mapping.copy, document), 'Mapping accepted a non-float backing array')
end
local function populated()
    local f = F.new()
    for index = 1, 3 do
        f.group(1, 'material', index, string.format('%016x', index), 0)
    end
    f.group(2, 'material', 1, '1111111100000001', 0)
    f.import('lut001.dds', F.document(23, 8, 20))
    f.import('lut000.dds', F.document(23, 8, 10))
    return f
end
local f = populated()
local dialog = M.new(f.host).open(f.groups)
assert(
    #dialog.columns == 4
        and dialog.columns[2].title == 'Primary'
        and dialog.columns[4].title == 'Support'
        and dialog.weapon_columns
        and dialog.gear_columns
)
dialog.on_auto_map({ primary = true, secondary = true })
assert(f.calls == 1 and #f.plan == 4)
assert(
    f.plan[1].document.data[0] == 10
        and f.plan[2].document.data[0] == 20
        and f.plan[3].document.data[0] == 10
        and f.plan[4].document.data[0] == 10,
    'Auto-map did not sort/reset/roll over'
)
assert(f.plan[1].family == 'material' and f.plan[1].targets[1].save_key == '3:1:0:0')
-- The chooser remains usable after a successful owned write, with new receipts.
dialog.on_map('source:1', 'weapon:1:material:1')
assert(f.calls == 2 and f.plan[1].document.data[0] == 20)
f = populated()
dialog = M.new(f.host).open(f.groups, { rollover = false })
assert(not pcall(dialog.on_auto_map, { primary = true }) and f.calls == 0)
-- A matching Pattern group contains an unselected material sibling. Only the
-- exact matching native key may follow this one-click material assignment.
f = F.new()
local material = f.group(1, 'material', 1, '0000000000000001', 0)
local pattern = f.group(1, 'pattern', 1, '0000000000000002', 0, 2)
f.import('lut000.dds', F.document(23, 8, 5.75, material.source_resource))
f.import('PatternLUT000.dds', F.document(3, 1, 2.25, pattern.source_resource))
local sibling = pattern.bindings[2].current
dialog = M.new(f.host).open(f.groups)
dialog.on_map('source:1', 'weapon:1:material:1')
assert(#f.plan == 2 and #f.plan[2].targets == 1 and f.plan[2].targets[1] == pattern.bindings[1])
assert(pattern.bindings[2].current == sibling and pattern.bindings[1].document.data[0] == 2.25)
assert(not pcall(dialog.on_map, 'source:2', 'weapon:1:material:1'), 'Pattern DDS mapped into a material table')
f = F.new()
material = f.group(1, 'material', 1, '0000000000000001', 0)
pattern = f.group(1, 'pattern', 1, '0000000000000002', 0, 2)
f.import('lut000.dds', F.document(23, 8, 5.75, material.source_resource))
f.import('PatternLUT000.dds', F.document(3, 1, 9, '0000000000000003'))
f.import('PatternLUT001.dds', F.document(3, 1, 7, pattern.source_resource))
dialog = M.new(f.host).open(f.groups)
dialog.on_auto_map({ primary = true })
assert(
    f.calls == 1
        and #f.plan == 3
        and pattern.bindings[1].document.data[0] == 7
        and pattern.bindings[2].document.data[0] == 9,
    'Auto-map overwrote a certified Pattern companion with its independent cycle'
)
for _, alter in ipairs({
    function(f)
        f.documents['lut000.dds'].data[0] = 99
    end,
    function(f)
        f.imports[1] = 'other.dds'
    end,
    function(f)
        f.groups[1].weapon_resource = 'ffffffffffffffff'
    end,
    function(f)
        f.groups[1].source_document.data[0] = 99
    end,
    function(f)
        f.foreign(f.groups[1].bindings[1])
    end,
    function(f)
        f.pending = true
    end,
}) do
    f = populated()
    dialog = M.new(f.host).open(f.groups)
    alter(f)
    assert(
        not pcall(dialog.on_map, 'source:1', 'weapon:1:material:1') and f.calls == 0,
        'Stale import/configuration/CurrentSource receipt reached the writer'
    )
end
f = populated()
f.fail = true
dialog = M.new(f.host).open(f.groups)
local before = f.groups[1].bindings[1].current
assert(
    not pcall(dialog.on_auto_map, { primary = true }) and f.calls == 1 and f.groups[1].bindings[1].current == before,
    'Refused atomic plan changed receipts'
)
f = populated()
f.runtime.supports_target_subsets = false
dialog = M.new(f.host).open(f.groups)
assert(
    not pcall(dialog.on_map, 'source:1', 'weapon:1:material:1') and f.calls == 0,
    'Mapping silently used a runtime without exact subsets'
)
print(
    'PASS weapon mapping: 4-column chooser, sorted per-weapon rollover, exact Pattern subsets, repeated mapping receipts, whole-plan stale guards and atomic host contract'
)
