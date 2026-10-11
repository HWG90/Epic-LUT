local ffi = require('ffi')
local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local DDS = dofile('src/core/dds.lua')
local Text = dofile('src/platform/text_editor.lua')
local api = Core.new()
local document = { width = 23, height = 8, data = ffi.new('float[736]') }
for index = 0, 735 do
    document.data[index] = index / 100 - 0.25
end
local source, blue = ffi.new('float[92]'), ffi.new('float[92]')
for column = 0, 22 do
    source[column * 4], source[column * 4 + 1], source[column * 4 + 2], source[column * 4 + 3] =
        column / 22, 0.4, 0.6, 1
    blue[column * 4], blue[column * 4 + 1], blue[column * 4 + 2], blue[column * 4 + 3] = 0.1, 0.2, 0.8, 1
end
source[3], source[7], source[91] = 0.25, 2.75, -0.5
local files = { DAVE2 = DDS.encode(source, 23, 1), Blue = DDS.encode(blue, 23, 1) }
local reads, writes = 0, 0
local m = {
    ui_core = Core,
    dds = DDS,
    lut_files = dofile('src/presets/lut_files.lua'),
    lut_editor_controls = dofile('src/editor/lut_editor_controls.lua'),
    lut_editor_view = dofile('src/editor/lut_editor_view.lua'),
    editor_tools = dofile('src/editor/editor_tools.lua'),
    semantics = dofile('src/core/semantics.lua'),
    palette = dofile('src/core/palette.lua'),
    windows = {
        row_presets = function()
            return { 'DAVE2', 'Blue' }
        end,
    },
    file_io = {
        read = function(path)
            reads = reads + 1
            local name = path:match('/row%-(.-)%.dds$')
            return assert(files[name], 'Missing row')
        end,
    },
}
local editor = dofile('src/editor/lut_editor.lua').new(m, function()
    return document
end, function(value)
    return value
end, function()
    writes = writes + 1
    return true
end, 'fixture-presets')
local handle = api.register({ id = 'row_preview', name = 'Epic LUT', pages = editor.pages() })
editor.attach(api, handle)
local mod = api.mods[handle.id]
mod.tabs_top = true
assert(handle.set('row_preset', 'DAVE2'))
editor.tools.open('rows')
local frame_width, frame_height = 1350, 420
mod.pages[1].render_layout = function(ui)
    if editor.tools.is_docked() then
        editor.tools.dock(ui, { x = ui.x + 8, y = ui.y + 30, w = frame_width, h = frame_height })
    end
    editor.tools.popup(ui)
end
local menu = Menu.new(api, function(value, size)
    return #value * size * 0.5
end, Text)
menu.visible, menu.epic_typography, menu.compact_fonts = true, true, true
menu.window_width, menu.window_height = 1850, 1050
menu.text_metrics = function(size)
    return { min_y = -size * 0.2, max_y = size * 0.85, height = size * 1.05 }
end
local function compose()
    local commands = menu.compose(1920, 1080)
    for _, command in ipairs(commands) do
        assert(not (command.text and command.text:find('attempt to ', 1, true)), command.text)
    end
    return commands
end
local function label(commands, text)
    for _, command in ipairs(commands) do
        if (command.full_text or command.text) == text then
            return command
        end
    end
