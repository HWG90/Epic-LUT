-- Imported palette editing. Source pixels are distinct from retained GPU buffers.
local E = {}
function E.new(m, document, note, save, presets, live_document, open_export, save_patch, save_bulk, import_rows)
    local ffi = require('ffi')
    local self = { undo = {}, redo = {}, busy = false, value_scroll = 0 }
    local channels = { { 1, 2, 3 }, { 1, 2, 3, 4 }, { 1 }, { 2 }, { 3 }, { 4 } }
    local function editable(d, column, channel)
        return d
            and not d.read_only
            and not d.stale
            and (
                self.handle.get('unlock')
                or (m.semantics.is_color(d.width, column) and channel <= 3)
                or d.kind == 'weapon'
                    and d.family == 'pattern'
                    and ((column == 2 and channel <= 3) or (column == 3 and channel == 4))
            )
    end
    function self.can_pick(row, column, mode)
        local d = document()
        if not d or not d.data or d.read_only or d.stale then
            return false, 'Load a current editable LUT first.'
        end
        if self.color_session and self.color_session.document ~= d then
            return false, 'The editor target changed; reopen the picker.'
        end
        row, column = row or self.handle.get('edit_row'), column or self.handle.get('edit_column')
        if row < 1 or row > d.height or column < 1 or column > d.width then
            return false, 'The selected cell is unavailable.'
        end
        for _, ch in ipairs(channels[mode or self.handle.get('grid_channel')]) do
            if not editable(d, column, ch) then
                return false, 'Unlock advanced edits to edit this channel.'
            end
        end
        return true
    end
    local function picker_channel(channel, mode)
        for _, ch in ipairs(channels[mode or self.handle.get('grid_channel')]) do
            if ch == channel then
                return true
            end
        end
        return false
    end
    local preset_files = m.lut_files.new(
        presets,
        { dds = m.dds, read = m.file_io.read, row_names = m.windows and m.windows.row_presets }
    )
    local row_preview_cache, row_preview_order = {}, {}
    function self.row_preset_preview(name)
        if type(name) ~= 'string' or name == '' then
            return nil, 'Choose a saved row preset to preview.'
        end
        local cached = row_preview_cache[name]
        if not cached then
            local ok, data, width, height = pcall(preset_files.load_row, name)
            if ok and data and (width == nil or width == 23) and (height == nil or height == 1) then
                cached = { document = { data = data, width = 23, height = 1, read_only = true, source = name } }
            else
                cached = { hint = 'Saved row not found. Save this name to create it.' }
            end
            row_preview_cache[name] = cached
            row_preview_order[#row_preview_order + 1] = name
            if #row_preview_order > 64 then
                row_preview_cache[table.remove(row_preview_order, 1)] = nil
            end
        end
        return cached.document, cached.hint
    end
    local color_columns = { 1, 3, 6, 7, 13, 15, 17, 18, 19, 20 }
    local color_labels = {}
    for _, column in ipairs(color_columns) do
        color_labels[#color_labels + 1] = m.semantics.columns[column]
    end
    function self.refresh_presets()
        if not self.handle then
            return
        end
        row_preview_cache, row_preview_order = {}, {}
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
        assert(d.data and not d.read_only and not d.stale, 'Load a current editable LUT first')
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
    function self.slider_begin(channel)
        local d = assert(document(), 'Load a LUT first')
        local row, column = self.handle.get('edit_row'), self.handle.get('edit_column')
        assert(not d.stale and editable(d, column, channel), 'Load an editable current LUT first')
        local session = { document = d, before = snapshot(d), row = row, column = column, channel = channel }
        if self.action_history and not self.action_history.busy then
            local ok, before = pcall(self.action_history.capture)
            if ok then session.action_before = before end
        end
        self.active_slider = session
        return session
    end
    function self.slider_preview(session, value)
        local d = session.document
        assert(document() == d and not d.stale and not d.read_only, 'Slider target changed; select a current LUT')
        assert(self.handle.get('edit_row') == session.row and self.handle.get('edit_column') == session.column,
            'Slider target changed; select a value again')
        assert(editable(d, session.column, session.channel), 'This channel is locked')
        local at = m.semantics.index(session.row, session.column, session.channel, d.width, d.height)
        local previous = tonumber(d.data[at])
        d.data[at] = value
        if tonumber(d.data[at]) ~= previous then
            d.revision = (d.revision or 0) + 1
        end
    end
    function self.slider_end(session, commit)
        local d = session.document
        self.active_slider = nil
        if self.action_history and document() == d then
            self.pending_slider = { before = session.action_before, commit = commit }
        end
        if document() ~= d or d.stale or d.read_only or snapshot(d) == session.before then return end
        if commit then
            self.undo[#self.undo + 1] = session.before
            if #self.undo > 64 then table.remove(self.undo, 1) end
            self.redo = {}
            note('Palette edited. Live preview updates automatically.')
        else
            ffi.copy(d.data, session.before, #session.before)
            d.revision = (d.revision or 0) + 1
        end
        self.sync()
    end
    function self.flush_slider_history()
        local pending = self.pending_slider
        self.pending_slider = nil
        if pending and pending.commit and pending.before then
            local ok, why = pcall(function()
                self.action_history.record(pending.before, self.action_history.capture())
            end)
            if not ok then note('Action history unavailable: ' .. tostring(why)) end
        end
    end
    function self.focus_cell(row, column)
        self.value_target = nil
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
        self.paste_anchor = nil
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
    local function scalar_target()
        local d = assert(document(), 'Load a LUT first')
        assert(d.data and not d.stale, 'Load a current LUT first')
        local target = self.value_target
        if target then
            assert(target.document == d, 'Value target changed; select a value again')
        else
            target = {
                row = self.handle.get('edit_row'),
                column = self.handle.get('edit_column'),
                channel = channels[self.handle.get('grid_channel')][1],
            }
        end
        local at = m.semantics.index(target.row, target.column, target.channel, d.width, d.height)
        return d, target, at
    end
    function self.focus_value(row, column, channel)
        local d = assert(document(), 'Load a LUT first')
        m.semantics.index(row, column, channel, d.width, d.height)
        self.value_target = { document = d, row = row, column = column, channel = channel }
        self.sync()
    end
    function self.clear_value_focus()
        self.value_target = nil
    end
    function self.copy_value()
        local d, target, at = scalar_target()
        local value = tonumber(d.data[at])
        assert(value == value and math.abs(value) ~= math.huge, 'Cannot copy a nonfinite value')
        self.value_clip = { bytes = ffi.string(d.data + at, 4), text = string.format('%.9g', value) }
        if self.clipboard and self.clipboard.set then
            local ok, why = self.clipboard.set(self.value_clip.text)
            assert(ok, why or 'System clipboard unavailable')
        end
        return note('Copied ' .. ({ 'R', 'G', 'B', 'A' })[target.channel] .. ' value: ' .. self.value_clip.text)
    end
    function self.paste_value()
        local d, target, at = scalar_target()
        assert(not d.read_only, 'Load an editable LUT first')
        assert(editable(d, target.column, target.channel), 'Unlock advanced edits to paste this channel')
        local text
        if self.clipboard and self.clipboard.get then
            local why
            text, why = self.clipboard.get()
            assert(text, why or 'System clipboard unavailable')
        else
            text = self.value_clip and self.value_clip.text
        end
        assert(type(text) == 'string' and #text <= 128, 'Copy a finite numeric value first')
        text = text:match('^%s*(.-)%s*$')
        local value = tonumber(text)
        assert(value and value == value and math.abs(value) ~= math.huge, 'Paste requires one finite numeric value')
        local typed = ffi.new('float[1]', value)
        assert(math.abs(tonumber(typed[0])) ~= math.huge, 'Value exceeds the float32 range')
        local control =
            self.api.mods[self.handle.id].controls[({ 'cell_r', 'cell_g', 'cell_b', 'cell_a' })[target.channel]]
        if not (control.raw_numeric or control.allow_out_of_range) then
            assert(value >= control.min and value <= control.max, 'Value exceeds the editor numeric range')
        end
        local bytes = self.value_clip and text == self.value_clip.text and self.value_clip.bytes or ffi.string(typed, 4)
        if ffi.string(d.data + at, 4) ~= bytes then
            d = remember()
            ffi.copy(d.data + at, bytes, 4)
            self.sync()
        end
        return note('Pasted one value; other channels are unchanged.')
    end
    function self.copy_resource_id(hash, clipboard)
        local formatted = m.resource_ids
            and m.resource_ids.format(hash, self.handle and self.handle.get('resource_format') == 2)
        if not formatted or formatted == 'unavailable' then
            return false, note('Load a LUT with a known texture ID first.')
        end
        clipboard = clipboard or self.clipboard or self.api and self.api.clipboard
        if not clipboard or not clipboard.set then
            return false, note('System clipboard unavailable.')
        end
        local text = formatted:sub(2, -2)
        local called, copied, why = pcall(clipboard.set, text)
        if not called or not copied then
            return false, note(tostring(called and (why or 'System clipboard unavailable.') or copied))
        end
        return true, note('Copied LUT ID: ' .. text)
    end
    function self.scratch_copy()
        local hex = self.handle.get('scratch_color')
        assert(self.clipboard and self.clipboard.set, 'System clipboard unavailable')
        local ok, why = self.clipboard.set(hex)
        assert(ok, why or 'System clipboard unavailable')
        return note('Copied Scratch HEX: ' .. hex)
    end
    function self.scratch_paste()
        assert(self.clipboard and self.clipboard.get, 'System clipboard unavailable')
        local text, why = self.clipboard.get()
        assert(type(text) == 'string' and #text <= 128, why or 'Paste requires a HEX color')
        text = text:match('^%s*(.-)%s*$'):gsub('^#', ''):gsub('^0[xX]', '')
        assert((#text == 6 or #text == 8) and text:match('^%x+$'), 'Paste a #RRGGBB or #RRGGBBAA HEX color')
        local values = { scratch_color = '#' .. text:sub(1, 6):upper() }
        if #text == 8 then
            values.scratch_alpha = tonumber(text:sub(7, 8), 16) / 255
        end
        local ok, reason = self.handle.set_many(values)
        assert(ok, reason)
        return note('Scratch HEX pasted. Paint a selection to apply it.')
    end
    function self.key(code, ctrl, shift, context)
        context = context or {}
        if code == 46 and not ctrl then
            if context.floating or context.control or not self.grid_bounds then
                return false
            end
            return true, self.reset_selection()
        end
        if not ctrl then
            return false
        end
        self.clipboard = context.clipboard or self.api.clipboard or self.clipboard
        if context.floating == 'editor_scratch' then
            if code == 67 then
                self.scratch_copy()
                return true
            end
            if code == 86 then
                self.scratch_paste()
                return true
            end
            return false
        end
        if context.floating and context.floating ~= 'editor_tools' then
            return false
        end
        if code == 90 or code == 89 then
            local d = assert(document(), 'Load a LUT first')
            assert(not d.read_only and not d.stale, 'Load an editable current LUT first')
            self.handle.activate((code == 89 or shift) and 'redo' or 'undo')
            return true
        end
        if code ~= 67 and code ~= 86 then
            return false
        end
        local scalar =
            { cell_r = 1, cell_g = 2, cell_b = 3, cell_a = 4, shader_mode = 4, detail_texture = 1, camo_pattern = 4 }
        local channel = scalar[context.control]
        if channel then
            local column = ({ shader_mode = 1, detail_texture = 2, camo_pattern = 22 })[context.control]
                or self.handle.get('edit_column')
            self.focus_value(self.handle.get('edit_row'), column, channel)
            if code == 67 then
                self.copy_value()
            else
                self.paste_value()
            end
        else
            self.clear_value_focus()
            if code == 67 then
                self.copy_selection()
            else
                local d = assert(document(), 'Load a LUT first')
                assert(not d.read_only and not d.stale, 'Load an editable current LUT first')
                self.paste_selection()
            end
        end
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
            'copy_value',
            'paste_value',
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
            self.grid_first, self.grid_selected = 1, nil
            self.selection = nil
            self.paste_anchor = nil
            self.value_target = nil
            if not d.original then
                d.original = ffi.new('float[?]', d.width * d.height * 4)
                ffi.copy(d.original, d.data, d.width * d.height * 16)
            end
        end
        local h = self.handle
        mod.controls.cell_color.can_open_picker = function(mode)
            return self.can_pick(nil, nil, mode)
        end
        mod.controls.cell_color.picker_channel_enabled = function(channel, mode)
            local session = self.color_session
            return picker_channel(channel, mode or (session and session.mode))
                and editable(d, session and session.column or h.get('edit_column'), channel)
        end
        mod.controls.cell_color.picker_begin = function(mode)
            assert(self.can_pick(nil, nil, mode))
            self.color_session = {
                document = d,
                before = snapshot(d),
                row = h.get('edit_row'),
                column = h.get('edit_column'),
                mode = mode or h.get('grid_channel'),
            }
        end
        mod.controls.cell_color.picker_preview = function(color, alpha)
            local session = assert(self.color_session)
            assert(document() == session.document, 'Editor target changed; reopen the picker')
            assert(self.can_pick(session.row, session.column, session.mode))
            local current_pixels = snapshot(d)
            local at = m.semantics.index(session.row, session.column, 1, d.width, d.height)
            local original = ffi.new('float[?]', d.width * d.height * 4)
            ffi.copy(original, session.before, #session.before)
            local before = rgb(original, at)
            for ch = 1, 3 do
                if picker_channel(ch, session.mode) then
                    d.data[at + ch - 1] = color[ch] == before[ch] and original[at + ch - 1] or color[ch] / 255
                end
            end
            if picker_channel(4, session.mode) then
                d.data[at + 3] = alpha
            end
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
            assert(self.can_pick())
            local target = remember()
            local at = m.semantics.index(h.get('edit_row'), h.get('edit_column'), 1, target.width, target.height)
            local before = rgb(target.data, at)
            for ch = 1, 3 do
                if picker_channel(ch) and rgb_value[ch] ~= before[ch] then
                    target.data[at + ch - 1] = rgb_value[ch] / 255
                end
            end
            if picker_channel(4) then
                target.data[at + 3] = alpha
            end
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
        local column = math.min(h.get('edit_column'), d.width)
        local weapon_pattern = d.kind == 'weapon' and d.family == 'pattern' and d.width == 3 and d.height == 1
        mod.controls.edit_column.choices = weapon_pattern and { 'Color', 'Mat/Opac', 'Roughness' }
            or m.semantics.columns
        local rows = {}
        for i = 1, d.height do
            rows[i] = 'Row ' .. i
        end
        mod.controls.edit_row.choices = rows
        mod.controls.advanced_row.choices = rows
        local color_column = column
        local i = m.semantics.index(row, color_column, 1, d.width, d.height)
        local values = { edit_row = row, advanced_row = row, edit_column = column }
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
            local value = col <= d.width and tonumber(d.data[m.semantics.index(row, col, ch, d.width, d.height)]) or 0
            local choices = {}
            for v = lo, hi do
                local label = id == 'shader_mode' and (v == 0 and 'Off / default' or 'Shader mode ' .. v)
                    or id == 'detail_texture' and m.semantics.bump_label(v)
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
            mod.controls['cell_' .. name].disabled = not editable(d, column, ch)
        end
        for _, id in ipairs({ 'shader_mode', 'detail_texture', 'camo_pattern' }) do
            mod.controls[id].disabled = weapon_pattern or not h.get('unlock')
        end
        local target = self.value_target
        local value_column = target and target.column or h.get('edit_column')
        local value_channel = target and target.channel or channels[h.get('grid_channel')][1]
        mod.controls.copy_value.disabled = d.stale == true
        mod.controls.paste_value.disabled = d.read_only or d.stale or not editable(d, value_column, value_channel)
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
        self.clipboard = api.clipboard
        self.handle = handle
        assert(handle.set('scratch_alpha', 1)) -- New scratch starts fully opaque each session.
        self.sync()
        self.refresh_presets()
        api.mods[handle.id].controls.row_preset_select.on_delete_choice = function(index, label)
            local name = assert(self.preset_names[index - 1], 'Choose a saved row preset')
            assert(name == label, 'Preset list changed; reopen it before removing a preset')
            preset_files.delete_row(name)
            if handle.get('row_preset') == name then
                assert(handle.set('row_preset', ''))
            end
            self.refresh_presets()
            return true, 'Removed saved row preset: ' .. name
        end
        for _, page in ipairs(api.mods[handle.id].pages) do
            if page.id == 'colors' then
                page.render_layout = self.layout
                page.on_wheel = self.wheel
                page.on_key = self.key
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
        if self.tools and self.tools.wheel and self.tools.wheel(x, y, delta) then
            return true
        end
        if self.pattern_editor and self.pattern_editor.wheel and self.pattern_editor.wheel(x, y, delta) then
            return true
        end
        local quick = self.pattern_quick_bounds
        if quick and x >= quick.x and x <= quick.x + quick.w and y >= quick.y and y <= quick.y + quick.h then
            return false
        end
        local b = self.grid_bounds
        if b and x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
            self.grid_first = math.max(1, math.min((self.grid_max or 0) + 1, (self.grid_first or 1) - delta / 120 * 3))
            self.grid_first = math.floor(self.grid_first)
            return true
        end
        b = self.value_bounds
        if b and x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
            self.value_scroll = math.max(
                0,
                math.min(self.value_max or 0, self.value_scroll - delta / 120 * (self.value_wheel_step or 24))
            )
            return true
        end
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
    function self.set_paste_anchor(row, column)
        local d = assert(document(), 'Load a LUT first')
        m.semantics.index(row, column, 1, d.width, d.height)
        self.paste_anchor = { document = d, row = row, column = column }
    end
    function self.select_rows(anchor_row, endpoint)
        local d = assert(document(), 'Load a LUT first')
        m.semantics.index(anchor_row, 1, 1, d.width, d.height)
        m.semantics.index(endpoint, 1, 1, d.width, d.height)
        self.selection = {
            rows = true,
            anchor_row = anchor_row,
            anchor_col = 1,
            r1 = math.min(anchor_row, endpoint),
            r2 = math.max(anchor_row, endpoint),
            c1 = 1,
            c2 = d.width,
        }
        self.set_paste_anchor(self.selection.r1, 1)
        self.value_target = nil
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
        m.semantics.index(s.r1, s.c1, 1, d.width, d.height)
        m.semantics.index(s.r2, s.c2, 4, d.width, d.height)
        local w, h = s.c2 - s.c1 + 1, s.r2 - s.r1 + 1
        assert(w > 0 and h > 0, 'Invalid selection bounds')
        local data = ffi.new('float[?]', w * h * 4)
        for r = 0, h - 1 do
            ffi.copy(data + r * w * 4, d.data + m.semantics.index(s.r1 + r, s.c1, 1, d.width, d.height), w * 16)
        end
        self.clip = {
            width = w,
            height = h,
            data = data,
            rows = s.rows,
            source_selection = self.selection,
            cursor_row = self.handle.get('edit_row'),
            cursor_column = self.handle.get('edit_column'),
        }
        return note('Copied rows ' .. s.r1 .. '-' .. s.r2 .. ', columns ' .. s.c1 .. '-' .. s.c2 .. ' (full RGBA)')
    end
    function self.paste_selection()
        local d = assert(document(), 'Import first')
        assert(not d.read_only and not d.stale, 'Load an editable current LUT first')
        local clip = assert(self.clip, 'Copy a selection first')
        m.dds.validate(clip.data, clip.width, clip.height)
        local row, column = self.handle.get('edit_row'), self.handle.get('edit_column')
        local anchor, selection = self.paste_anchor, self.selection
        if anchor then
            assert(anchor.document == d, 'Paste target changed; select a destination again')
            row, column = anchor.row, anchor.column
        elseif
            selection
            and (selection ~= clip.source_selection or (row == clip.cursor_row and column == clip.cursor_column))
        then
            row, column = selection.r1, selection.c1
        end
        m.semantics.index(row, column, 1, d.width, d.height)
        assert(row + clip.height - 1 <= d.height and column + clip.width - 1 <= d.width, 'Clipboard does not fit here')
        -- Copy/paste transfers complete existing RGBA values, including camo
        -- selectors. Advanced mode gates typed/painted fields, not this exact
        -- transfer, consistent with the separate Paste Row action.
        -- Pixel bytes are copied only after the entire destination passes validation.
        d = remember()
        for r = 0, clip.height - 1 do
            local target = m.semantics.index(row + r, column, 1, d.width, d.height)
            ffi.copy(d.data + target, clip.data + r * clip.width * 4, clip.width * 16)
        end
        self.selection = {
            rows = clip.rows,
            anchor_row = row,
            anchor_col = column,
            r1 = row,
            r2 = row + clip.height - 1,
            c1 = column,
            c2 = column + clip.width - 1,
        }
        self.paste_anchor = { document = d, row = row, column = column }
        self.value_target = nil
        self.sync()
        return note(
            'Pasted '
                .. clip.height
                .. ' rows x '
                .. clip.width
                .. ' columns at row '
                .. row
                .. ', column '
                .. column
                .. ' (full RGBA, including material and camo controls)'
        )
    end
    function self.restore_arrowhead(scope)
        local d = assert(document(), 'Load a current LUT first')
        assert(self.document == d and d.data and not d.read_only and not d.stale, 'Load an editable current LUT first')
        local source = assert(
            self.arrowhead_source and self.arrowhead_source(d),
            'Arrowhead source unavailable for this LUT; Load Current Gear and wait for snapshots'
        )
        assert(
            source.width == d.width and source.height == d.height,
            'Arrowhead LUT dimensions differ; loaded colors were retained'
        )
        local s
        if scope == 'lut' then
            s = { r1 = 1, r2 = d.height, c1 = 1, c2 = d.width }
        elseif scope == 'row' then
            local row = self.handle.get('edit_row')
            s = { r1 = row, r2 = row, c1 = 1, c2 = d.width }
        else
            assert(scope == 'selection', 'Invalid restoration scope')
            s = self.selection
                or {
                    r1 = self.handle.get('edit_row'),
                    r2 = self.handle.get('edit_row'),
                    c1 = self.handle.get('edit_column'),
                    c2 = self.handle.get('edit_column'),
                }
        end
        assert(s.r1 <= s.r2 and s.c1 <= s.c2, 'Invalid restoration bounds')
        m.semantics.index(s.r1, s.c1, 1, d.width, d.height)
        m.semantics.index(s.r2, s.c2, 4, d.width, d.height)
        d = remember()
        for row = s.r1, s.r2 do
            local at = m.semantics.index(row, s.c1, 1, d.width, d.height)
            ffi.copy(d.data + at, source.data + at, (s.c2 - s.c1 + 1) * 16)
        end
        self.sync()
        return note('Restored Arrowhead ' .. scope .. ' values (full RGBA); other edits retained.')
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
    function self.reset_selection()
        local d = assert(document(), 'Load a LUT first')
        assert(self.document == d, 'Editor target changed; load or select the current LUT first')
        assert(d.data and not d.read_only and not d.stale, 'Load an editable current LUT first')
        assert(d.original, 'Original table unavailable')
        local selected = self.selection
            or {
                r1 = self.handle.get('edit_row'),
                r2 = self.handle.get('edit_row'),
                c1 = self.handle.get('edit_column'),
                c2 = self.handle.get('edit_column'),
            }
        m.semantics.index(selected.r1, selected.c1, 1, d.width, d.height)
        m.semantics.index(selected.r2, selected.c2, 4, d.width, d.height)
        assert(selected.r1 <= selected.r2 and selected.c1 <= selected.c2, 'Invalid selection bounds')
        local width, changed = selected.c2 - selected.c1 + 1, false
        for row = selected.r1, selected.r2 do
            local at = m.semantics.index(row, selected.c1, 1, d.width, d.height)
            if ffi.string(d.data + at, width * 16) ~= ffi.string(d.original + at, width * 16) then
                changed = true
                break
            end
        end
        if not changed then
            return note('Selected cells already match their loaded values.')
        end
        d = remember()
        for row = selected.r1, selected.r2 do
            local at = m.semantics.index(row, selected.c1, 1, d.width, d.height)
            ffi.copy(d.data + at, d.original + at, width * 16)
        end
        self.sync()
        return note('Reset selected cells to their loaded values (full RGBA).')
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
    self.tools = m.editor_tools
        and m.editor_tools.new({
            editor = self,
            document = document,
            note = note,
            ui_core = m.ui_core,
            palette = m.palette,
            default_open_docked = true,
        })
    self.scratch_tool = m.scratch_tool
        and m.scratch_tool.new({
            editor = self,
            document = document,
            ui_core = m.ui_core,
        })
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
        swatch_tooltip = m.palette.value_tooltip,
        editable = editable,
        color_columns = color_columns,
    })
    self.pages = m.lut_editor_controls.new({
        dds = m.dds,
        preset_files = preset_files,
        editor = self,
        palette = m.palette,
        semantics = m.semantics,
        document = document,
        note = note,
        save = save,
        open_export = open_export,
        save_patch = save_patch,
        save_bulk = save_bulk,
        import_rows = import_rows,
        remember = remember,
        change = change,
        history = history,
        color_columns = color_columns,
        color_labels = color_labels,
    })
    return self
end
return E
