-- Imported palette editing. Source pixels are distinct from retained GPU buffers.
local E = {}
function E.new(m, document, note, save, presets, live_document, open_export, save_patch)
    local ffi = require('ffi')
    local self = { undo = {}, redo = {}, busy = false, value_scroll = 0 }
    local preset_files = m.lut_files.new(
        presets,
        { dds = m.dds, read = m.file_io.read, row_names = m.windows and m.windows.row_presets }
    )
    local color_columns = { 1, 3, 6, 7, 13, 15, 17, 18, 19, 20 }
    local color_labels = {}
    for _, column in ipairs(color_columns) do
        color_labels[#color_labels + 1] = m.semantics.columns[column]
    end
    function self.refresh_presets()
        if not self.handle then
            return
        end
        self.preset_names = preset_files.row_names()
        local choices = { 'New preset...' }
        for _, name in ipairs(self.preset_names) do
            choices[#choices + 1] = name
        end
        self.api.mods[self.handle.id].controls.row_preset_select.choices = choices
        local current = self.handle.get('row_preset')
        local selected = 1
        for i, name in ipairs(self.preset_names) do
            if name == current then
                selected = i + 1
            end
        end
        self.busy = true
        assert(self.handle.set('row_preset_select', selected))
        self.busy = false
    end
    local function snapshot(d)
        return ffi.string(d.data, d.width * d.height * 16)
    end
    local function remember()
        local d = assert(document(), 'Import a palette first')
        d.revision = (d.revision or 0) + 1
        self.undo[#self.undo + 1] = snapshot(d)
        if #self.undo > 64 then
            table.remove(self.undo, 1)
        end
        self.redo = {}
        return d
    end
    local function rgb(data, i)
        local values = {}
        for ch = 0, 2 do
            values[#values + 1] = math.floor(math.max(0, math.min(1, data[i + ch])) * 255 + 0.5)
        end
        return values
    end
    local function change(column, channel, value)
        if self.busy then
            return
        end
        local d = remember()
        local i = m.semantics.index(self.handle.get('edit_row'), column, channel, d.width, d.height)
        d.data[i] = value
        self.sync()
        note('Palette edited. Live preview updates automatically.')
    end
    function self.focus_cell(row, column)
        self.sync()
        assert(self.handle.set('edit_row', row))
        assert(self.handle.set('edit_column', column))
        for index, col in ipairs(color_columns) do
            if col == column then
                assert(self.handle.set('color_field', index))
                break
            end
        end
        self.open_row = row
        self.focus_column = column
        self.selection = { r1 = row, r2 = row, c1 = column, c2 = column }
        self.sync()
    end
    function self.paint_rgb(row, column, hex)
        self.focus_cell(row, column)
        local d = remember()
        local at = m.semantics.index(row, column, 1, d.width, d.height)
        local r, g, b = m.palette.rgb(hex)
        d.data[at], d.data[at + 1], d.data[at + 2] = r, g, b
        self.sync()
        return true
    end
    function self.sync()
        if not self.handle or self.busy then
            return
        end
        local d = document()
        local mod = self.api.mods[self.handle.id]
        for _, id in ipairs({
            'edit_row',
            'advanced_row',
            'color_field',
            'cell_color',
            'edit_column',
            'cell_r',
            'cell_g',
            'cell_b',
            'cell_a',
            'unlock',
            'shader_mode',
            'detail_texture',
            'camo_pattern',
            'grid_tool',
            'grid_channel',
        }) do
            mod.controls[id].disabled = not d
        end
        if not d then
            return
        end
        if self.document ~= d then
            self.document = d
            self.undo = {}
            self.redo = {}
            self.open_row = nil
            self.value_scroll = 0
            self.selection = nil
            if not d.original then
                d.original = ffi.new('float[?]', d.width * d.height * 4)
                ffi.copy(d.original, d.data, d.width * d.height * 16)
            end
        end
        local h = self.handle
        mod.controls.cell_color.picker_begin = function()
            self.color_session =
                { document = d, before = snapshot(d), row = h.get('edit_row'), column = h.get('edit_column') }
        end
        mod.controls.cell_color.picker_preview = function(color, alpha)
            local session = assert(self.color_session)
            assert(document() == session.document, 'Editor target changed; reopen the picker')
            local current_pixels = snapshot(d)
            local at = m.semantics.index(session.row, session.column, 1, d.width, d.height)
            local original = ffi.new('float[?]', d.width * d.height * 4)
            ffi.copy(original, session.before, #session.before)
            local before = rgb(original, at)
            for ch = 1, 3 do
                d.data[at + ch - 1] = color[ch] == before[ch] and original[at + ch - 1] or color[ch] / 255
            end
            d.data[at + 3] = alpha
            if snapshot(d) ~= current_pixels then
                session.changed = true
                d.revision = (d.revision or 0) + 1
                self.sync()
            end
        end
        mod.controls.cell_color.picker_end = function(commit)
            local session = self.color_session
            self.color_session = nil
            if not session or document() ~= session.document then
                return
            end
            if commit then
                if snapshot(d) ~= session.before then
                    self.undo[#self.undo + 1] = session.before
                    self.redo = {}
                end
            elseif session.changed then
                ffi.copy(d.data, session.before, #session.before)
                d.revision = (d.revision or 0) + 1
                self.sync()
            end
        end
        mod.controls.cell_color.picker_alpha = function()
            local at = m.semantics.index(h.get('edit_row'), h.get('edit_column'), 4, d.width, d.height)
            return tonumber(d.data[at])
        end
        mod.controls.cell_color.picker_commit = function(rgb_value, alpha)
            if self.color_session then
                mod.controls.cell_color.picker_preview(rgb_value, alpha)
                return true
            end
            local target = remember()
            local at = m.semantics.index(h.get('edit_row'), h.get('edit_column'), 1, target.width, target.height)
            local before = rgb(target.data, at)
            for ch = 1, 3 do
                if rgb_value[ch] ~= before[ch] then
                    target.data[at + ch - 1] = rgb_value[ch] / 255
                end
            end
            target.data[at + 3] = alpha
            self.sync()
            return true
        end
        mod.controls.scratch_color.picker_alpha = function()
            return h.get('scratch_alpha')
        end
        mod.controls.scratch_color.picker_commit = function(color, alpha)
            local ok, why = h.set_many({
                scratch_color = string.format('#%02X%02X%02X', color[1], color[2], color[3]),
                scratch_alpha = alpha,
            })
            assert(ok, why)
            self.scratch = { color[1], color[2], color[3] }
            return true
        end
        local row = math.min(h.get('edit_row'), d.height)
        local column = h.get('edit_column')
        local rows = {}
        for i = 1, d.height do
            rows[i] = 'Row ' .. i
        end
        mod.controls.edit_row.choices = rows
        mod.controls.advanced_row.choices = rows
        local color_column = h.get('edit_column')
        local i = m.semantics.index(row, color_column, 1, d.width, d.height)
        local values = { edit_row = row, advanced_row = row }
        local r = rgb(d.data, i)
        values.cell_color = string.format('#%02X%02X%02X', r[1], r[2], r[3])
        for ch, name in ipairs({ 'r', 'g', 'b', 'a' }) do
            local index = m.semantics.index(row, column, ch, d.width, d.height)
            local value = tonumber(d.data[index])
            local control = mod.controls['cell_' .. name]
            control.drag_min, control.drag_max, control.step = m.semantics.range(column, ch, value)
            control.min, control.max = -1e10, 1e10 -- Typed floats are independent of the useful drag range.
            control.description = (m.semantics.hints[column] or 'Unconfirmed shader meaning.')
                .. ' Imported value: '
                .. string.format('%.8g', d.original[index])
            values['cell_' .. name] = value
        end
        for _, spec in ipairs({
            { 'shader_mode', 1, 4, 0, 3 },
            { 'detail_texture', 2, 1, 0, 25 },
            {
                'camo_pattern',
                22,
                4,
                -1,
                5,
            },
        }) do
            local id, col, ch, lo, hi = unpack(spec)
            local value = tonumber(d.data[m.semantics.index(row, col, ch, d.width, d.height)])
            local choices = {}
            for v = lo, hi do
                local label = id == 'shader_mode' and (v == 0 and 'Off / default' or 'Shader mode ' .. v)
                    or id == 'detail_texture' and 'Bump map ' .. v
                    or (v == -1 and 'Off' or 'Pattern ' .. v)
                choices[#choices + 1] = label
            end
            local selected = value % 1 == 0 and value >= lo and value <= hi and value - lo + 1
            if not selected then
                choices[#choices + 1] = 'Custom: ' .. string.format('%.7g', value)
                selected = #choices
            end
            mod.controls[id].choices = choices
            values[id] = selected
        end
        self.busy = true
        local ok, why = h.set_many(values)
        self.busy = false
        assert(ok, why)
        for ch, name in ipairs({ 'r', 'g', 'b', 'a' }) do
            mod.controls['cell_' .. name].disabled = not (
                h.get('unlock') or (m.semantics.is_color(d.width, column) and ch <= 3)
            )
        end
        for _, id in ipairs({ 'shader_mode', 'detail_texture', 'camo_pattern' }) do
            mod.controls[id].disabled = not h.get('unlock')
        end
        for _, page in ipairs(mod.pages) do
            if page.id == 'colors' then
                page.controls = { mod.controls.edit_row, mod.controls.color_field, mod.controls.cell_color }
                for region = 1, d.height do
                    local selected = region
                    local index = m.semantics.index(region, color_column, 1, d.width, d.height)
                    page.controls[#page.controls + 1] = {
                        type = 'text',
                        label = 'Row ' .. region,
                        swatch_label = true,
                        page = page,
                        groups = {},
                        depth = 0,
                        swatches = {
                            {
                                rgb = rgb(d.data, index),
                                row = 'Now',
                                owner = mod,
                                control = mod.controls.cell_color,
                                prepare = function()
                                    assert(h.set('edit_row', selected))
                                    self.sync()
                                end,
                            },
                            { rgb = rgb(d.original, index), row = 'Imported' },
                        },
                    }
                end
                page.controls[#page.controls + 1] = mod.controls.reset_color
            end
        end
    end
    local function history(from, to)
        local d = assert(document(), 'Import first')
        local value = table.remove(from)
        if not value then
            return note('No more history')
        end
        to[#to + 1] = snapshot(d)
        ffi.copy(d.data, value, #value)
        d.revision = (d.revision or 0) + 1
        self.sync()
        return note('Palette history updated. Live preview updates automatically.')
    end
    function self.attach(api, handle)
        self.api = api
        self.handle = handle
        assert(handle.set('scratch_alpha', 1)) -- New scratch starts fully opaque each session.
        self.sync()
        self.refresh_presets()
        for _, page in ipairs(api.mods[handle.id].pages) do
            if page.id == 'colors' then
                page.render_layout = self.layout
                page.on_wheel = self.wheel
            end
        end
    end
    function self.reset()
        local d = remember()
        ffi.copy(d.data, d.original, d.width * d.height * 16)
        self.sync()
        return note('Custom edits reset to the imported palette. Apply to update the live LUTs.')
    end
    function self.wheel(x, y, delta)
        local b = self.value_bounds
        if b and x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
            self.value_scroll = math.max(0, math.min(self.value_max or 0, self.value_scroll - delta / 120 * 90))
            return true
        end
    end
    local channels = { { 1, 2, 3 }, { 1, 2, 3, 4 }, { 1 }, { 2 }, { 3 }, { 4 } }
    local function editable(d, column, channel)
        return self.handle.get('unlock') or (m.semantics.is_color(d.width, column) and channel <= 3)
    end
    local function paint(row, column)
        local d = assert(document(), 'Import first')
        local selected = channels[self.handle.get('grid_channel')]
        for _, ch in ipairs(selected) do
            assert(editable(d, column, ch), 'Unlock advanced edits to paint non-color channels')
        end
        d = remember()
        local r, g, b = m.palette.rgb(self.handle.get('scratch_color'))
        local values = { r, g, b, self.handle.get('scratch_alpha') }
        for _, ch in ipairs(selected) do
            d.data[m.semantics.index(row, column, ch, d.width, d.height)] = values[ch]
        end
        self.sync()
        return note('Pixel painted. Live preview updates automatically.')
    end
    function self.copy_selection()
        local d = assert(document(), 'Import first')
        local s = self.selection
            or {
                r1 = self.handle.get('edit_row'),
                r2 = self.handle.get('edit_row'),
                c1 = self.handle.get('edit_column'),
                c2 = self.handle.get('edit_column'),
            }
        local w, h = s.c2 - s.c1 + 1, s.r2 - s.r1 + 1
        local data = ffi.new('float[?]', w * h * 4)
        for r = 0, h - 1 do
            ffi.copy(data + r * w * 4, d.data + m.semantics.index(s.r1 + r, s.c1, 1, d.width, d.height), w * 16)
        end
        self.clip = { width = w, height = h, data = data }
        return note('Copied rows ' .. s.r1 .. '-' .. s.r2 .. ', columns ' .. s.c1 .. '-' .. s.c2 .. ' (full RGBA)')
    end
    function self.paste_selection()
        local d = assert(document(), 'Import first')
        local clip = assert(self.clip, 'Copy a selection first')
        local row, column = self.handle.get('edit_row'), self.handle.get('edit_column')
        assert(row + clip.height - 1 <= d.height and column + clip.width - 1 <= d.width, 'Clipboard does not fit here')
        local selected = channels[2] -- Clipboard paste restores full RGBA, independent of paint channel.
        for c = column, column + clip.width - 1 do
            for _, ch in ipairs(selected) do
                assert(editable(d, c, ch), 'Unlock advanced edits to paste non-color channels')
            end
        end
        d = remember()
        for r = 0, clip.height - 1 do
            for c = 0, clip.width - 1 do
                for _, ch in ipairs(selected) do
                    d.data[m.semantics.index(row + r, column + c, ch, d.width, d.height)] =
                        clip.data[(r * clip.width + c) * 4 + ch - 1]
                end
            end
        end
        self.sync()
        return note('Pasted ' .. clip.width .. ' columns into row ' .. row .. ', column ' .. column .. ' (full RGBA)')
    end
    function self.reset_part(full_row)
        local d = assert(document(), 'Load a LUT first')
        local row, column = self.handle.get('edit_row'), self.handle.get('edit_column')
        local width = full_row and d.width or 1
        local at = m.semantics.index(row, full_row and 1 or column, 1, d.width, d.height)
        assert(d.original, 'Original table unavailable')
        d = remember()
        ffi.copy(d.data + at, d.original + at, width * 16)
        self.sync()
        return note(
            'Reset row ' .. row .. (full_row and ' (all columns)' or ', column ' .. column) .. ' to its loaded values'
        )
    end
    function self.is_dirty()
        local d = document()
        if not d or not d.original then
            return false
        end
        return snapshot(d) ~= (d.saved_pixels or ffi.string(d.original, d.width * d.height * 16))
    end
    function self.move_selection(row, column)
        local d = assert(document(), 'Import first')
        local s = assert(self.selection, 'Select pixels first')
        local w, h = s.c2 - s.c1 + 1, s.r2 - s.r1 + 1
        assert(row + h - 1 <= d.height and column + w - 1 <= d.width, 'Selection does not fit here')
        local selected = channels[self.handle.get('grid_channel')]
        for c = 0, w - 1 do
            for _, ch in ipairs(selected) do
                assert(
                    editable(d, s.c1 + c, ch) and editable(d, column + c, ch),
                    'Unlock advanced edits to move non-color channels'
                )
            end
        end
        self.copy_selection()
        local clip = self.clip
        d = remember()
        for r = s.r1, s.r2 do
            for c = s.c1, s.c2 do
                for _, ch in ipairs(selected) do
                    d.data[m.semantics.index(r, c, ch, d.width, d.height)] = 0
                end
            end
        end
        for r = 0, h - 1 do
            for c = 0, w - 1 do
                for _, ch in ipairs(selected) do
                    d.data[m.semantics.index(row + r, column + c, ch, d.width, d.height)] =
                        clip.data[(r * w + c) * 4 + ch - 1]
                end
            end
        end
        self.selection = { r1 = row, r2 = row + h - 1, c1 = column, c2 = column + w - 1 }
        self.sync()
        return note('Selection moved. Live preview updates automatically.')
    end
    function self.preview(bounds, live)
        local d = live and live_document and live_document() or (not live and document())
        local commands = {}
        if not d then
            return {
                {
                    type = 'text',
                    x = bounds.x,
                    y = bounds.y + bounds.h / 2,
                    text = 'Original live LUT pixels unavailable for this resource.',
                    size = 11 * bounds.scale,
                    c = { 224, 230, 234 },
                    a = 1,
                },
            }
        end
        local scale = bounds.scale
        local cell = bounds.w / d.width
        local rowh = (bounds.h - 24 * scale) / d.height
        local function label(x, y, value, size)
            commands[#commands + 1] =
                { type = 'text', x = x, y = y, text = value, size = size * scale, c = { 224, 230, 234 }, a = 1 }
        end
        for column = 1, d.width do
            label(bounds.x + (column - 1) * cell, bounds.y + bounds.h - 12 * scale, 'Col ' .. column, 8)
        end
        for row = 1, d.height do
            for column = 1, d.width do
                local at = ((row - 1) * d.width + column - 1) * 4
                local x = bounds.x + (column - 1) * cell
                local y = bounds.y + bounds.h - 24 * scale - row * rowh
                commands[#commands + 1] = {
                    type = 'rect',
                    x = x,
                    y = y,
                    w = cell - 2 * scale,
                    h = rowh - 2 * scale,
                    c = { 30, 35, 40 },
                    a = 1,
                }
                commands[#commands + 1] = {
                    type = 'rect',
                    x = x + 2 * scale,
                    y = y + rowh - 12 * scale,
                    w = cell - 6 * scale,
                    h = 9 * scale,
                    c = rgb(d.data, at),
                    a = 1,
                }
                for ch = 0, 3 do
                    label(
                        x + 2 * scale,
                        y + rowh - (24 + ch * 10) * scale,
                        ({ 'R', 'G', 'B', 'A' })[ch + 1] .. ' ' .. string.format('%.5g', tonumber(d.data[at + ch])),
                        7
                    )
                end
            end
        end
        return commands
    end
    self.layout = m.lut_editor_view.new({
        editor = self,
        semantics = m.semantics,
        ui_core = m.ui_core,
        format_resource_id = m.format_resource_id,
        document = document,
        note = note,
        paint = paint,
        rgb = rgb,
        swatch = m.palette.swatch,
        editable = editable,
        color_columns = color_columns,
    })
    self.pages = m.lut_editor_controls.new({
        preset_files = preset_files,
        editor = self,
        palette = m.palette,
        semantics = m.semantics,
        document = document,
        note = note,
        save = save,
        open_export = open_export,
        save_patch = save_patch,
        remember = remember,
        change = change,
        history = history,
        color_columns = color_columns,
        color_labels = color_labels,
    })
    return self
end
return E
