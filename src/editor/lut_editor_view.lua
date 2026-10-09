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
    local selection_drag
    local function same_source(state)
        local current = document()
        return current == state.document
            and current
            and current.data == state.data
            and current.width == state.width
            and current.height == state.height
            and current.source == state.source
            and self.gear == state.gear
    end
    local function layout(ui)
        local d = document()
        local h = self.handle
        if selection_drag and (not same_source(selection_drag) or h.get('grid_tool') ~= 1) then
            selection_drag.cancel()
        end
        local mod = self.api.mods[h.id]
        local theme = ui.theme
        local dark, blue, white, muted = theme.panel, theme.header, theme.white, theme.muted
        local show_values = h.get('value_editor_visible') ~= false
        local left = show_values and math.floor(ui.w * 0.70) or ui.w
        self.grid_bounds, self.value_bounds = nil, nil
        if not d then
            self.grid_max = 0
        end
        local right = ui.x + left + 12
        local rightw = ui.w - left - 12
        local top = ui.y + ui.h
        local gear_controls = mod.controls.editor_load_armor
        local extra_header = gear_controls and 36 or 0
        local font_scale = (ui.text_size and ui.text_size(14) or 12) / 12
        local footer_inset = 6 * font_scale
        local footer_height = math.max(26 * font_scale, ui.control_height and ui.control_height(14, 5) or 0)
        local footer_band = footer_height + footer_inset * 2
        local content_bottom = footer_band + 4 * font_scale
        local gridbottom = ui.y + content_bottom
        local portrait = package.loaded['epic.player_preview.v1']
        local function panel(x, y, w, height, title, reserved)
            ui.rect(x, y, w, height, dark)
            ui.rect(x, y + height - 27, w, 27, blue)
            ui.bounded(x + 8, y + height - 21, title, 17, white, math.max(0, w - 16 - (reserved or 0)))
        end
        local function button(x, y, w, label, id)
            w = math.max(0, math.min(w, ui.x + ui.w - x - 6))
            if w < 20 then
                return
            end
            local loading = id == 'populate_worn' or id == 'editor_load_armor' or id == 'editor_load_helmet'
            local featured = loading
                or id == 'export_selected'
                or id == 'save_dds'
                or id == 'save_setup'
                or id == 'save_row'
            local control = mod.controls[id]
            local selected = control and control.type == 'toggle' and h.get(id)
            ui.button(x, y, w, 26, label, function()
                ui.activate(id)
            end, {
                selected = selected,
                enabled = not control or not control.disabled,
                accent = featured
                    and (loading and ui.load_color(self.load_seen and self.load_seen()) or { 244, 202, 53 }),
                ink = featured and { 25, 28, 31 },
                size = 15,
                help = control and control.description,
            })
        end
        panel(
            ui.x,
            gridbottom,
            left,
            ui.h - content_bottom,
            (self.is_dirty() and 'Pixel Grid - unsaved edits' or 'Pixel Grid')
                .. (
                    d
                        and (' / ' .. d.height .. ' x ' .. d.width .. ' / ' .. (d.source or 'Current LUT')
                            :gsub('\\', '/')
                            :match('[^/]+$'))
                    or ''
                )
        )
        if show_values then
            local actions = mod.controls.copy_value and mod.controls.paste_value
            local compact = rightw < 360
            local copy_label, paste_label = compact and 'Copy' or 'Copy Value', compact and 'Paste' or 'Paste Value'
            local action_width = math.min(110, math.max(46, (rightw - 110) / 2))
            local reserved = actions and action_width * 2 + 10 or 0
            panel(right, gridbottom, rightw, ui.h - content_bottom, 'Value Editor', reserved)
            if actions then
                local function value_action(id, label, x)
                    local control = mod.controls[id]
                    ui.button(x, top - 25, action_width, 23, label, function()
                        ui.activate(id)
                    end, { enabled = not control.disabled, size = 13, help = control.description })
                end
                value_action('copy_value', copy_label, right + rightw - 8 - action_width * 2 - 4)
                value_action('paste_value', paste_label, right + rightw - 8 - action_width)
            end
        end
        local function open_tools(tab)
            if not self.tools then
                return
            end
            self.tools.open(tab)
        end
        local function overlays()
            if self.tools and self.tools.is_open() then
                self.tools.popup(ui)
            end
            if self.pattern_editor then
                self.pattern_editor.popup(ui)
            end
            if self.scratch_tool then
                self.scratch_tool.popup(ui)
            end
        end
        ui.rect(ui.x, ui.y, ui.w, footer_band, dark)
        local function shortcut(x, width, label, action, selected, enabled)
            ui.button(x, ui.y + footer_inset, width, footer_height, label, action, {
                selected = selected,
                enabled = enabled,
                accent = label == 'Tools' and { 244, 202, 53 },
                ink = label == 'Tools' and { 25, 28, 31 },
            })
        end
        local function measured(label, minimum)
            return math.max(
                minimum,
                (ui.text_width and ui.text_width(label, 14) or #label * 14 * 0.62) + 18 * font_scale
            )
        end
        local apply_id = 'editor_apply_' .. (self.gear or 'armor')
        if not mod.controls[apply_id] then
            apply_id = 'apply_editor'
        end
        local apply_label = 'Apply ' .. (self.gear or 'palette')
        local values_label = show_values and 'Hide Values' or 'Show Values'
        local gap = 6 * font_scale
        local tools_width, scratch_width, values_width =
            measured('Tools', 62), measured('Scratch', 76), measured(values_label, 108)
        local brush_label_padding = 8 * font_scale
        local brush_label_width = (ui.text_width and ui.text_width('Brush', 13) or 45) + brush_label_padding
        local brush_chip_width = 36 * font_scale
        local brush_width = brush_label_width + brush_chip_width
        local apply_width = d and mod.controls[apply_id] and measured(apply_label, 132) or 0
        local stop_width = mod.controls.stop_identify and measured('Stop Highlight', 124) or 0
        local fixed_width = scratch_width + values_width + brush_width + gap * 2
        if apply_width > 0 then
            fixed_width = fixed_width + gap + apply_width
        end
        if stop_width > 0 then
            fixed_width = fixed_width + gap + stop_width
        end
        local fixed_x = ui.x + ui.w - 8 * font_scale - fixed_width
        shortcut(ui.x + 8 * font_scale, tools_width, 'Tools', function()
            open_tools()
        end, self.tools and self.tools.is_open(), self.tools ~= nil)
        if self.tools and self.tools.is_open() then
            local children =
                { { 'Import', 'import' }, { 'Rows', 'rows' }, { 'Export', 'export' }, { 'Options', 'options' } }
            local begin = ui.x + 8 * font_scale + tools_width + gap
            local width = math.max(20, (fixed_x - begin - gap * #children) / #children)
            for i, child in ipairs(children) do
                local tab = child[2]
                shortcut(begin + (i - 1) * (width + gap), width, child[1], function()
                    open_tools(tab)
                end, self.tools.tab == tab)
            end
        end
        shortcut(fixed_x, scratch_width, 'Scratch', function()
            if self.scratch_tool then
                self.scratch_tool.open()
            end
        end, self.scratch_tool and self.scratch_tool.is_open(), self.scratch_tool ~= nil)
        local fx = fixed_x + scratch_width + gap
        shortcut(fx, values_width, values_label, function()
            ui.activate('value_editor_visible')
        end, show_values)
        fx = fx + values_width + gap
        ui.bounded(
            fx,
            ui.text_y and ui.text_y(ui.y + footer_inset, footer_height, 13, 'Brush')
                or (ui.y + footer_inset + (footer_height - (ui.text_size and ui.text_size(13) or 13)) / 2),
            'Brush',
            13,
            muted,
            brush_label_width - brush_label_padding
        )
        ui.rect(
            fx + brush_label_width,
            ui.y + footer_inset,
            brush_chip_width,
            footer_height,
            self.scratch or { 255, 255, 255 }
        )
        ui.hit(fx + brush_label_width, ui.y + footer_inset, brush_chip_width, footer_height, function()
            ui.activate('scratch_color')
        end, nil, nil, 'Edit the current brush color. The Scratch window also includes alpha.')
        fx = fx + brush_width
        if apply_width > 0 then
            fx = fx + gap
            shortcut(fx, apply_width, apply_label, function()
                ui.activate(apply_id)
            end, nil, not mod.controls[apply_id].disabled)
            fx = fx + apply_width
        end
        if stop_width > 0 then
            shortcut(fx + gap, stop_width, 'Stop Highlight', function()
                ui.activate('stop_identify')
            end)
        end
        if gear_controls then
            self.gear = self.gear or 'armor'
            local tab_width = math.min(136, math.max(62, left * 0.17))
            local load_width = math.min(190, left * 0.24)
            local selector_x = ui.x + 28
            local load_x = ui.x + left - load_width - 10
            for n, kind in ipairs({ 'helmet', 'armor' }) do
                local x = ui.x + 10 + (n - 1) * (tab_width + 6)
                local target = kind
                local ready = not self.can_select_gear or self.can_select_gear(kind)
                ui.button(x, top - 58, tab_width, 26, kind == 'helmet' and 'Helmet LUT' or 'Armor LUT', function()
                    self.gear = target
                    ui.activate('editor_load_' .. target)
                end, { enabled = ready, selected = self.gear == kind })
            end
            if self.pattern_editor then
                ui.button(
                    ui.x + 10 + (tab_width + 6) * 2,
                    top - 58,
                    math.min(142, left * 0.21),
                    26,
                    'Pattern LUT Editor',
                    function()
                        ui.activate('pattern_open')
                    end,
                    { accent = { 244, 202, 53 }, ink = { 25, 28, 31 }, help = 'Edit separate 3x1 Pattern LUTs.' }
                )
            end
            button(load_x, top - 58, load_width, 'Load Current Gear', 'populate_worn')
            local selector_width = math.min(220, left * 0.32)
            ui.rect(ui.x + 16, top - 94, 2, 26, theme.focus)
            ui.choice('basic_' .. self.gear .. '_lut', selector_x, top - 94, selector_width)
            local control = self.api.mods[self.handle.id].controls['basic_' .. self.gear .. '_lut']
            local resource = control.choice_details and control.choice_details[h.get('basic_' .. self.gear .. '_lut')]
            local resource_width = ui.x + left - selector_x - selector_width - 30
            if resource and resource_width > 40 then
                ui.bounded(selector_x + 12 + selector_width, top - 86, resource, 12, { 244, 202, 53 }, resource_width)
            end
        elseif d and mod.controls.lut and ui.choice then
            ui.choice('lut', ui.x + 10, top - 58, math.min(360, left - 24))
        end
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
                ui.text(
                    ui.x + 12,
                    top - 90 - extra_header,
                    'Load Current Gear to enable the Armor and Helmet selectors.',
                    18,
                    white
                )
                button(
                    ui.x + 12,
                    top - 140,
                    left - 24,
                    'Load Current ' .. (self.gear == 'armor' and 'Armor' or 'Helmet'),
                    'editor_load_' .. self.gear
                )
                button(ui.x + 12, top - 180, 180, 'Choose file...', 'browse')
                ui.text(ui.x + 12, top - 206, 'Uses currently worn LUT values; a file import is optional.', 14, muted)
                overlays()
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
            overlays()
            return
        end
        local toolbar_pattern = self.pattern_editor and not gear_controls
        local toolbar_scale = math.min(1, (left - 20) / (toolbar_pattern and 798 or 650))
        local function tool_x(offset)
            return ui.x + 10 + offset * toolbar_scale
        end
        if ui.choice then
            ui.choice('grid_tool', tool_x(0), top - 92 - extra_header, 130 * toolbar_scale)
            ui.choice('grid_channel', tool_x(136), top - 92 - extra_header, 118 * toolbar_scale)
        end
        button(tool_x(260), top - 92 - extra_header, 56 * toolbar_scale, 'Copy', 'copy_selection')
        button(tool_x(322), top - 92 - extra_header, 56 * toolbar_scale, 'Paste', 'paste_selection')
        button(tool_x(384), top - 92 - extra_header, 56 * toolbar_scale, 'Undo', 'undo')
        button(tool_x(446), top - 92 - extra_header, 56 * toolbar_scale, 'Redo', 'redo')
        if toolbar_pattern then
            ui.button(tool_x(508), top - 92 - extra_header, 142 * toolbar_scale, 26, 'Pattern LUT Editor', function()
                ui.activate('pattern_open')
            end, {
                accent = { 244, 202, 53 },
                ink = { 25, 28, 31 },
                help = 'Edit separate 3x1 Pattern LUTs.',
            })
        end
        button(
            tool_x(toolbar_pattern and 656 or 508),
            top - 92 - extra_header,
            142 * toolbar_scale,
            '[ ' .. (h.get('show_alpha') and 'x' or ' ') .. ' ] Show Alpha',
            'show_alpha'
        )
        local grid_top = top - 129 - extra_header
        local grid_floor = gridbottom + 30
        local width_cell = (left - 98) / d.width
        if portrait_width then
            width_cell = math.min(width_cell, (left - portrait_width - 112) / d.width)
        end
        local space = math.max(18, grid_top - grid_floor)
        local cell = math.max(4, math.min(d.height > 8 and 40 or 64, width_cell, space / math.min(d.height, 8)))
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
                ui.button(x, gridbottom + 3, 54, 24, label, function()
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
                top - 119 - extra_header,
                d.width == 23 and semantics.short_columns[c] or tostring(c),
                12,
                muted,
                cell - 2
            )
        end
        local row = h.get('edit_row')
        local column = h.get('edit_column')
        local function select_cell(selected_row, selected_col)
            self.open_row = selected_row
            if h.get('edit_row') ~= selected_row then
                assert(h.set('edit_row', selected_row))
            end
            if h.get('edit_column') ~= selected_col then
                assert(h.set('edit_column', selected_col))
            end
            self.focus_column = selected_col
            for i, col in ipairs(color_columns) do
                if col == selected_col then
                    if h.get('color_field') ~= i then
                        assert(h.set('color_field', i))
                    end
                    break
                end
            end
            self.sync()
        end
        local function begin_selection_drag(selected_row, selected_col, rows_only)
            if not ui.begin_drag or not self.selection then
                return
            end
            local state = {
                document = d,
                data = d.data,
                width = d.width,
                height = d.height,
                source = d.source,
                gear = self.gear,
                row = selected_row,
                column = selected_col,
                anchor_row = self.selection.anchor_row or self.selection.r1,
                anchor_col = self.selection.anchor_col or self.selection.c1,
                selection = self.selection,
                rows_only = rows_only,
            }
            selection_drag = state
            local function cancel()
                if not same_source(state) and self.selection == state.selection then
                    self.selection = nil
                end
                if selection_drag == state then
                    selection_drag = nil
                end
            end
            local function move(x, y)
                if selection_drag ~= state then
                    return
                end
                if not same_source(state) or h.get('grid_tool') ~= 1 then
                    if state.cancel then
                        state.cancel()
                    else
                        cancel()
                    end
                    return
                end
                if not x or not y then
                    return
                end
                local selected_col = rows_only and 1
                    or math.max(1, math.min(d.width, math.floor((x - ui.x - 82) / cell) + 1))
                local selected_row =
                    math.max(first_row, math.min(last_row, first_row + math.floor((grid_top - y) / cell)))
                if selected_row == state.row and selected_col == state.column then
                    return
                end
                state.row, state.column = selected_row, selected_col
                if rows_only then
                    self.select_rows(state.anchor_row, selected_row)
                else
                    self.selection = {
                        anchor_row = state.anchor_row,
                        anchor_col = state.anchor_col,
                        r1 = math.min(state.anchor_row, selected_row),
                        r2 = math.max(state.anchor_row, selected_row),
                        c1 = math.min(state.anchor_col, selected_col),
                        c2 = math.max(state.anchor_col, selected_col),
                    }
                end
                state.selection = self.selection
                select_cell(selected_row, selected_col)
                if self.set_paste_anchor then
                    self.set_paste_anchor(self.selection.r1, self.selection.c1)
                end
            end
            state.cancel = ui.begin_drag(move, function(x, y)
                move(x, y)
                cancel()
            end, cancel)
        end
        local can_identify = mod.controls.identify_region
        local fill_ui = setmetatable({
            rect = function(x, y, width, height, color, alpha)
                ui.rect(x, y, width, height, color, alpha, 'swatch_fill')
            end,
        }, { __index = ui })
        for r = first_row, last_row do
            local y = grid_top - (r - first_row + 1) * cell
            local selected_row = r
            ui.bounded(ui.x + 10, y + cell * 0.35, 'Row ' .. r, 12, { 244, 202, 53 }, 68)
            ui.hit(
                ui.x + 8,
                y,
                70,
                cell,
                function()
                    local ok, why = pcall(function()
                        if h.get('grid_tool') ~= 1 then
                            assert(h.set('grid_tool', 1))
                        end
                        local anchor = ui.shift
                                and ui.shift()
                                and self.selection
                                and (self.selection.anchor_row or self.selection.r1)
                            or selected_row
                        self.select_rows(anchor, selected_row)
                        select_cell(selected_row, 1)
                        self.set_paste_anchor(self.selection.r1, 1)
                        begin_selection_drag(selected_row, 1, true)
                    end)
                    if not ok then
                        note(tostring(why))
                    end
                end,
                can_identify
                        and function()
                            assert(h.set('edit_row', selected_row))
                            self.sync()
                            ui.activate('identify_region')
                        end
                    or nil,
                nil,
                'Click or drag to select whole rows. Shift-click extends the row range.'
                    .. (can_identify and ' Right-click to flash this region.' or '')
            )
        end
        for r = first_row, last_row do
            for c = 1, d.width do
                local selected_row, selected_col = r, c
                local index = semantics.index(r, c, 1, d.width, d.height)
                local x = ui.x + 82 + (c - 1) * cell
                local y = grid_top - (r - first_row + 1) * cell
                local color = rgb(d.data, index)
                local channel = h.get('grid_channel')
                if channel >= 3 then
                    local value = math.floor(math.max(0, math.min(1, d.data[index + channel - 3])) * 255 + 0.5)
                    color = { value, value, value }
                end
                ui.rect(x, y, cell, cell, { 75, 78, 82 }, nil, 'swatch_border')
                if deps.swatch then
                    deps.swatch(
                        fill_ui,
                        x + 1,
                        y + 1,
                        cell - 2,
                        cell - 2,
                        color,
                        d.data[index + 3],
                        h.get('show_alpha') and channel < 3
                    )
                else
                    fill_ui.rect(x + 1, y + 1, cell - 2, cell - 2, color)
                end
                ui.hit(
                    x,
                    y,
                    cell,
                    cell,
                    function()
                        local ok, why = pcall(function()
                            if self.clear_value_focus then
                                self.clear_value_focus()
                            end
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
                                self.selection = {
                                    anchor_row = selected_row,
                                    anchor_col = selected_col,
                                    r1 = selected_row,
                                    r2 = selected_row,
                                    c1 = selected_col,
                                    c2 = selected_col,
                                }
                            end
                            select_cell(selected_row, selected_col)
                            if self.selection and self.set_paste_anchor then
                                self.set_paste_anchor(self.selection.r1, self.selection.c1)
                            end
                            if tool == 1 then
                                begin_selection_drag(selected_row, selected_col)
                            end
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
                    function()
                        local values = deps.swatch_tooltip and deps.swatch_tooltip(d, selected_row, selected_col)
                        return values and (values .. '\nDouble-click edits. Middle-click copies.') or nil
                    end,
                    function()
                        self.focus_cell(selected_row, selected_col)
                        ui.activate('cell_color')
                    end
                )
            end
        end
        -- Stroke every selected cell boundary without painting a filled gold
        -- surface. Shared edges are drawn once; RGB/checkers keep their bounds.
        local selected = self.selection or { r1 = row, r2 = row, c1 = column, c2 = column }
        local selected_first, selected_last = math.max(first_row, selected.r1), math.min(last_row, selected.r2)
        if selected_first <= selected_last then
            local x = ui.x + 82 + (selected.c1 - 1) * cell
            local y = grid_top - (selected_last - first_row + 1) * cell
            local width = (selected.c2 - selected.c1 + 1) * cell
            local height = (selected_last - selected_first + 1) * cell
            local gold, border = { 244, 202, 53 }, 2
            for c = selected.c1, selected.c2 + 1 do
                local edge = ui.x + 82 + (c - 1) * cell
                ui.rect(edge - border / 2, y, border, height, gold, nil, 'selection_outline')
            end
            for r = selected_first, selected_last + 1 do
                local edge = grid_top - (r - first_row) * cell
                ui.rect(x - border / 2, edge - border / 2, width + border, border, gold, nil, 'selection_outline')
            end
        end
        if show_values then
            if ui.choice then
                ui.choice('edit_row', right + 8, top - 57, rightw - 16)
            end
            if can_identify then
                -- Stop Highlight is kept in the persistent tools bar.
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
            local clip_top, clip_bottom = top - 96, gridbottom + 12
            self.value_bounds = { x = right, y = gridbottom, w = rightw, h = ui.h - content_bottom }
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
                        ui.rect(
                            right + 8,
                            cursor,
                            rightw - 20,
                            23,
                            (ui.surface_color(right + 8, cursor, rightw - 20, 23, { selected = r == row }))
                        )
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
                            local function prepare(channel)
                                assert(h.set('edit_row', selected_row))
                                assert(h.set('edit_column', selected_col))
                                for i, col in ipairs(color_columns) do
                                    if col == selected_col then
                                        assert(h.set('color_field', i))
                                        break
                                    end
                                end
                                self.sync()
                                if channel and self.focus_value then
                                    self.focus_value(selected_row, selected_col, channel)
                                end
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
                                ipairs(
                                    words(semantics.hints[c] or 'Unconfirmed shader meaning. Raw values are retained.')
                                )
                            do
                                local line_height = math.max(14, (ui.text_size and ui.text_size(13) or 13) + 3)
                                cursor = cursor - line_height
                                if visible(cursor, line_height) then
                                    ui.bounded(right + 12, cursor + 2, line, 13, muted, rightw - 36)
                                end
                            end
                            for ch, name in ipairs({ 'r', 'g', 'b', 'a' }) do
                                local selected_channel = ch
                                local enum = (c == 1 and ch == 4 and 'shader_mode')
                                    or (c == 2 and ch == 1 and 'detail_texture')
                                    or (c == 22 and ch == 4 and 'camo_pattern')
                                local numeric_height = math.max(21, (ui.text_size and ui.text_size(14) or 14) + 8)
                                local field_height = enum and 26 or numeric_height
                                cursor = cursor - field_height - 4
                                if visible(cursor, field_height) then
                                    local value = tonumber(d.data[semantics.index(r, c, ch, d.width, d.height)])
                                    ui.text(right + 12, cursor + 6, name:upper(), 13, muted)
                                    if enum and ui.choice then
                                        ui.choice(enum, right + 29, cursor, rightw - 46, function()
                                            prepare(selected_channel)
                                        end)
                                    elseif ui.number then
                                        local lo, hi = semantics.range(c, ch, value)
                                        ui.number(
                                            'cell_' .. name,
                                            right + 29,
                                            cursor,
                                            rightw - 46,
                                            value,
                                            function()
                                                prepare(selected_channel)
                                            end,
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
        end -- optional Value Editor
        overlays()
    end
    return layout
end
return V