end
local function cells(commands)
    local b, w, output = assert(editor.tools.row_preview_bounds), menu.window_bounds, {}
    local left, bottom = w.x + b.x * w.scale, w.y + b.y * w.scale
    local right, top = left + b.w * w.scale, bottom + b.h * w.scale
    for _, command in ipairs(commands) do
        if
            command.type == 'rect'
            and command.ui_role == 'swatch_border'
            and command.x >= left - 0.01
            and command.x + command.w <= right + 0.01
            and command.y >= bottom - 0.01
            and command.y + command.h <= top + 0.01
        then
            assert(
                command.w / w.scale <= 40.01 and math.abs(command.w - command.h) < 0.01,
                'Saved row preview cell expanded or lost square geometry'
            )
            output[#output + 1] = command
        end
    end
    table.sort(output, function(a, b)
        return a.x < b.x
    end)
    return output
end
local original = ffi.string(document.data, 2944)
local history, revision, selection = #editor.undo, document.revision, editor.selection
local preview = assert(editor.row_preset_preview('DAVE2'))
assert(
    preview.width == 23
        and preview.height == 1
        and preview.read_only
        and ffi.string(preview.data, 368) == ffi.string(source, 368)
)
assert(editor.row_preset_preview('DAVE2') == preview and reads == 1, 'Saved row is reloaded on every preview draw')
local commands = compose()
assert(
    label(commands, 'Saved row: DAVE2') and editor.tools.row_preview_bounds.beside and #cells(commands) == 23,
    'Wide Rows Tools does not show its 23-column saved preset beside the actions'
)
assert(
    editor.tools.row_preview_bounds.x >= editor.tools.content_bounds.x + editor.tools.content_bounds.w,
    'Saved row preview overlaps the left action/preset controls'
)
local before_reads = reads
compose()
compose()
assert(reads == before_reads, 'Cached preview repeatedly reads the DDS file')
local before_alpha = ffi.string(preview.data, 368)
assert(handle.set('show_alpha', true))
commands = compose()
assert(ffi.string(preview.data, 368) == before_alpha, 'Show Alpha mutated the saved row data')
local first, second = cells(commands)[1], cells(commands)[2]
local fills, second_fills = 0, 0
for _, command in ipairs(commands) do
    if
        command.ui_role == 'swatch_fill'
        and command.x > first.x
        and command.x + command.w < first.x + first.w
        and command.y > first.y
        and command.y + command.h <= first.y + first.h
    then
        fills = fills + 1
    end
    if
        command.ui_role == 'swatch_fill'
        and command.x > second.x
        and command.x + command.w < second.x + second.w
        and command.y > second.y
        and command.y + command.h <= second.y + second.h
    then
        second_fills = second_fills + 1
    end
end
assert(
    fills > 1 and second_fills == 1,
    'Valid opacity did not show checkerboard or raw HDR alpha was treated as opacity'
)
local x, y = first.x + first.w / 2, first.y + first.h / 2
for _, down in ipairs({ true, false }) do
    menu.tick({
        down = function(key)
            return down and key == 1
        end,
        mouse = function()
            return x, y
        end,
    }, 0)
end
assert(
    not menu.color_picker and editor.selection == selection and #editor.undo == history,
    'Clicking a read-only saved row preview edited/opened the real document'
)

-- Draft names can preview an existing file while the saved name and real LUT
-- remain unchanged. Missing/new names get a cached, inert explanation.
menu.text_edit = { mod = mod, control = mod.controls.row_preset, text = 'Blue', replace = false }
commands = compose()
assert(
    label(commands, 'Saved row: Blue')
        and handle.get('row_preset') == 'DAVE2'
        and editor.tools.row_preview_bounds.document.data[2] == blue[2],
    'Draft name did not show its saved-row preview'
)
menu.key(27)
assert(handle.set('row_preset', 'Missing'))
commands = compose()
assert(label(commands, 'Saved row not found. Save this name to create it.') and #cells(commands) == 0)
before_reads = reads
compose()
assert(reads == before_reads, 'Missing-row hint caused repeated filesystem reads')
assert(handle.set('row_preset', 'DAVE2'))
source[0] = 0.8125
files.DAVE2 = DDS.encode(source, 23, 1)
editor.refresh_presets()
local replaced = assert(editor.row_preset_preview('DAVE2'))
assert(
    replaced ~= preview and replaced.data[0] == 0.8125,
    'Save/import/delete preset refresh did not invalidate preview cache'
)

for _, docked in ipairs({ true, false }) do
    for _, font in ipairs({ 12, 20 }) do
        for _, scale in ipairs({ 0.7, 1.15 }) do
            menu.font_size, menu.ui_scale = font, scale
            editor.tools.set_docked(docked)
            frame_width, frame_height = docked and 560 or 620, docked and 300 or 540
            editor.tools.scroll = 0
            local start_commands = compose()
            assert(not editor.tools.row_preview_bounds.beside, 'Narrow Rows preview squeezed beside the controls')
            local thumb
            for _, command in ipairs(start_commands) do
                if command.scrollbar == (docked and 'editor_tools_docked' or 'editor_tools_rows') then
                    thumb = command
                end
            end
            if editor.tools.maximum > 0 then
                assert(thumb, 'Wrapped saved row preview has no scroll control')
                local tx, ty = thumb.x + thumb.w / 2, thumb.y + thumb.h / 2
                for _, point in ipairs({ { tx, ty, true }, { tx, ty - 2000, true }, { tx, ty - 2000, false } }) do
                    menu.tick({
                        down = function(key)
                            return point[3] and key == 1
                        end,
                        mouse = function()
                            return point[1], point[2]
                        end,
                    }, 0)
                end
            end
            assert(
                editor.tools.scroll >= editor.tools.maximum - 1,
                'Rows scrollbar cannot reach its saved preset preview'
            )
            commands = compose()
            assert(
                label(commands, 'Saved row: DAVE2') and #cells(commands) == 23,
                'Wrapped Rows preview is not reachable within its docked/floating scroll range'
            )
            local b, w = editor.tools.row_preview_bounds, menu.window_bounds
            local outer = editor.tools.bounds
            local left, bottom, right, top
            if docked then
                left, bottom = w.x + outer.x * w.scale, w.y + outer.y * w.scale
                right, top = left + outer.w * w.scale, bottom + outer.h * w.scale
            else
                for _, command in ipairs(commands) do
                    if command.window_frame == 'floating:editor_tools' then
                        local f = command.frame_bounds
                        left, bottom, right, top = f.x, f.y, f.x + f.w, f.y + f.h
                        break
                    end
                end
            end
            assert(left)
            for _, cell in ipairs(cells(commands)) do
                assert(
                    cell.x >= left and cell.y >= bottom and cell.x + cell.w <= right and cell.y + cell.h <= top,
                    'Saved row preview escaped the Tools frame'
                )
            end
            assert(b.document.read_only and not menu.color_picker)
        end
    end
end
assert(
    ffi.string(document.data, 2944) == original
        and document.revision == revision
        and #editor.undo == history
        and editor.selection == selection
        and writes == 0,
    'Saved row preview changed actual editor bytes, revision, history, selection or writes'
)
print(
    'PASS saved row preview: cached exact read-only DDS, right-side/wrapped23 cells, alpha-safe visuals, draft/missing names, invalidation and docked/floating font/scale containment'
)
