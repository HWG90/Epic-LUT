local E = dofile('src/presets/gear_export.lua')
local a, b = { original = 1, current = 2, save_key = 'a' }, { original = 3, current = 3, save_key = 'b', helmet = true }
local menu, writes, scans = {}, {}, 0
local groups = { { bindings = { a } }, { bindings = { b } } }
local original = { [1] = { resource = '1111111111111111', width = 23 }, [3] = { resource = '3333333333333333', width = 23 } }
local draft = { width = 23, draft = true }
local e = E.new({ engine = {}, gear_catalog = { kind = function(b) return b.helmet and 'helmet' or 'armor' end } }, {
    stop_identification = function() return true end,
    refresh = function() scans = scans + 1 end,
    menu = function() return menu end,
    selected = function() return nil end, current_lut = function() return 1 end,
    groups = function() return groups end,
    original = function(o) return original[o] end,
    label = function(id) return id == '1111111111111111' and 'Desert' end,
    draft = function(index) return index == 1 and draft end,
    applied_document = function() return { width = 23 } end,
    present = function() return true end, binding = function(b) return b.current end,
    export_preference = function() return nil, false end,
    export_control = function() return nil, false end,
    has_patterns = function() return false end,
    write_patch = function(name, entries)
        writes[#writes + 1] = { name = name, entries = entries }
        return 'output', #entries
    end,
})
assert(e.choose_patches('Test'))
local dialog = menu.lut_apply_dialog
assert(scans == 1 and #writes == 0 and dialog.columns[1].items[1].label == 'Desert')
assert(dialog.columns[1].items[1].checked and not dialog.columns[2].items[1].checked)
assert(dialog.on_apply({ [1] = true, [2] = true }))
assert(#writes == 1 and #writes[1].entries == 2 and writes[1].entries[1].document == draft)
writes = {}; dialog.combine = false
assert(dialog.on_apply({ [1] = true, [2] = true }))
assert(#writes == 2 and writes[1].name == 'Desert' and writes[2].name == 'Test Helmet LUT 1')
writes = {}; b.current = 4
assert(not pcall(dialog.on_apply, { [1] = true, [2] = true }) and #writes == 0)
b.current = 3; menu.lut_apply_dialog = nil
assert(not pcall(dialog.on_apply, { [1] = true }) and #writes == 0)
-- Companion discovery is shared across the whole explicit export operation.
local pattern_scans = 0
local p = { original = 5, current = 5, save_key = 'p' }
original[5] = { resource = '5555555555555555', width = 3, height = 1 }
-- Reuse captured host dependencies through the production closure.
local function upvalue(f, key)
    for i = 1, 30 do local n, v = debug.getupvalue(f, i); if n == key then return v end end
end
local host = upvalue(e.pattern_entries, 'host')
local modules = upvalue(e.pattern_entries, 'modules')
modules.engine.PATTERN_SLOT = 1
modules.export_pairing = { live = function() return { p } end }
host.has_patterns = function() return true end
host.scan_patterns = function() pattern_scans = pattern_scans + 1; return {} end
host.material_key = function() return 'same' end
assert(e.choose_patches('Companions'))
assert(menu.lut_apply_dialog.on_apply({ [1] = true, [2] = true }))
assert(pattern_scans == 1 and #writes == 1 and #writes[1].entries == 4)
print('PASS selected patch export: names, draft pixels, combined/separate assignments, stale/cancel guards and idle discovery')
