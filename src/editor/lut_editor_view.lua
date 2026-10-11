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
    local splitter_drag
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
        local pattern = self.pattern_editor
        local pattern_host = not self.embedded and pattern and pattern.workspace and pattern.quick
        if pattern_host and pattern.set_workspace_host then
            pattern.set_workspace_host(true)
        end
        local pattern_full = pattern_host and pattern.is_open and pattern.is_open()
        if selection_drag and (pattern_full or not same_source(selection_drag) or h.get('grid_tool') ~= 1) then
            selection_drag.cancel()
        end
        if
            splitter_drag
            and (
                not same_source(splitter_drag)
                or self.tools ~= splitter_drag.tools
                or not self.tools.is_open()
                or not self.tools.is_docked()
                or splitter_drag.pattern_full ~= pattern_full
            )
        then
            splitter_drag.stop('Tools layout changed')
        end
        self.tools_splitter = nil
        self.pattern_quick_bounds, self.pattern_workspace_bounds = nil, nil
        local mod = self.api.mods[h.id]
        local theme = ui.theme
        local dark, blue, white, muted = theme.panel, theme.header, theme.white, theme.muted
        local show_values = h.get('value_editor_visible') ~= false
        local left = show_values and math.floor(ui.w * 0.70) or ui.w
        local tools_bounds
        self.grid_bounds, self.value_bounds, self.value_viewport = nil, nil, nil
        if not d then
            self.grid_max = 0
        end
        local right = ui.x + left + 12
        local rightw = ui.w - left - 12
        local top = ui.y + ui.h
        local gear_controls = mod.controls.editor_load_armor
        local font_scale = (ui.text_size and ui.text_size(14) or 12) / 12
        local panel_header_height = math.max(27, ui.control_height and ui.control_height(17, 4, 27, 'heading') or 0)
        local header_shift = panel_header_height - 27
        local header_bottom = top - panel_header_height
        local header_height = math.max(26, ui.control_height and ui.control_height(14, 5) or 0)
        local header_gap = 10 * font_scale
        local header_items, header_rows, header_x = {}, 1, 10
        local function header_item(label, kind)
            local width =
                math.min(left - 20, (ui.text_width and ui.text_width(label, 14) or #label * 8) + 18 * font_scale)
            if header_x > 10 and header_x + width > left - 10 then
                header_rows, header_x = header_rows + 1, 10
            end
            header_items[#header_items + 1] =
                { label = label, kind = kind, x = header_x, width = width, row = header_rows }
            header_x = header_x + width + 6 * font_scale
        end
        if gear_controls then
            header_item('Helmet LUT', 'helmet')
            header_item('Armor LUT', 'armor')
            if self.pattern_editor then
                header_item('Pattern LUT Editor', 'pattern')
            end
            header_item('Load Current Gear', 'load')
        end
        local extra_header = gear_controls and (header_height + header_rows * (header_height + header_gap) - 26)
            or (self.embedded and -34 or 0)
        extra_header = extra_header + header_shift
        local footer_inset = 6 * font_scale
        local footer_height = math.max(26 * font_scale, ui.control_height and ui.control_height(14, 5) or 0)
        local footer_band = footer_height + footer_inset * 2
        if self.embedded then
            footer_band = 0
        end
        local content_bottom = footer_band + 4 * font_scale
        local gridbottom = ui.y + content_bottom
        local portrait = not self.embedded and package.loaded['epic.player_preview.v1']
        local function panel(x, y, w, height, title, reserved, header_plane)
            ui.rect(x, y, w, height, dark)
            local finish_header = header_plane and ui.surface and ui.surface(header_plane)
            local header_y = y + height - panel_header_height
            ui.rect(x, header_y, w, panel_header_height, blue)
            if ui.epic_style then
                local edge = ui.pixel_width or 1
                ui.rect(x, y, w, edge, theme.line, nil, 'control_accent')
                ui.rect(x, y, edge, height, theme.line, nil, 'control_accent')
                ui.rect(x + w - edge, y, edge, height, theme.line, nil, 'control_accent')
                ui.rect(x, header_y, w, edge, theme.line, nil, 'control_accent')
                ui.rect(
                    x + 8 * font_scale,
                    header_y,
                    math.min(40 * font_scale, w),
                    edge * 2,
                    theme.brass,
                    nil,
                    'control_accent'
                )
            end
            ui.bounded(
                x + 8 * font_scale,
                ui.text_y and ui.text_y(header_y, panel_header_height, 17, title, 'heading') or header_y + 6,
                title,
                17,
                white,
                math.max(0, w - 16 * font_scale - (reserved or 0)),
                'heading'
            )
            if finish_header then
                finish_header()
            end
        end
        local function button(x, y, w, label, id, height)
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
            ui.button(x, y, w, height or 26, label, function()
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
            (pattern_full and 'Pattern LUT' or self.is_dirty() and 'Pixel Grid - unsaved edits' or 'Pixel Grid')
                .. (
                    pattern_full and ' / 1 x 3'
                    or d and (' / ' .. d.height .. ' x ' .. d.width .. ' / ' .. (d.source or 'Current LUT')
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
            panel(
                right,
                gridbottom,
                rightw,
                ui.h - content_bottom,
                compact and 'Values' or 'Value Editor',
                reserved,
                130
            )
            if actions then
                local finish_actions = ui.surface and ui.surface(130)
                local function value_action(id, label, x)
                    local control = mod.controls[id]
                    ui.button(x, top - panel_header_height + 2, action_width, panel_header_height - 4, label, function()
                        ui.activate(id)
                    end, { enabled = not control.disabled, size = 13, help = control.description })
                end
                value_action('copy_value', copy_label, right + rightw - 8 - action_width * 2 - 4)
                value_action('paste_value', paste_label, right + rightw - 8 - action_width)
                if finish_actions then
                    finish_actions()
                end
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
                if self.tools.dock then
                    self.tools.dock(ui, tools_bounds)
                end
                self.tools.popup(ui)
            end
            if self.pattern_editor then
                self.pattern_editor.popup(ui)
            end
            if self.scratch_tool then
                self.scratch_tool.popup(ui)
            end
        end
        if not self.embedded then
            local finish_footer = ui.surface and ui.surface(130)
            ui.rect(ui.x, ui.y, ui.w, footer_band, dark)
            local function shortcut(x, width, label, action, selected, enabled, primary)
                ui.button(x, ui.y + footer_inset, width, footer_height, label, action, {
                    selected = selected,
                    enabled = enabled,
                    accent = primary and { 244, 202, 53 },
                    ink = primary and { 25, 28, 31 },
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
            local selector = mod.controls['basic_' .. (self.gear or 'armor') .. '_lut']
            local selected = selector and selector.choices[h.get(selector.id)]
            local apply_label = 'Apply ' .. (selected and selected:match('^Cape') and 'cape' or self.gear or 'palette')
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
            if self.tools and self.tools.is_open() and self.tools.is_docked and self.tools.is_docked() then
                local title_x = ui.x + 8 * font_scale + tools_width + gap
                local title_width = fixed_x - title_x - gap
                if title_width > 0 then
                    ui.bounded(
                        title_x,
                        ui.text_y and ui.text_y(ui.y + footer_inset, footer_height, 14, 'LUT Editor Tools', 'heading')
                            or ui.y + footer_inset + 4,
                        'LUT Editor Tools',
                        14,
                        muted,
                        title_width,
                        'heading'
                    )
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
                brush_label_width
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
                end, nil, not mod.controls[apply_id].disabled, true)
                fx = fx + apply_width
            end
            if stop_width > 0 then
                shortcut(fx + gap, stop_width, 'Stop Highlight', function()
                    ui.activate('stop_identify')
                end)
            end
            if finish_footer then
                finish_footer()
            end
        end -- main footer
        if gear_controls then
            self.gear = self.gear == 'helmet' and 'helmet' or 'armor'
            for _, item in ipairs(header_items) do
                local target = item.kind
                local featured = target == 'load'
                local ready = target == 'load'
                    or target == 'pattern'
                    or target ~= 'pattern' and (not self.can_select_gear or self.can_select_gear(target))
                ui.button(
                    ui.x + item.x,
                    top - 32 - header_shift - header_height - (item.row - 1) * (header_height + header_gap),
                    item.width,
                    header_height,
                    item.label,
                    function()
                        if target == 'load' then
                            ui.activate('populate_worn')
                        elseif target == 'pattern' then
                            ui.activate('pattern_open')
                        else
                            if pattern_full and pattern.dismiss then
                                if pattern.dismiss() == false then
                                    return
                                end
                                if self.gear == target then
                                    return
                                end
                            end
                            self.gear = target
                            ui.activate('editor_load_' .. target)
                        end
                    end,
                    {
                        enabled = ready,
                        selected = target == 'pattern' and pattern_full or not pattern_full and self.gear == target,
                        accent = featured
                            and (
                                target == 'load' and ui.load_color(self.load_seen and self.load_seen())
                                or { 244, 202, 53 }
                            ),
                        ink = featured and { 25, 28, 31 },
                        help = target == 'armor' and 'Select Armor or Cape LUTs from the dropdown below.'
                            or target == 'pattern' and 'Edit separate 3x1 Armor and Helmet Pattern LUTs.',
                    }
                )
            end
            local selector_x = ui.x + 28
            local selector_y = top - 32 - header_shift - header_height - header_rows * (header_height + header_gap)
            header_bottom = selector_y
            if not pattern_full then
                local selector_width = math.min(220, left * 0.32)
                ui.rect(ui.x + 16, selector_y, 2, 26, theme.focus, nil, 'control_accent')
                ui.choice('basic_' .. self.gear .. '_lut', selector_x, selector_y, selector_width)
                local control = self.api.mods[self.handle.id].controls['basic_' .. self.gear .. '_lut']
                local resource = control.choice_details
                    and control.choice_details[h.get('basic_' .. self.gear .. '_lut')]
                local hash = control.choice_hashes and control.choice_hashes[h.get('basic_' .. self.gear .. '_lut')]
                local resource_width = ui.x + left - selector_x - selector_width - 30
                if resource and resource_width > 40 then
                    if hash and mod.controls.rename_lut then
                        ui.hit(
                            selector_x + 12 + selector_width,
                            selector_y,
                            resource_width,
                            26,
                            function()
                                ui.activate('rename_lut')
                            end,
                            nil,
                            nil,
                            '[0x' .. hash .. ']\nClick to name this LUT. Clear its name to show the texture ID again.'
                        )
                    end
                    ui.bounded(
                        selector_x + 12 + selector_width,
                        ui.text_y and ui.text_y(selector_y, 26, 12, resource, 'hint') or selector_y + 8,
                        resource,
                        12,
                        muted,
                        resource_width,
                        'hint'
                    )
                end
            end
        elseif d and mod.controls.lut and ui.choice then
            ui.choice('lut', ui.x + 10, top - 58 - header_shift, math.min(360, left - 24))
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
        local docking = not self.embedded
            and self.tools
            and self.tools.is_open()
            and self.tools.is_docked
            and self.tools.is_docked()
        local function dock_tools(ceiling)
            local available = ceiling - gridbottom - 16 * font_scale
            if not docking or available <= 0 then
                return
            end
            tools_bounds = {
                x = ui.x + 8 * font_scale,
                y = gridbottom + 8 * font_scale,
                w = left - (portrait_width or 0) - 16 * font_scale,
                h = available,
            }
        end
        if not d and not pattern_full then
            -- Empty documents share the responsive header with loaded ones.
            -- Flow each block from its predecessor instead of retaining the
            -- pre-header offsets, and reserve the measured font ink height.
            local gap, width = 8 * font_scale, left - 24
            local cursor = header_bottom - gap
            local row_height = math.max(26, 26 * font_scale, ui.control_height and ui.control_height(15, 5) or 0)
            local function message(value, size, color, role)
                local lines, line = {}, ''
                local resolved = ui.text_size and ui.text_size(size, role) or size
                for word in value:gmatch('%S+') do
                    local candidate = line == '' and word or line .. ' ' .. word
                    local measured = ui.text_width and ui.text_width(candidate, size, role)
                        or #candidate * resolved * 0.62
                    if line ~= '' and measured > width then
                        lines[#lines + 1], line = line, word
                    else
                        line = candidate
                    end
                end
                if line ~= '' then
                    lines[#lines + 1] = line
                end
                for i, text in ipairs(lines) do
                    local metrics = ui.text_metrics and ui.text_metrics(size, text, role)
                        or { height = resolved, min_y = 0 }
                    cursor = cursor - metrics.height
                    ui.bounded(ui.x + 12, cursor - metrics.min_y, text, size, color, width, role)
                    if i < #lines then
                        cursor = cursor - 4 * font_scale
                    end
                end
                cursor = cursor - gap
            end
            local browse_width = math.min(
                width,
                math.max(180, (ui.text_width and ui.text_width('Choose file...', 15) or 112) + 16 * font_scale)
            )
            local gear = self.api and self.api.mods[self.handle.id].controls.editor_load_armor
            if gear then
                message('Load Current Gear to enable the Armor and Helmet selectors.', 18, white)
                cursor = cursor - row_height
                local load_width = width - browse_width - gap
                button(
                    ui.x + 12,
                    cursor,
                    load_width,
                    'Load Current ' .. (self.gear == 'armor' and 'Armor' or 'Helmet'),
                    'editor_load_' .. self.gear,
                    row_height
                )
                button(ui.x + 12 + load_width + gap, cursor, browse_width, 'Choose file...', 'browse', row_height)
                cursor = cursor - gap
                message('Uses currently worn LUT values; a file import is optional.', 14, muted, 'hint')
                dock_tools(cursor)
                overlays()
                return
            end
            message('Choose a DDS or ZIP to begin.', 18, white)
            cursor = cursor - row_height
            button(ui.x + 12, cursor, browse_width, 'Choose file...', 'browse', row_height)
            local populate_label = 'Populate editor with current applied palette'
            local populate_x = ui.x + 12 + browse_width + gap
            local populate_width = width - browse_width - gap
            local measured = ui.text_width and ui.text_width(populate_label, 15) or #populate_label * 8
            if populate_width < measured + 16 * font_scale then
                cursor = cursor - row_height - gap
                populate_x, populate_width = ui.x + 12, width
            end
            button(populate_x, cursor, populate_width, populate_label, 'populate_applied', row_height)
            cursor = cursor - gap
            if ui.choice then
                cursor = cursor - 26
                ui.choice('lut', ui.x + 12, cursor, math.min(360, width))
                cursor = cursor - gap
            end
            message('Uses the applied values from the selected Live LUT.', 14, muted, 'hint')
            dock_tools(cursor)
            overlays()
            return
        end
        local toolbar_pattern = self.pattern_editor and not gear_controls
        local toolbar_scale = math.min(1, (left - 20) / (toolbar_pattern and 798 or 650))
        local function tool_x(offset)
            return ui.x + 10 + offset * toolbar_scale
        end
        if not pattern_full then
            if ui.choice then
                ui.choice('grid_tool', tool_x(0), top - 92 - extra_header, 130 * toolbar_scale)
                ui.choice('grid_channel', tool_x(136), top - 92 - extra_header, 118 * toolbar_scale)
            end
            button(tool_x(260), top - 92 - extra_header, 56 * toolbar_scale, 'Copy', 'copy_selection')
            button(tool_x(322), top - 92 - extra_header, 56 * toolbar_scale, 'Paste', 'paste_selection')
            button(tool_x(384), top - 92 - extra_header, 56 * toolbar_scale, 'Undo', 'undo')
            button(tool_x(446), top - 92 - extra_header, 56 * toolbar_scale, 'Redo', 'redo')
            if toolbar_pattern then
                ui.button(
                    tool_x(508),
                    top - 92 - extra_header,
                    142 * toolbar_scale,
                    26,
                    'Pattern LUT Editor',
                    function()
                        ui.activate('pattern_open')
                    end,
                    {
                        help = 'Edit separate 3x1 Pattern LUTs.',
                    }
                )
            end
            button(
                tool_x(toolbar_pattern and 656 or 508),
                top - 92 - extra_header,
                142 * toolbar_scale,
                '[ ' .. (h.get('show_alpha') and 'x' or ' ') .. ' ] Show Alpha',
                'show_alpha'
            )
        end
        local quick_height = pattern_host and not pattern_full and pattern.quick_height and pattern.quick_height(ui)
            or 0
        local grid_top = pattern_full and (header_bottom + (gear_controls and 26 or 0) - 8 * font_scale)
            or top - 129 - extra_header
        local grid_floor = gridbottom + 30 + quick_height
        if grid_top <= grid_floor then
            self.grid_bounds = nil
            overlays()
            return
        end
        local grid_width, grid_height = d and d.width or 23, d and d.height or 8
        local width_cell = (left - 98) / grid_width
        if portrait_width then
            width_cell = math.min(width_cell, (left - portrait_width - 112) / grid_width)
        end
        local space = math.max(18, grid_top - grid_floor)
        local rows_to_fit = math.min(grid_height, 8)
        local preferred_cell = math.max(4, math.min(self.embedded and grid_height <= 8 and 64 or 40, width_cell))
        local minimum_cell =
            math.min(preferred_cell, math.max(18, ui.control_height and ui.control_height(12, 2, 18) or 18))
        local cell = math.max(minimum_cell, math.min(preferred_cell, space / rows_to_fit))
        if docking then
            local minimum = self.tools.minimum_height and self.tools.minimum_height(ui) or 140
            local bottom = gridbottom + 8 * font_scale
            local total = math.max(0, grid_top - bottom - 30 - 8 * font_scale - quick_height)
            local minimum_grid = pattern_full and math.max(120, 120 * font_scale)
                or minimum_cell * math.min(2, grid_height)
            local maximum = math.max(0, total - minimum_grid - 8 * font_scale)
            minimum = math.min(minimum, maximum)
            local available = math.max(4, total - minimum)
            cell = math.max(minimum_cell, math.min(preferred_cell, available / rows_to_fit))
            local rows = math.min(rows_to_fit, math.max(1, math.floor((available + 0.01) / cell)))
            -- Reserve readable rows before giving the remaining height to Tools.
            -- Wider cells must not evict rows when Values or Preview are hidden.
            local wanted = pattern_full and minimum or math.max(minimum, total - cell * rows - 8 * font_scale)
            dock_tools(gridbottom + 16 * font_scale + wanted)
            if tools_bounds then
                local ratio = self.tools.split_ratio
                if type(ratio) == 'number' and ratio == ratio and math.abs(ratio) ~= math.huge then
                    tools_bounds.h = math.max(minimum, math.min(maximum, ratio * total))
                else
                    tools_bounds.h = math.max(minimum, math.min(maximum, tools_bounds.h))
                end
                local line_y = tools_bounds.y + tools_bounds.h + 4 * font_scale
                local hit_height = 8 * font_scale + 2
                self.tools_splitter = {
                    x = tools_bounds.x,
                    y = line_y - hit_height / 2,
                    w = tools_bounds.w,
                    h = hit_height,
                    line_y = line_y,
                    line_offset = 4 * font_scale,
                    bottom = tools_bounds.y,
                    total = total,
                    minimum = minimum,
                    maximum = maximum,
                    minimum_cell = minimum_cell,
                }
                grid_floor = tools_bounds.y + tools_bounds.h + 8 * font_scale + 30 + quick_height
                space = math.max(4, grid_top - grid_floor)
            end
        end
        -- The final viewport includes the user-selected Tools split. Clamp cell
        -- growth against that height, keeping text readable when scrolling is needed.
        cell = math.max(minimum_cell, math.min(preferred_cell, space / rows_to_fit))
        if self.tools_splitter then
            self.tools_splitter.cell = cell
        end
        local row, column = h.get('edit_row'), h.get('edit_column')
        local can_identify = mod.controls.identify_region
        if not pattern_full then
            local visible_rows = math.max(1, math.min(d.height, math.floor((space + 0.01) / cell)))
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
                    grid_floor - 19,
                    'Rows ' .. first_row .. '-' .. last_row .. ' of ' .. d.height .. ' / scroll here',
                    12,
                    muted,
                    left - 150,
                    'hint'
                )
                local function navigate(x, label, direction)
                    ui.button(x, grid_floor - 27, 54, 24, label, function()
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
                    cell - 2,
                    'hint'
                )
            end
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
            local fill_ui = setmetatable({
                rect = function(x, y, width, height, color, alpha)
                    ui.rect(x, y, width, height, color, alpha, 'swatch_fill')
                end,
            }, { __index = ui })
            for r = first_row, last_row do
                local y = grid_top - (r - first_row + 1) * cell
                local selected_row = r
                ui.bounded(ui.x + 10, y + cell * 0.35, 'Row ' .. r, 12, r == row and theme.brass or muted, 68)
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
        end -- Material table; Pattern workspace owns its replacement rectangle.
        if pattern_host then
            local bounds = {
                x = ui.x + 8 * font_scale,
                y = grid_floor - quick_height - 30,
                w = left - (portrait_width or 0) - 16 * font_scale,
                h = pattern_full and grid_top - grid_floor + 30 or quick_height,
            }
            if pattern_full then
                self.pattern_workspace_bounds = bounds
                pattern.workspace(ui, bounds)
            else
                self.pattern_quick_bounds = bounds
                local control = mod.controls['basic_' .. (self.gear or 'armor') .. '_lut']
                local chosen = control and control.choices[h.get(control.id)]
                pattern.quick(ui, bounds, chosen and chosen:match('^Cape') and 'cape' or self.gear)
            end
        end
        if show_values and d then
            local finish_options = ui.surface and ui.surface(130)
            local inspector_button_width = (rightw - 21) / 2
            local inspector_gap = 6 * font_scale
            local selector_y = top - panel_header_height - inspector_gap - 26
            local options_height = math.max(26, ui.control_height and ui.control_height(15, 5, 26) or 0)
            local options_y = selector_y - inspector_gap - options_height
            local function inspector_label(full, compact)
                local width = ui.text_width and ui.text_width(full, 15) or #full * 8
                return width + 16 * font_scale <= inspector_button_width and full or compact
            end
            if ui.choice then
                ui.choice('edit_row', right + 8, selector_y, rightw - 16)
            end
            if can_identify then
                -- Stop Highlight is kept in the persistent tools bar.
            end
            button(
                right + 8,
                options_y,
                inspector_button_width,
                inspector_label(
                    h.get('group_rows') and 'Group by rows: ON' or 'Selected row only',
                    h.get('group_rows') and 'All rows' or 'One row'
                ),
                'group_rows',
                options_height
            )
            button(
                right + 13 + (rightw - 21) / 2,
                options_y,
                inspector_button_width,
                inspector_label(
                    h.get('unlock') and 'Advanced: ON' or 'Unlock advanced edits',
                    h.get('unlock') and 'Advanced' or 'Unlock'
                ),
                'unlock',
                options_height
            )
            if finish_options then
                finish_options()
            end
            local clip_top, clip_bottom = options_y - inspector_gap, gridbottom + 12
            local viewport = math.max(0, clip_top - clip_bottom)
            self.value_viewport = { x = right, y = clip_bottom, w = rightw, h = viewport }
            self.value_bounds = self.value_viewport
            local scroll = math.max(0, self.value_scroll)
            local cursor = clip_top + scroll
            local function visible(y, height)
                return viewport > 0 and y < clip_top and y + height > clip_bottom
            end
            local function text_height(size, value, role, padding, minimum)
                return math.max(
                    minimum,
                    ui.control_height and ui.control_height(size, padding, value, role)
                        or (ui.text_size and ui.text_size(size, role) or size) + padding * 2 * font_scale
                )
            end
            local function text_inside(y, height, size, value, role)
                if not ui.text_metrics or not ui.text_y then
                    return visible(y, height)
                end
                local ink = ui.text_metrics(size, value, role)
                local baseline = ui.text_y(y, height, size, value, role)
                return visible(baseline + ink.min_y, ink.height)
            end
            local function words(value)
                local lines, line = {}, ''
                local width = rightw - 36
                local size = ui.text_size and ui.text_size(13, 'hint') or 13
                local function fits(value)
                    return (ui.text_width and ui.text_width(value, 13, 'hint') or #value * size * 0.62) <= width
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
            self.value_wheel_step = math.max(8, math.min(24, text_height(13, 'Value', 'hint', 1, 14)))
            local content
            local function draw_body()
                for r = 1, d.height do
                    if h.get('group_rows') or r == row then
                        local selected_row = r
                        local row_label = (self.open_row == r and 'v ' or '> ') .. 'Row ' .. r
                        local row_heading_height = text_height(14, row_label, 'heading', 4, 23)
                        cursor = cursor - row_heading_height - 2 * font_scale
                        if text_inside(cursor, row_heading_height, 14, row_label, 'heading') then
                            local row_selected = r == row
                            if not ui.epic_style or self.open_row == r or row_selected then
                                ui.rect(
                                    right + 8,
                                    cursor,
                                    rightw - 20,
                                    row_heading_height,
                                    (
                                        ui.surface_color(
                                            right + 8,
                                            cursor,
                                            rightw - 20,
                                            row_heading_height,
                                            { selected = r == row }
                                        )
                                    )
                                )
                            end
                            if ui.epic_style then
                                local edge = ui.pixel_width or 1
                                ui.rect(right + 8, cursor, rightw - 20, edge, theme.line, nil, 'control_accent')
                                if row_selected then
                                    ui.rect(
                                        right + 8,
                                        cursor,
                                        edge * 2,
                                        row_heading_height,
                                        theme.brass,
                                        nil,
                                        'control_accent'
                                    )
                                end
                            end
                            local pulse = 0.5 + 0.5 * math.sin(os.clock() * 3)
                            ui.text(
                                right + 13,
                                ui.text_y and ui.text_y(cursor, row_heading_height, 14, row_label, 'heading')
                                    or cursor + 6,
                                row_label,
                                14,
                                ui.epic_style and (row_selected and theme.brass or white)
                                    or can_identify and {
                                        math.floor(175 + 69 * pulse),
                                        math.floor(180 + 22 * pulse),
                                        math.floor(140 - 87 * pulse),
                                    }
                                    or white,
                                'heading'
                            )
                            ui.hit(right + 8, cursor, can_identify and 24 or rightw - 20, row_heading_height, function()
                                local expanded = self.open_row ~= selected_row
                                assert(h.set('edit_row', selected_row))
                                self.value_scroll = 0
                                self.sync()
                                self.open_row = expanded and selected_row or nil
                            end)
                            if can_identify then
                                ui.hit(right + 32, cursor, rightw - 44, row_heading_height, function()
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
                                local column_label = 'Column ' .. c .. ': ' .. semantics.columns[c]
                                local column_heading_height = text_height(14, column_label, 'heading', 3, 21)
                                cursor = cursor - column_heading_height
                                if text_inside(cursor, column_heading_height, 14, column_label, 'heading') then
                                    ui.bounded(
                                        right + 12,
                                        ui.text_y
                                                and ui.text_y(
                                                    cursor,
                                                    column_heading_height,
                                                    14,
                                                    column_label,
                                                    'heading'
                                                )
                                            or cursor + 3,
                                        column_label,
                                        14,
                                        white,
                                        rightw - 58,
                                        'heading'
                                    )
                                    if true then
                                        local index = semantics.index(r, c, 1, d.width, d.height)
                                        local chip_y = cursor + (column_heading_height - 18) / 2
                                        ui.rect(
                                            right + rightw - 40,
                                            chip_y,
                                            24,
                                            18,
                                            rgb(d.data, index),
                                            nil,
                                            'swatch_fill'
                                        )
                                        ui.hit(right + rightw - 40, chip_y, 24, 18, function()
                                            prepare()
                                            ui.activate('cell_color')
                                        end)
                                    end
                                end
                                for _, line in
                                    ipairs(
                                        words(
                                            semantics.hints[c] or 'Unconfirmed shader meaning. Raw values are retained.'
                                        )
                                    )
                                do
                                    local line_height = text_height(13, line, 'hint', 2, 14)
                                    cursor = cursor - line_height
                                    if text_inside(cursor, line_height, 13, line, 'hint') then
                                        ui.bounded(
                                            right + 12,
                                            ui.text_y and ui.text_y(cursor, line_height, 13, line, 'hint') or cursor + 2,
                                            line,
                                            13,
                                            muted,
                                            rightw - 36,
                                            'hint'
                                        )
                                    end
                                end
                                for ch, name in ipairs({ 'r', 'g', 'b', 'a' }) do
                                    local selected_channel = ch
                                    local enum = (c == 1 and ch == 4 and 'shader_mode')
                                        or (c == 2 and ch == 1 and 'detail_texture')
                                        or (c == 22 and ch == 4 and 'camo_pattern')
                                    local numeric_height = math.max(21, (ui.text_size and ui.text_size(14) or 14) + 8)
                                    local field_height = math.max(
                                        enum and 26 or numeric_height,
                                        ui.control_height and ui.control_height(14, 5, 26) or 0
                                    )
                                    cursor = cursor - field_height - 4
                                    local value = tonumber(d.data[semantics.index(r, c, ch, d.width, d.height)])
                                    local widget_height = enum and 26 or numeric_height
                                    local channel_label = name:upper()
                                    local selected_field = r == h.get('edit_row') and c == h.get('edit_column')
                                    local field_label = enum and mod.controls[enum].choices[h.get(enum)]
                                        or (selected_field and ui.input_value and ui.input_value('cell_' .. name))
                                        or string.format('%.7g', value)
                                    if
                                        visible(cursor, field_height)
                                        or text_inside(cursor, widget_height, 13, channel_label)
                                        or text_inside(cursor, widget_height, 14, tostring(field_label))
                                    then
                                        ui.text(
                                            right + 12,
                                            ui.text_y and ui.text_y(cursor, widget_height, 13, channel_label)
                                                or cursor + 6,
                                            channel_label,
                                            13,
                                            muted
                                        )
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
                                                selected_field
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
                content = clip_top + scroll - cursor
                self.value_max = math.max(0, content - viewport)
                self.value_scroll = math.max(0, math.min(self.value_scroll, self.value_max))
            end
            if ui.viewport and viewport > 0 then
                ui.viewport(self.value_viewport, draw_body, { top = top, bottom = ui.y, color = dark })
            else
                draw_body()
            end
            if self.value_max > 0 and ui.scrollbar then
                local finish_scrollbar = ui.surface and ui.surface(130)
                ui.scrollbar(
                    'value_editor',
                    right + rightw - 8,
                    clip_bottom,
                    viewport,
                    content,
                    viewport,
                    self.value_scroll,
                    function(value)
                        -- The common scrollbar rounds intermediate offsets.
                        -- Snap endpoints so fractional font metrics cannot
                        -- leave the final whole row just outside the viewport.
                        self.value_scroll = value <= 1 and 0 or value >= self.value_max - 1 and self.value_max or value
                        self.focus_column = nil
                    end
                )
                if finish_scrollbar then
                    finish_scrollbar()
                end
            end
        end -- optional Value Editor
        overlays()
        local divider = self.tools_splitter
        if divider then
            local hovering = ui.hovering and ui.hovering(divider.x, divider.y, divider.w, divider.h)
            local color = splitter_drag and theme.focus or hovering and theme.border_hover or theme.border
            local stroke = 2 * (ui.pixel_width or 1)
            ui.rect(divider.x, divider.line_y - stroke / 2, divider.w, stroke, color, nil, 'control_accent')
            ui.rect(
                divider.x + divider.w / 2 - 16 * font_scale,
                divider.line_y - stroke * 1.5,
                32 * font_scale,
                stroke * 3,
                color,
                nil,
                'control_accent'
            )
            if ui.begin_drag and divider.maximum > divider.minimum then
                ui.hit(divider.x, divider.y, divider.w, divider.h, function()
                    local state = {
                        document = d,
                        data = d.data,
                        width = d.width,
                        height = d.height,
                        source = d.source,
                        gear = self.gear,
                        tools = self.tools,
                        pattern_full = pattern_full,
                    }
                    local function clear()
                        state.tools.splitter_dragging = false
                        if splitter_drag == state then
                            splitter_drag = nil
                        end
                    end
                    local function move(_, y)
                        if splitter_drag ~= state or not y then
                            return
                        end
                        local current = self.tools_splitter
                        if
                            not current
                            or not same_source(state)
                            or not state.tools.is_open()
                            or not state.tools.is_docked()
                        then
                            state.stop('Tools layout changed')
                            return
                        end
                        if not state.grab then
                            state.grab = y - current.line_y
                            return
                        end
                        local height = math.max(
                            current.minimum,
                            math.min(current.maximum, y - state.grab - current.line_offset - current.bottom)
                        )
                        state.tools.split_ratio = height / current.total
                    end
                    state.stop = ui.begin_drag(move, function(x, y)
                        move(x, y)
                        clear()
                    end, clear)
                    splitter_drag = state
                    state.tools.splitter_dragging = true
                end, nil, nil, 'Drag to resize the LUT table and docked Tools.')
            end
        end
    end
    return layout
end
return V
