-- LUT layout and hit targets. Document edits remain owned by the injected editor.
local V = {}
function V.new(deps)
    local self = deps.editor
    local semantics = deps.semantics
    local ui_core = deps.ui_core
    local format_resource_id = deps.format_resource_id
    local document, note, paint = deps.document, deps.note, deps.paint
    local rgb, editable, color_columns = deps.rgb, deps.editable, deps.color_columns
    local ffi = require('ffi')
    local function layout(ui)
        local d = document()
        local h = self.handle
        local mod = self.api.mods[h.id]
        local dark = { 17, 18, 20 }
        local blue = { 35, 62, 90 }
        local white = { 224, 230, 234 }
        local muted = { 145, 156, 165 }
        local left = math.floor(ui.w * 0.66)
        local right = ui.x + left + 12
        local rightw = ui.w - left - 12
        local top = ui.y + ui.h
        local bottomh = math.max(math.floor(ui.h * 0.43), math.min(290, math.floor(ui.h * 0.70)))
        if self.more_options then
            bottomh = math.max(bottomh, math.min(395, math.floor(ui.h * 0.70)))
        end
        local gridbottom = ui.y + bottomh + 12
        local function panel(x, y, w, height, title)
            ui.rect(x, y, w, height, dark)
            ui.rect(x, y + height - 27, w, 27, blue)
            ui.text(x + 8, y + height - 21, title, 17, white)
        end
        local function button(x, y, w, label, id)
            w = math.max(0, math.min(w, ui.x + ui.w - x - 6))
            if w < 20 then
                return
            end
            local featured = id == 'export_selected' or id == 'save_dds' or id == 'save_setup' or id == 'save_row'
            ui.rect(x, y, w, 26, featured and { 244, 202, 53 } or blue)
            ui.bounded(x + 6, y + 5, label, 15, featured and { 25, 28, 31 } or white, w - 12)
            ui.hit(x, y, w, 26, function()
                ui.activate(id)
            end)
        end
        panel(
            ui.x,
            gridbottom,
            left,
            ui.h - bottomh - 12,
            self.is_dirty() and 'Pixel Grid - unsaved edits' or 'Pixel Grid'
        )
        panel(right, ui.y, rightw, ui.h, 'Value Editor - grouped by rows')
        panel(ui.x, ui.y, left * 0.40 - 6, bottomh, 'Options')
        panel(ui.x + left * 0.40, ui.y, left * 0.30 - 6, bottomh, 'Row Presets')
        panel(ui.x + left * 0.70, ui.y, left * 0.30, bottomh, 'Scratch Pixel')
        local gear_controls = self.api and self.api.mods[self.handle.id].controls.editor_load_armor
        if gear_controls then
            self.gear = self.gear or 'armor'
            for n, kind in ipairs({ 'helmet', 'armor' }) do
                local x = ui.x + 10 + (n - 1) * 142
                local target = kind
                ui.rect(x, top - 58, 136, 26, self.gear == kind and { 49, 82, 115 } or { 24, 39, 52 })
                ui.bounded(x + 8, top - 53, kind == 'helmet' and 'Helmet LUT' or 'Armor LUT', 14, white, 120)
                ui.hit(x, top - 58, 136, 26, function()
                    self.gear = target
                    ui.activate('editor_load_' .. target)
                end)
            end
            local selector_width = math.max(120, math.min(180, left - 312))
            ui.choice('basic_' .. self.gear .. '_lut', ui.x + 300, top - 58, selector_width)
            local control = self.api.mods[self.handle.id].controls['basic_' .. self.gear .. '_lut']
            local resource = control.choice_details and control.choice_details[h.get('basic_' .. self.gear .. '_lut')]
            if resource then
                ui.bounded(
                    ui.x + 312 + selector_width,
                    top - 50,
                    resource,
                    12,
                    { 244, 202, 53 },
                    math.max(0, left - selector_width - 324)
                )
            end
        end
        local portrait = package.loaded['epic.player_preview.v1']
        local portrait_width
        if portrait and portrait.dock then
            local requested_width = math.min(200, left * 0.30)
            local ph = math.max(80, top - (gear_controls and 34 or 0) - 160 - gridbottom)
            -- Keep page/lifecycle signaling even while floated or hidden.
            portrait.dock({
                x = ui.x + left - requested_width - 8,
                y = gridbottom + 32,
                w = requested_width,
                h = ph - 12,
            })
            if not portrait.is_docked or portrait.is_docked() then
                portrait_width = requested_width
            end
        end
        if not d then
            local gear = self.api and self.api.mods[self.handle.id].controls.editor_load_armor
            if gear then
                ui.text(ui.x + 12, top - 90, 'Select a gear tab to load its currently worn colors.', 18, white)
                button(
                    ui.x + 12,
                    top - 140,
                    left - 24,
                    'Load Current ' .. (self.gear == 'armor' and 'Armor' or 'Helmet'),
                    'editor_load_' .. self.gear
                )
                button(ui.x + 12, top - 180, 180, 'Choose file...', 'browse')
                ui.text(ui.x + 12, top - 206, 'Uses currently worn LUT values; a file import is optional.', 14, muted)
                return
            end
            ui.text(ui.x + 12, top - 58, 'Choose a DDS or ZIP to begin.', 18, white)
            button(ui.x + 12, top - 102, 180, 'Choose file...', 'browse')
            button(
                ui.x + 198,
                top - 102,
                math.min(360, left - 210),
                'Populate editor with current applied palette',
                'populate_applied'
            )
            if ui.choice then
                ui.choice('lut', ui.x + 12, top - 145, math.min(360, left - 24))
            end
            ui.text(ui.x + 12, top - 169, 'Uses the applied values from the selected Live LUT.', 14, muted)
            return
        end
        if gear_controls then
            top = top - 34
        end
        local resource = d.resource_object and format_resource_id and format_resource_id(d.resource_object)
            or d.resource
        ui.text(
            ui.x + 10,
            top - 49,
            resource and ((d.source or 'Live LUT') .. ' / ID: ' .. resource)
                or (d.height .. ' rows x ' .. d.width .. ' columns. Display clamps RGB; file values stay intact.'),
            14,
            muted
        )
        if ui.choice then
            ui.choice('grid_tool', ui.x + 10, top - 82, 170)
            ui.choice('grid_channel', ui.x + 190, top - 82, 150)
        end
        button(ui.x + 350, top - 82, 70, 'Copy', 'copy_selection')
        button(ui.x + 425, top - 82, 70, 'Paste', 'paste_selection')
        if self.pattern_editor then
            local px, py, pw = ui.x + 505, top - 82, 174
            ui.rect(px - 1, py - 1, pw + 2, 28, { 255, 224, 90 })
            ui.rect(px, py, pw, 26, { 244, 202, 53 })
            ui.bounded(px + 7, py + 5, 'Pattern LUT Editor', 15, { 25, 28, 31 }, pw - 14)
            ui.hit(px, py, pw, 26, function()
                ui.activate('pattern_open')
            end, nil, nil, 'Open the separate 3x1 Pattern LUT Editor.')
        end
        button(
            ui.x + (self.pattern_editor and 689 or 505),
            top - 82,
            142,
            '[ ' .. (h.get('show_alpha') and 'x' or ' ') .. ' ] Show Alpha',
            'show_alpha'
        )
        local grid_top = top - 120
        local grid_floor = gridbottom + 30
        local width_cell = (left - 98) / d.width
        if portrait_width then
            width_cell = math.min(width_cell, (left - portrait_width - 112) / d.width)
        end
        local space = math.max(18, grid_top - grid_floor)
        local cell = math.max(18, math.min(width_cell, space / math.min(d.height, 8)))
        local visible_rows = math.max(1, math.min(d.height, math.floor(space / cell)))
        self.grid_max = math.max(0, d.height - visible_rows)
        self.grid_first = math.max(1, math.min(self.grid_max + 1, self.grid_first or 1))
        local selected_grid_row = h.get('edit_row')
        if self.grid_selected ~= selected_grid_row then
            if selected_grid_row < self.grid_first then
                self.grid_first = selected_grid_row
            end
            if selected_grid_row >= self.grid_first + visible_rows then
                self.grid_first = selected_grid_row - visible_rows + 1
            end
            self.grid_selected = selected_grid_row
        end
        local first_row, last_row = self.grid_first, self.grid_first + visible_rows - 1
        self.grid_bounds = { x = ui.x, y = grid_floor, w = left - (portrait_width or 0) - 8, h = space }
        if self.grid_max > 0 then
            ui.bounded(
                ui.x + 10,
                gridbottom + 11,
                'Rows ' .. first_row .. '-' .. last_row .. ' of ' .. d.height .. ' / scroll here',
                12,
                muted,
                left - 150
            )
            local function navigate(x, label, direction)
                ui.rect(x, gridbottom + 3, 54, 24, blue)
                ui.bounded(x + 5, gridbottom + 8, label, 12, white, 44)
                ui.hit(x, gridbottom + 3, 54, 24, function()
                    self.grid_first =
                        math.max(1, math.min(self.grid_max + 1, self.grid_first + direction * visible_rows))
                end)
            end
            navigate(ui.x + left - 124, '< Rows', -1)
            navigate(ui.x + left - 64, 'Rows >', 1)
        end
        for c = 1, d.width do
            ui.bounded(
                ui.x + 82 + (c - 1) * cell,
                top - 110,
                d.width == 23 and semantics.short_columns[c] or tostring(c),
                12,
                muted,
                cell - 2
            )
        end
        for r = first_row, last_row do
            local y = grid_top - (r - first_row + 1) * cell
            local selected_row = r
            ui.bounded(ui.x + 10, y + cell * 0.35, 'Row ' .. r, 12, { 244, 202, 53 }, 68)
            if self.api and self.api.mods[self.handle.id].controls.identify_region then
                ui.hit(ui.x + 8, y, 70, cell, function()
                    assert(h.set('edit_row', selected_row))
                    self.sync()
                    ui.activate('identify_region')
                end)
            end
        end
        local row = h.get('edit_row')
        local column = h.get('edit_column')
        for r = first_row, last_row do
            for c = 1, d.width do
                local selected_row, selected_col = r, c
                local index = semantics.index(r, c, 1, d.width, d.height)
                local x = ui.x + 82 + (c - 1) * cell
                local y = grid_top - (r - first_row + 1) * cell
                local s = self.selection
                local selected = s and r >= s.r1 and r <= s.r2 and c >= s.c1 and c <= s.c2
                local color = rgb(d.data, index)
                local channel = h.get('grid_channel')
                if channel >= 3 then
                    local value = math.floor(math.max(0, math.min(1, d.data[index + channel - 3])) * 255 + 0.5)
                    color = { value, value, value }
                end
                ui.rect(
                    x,
                    y,
                    cell,
                    cell,
                    (selected or (r == row and c == column)) and { 244, 202, 53 } or { 75, 78, 82 }
                )
                if deps.swatch then
                    deps.swatch(
                        ui,
                        x + 1,
                        y + 1,
                        cell - 2,
                        cell - 2,
                        color,
                        d.data[index + 3],
                        h.get('show_alpha') and channel < 3
                    )
                else
                    ui.rect(x + 1, y + 1, cell - 2, cell - 2, color)
                end
                ui.hit(
                    x,
                    y,
                    cell,
                    cell,
                    function()
                        local ok, why = pcall(function()
                            local tool = h.get('grid_tool')
                            if tool == 3 then
                                self.move_selection(selected_row, selected_col)
                            elseif tool == 2 then
                                paint(selected_row, selected_col)
                            elseif self.selection and ui.shift and ui.shift() then
                                local anchor_row, anchor_col =
                                    self.selection.anchor_row or self.selection.r1,
                                    self.selection.anchor_col or self.selection.c1
                                self.selection = {
                                    anchor_row = anchor_row,
                                    anchor_col = anchor_col,
                                    r1 = math.min(anchor_row, selected_row),
                                    r2 = math.max(anchor_row, selected_row),
                                    c1 = math.min(anchor_col, selected_col),
                                    c2 = math.max(anchor_col, selected_col),
                                }
                            else
                                self.selection =
                                    { r1 = selected_row, r2 = selected_row, c1 = selected_col, c2 = selected_col }
                            end
                            self.open_row = selected_row
                            assert(h.set('edit_row', selected_row))
                            assert(h.set('edit_column', selected_col))
                            self.focus_column = selected_col
                            for i, col in ipairs(color_columns) do
                                if col == selected_col then
                                    assert(h.set('color_field', i))
                                    break
                                end
                            end
                            self.sync()
                        end)
                        if not ok then
                            note(tostring(why))
                        end
                    end,
                    nil,
                    function()
                        local at = semantics.index(selected_row, selected_col, 1, d.width, d.height)
                        local data = ffi.new('float[4]')
                        ffi.copy(data, d.data + at, 16)
                        self.clip = { data = data, width = 1, height = 1 }
                        local color = rgb(d.data, at)
                        self.scratch = { color[1], color[2], color[3] }
                        assert(h.set('scratch_color', string.format('#%02X%02X%02X', color[1], color[2], color[3])))
                        assert(h.set('scratch_alpha', math.max(0, math.min(1, tonumber(d.data[at + 3])))))
                        note('Swatch copied to scratch and pixel clipboard.')
                    end,
                    'Double-click to edit RGBA. Raw shader columns use numeric values; unchanged channels retain their exact values.',
                    function()
                        self.focus_cell(selected_row, selected_col)
                        ui.activate('cell_color')
                    end
                )
            end
        end
        local can_identify = self.api and self.handle and self.api.mods[self.handle.id].controls.identify_region
        if ui.choice then
            ui.choice('edit_row', right + 8, top - 57, rightw - 16)
        end
        if can_identify then
            button(ui.x + ui.w - 150, ui.y - 24, 150, 'Stop Highlight', 'stop_identify')
        end
        button(
            right + 8,
            top - 86,
            (rightw - 21) / 2,
            h.get('group_rows') and 'Group by rows: ON' or 'Selected row only',
            'group_rows'
        )
        button(
            right + 13 + (rightw - 21) / 2,
            top - 86,
            (rightw - 21) / 2,
            h.get('unlock') and 'Advanced: ON' or 'Unlock advanced edits',
            'unlock'
        )
        local clip_top, clip_bottom = top - 96, ui.y + 12
        self.value_bounds = { x = right, y = ui.y, w = rightw, h = ui.h }
        local scroll = self.value_scroll
        local cursor = clip_top + scroll
        local function visible(y, height)
            return y >= clip_bottom and y + height <= clip_top
        end
        local function words(value)
            local lines, line = {}, ''
            local width = rightw - 36
            local size = ui.text_size and ui.text_size(13) or 13
            local function fits(value)
                return (ui.text_width and ui.text_width(value, 13) or #value * size * 0.62) <= width
            end
            for word in tostring(value):gmatch('%S+') do
                if #line > 0 and not fits(line .. ' ' .. word) then
                    lines[#lines + 1] = line
                    line = word
                else
                    line = line == '' and word or line .. ' ' .. word
                end
            end
            if #line > 0 then
                lines[#lines + 1] = line
            end
            return lines
        end
        for r = 1, d.height do
            if h.get('group_rows') or r == row then
                local selected_row = r
                cursor = cursor - 25
                if visible(cursor, 23) then
                    ui.rect(right + 8, cursor, rightw - 20, 23, r == row and { 49, 82, 115 } or blue)
                    local pulse = 0.5 + 0.5 * math.sin(os.clock() * 3)
                    ui.text(
                        right + 13,
                        cursor + 6,
                        (self.open_row == r and 'v ' or '> ') .. 'Row ' .. r,
                        14,
                        can_identify
                                and {
                                    math.floor(175 + 69 * pulse),
                                    math.floor(180 + 22 * pulse),
                                    math.floor(140 - 87 * pulse),
                                }
                            or white
                    )
                    ui.hit(right + 8, cursor, can_identify and 24 or rightw - 20, 23, function()
                        local expanded = self.open_row ~= selected_row
                        assert(h.set('edit_row', selected_row))
                        self.value_scroll = 0
                        self.sync()
                        self.open_row = expanded and selected_row or nil
                    end)
                    if can_identify then
                        ui.hit(right + 32, cursor, rightw - 44, 23, function()
                            local expanded = self.open_row ~= selected_row
                            assert(h.set('edit_row', selected_row))
                            self.value_scroll = 0
                            self.sync()
                            self.open_row = expanded and selected_row or nil
                            if expanded then
                                ui.activate('identify_region')
                            end
                        end)
                    end
                end
                if self.open_row == r then
                    for c = 1, d.width do
                        local selected_col = c
                        if self.focus_column == c then
                            self.value_scroll = math.max(0, clip_top + scroll - cursor)
                            self.focus_column = nil
                        end
                        local function prepare()
                            assert(h.set('edit_row', selected_row))
                            assert(h.set('edit_column', selected_col))
                            for i, col in ipairs(color_columns) do
                                if col == selected_col then
                                    assert(h.set('color_field', i))
                                    break
                                end
                            end
                            self.sync()
                        end
                        cursor = cursor - 21
                        if visible(cursor, 17) then
                            ui.bounded(
                                right + 12,
                                cursor + 3,
                                'Column ' .. c .. ': ' .. semantics.columns[c],
                                14,
                                white,
                                rightw - 58
                            )
                            if true then
                                local index = semantics.index(r, c, 1, d.width, d.height)
                                ui.rect(right + rightw - 40, cursor - 1, 24, 18, rgb(d.data, index))
                                ui.hit(right + rightw - 40, cursor - 1, 24, 18, function()
                                    prepare()
                                    ui.activate('cell_color')
                                end)
                            end
                        end
                        for _, line in
                            ipairs(words(semantics.hints[c] or 'Unconfirmed shader meaning. Raw values are retained.'))
                        do
                            local line_height = math.max(14, (ui.text_size and ui.text_size(13) or 13) + 3)
                            cursor = cursor - line_height
                            if visible(cursor, line_height) then
                                ui.bounded(right + 12, cursor + 2, line, 13, muted, rightw - 36)
                            end
                        end
                        for ch, name in ipairs({ 'r', 'g', 'b', 'a' }) do
                            local enum = (c == 1 and ch == 4 and 'shader_mode')
                                or (c == 2 and ch == 1 and 'detail_texture')
                                or (c == 22 and ch == 4 and 'camo_pattern')
                            cursor = cursor - (enum and 30 or 24)
                            if visible(cursor, enum and 26 or 21) then
                                local value = tonumber(d.data[semantics.index(r, c, ch, d.width, d.height)])
                                ui.text(right + 12, cursor + 6, name:upper(), 13, muted)
                                if enum and ui.choice then
                                    ui.choice(enum, right + 29, cursor, rightw - 46, prepare)
                                elseif ui.number then
                                    local lo, hi = semantics.range(c, ch, value)
                                    ui.number(
                                        'cell_' .. name,
                                        right + 29,
                                        cursor,
                                        rightw - 46,
                                        value,
                                        prepare,
                                        editable(d, c, ch),
                                        lo,
                                        hi,
                                        r == h.get('edit_row') and c == h.get('edit_column')
                                    )
                                else
                                    ui.text(right + 29, cursor + 5, string.format('%.7g', value), 13, white)
                                end
                            end
                        end
                        cursor = cursor - 10
                        if visible(cursor, 1) then
                            ui.rect(right + 10, cursor, rightw - 22, 1, { 65, 70, 75 })
                        end
                    end
                end
            end
        end
        local content = clip_top + scroll - cursor
        local viewport = clip_top - clip_bottom
        self.value_max = math.max(0, content - viewport)
        self.value_scroll = math.min(self.value_scroll, self.value_max)
        if self.value_max > 0 then
            local thumb = math.max(18, viewport * viewport / content)
            ui.rect(right + rightw - 6, clip_bottom, 4, viewport, { 50, 55, 60 })
            ui.rect(
                right + rightw - 7,
                clip_top - thumb - (viewport - thumb) * self.value_scroll / self.value_max,
                6,
                thumb,
                { 120, 135, 150 }
            )
        end
        local optionsy = ui.y + bottomh - 55
        local step = math.min(32, (bottomh - 65) / 7)
        local optionw = left * 0.4 - 20
        local gear = self.api and self.api.mods[self.handle.id].controls.editor_load_armor
        if gear then
            step = math.min(30, (bottomh - 65) / (self.more_options and 12 or 8))
            ui.rect(ui.x + 10, optionsy - step * 1.5, optionw, 1, { 65, 76, 85 })
            ui.rect(ui.x + 10, optionsy - step * 4.5, optionw, 1, { 65, 76, 85 })
            button(ui.x + 10, optionsy, (optionw - 5) / 2, 'Import file', 'browse')
            button(ui.x + 15 + (optionw - 5) / 2, optionsy, (optionw - 5) / 2, 'Send to LUT Editor', 'save_palette')
            ui.choice('palette', ui.x + 10, optionsy - step, optionw * 0.6)
            ui.rect(ui.x + 14 + optionw * 0.6, optionsy - step, optionw * 0.4 - 4, 26, blue)
            ui.bounded(ui.x + 18 + optionw * 0.6, optionsy - step + 5, 'Preview Palette', 14, white, optionw * 0.4 - 12)
            ui.hit(ui.x + 14 + optionw * 0.6, optionsy - step, optionw * 0.4 - 4, 26, function()
                if ui.preview then
                    ui.preview(self.preview)
                end
            end)
            button(
                ui.x + 10,
                optionsy - step * 2,
                optionw,
                'Apply to '
                    .. (self.gear == 'armor' and 'Armor' or 'Helmet')
                    .. ' LUT '
                    .. h.get('basic_' .. self.gear .. '_lut'),
                'editor_apply_' .. self.gear
            )
            button(
                ui.x + 10,
                optionsy - step * 3,
                optionw,
                '[ ' .. (h.get('preserve_emissives') and 'x' or ' ') .. ' ] Preserve Original Emissives',
                'preserve_emissives'
            )
            button(ui.x + 10, optionsy - step * 4, (optionw - 5) / 2, 'Undo', 'undo')
            button(ui.x + 15 + (optionw - 5) / 2, optionsy - step * 4, (optionw - 5) / 2, 'Redo', 'redo')
            ui.rect(ui.x + 10, optionsy - step * 4 - 7, optionw, 1, { 90, 103, 110 })
            button(
                ui.x + 10,
                optionsy - step * 5 - 5,
                optionw,
                'Export Name: ' .. (ui.input_value and ui.input_value('save_name') or h.get('save_name')),
                'save_name'
            )
            button(ui.x + 10, optionsy - step * 6 - 5, optionw * 0.35 - 3, 'Export...', 'export_selected')
            if ui.choice then
                ui.choice('export_format', ui.x + 15 + optionw * 0.35, optionsy - step * 6 - 5, optionw * 0.65 - 5)
            end
            button(ui.x + 10, optionsy - step * 7 - 5, optionw, 'Open Export Location', 'open_export')
            ui.rect(ui.x + 10, optionsy - step * 8 - 5, optionw, 26, { 24, 39, 52 })
            ui.bounded(
                ui.x + 16,
                optionsy - step * 8,
                (self.more_options and 'v ' or '> ') .. 'More Options',
                14,
                white,
                optionw - 12
            )
            ui.hit(ui.x + 10, optionsy - step * 8 - 5, optionw, 26, function()
                self.more_options = not self.more_options
            end)
            if self.more_options then
                button(ui.x + 10, optionsy - step * 9 - 5, (optionw - 5) / 2, 'All Armor LUTs', 'editor_all_armor')
                button(
                    ui.x + 15 + (optionw - 5) / 2,
                    optionsy - step * 9 - 5,
                    (optionw - 5) / 2,
                    'All Helmet LUTs',
                    'editor_all_helmet'
                )
                button(ui.x + 10, optionsy - step * 10 - 5, optionw, 'Restore Arrowhead LUT (Original)', 'restore')
                button(ui.x + 10, optionsy - step * 11 - 5, optionw, 'Save applied setup', 'save_setup')
                if portrait and portrait.meshes then
                    local my = optionsy - step * 12 - 5
                    ui.rect(ui.x + 10, my, optionw, 26, blue)
                    ui.bounded(ui.x + 16, my + 5, 'Preview Meshes / Masks', 14, white, optionw - 12)
                    ui.hit(ui.x + 10, my, optionw, 26, function()
                        self.mesh_popup = true
                        self.mesh_page = 1
                        if self.pattern_editor then
                            self.pattern_editor.open = false
                        end
                    end)
                end
            end
        else
            button(ui.x + 10, optionsy, (optionw - 5) / 2, 'Import file', 'browse')
            button(ui.x + 15 + (optionw - 5) / 2, optionsy, (optionw - 5) / 2, 'Send to LUT Editor', 'save_palette')
            if ui.choice then
                ui.choice('palette', ui.x + 10, optionsy - step, optionw * 0.60 - 3)
                local px = ui.x + 10 + optionw * 0.60 + 2
                ui.rect(px, optionsy - step, optionw * 0.40 - 2, 26, blue)
                ui.bounded(px + 4, optionsy - step + 5, 'Preview Palette', 15, white, optionw * 0.40 - 10)
                ui.hit(px, optionsy - step, optionw * 0.40 - 2, 26, function()
                    if ui.preview then
                        ui.preview(self.preview)
                    end
                end)
                ui.choice('lut', ui.x + 10, optionsy - step * 2, optionw * 0.60 - 3)
                ui.rect(px, optionsy - step * 2, optionw * 0.40 - 2, 26, blue)
                ui.bounded(px + 4, optionsy - step * 2 + 5, 'Preview Live LUT', 15, white, optionw * 0.40 - 10)
                ui.hit(px, optionsy - step * 2, optionw * 0.40 - 2, 26, function()
                    if ui.preview then
                        ui.preview(function(bounds)
                            return self.preview(bounds, true)
                        end)
                    end
                end)
            end
            button(ui.x + 10, optionsy - step * 3, (optionw - 5) / 2, 'Restore Original', 'restore')
            button(
                ui.x + 15 + (optionw - 5) / 2,
                optionsy - step * 3,
                (optionw - 5) / 2,
                'Reset Custom LUT',
                'reset_custom'
            )
            button(ui.x + 10, optionsy - step * 4, (optionw - 5) / 2, 'Undo', 'undo')
            button(ui.x + 15 + (optionw - 5) / 2, optionsy - step * 4, (optionw - 5) / 2, 'Redo', 'redo')
            button(ui.x + 10, optionsy - step * 5, optionw, 'Save applied setup', 'save_setup')
            button(ui.x + 10, optionsy - step * 6, optionw, 'Apply edited palette to checked targets', 'apply_editor')
            button(
                ui.x + 10,
                optionsy - step * 7,
                (optionw - 5) / 2,
                '[ ' .. (h.get('target_helmet') and 'x' or ' ') .. ' ] Helmet',
                'target_helmet'
            )
            button(
                ui.x + 15 + (optionw - 5) / 2,
                optionsy - step * 7,
                (optionw - 5) / 2,
                '[ ' .. (h.get('target_armor') and 'x' or ' ') .. ' ] Armor',
                'target_armor'
            )
        end
        local presetx = ui.x + left * 0.40 + 10
        local panelw = left * 0.30 - 20
        ui.text(presetx, optionsy, 'Selected row: ' .. row, 15, white)
        if ui.preset then
            ui.preset('row_preset', 'row_preset_select', presetx, optionsy - 38, panelw)
        else
            button(presetx, optionsy - 38, panelw, 'Preset: ' .. h.get('row_preset'), 'row_preset')
        end
        button(presetx, optionsy - 72, panelw, 'Save selected row', 'save_row')
        button(presetx, optionsy - 106, panelw, 'Apply preset to row', 'load_row')
        button(presetx, optionsy - 146, (panelw - 5) / 2, 'Copy row', 'copy_row')
        button(presetx + (panelw + 5) / 2, optionsy - 146, (panelw - 5) / 2, 'Paste row', 'paste_row')
        button(presetx, optionsy - 180, (panelw - 5) / 2, 'Reset row', 'reset_row')
        button(presetx + (panelw + 5) / 2, optionsy - 180, (panelw - 5) / 2, 'Reset cell', 'reset_cell')
        local scratchx = ui.x + left * 0.70 + 10
        local hue = ui_core.rgb_hsv(self.scratch or { 255, 255, 255 })
        local gh = math.max(40, math.min(180, bottomh - 164))
        local gw = panelw - 39
        for vy = 0, 19 do
            for sx = 0, 19 do
                local saturation, value = sx / 19, vy / 19
                local x, y = scratchx + sx * gw / 20, optionsy - 35 - gh + vy * gh / 20
                ui.rect(x, y, gw / 20 + 1, gh / 20 + 1, ui_core.hsv_rgb(hue, saturation, value))
                ui.hit(x, y, gw / 20, gh / 20, function()
                    local color = ui_core.hsv_rgb(hue, saturation, value)
                    assert(h.set('scratch_color', string.format('#%02X%02X%02X', color[1], color[2], color[3])))
                end)
            end
        end
        for i = 0, 19 do
            local chosen = i / 20
            local y = optionsy - 35 - gh + i * gh / 20
            ui.rect(scratchx + gw + 5, y, 12, gh / 20 + 1, ui_core.hsv_rgb(chosen, 1, 1))
            ui.hit(scratchx + gw + 5, y, 12, gh / 20, function()
                local color = ui_core.hsv_rgb(chosen, 1, 1)
                assert(h.set('scratch_color', string.format('#%02X%02X%02X', color[1], color[2], color[3])))
            end)
        end
        local alphax, alphay = scratchx + gw + 23, optionsy - 35 - gh
        local alpha = ui.vertical and ui.vertical('scratch_alpha', alphax, alphay, 16, gh) or h.get('scratch_alpha')
        local scratch = self.scratch or { 255, 255, 255 }
        for row = 0, 19 do
            local opacity = row / 19
            for col = 0, 1 do
                local background = (row + col) % 2 == 0 and 220 or 125
                local color = {}
                for ch = 1, 3 do
                    color[ch] = math.floor(background * (1 - opacity) + scratch[ch] * opacity + 0.5)
                end
                ui.rect(alphax + col * 8, alphay + row * gh / 20, 8, gh / 20 + 1, color)
            end
            if not ui.vertical then
                local chosen = opacity
                ui.hit(alphax, alphay + row * gh / 20, 16, gh / 20, function()
                    assert(h.set('scratch_alpha', chosen))
                end)
            end
        end
        local markery = alphay + alpha * gh
        ui.rect(alphax - 2, markery - 2, 20, 4, { 15, 15, 15 })
        ui.rect(alphax - 2, markery - 1, 20, 2, { 255, 255, 255 })
        ui.bounded(scratchx, alphay - 19, string.format('A: %.2f', alpha), 12, white, panelw)
        ui.rect(scratchx, optionsy - 24, panelw, 24, self.scratch or { 255, 255, 255 })
        ui.hit(scratchx, optionsy - 24, panelw, 24, function()
            ui.activate('scratch_color')
        end)
        button(scratchx, ui.y + 15, panelw, 'Paint selected RGB', 'paint_scratch')
        if self.mesh_popup and portrait and portrait.meshes and ui.floating then
            ui.floating(
                'preview_meshes',
                function(x, y, w, ht)
                    local masks = self.mesh_masks == true and portrait.material_masks ~= nil
                    local rows = masks and portrait.material_masks() or portrait.meshes()
                    ui.rect(x + 12, y + ht - 63, 185, 24, blue)
                    ui.bounded(x + 18, y + ht - 58, masks and 'Hip / Leg Masks' or 'Mesh Visibility', 13, white, 173)
                    ui.hit(x + 12, y + ht - 63, 185, 24, function()
                        self.mesh_masks = not masks
                        self.mesh_page = 1
                    end)
                    local per = 16
                    local pages = math.max(1, math.ceil(#rows / per))
                    self.mesh_page = math.min(self.mesh_page or 1, pages)
                    ui.bounded(
                        x + 205,
                        y + ht - 58,
                        masks and 'Click: Original > Black > White' or 'Click to hide/show a preview mesh.',
                        12,
                        white,
                        w - 217
                    )
                    if #rows == 0 then
                        ui.bounded(x + 12, y + ht - 100, 'Open Player Preview first.', 14, white, w - 24)
                    end
                    for i = (self.mesh_page - 1) * per + 1, math.min(#rows, self.mesh_page * per) do
                        local row = rows[i]
                        local ry = y + ht - 98 - ((i - 1) % per) * 25
                        ui.rect(x + 12, ry, w - 24, 23, row.visible and blue or { 55, 58, 60 })
                        ui.bounded(
                            x + 18,
                            ry + 4,
                            (masks and ('[' .. row.mode .. '] ') or (row.visible and '[ x ] ' or '[   ] ')) .. row.label,
                            12,
                            white,
                            w - 36
                        )
                        ui.hit(x + 12, ry, w - 24, 23, function()
                            if masks then
                                local mode = row.mode == 'original' and 'black'
                                    or row.mode == 'black' and 'white'
                                    or 'original'
                                portrait.set_material_mask(row.piece, row.material, row.slot, mode)
                            else
                                portrait.set_mesh(row.piece, row.mesh, not row.visible)
                            end
                        end)
                    end
                    local function action(bx, bw, label, fn)
                        ui.rect(bx, y + 12, bw, 28, blue)
                        ui.bounded(bx + 6, y + 18, label, 13, white, bw - 12)
                        ui.hit(bx, y + 12, bw, 28, fn)
                    end
                    local first_row = (self.mesh_page - 1) * per + 1
                    local last_row = math.min(#rows, self.mesh_page * per)
                    local function page_action(index, label, mode)
                        local bw = (w - 34) / 3
                        local bx = x + 12 + (index - 1) * (bw + 5)
                        ui.rect(bx, y + 46, bw, 27, blue)
                        ui.bounded(bx + 6, y + 52, label, 13, white, bw - 12)
                        ui.hit(bx, y + 46, bw, 27, function()
                            for i = first_row, last_row do
                                local row = rows[i]
                                if masks then
                                    portrait.set_material_mask(row.piece, row.material, row.slot, mode)
                                else
                                    portrait.set_mesh(row.piece, row.mesh, mode == 'show')
                                end
                            end
                        end)
                    end
                    if masks then
                        page_action(1, 'Page: Black', 'black')
                        page_action(2, 'Page: White', 'white')
                        page_action(3, 'Page: Original', 'original')
                    else
                        page_action(1, 'Show Page', 'show')
                        page_action(2, 'Hide Page', 'hide')
                    end
                    action(x + 12, 90, '< Previous', function()
                        self.mesh_page = math.max(1, self.mesh_page - 1)
                    end)
                    ui.bounded(x + 110, y + 20, string.format('%d / %d', self.mesh_page, pages), 13, white, 80)
                    action(x + 195, 80, 'Next >', function()
                        self.mesh_page = math.min(pages, self.mesh_page + 1)
                    end)
                    action(
                        x + 290,
                        w - 302,
                        masks and 'Reset All Masks' or 'Reset Visibility',
                        masks and portrait.reset_material_masks or portrait.reset_meshes
                    )
                end,
                620,
                550,
                function()
                    self.mesh_popup = false
                end,
                40
            )
        elseif self.pattern_editor then
            self.pattern_editor.popup(ui)
        end
    end
    return layout
end
return V
