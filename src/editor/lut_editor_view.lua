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
        local bottomh = math.floor(ui.h * 0.43)
        if self.more_options then
            bottomh = math.max(bottomh, math.min(305, math.floor(ui.h * 0.65)))
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
            ui.rect(x, y, w, 26, blue)
            ui.bounded(x + 6, y + 5, label, 15, white, w - 12)
            ui.hit(x, y, w, 26, function()
                ui.activate(id)
            end)
        end
        panel(ui.x, gridbottom, left, ui.h - bottomh - 12, 'Pixel Grid')
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
            portrait_width = math.min(200, left * 0.30)
            local ph = math.max(80, top - (gear_controls and 34 or 0) - 116 - gridbottom)
            portrait.dock({ x = ui.x + left - portrait_width - 8, y = gridbottom + 32, w = portrait_width, h = ph - 12 })
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
        local cell = math.min((left - 98) / d.width, (ui.h - bottomh - 140 - (gear_controls and 34 or 0)) / d.height)
        if portrait_width then
            cell = math.min(cell, (left - portrait_width - 112) / d.width)
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
        for r = 1, d.height do
            local y = top - 120 - r * cell
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
        for r = 1, d.height do
            for c = 1, d.width do
                local selected_row, selected_col = r, c
                local index = semantics.index(r, c, 1, d.width, d.height)
                local x = ui.x + 82 + (c - 1) * cell
                local y = top - 120 - r * cell
                local s = self.selection
                local selected = s and r >= s.r1 and r <= s.r2 and c >= s.c1 and c <= s.c2
                local color = rgb(d.data, index)
                local channel = h.get('grid_channel')
                if channel == 2 then
                    local alpha = math.max(0, math.min(1, d.data[index + 3]))
                    local background = (r + c) % 2 == 0 and 80 or 130
                    for ch = 1, 3 do
                        color[ch] = math.floor(color[ch] * alpha + background * (1 - alpha) + 0.5)
                    end
                end
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
                ui.rect(x + 1, y + 1, cell - 2, cell - 2, color)
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
                    'Double-click a color swatch to edit its RGB. Middle-click copies it.',
                    function()
                        if semantics.is_color(d.width, selected_col) then
                            self.focus_cell(selected_row, selected_col)
                            ui.activate('cell_color')
                        else
                            note(
                                'Select a color column to open the RGB picker. Use the value controls for this column.'
                            )
                        end
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
            local limit = math.max(24, math.floor((rightw - 36) / 6))
            for word in tostring(value):gmatch('%S+') do
                if #line > 0 and #line + #word + 1 > limit then
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
                            if semantics.is_color(d.width, c) then
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
                            cursor = cursor - 14
                            if visible(cursor, 12) then
                                ui.text(right + 12, cursor + 2, line, 13, muted)
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
            step = math.min(30, (bottomh - 65) / (self.more_options and 8 or 5))
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
            ui.rect(ui.x + 10, optionsy - step * 5, optionw, 26, { 24, 39, 52 })
            ui.bounded(
                ui.x + 16,
                optionsy - step * 5 + 5,
                (self.more_options and 'v ' or '> ') .. 'More Options',
                14,
                white,
                optionw - 12
            )
            ui.hit(ui.x + 10, optionsy - step * 5, optionw, 26, function()
                self.more_options = not self.more_options
            end)
            if self.more_options then
                button(ui.x + 10, optionsy - step * 6, (optionw - 5) / 2, 'All Armor LUTs', 'editor_all_armor')
                button(
                    ui.x + 15 + (optionw - 5) / 2,
                    optionsy - step * 6,
                    (optionw - 5) / 2,
                    'All Helmet LUTs',
                    'editor_all_helmet'
                )
                button(ui.x + 10, optionsy - step * 7, optionw, 'Restore Arrowhead LUT (Original)', 'restore')
                button(ui.x + 10, optionsy - step * 8, optionw, 'Save applied setup', 'save_setup')
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
        local scratchx = ui.x + left * 0.70 + 10
        local hue = ui_core.rgb_hsv(self.scratch or { 255, 255, 255 })
        local gh = math.min(180, bottomh - 140)
        local gw = panelw - 18
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
        ui.rect(scratchx, optionsy - 24, panelw, 24, self.scratch or { 255, 255, 255 })
        ui.hit(scratchx, optionsy - 24, panelw, 24, function()
            ui.activate('scratch_color')
        end)
        button(scratchx, ui.y + 15, panelw, 'Paint selected RGB', 'paint_scratch')
    end
    return layout
end
return V
