local ffi = require('ffi')
local core = dofile('vendor/menu/core.lua')
local api = core.new({
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
})
local function make_document(base)
    local d = { width = 23, height = 32, data = ffi.new('float[2944]') }
    for i = 0, 2943 do
        d.data[i] = base + (i % 97) / 8
    end
    ffi.cast('uint32_t *', d.data)[4 * 23 * 4 + 39] = 0x80000000
    d.data[16] = 23.375
    d.data[33] = -2.5
    return d
end
local document = make_document(20)
local m = {
    ui_core = core,
    lut_files = dofile('src/presets/lut_files.lua'),
    file_io = dofile('src/core/file_io.lua'),
    dds = dofile('src/core/dds.lua'),
    palette = dofile('src/core/palette.lua'),
    semantics = dofile('src/core/semantics.lua'),
    lut_editor_controls = dofile('src/editor/lut_editor_controls.lua'),
    lut_editor_view = dofile('src/editor/lut_editor_view.lua'),
    windows = {
        row_presets = function()
            return {}
        end,
    },
}
local editor = dofile('src/editor/lut_editor.lua').new(m, function()
    return document
end, function(value)
    return value
end, function()
    return true
end, 'tests/tmp/presets')
local h = api.register({ id = 'row_clipboard', name = 'Epic LUT', pages = editor.pages() })
editor.attach(api, h)
assert(h.set('unlock', true))
local row_bytes = 23 * 16
local function bytes()
    return ffi.string(document.data, 32 * row_bytes)
end
local function selected_rows(first, last)
    editor.select_rows(first, last)
    assert(h.set('edit_row', last) and h.set('edit_column', 23)) -- Last drag endpoint is not the paste anchor.
end
local initial = bytes()
selected_rows(1, 2)
assert(editor.selection.rows and editor.selection.c1 == 1 and editor.selection.c2 == 23)
assert(h.activate('copy_selection'))
assert(editor.clip.width == 23 and editor.clip.height == 2)
local two_rows = ffi.string(editor.clip.data, 2 * row_bytes)
selected_rows(10, 11)
local count = #editor.undo
assert(h.activate('paste_selection'))
local expected = initial:sub(1, 9 * row_bytes) .. two_rows .. initial:sub(11 * row_bytes + 1)
assert(bytes() == expected, 'Two rows pasted at the last endpoint or changed other rows')
assert(
    #editor.undo == count + 1 and editor.selection.r1 == 10 and editor.selection.r2 == 11,
    'Row block did not create one undo/selection'
)
assert(h.activate('undo') and bytes() == initial, 'Two-row paste undo was not exact')
selected_rows(6, 4)
assert(editor.selection.r1 == 4 and editor.selection.r2 == 6, 'Reverse row range was not normalized')
assert(h.activate('copy_selection') and editor.clip.height == 3)
local three_rows = ffi.string(editor.clip.data, 3 * row_bytes)
assert(three_rows == initial:sub(3 * row_bytes + 1, 6 * row_bytes), 'Three-row copy lost material/alpha values')
selected_rows(15, 17)
count = #editor.undo
assert(h.activate('paste_selection'))
expected = initial:sub(1, 14 * row_bytes) .. three_rows .. initial:sub(17 * row_bytes + 1)
assert(bytes() == expected and #editor.undo == count + 1, 'Three rows pasted outside the destination set')
assert(h.activate('undo') and bytes() == initial)
-- The immutable clipboard survives changing to another 32-row document.
document = make_document(70)
editor.sync()
assert(not editor.paste_anchor and not editor.selection, 'New document retained an old selection anchor')
local other = bytes()
selected_rows(29, 31)
assert(h.activate('paste_selection'))
expected = other:sub(1, 28 * row_bytes) .. three_rows .. other:sub(31 * row_bytes + 1)
assert(bytes() == expected and #editor.undo == 1, 'Cross-document paste lost rows or exact float bits')
assert(h.activate('undo') and bytes() == other, 'Cross-document row paste undo failed')
-- Validate the full destination before changing any pixel or undo history.
local unchanged = bytes()
count = #editor.undo
selected_rows(31, 32)
assert(
    not pcall(editor.paste_selection) and bytes() == unchanged and #editor.undo == count,
    'Oversize row paste partially mutated data'
)
selected_rows(12, 14)
assert(h.set('unlock', false))
assert(
    not pcall(editor.paste_selection) and bytes() == unchanged and #editor.undo == count,
    'Locked rows were pasted or partially changed'
)
assert(h.set('unlock', true))
document.read_only = true
assert(not pcall(editor.paste_selection) and bytes() == unchanged, 'Read-only row paste was accepted')
document.read_only = nil
document.stale = true
assert(not pcall(editor.paste_selection) and bytes() == unchanged, 'Stale row paste was accepted')
document.stale = nil
local old = editor.clip.data[0]
editor.clip.data[0] = math.huge
assert(
    not pcall(editor.paste_selection) and bytes() == unchanged and #editor.undo == count,
    'Nonfinite clipboard partially pasted'
)
editor.clip.data[0] = old
-- A rectangular destination uses its top-left even if the drag ended bottom-right.
editor.paste_anchor = nil
editor.selection = { r1 = 8, r2 = 10, c1 = 1, c2 = 23 }
assert(h.set('edit_row', 10) and h.set('edit_column', 23))
assert(h.activate('paste_selection'))
expected = unchanged:sub(1, 7 * row_bytes) .. three_rows .. unchanged:sub(10 * row_bytes + 1)
assert(bytes() == expected, 'Rectangle paste used the drag endpoint instead of the selection top-left')
print(
    'PASS row clipboard: 2/3 complete RGBA rows, reverse ranges, normalized destination anchor, cross-document 32-row paste, exact HDR/signed-zero bits and atomic locks/fit/undo'
)
