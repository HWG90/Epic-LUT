-- Primary RGB and checked-region camo. No shader, alpha or raw-column controls.
local B = {}
B.minimum_height = 1000
function B.new(info, select_row, help, select_camo_row)
    help = help or {}
    local self = { action_scroll = 0, region_scroll = {}, region_maximum = {}, region_bounds = {} }
    function self.wheel(x, y, delta)
        local actions = self.action_bounds
        if
            actions
            and x >= actions.x
            and x <= actions.x + actions.w
            and y >= actions.y
            and y <= actions.y + actions.h
        then
            self.action_scroll = math.max(0, math.min(self.action_maximum or 0, self.action_scroll - delta / 120 * 36))
            return true
        end
        for kind, b in pairs(self.region_bounds) do
            if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
                self.region_scroll[kind] = math.max(
                    0,
                    math.min(self.region_maximum[kind] or 0, (self.region_scroll[kind] or 0) - delta / 120 * 36)
                )
                return true
            end
        end
    end
    function self.draw(ui)
        local state = info()
        local d = state.editor
        local bulk_dds = state.export_format == 4
        local top = ui.y + ui.h
        local left = ui.w * 0.54
        local right = ui.x + left + 18
        local width = ui.w - left - 18
        local theme = ui.theme
        local white, muted = theme.white, theme.muted
        local divider = theme.line
        ui.rect(ui.x + left / 2, ui.y + 48, 1, math.max(0, ui.h - 148), divider)
        ui.rect(right - 9, ui.y, 1, ui.h, divider)
        local guidance = help.basic or {}
        local function button(x, y, w, label, id, enabled, drawing, height)
            local ui = drawing or ui
            local featured = enabled ~= false
                and (id == 'populate_worn' or id == 'export_selected' or id == 'save_dds' or id == 'save_setup')
            local accent = featured and (id == 'populate_worn' and ui.load_color(state.load_seen) or { 244, 202, 53 })
            return ui.button(x, y, w, height or 28, label, function()
                ui.activate(id)
            end, {
                enabled = enabled,
                accent = accent,
                ink = featured and { 25, 28, 31 },
                help = guidance[id],
            })
        end
        local heading_size = ui.text_size and ui.text_size(14, 'heading') or 14
        local hint_size = ui.text_size and ui.text_size(14, 'hint') or 14
        local gap = ui.spacing and ui.spacing(4) or 4
        local control_height = ui.control_height and ui.control_height(14, 4, 28) or 28
        local color_label_height = ui.control_height and ui.control_height(12, 1, 14) or 14
        local color_height = math.max(22, control_height - gap)
        local colorway_y = ui.y + 38 + gap
        local camo_y = colorway_y + 26 + gap
        local color_y = camo_y + 26 + gap
        local camo_heading_y = color_y + color_height + color_label_height + gap * 2
        local load_y = top - control_height - gap
        button(ui.x + 10, load_y, left - 20, 'Load Current Gear', 'populate_worn', nil, nil, control_height)
        local gear_heading_height = ui.control_height and ui.control_height(14, 1, 20, 'heading') or heading_size + gap
        local gear_heading_y = load_y - gear_heading_height - gap
        local lut_y = gear_heading_y - 26 - gap
        local import_heading_height = ui.control_height and ui.control_height(12, 2, 20, 'heading')
            or heading_size + gap
        local import_heading_y = lut_y - import_heading_height - gap
        local import_y = import_heading_y - control_height - gap
        local region_heading_height = ui.control_height and ui.control_height(12, 1, 20, 'hint') or 20
        local region_top = state.loaded and import_y - gap * 2 or lut_y
        local cliptop = region_top - region_heading_height - gap
        local clipbottom = camo_heading_y + math.max(heading_size, hint_size) + gap
        local region_height = math.max(0, cliptop - clipbottom)
        local half = (left - 26) / 2
        for n, kind in ipairs({ 'armor', 'helmet' }) do
            local x = ui.x + 10 + (n - 1) * (half + 6)
            local panel = state.raw and state.raw.basic and state.raw.basic[kind]
            local document = state.palette_ready ~= false and panel and panel.document
            local rows = document and document.height or 0
            local checked_rows = panel and panel.camo_rows
            local checked_count, first_checked = 0, nil
            for row = 1, rows do
                if checked_rows and checked_rows[row] then
                    checked_count = checked_count + 1
                    first_checked = first_checked or row
                end
            end
            local region_label_width =
                math.max(80, (ui.text_width and ui.text_width('Region ' .. math.max(8, rows), 12) or 75) + gap * 2)
            local checkbox_width = math.max(28, (ui.text_width and ui.text_width('Camo', 12, 'hint') or 28) + gap * 2)
            local checkbox_x = x + region_label_width
            local color_offset = region_label_width + checkbox_width + gap
            local row_height = rows == 8 and math.max(29, math.min(40, region_height / 8)) or 29
            local maximum = math.max(0, math.ceil(rows * row_height - region_height - 0.01))
            local scroll = math.min(self.region_scroll[kind] or 0, maximum)
            self.region_maximum[kind], self.region_scroll[kind] = maximum, scroll
            self.region_bounds[kind] = {
                x = x,
                y = clipbottom,
                w = half,
                h = region_height,
                camo_x = checkbox_x,
                camo_width = checkbox_width,
                color_x = x + color_offset,
                row_height = row_height,
            }
            local gear_name = kind == 'armor' and 'Armor' or 'Helmet'
            ui.bounded(
                x,
                ui.text_y and ui.text_y(gear_heading_y, gear_heading_height, 14, gear_name, 'heading') or gear_heading_y,
                gear_name,
                14,
                state.palette_ready == false and muted or white,
                half,
                'heading'
            )
            if panel and panel.resource then
                local label = 'ID: ' .. panel.resource
                local id_offset = (ui.text_width and ui.text_width(gear_name, 14, 'heading') or 65) + gap * 2
                ui.bounded(
                    x + id_offset,
                    ui.text_y and ui.text_y(gear_heading_y, gear_heading_height, 12, label, 'hint') or gear_heading_y,
                    label,
                    12,
                    muted,
                    math.max(0, half - id_offset),
                    'hint'
                )
            end
            ui.choice('basic_' .. kind .. '_lut', x, lut_y, half)
            if state.loaded then
                local title = 'Apply Imported Texture'
                ui.bounded(
                    x,
                    ui.text_y and ui.text_y(import_heading_y, import_heading_height, 12, title, 'heading')
                        or import_heading_y + gap,
                    title,
                    12,
                    white,
                    half,
                    'heading'
                )
                local filename = (state.loaded.source or ''):gsub('\\', '/'):match('[^/]+$') or 'DDS'
                local arrow_width = math.min(half / 3, math.max(control_height, ui.spacing and ui.spacing(44) or 44))
                local import_label = 'Apply ' .. filename
                local import_width = ui.width_cap and ui.width_cap(half, import_label, 'field') or half
                local action_width = ui.width_cap and ui.width_cap(import_width - arrow_width, import_label, 'action')
                    or import_width - arrow_width
                button(
                    x,
                    import_y,
                    action_width,
                    import_label,
                    'apply_import_' .. kind,
                    panel ~= nil and panel.group ~= nil and not state.busy,
                    nil,
                    control_height
                )
                ui.choice('palette', x + action_width, import_y, arrow_width, nil, {
                    button = true,
                    height = control_height,
                    enabled = not state.busy,
                    anchor_x = x,
                    anchor_width = action_width + arrow_width,
                    help = 'Choose the imported texture. Press Apply to replace the LUT selected above.',
                })
            end
            ui.bounded(
                checkbox_x,
                ui.text_y and ui.text_y(cliptop + gap, region_heading_height, 12, 'Camo', 'hint') or cliptop + gap,
                'Camo',
                12,
                muted,
                checkbox_width,
                'hint'
            )
            if document then
                for row = 1, document.height do
                    local cursor = cliptop + scroll - row * row_height
                    if cursor >= clipbottom - 0.01 and cursor + row_height - 1 <= cliptop + 0.01 then
                        local at = (row - 1) * document.width * 4
                        local rgb = {}
                        for ch = 0, 2 do
                            rgb[#rgb + 1] = math.floor(math.max(0, math.min(1, document.data[at + ch])) * 255 + 0.5)
                        end
                        local pulse = 0.5 + 0.5 * math.sin((state.time or 0) * 3)
                        ui.bounded(
                            x + 3,
                            ui.text_y and ui.text_y(cursor, row_height - 1, 12, 'Region ' .. row)
                                or cursor + (row_height - 12) / 2,
                            'Region ' .. row,
                            12,
                            { math.floor(175 + 69 * pulse), math.floor(180 + 22 * pulse), math.floor(140 - 87 * pulse) },
                            region_label_width - 6
                        )
                        ui.rect(x + color_offset, cursor + 2, math.max(0, half - color_offset - 3), row_height - 3, rgb)
                        local selected = row
                        local target = kind
                        local checked = checked_rows and checked_rows[row] == true
                        ui.checkbox(
                            checkbox_x,
                            cursor + 1,
                            checkbox_width,
                            row_height - 2,
                            checked,
                            document.width == 23
                                and checked_rows ~= nil
                                and select_camo_row ~= nil
                                and not state.busy
                                and not document.stale
                                and not document.read_only,
                            function(value)
                                select_camo_row(selected, target, value, checked_rows)
                            end,
                            'Include this region when applying a camo pattern, colorway or color.'
                        )
                        ui.hit(x, cursor, region_label_width - 2, row_height - 1, function()
                            if select_row(selected, target) ~= false then
                                ui.activate('identify_region')
                            end
                        end, nil, nil, 'Flash this region on your character to find which part it colors.')
                        ui.hit(x + color_offset, cursor, math.max(0, half - color_offset), row_height - 1, function()
                            if select_row(selected, target) ~= false then
                                ui.activate('cell_color', nil, 1)
                            end
                        end, nil, nil, 'Edit this region color. Your changes apply to this gear table automatically.')
                    end
                end
            else
                ui.bounded(
                    x,
                    cliptop - 39,
                    state.palette_ready == false and 'Load current gear or import a LUT.'
                        or (panel and panel.unavailable and 'Original LUT unavailable.' or 'Reading colors...'),
                    12,
                    muted,
                    half,
                    'hint'
                )
                ui.bounded(x, cliptop - 59, 'Try another LUT # or Load Current Colors.', 12, muted, half, 'hint')
            end
            ui.bounded(x, camo_heading_y, 'Camo', 12, white, half, 'heading')
            local label_width = ui.text_width and ui.text_width('Camo', 12, 'heading') or heading_size * 2.5
            ui.bounded(
                x + label_width + gap * 2,
                camo_heading_y,
                checked_count > 0 and (checked_count .. ' checked regions') or 'Check regions above',
                12,
                muted,
                math.max(0, half - label_width - gap * 2),
                'hint'
            )
            ui.choice(
                'basic_' .. kind .. '_camo',
                x,
                camo_y,
                half,
                nil,
                { enabled = checked_count > 0 and not state.busy }
            )
            ui.choice(
                'basic_' .. kind .. '_camo_colorway',
                x,
                colorway_y,
                half,
                nil,
                { enabled = checked_count > 0 and not state.busy }
            )
            local camo_editable = document
                and document.width == 23
                and checked_count > 0
                and not state.busy
                and not document.stale
                and not document.read_only
            local color_width = (half - gap * 3) / 4
            for color = 1, 4 do
                local cx = x + (color - 1) * (color_width + gap)
                local rgb = { 65, 68, 67 }
                if camo_editable then
                    for channel = 0, 2 do
                        local value = document.data[((first_checked - 1) * document.width + 15 + color) * 4 + channel]
                        rgb[channel + 1] = math.floor(math.max(0, math.min(1, value)) * 255 + 0.5)
                    end
                end
                ui.bounded(cx, color_y + color_height + gap, tostring(color), 12, muted, color_width, 'hint')
                ui.rect(cx, color_y, color_width, color_height, rgb)
                if camo_editable then
                    local control = 'basic_' .. kind .. '_camo_color_' .. color
                    ui.hit(cx, color_y, color_width, color_height, function()
                        ui.activate(control, nil, 1)
                    end, nil, nil, 'Edit Camo color ' .. color .. ' for checked regions in this LUT.')
                end
            end
            if ui.scrollbar and maximum > 0 and region_height > 0 then
                ui.scrollbar(
                    'basic_' .. kind .. '_regions',
                    x + half - 3,
                    clipbottom,
                    region_height,
                    rows * row_height,
                    region_height,
                    scroll,
                    function(value)
                        self.region_scroll[kind] = value
                    end
                )
            end
            if kind == 'armor' then
                button(x, ui.y + 10, (half - 6) * 0.43, 'Copy Helmet', 'basic_copy_helmet')
                button(
                    x + (half - 6) * 0.43 + 6,
                    ui.y + 10,
                    (half - 6) * 0.57,
                    'Copy Helmet to All',
                    'basic_copy_helmet_all'
                )
            else
                button(x, ui.y + 10, half, 'Copy Armor', 'basic_copy_armor')
            end
        end
        -- Lay out the action column from its measured content. Status and dirty
        -- guidance belong to the same scroll range as the controls they describe.
        -- A fixed footer notice used to paint over Open Export Location.
        local footer_y, footer_top = ui.y + gap, ui.y + gap + control_height
        local footer_width = math.min(
            (width - gap) / 2,
            math.max(150, (ui.text_width and ui.text_width('Stop Highlight', 14) or hint_size * 9) + gap * 5)
        )
        local mask_height = math.max(
            control_height - gap * 2,
            ui.control_height and ui.control_height(14, 1, 0, 'heading') or heading_size + gap
        )
        local mask_bottom = footer_top + gap
        local clip_top, clip_bottom = top - 30, mask_bottom + mask_height
        self.footer_bounds = { x = right, y = footer_y, w = width, h = control_height, button_width = footer_width }
        local viewport = math.max(1, clip_top - clip_bottom)
        local rows, depth = {}, 0
        local function add(height, draw, after)
            rows[#rows + 1] = { depth = depth, height = height, draw = draw }
            depth = depth + height + (after == nil and gap * 1.5 or after)
        end
        local function measure(value, size, role)
            if ui.text_width then
                return ui.text_width(value, size, role)
            end
            return #value * (ui.text_size and ui.text_size(size, role) or size) * 0.62
        end
        local function paragraph(value, role, color, after)
            value = tostring(value or '')
            if value == '' then
                return
            end
            local size = role == 'heading' and 14 or 13
            local line_height = ui.control_height and ui.control_height(size, 1, 0, role)
                or (ui.text_size and ui.text_size(size, role) or size) + gap
            local lines = {}
            for source in (value .. '\n'):gmatch('(.-)\n') do
                local line = ''
                for word in source:gmatch('%S+') do
                    local candidate = line == '' and word or line .. ' ' .. word
                    if line ~= '' and measure(candidate, size, role) > width - 4 then
                        lines[#lines + 1], line = line, word
                    else
                        line = candidate
                    end
                end
                lines[#lines + 1] = line
            end
            if ui.text_metrics then
                for _, line in ipairs(lines) do
                    local ink = ui.text_metrics(size, line, role)
                    line_height = math.max(line_height, ink.height + gap / 2)
                end
            end
            add(#lines * line_height, function(drawing, y)
                for index, line in ipairs(lines) do
                    local ly = y + (#lines - index) * line_height
                    local baseline = drawing.text_y and drawing.text_y(ly, line_height, size, line, role) or ly
                    drawing.bounded(right, baseline, line, size, color or white, width, role)
                end
            end, after)
        end
        local function buttons(items, after)
            add(control_height, function(drawing, y)
                local count = #items
                local w = (width - gap * (count - 1)) / count
                for index, item in ipairs(items) do
                    button(right + (index - 1) * (w + gap), y, w, item[1], item[2], item[3], drawing, control_height)
                end
            end, after)
        end
        local function choice(id, after)
            add(control_height, function(drawing, y)
                drawing.choice(id, right, y, width)
            end, after)
        end
        local function divider_row()
            add(1, function(drawing, y)
                drawing.rect(right, y, width, 1, divider)
            end, gap * 2)
        end
        paragraph('Click a region color to edit; its label flashes the region.', 'hint', muted)
        paragraph('Import a palette (optional)', 'heading')
        buttons({ { 'Import DDS / ZIP / RAR...', 'browse' } })
        local plan = state.raw and state.raw.matching
        if state.busy then
            paragraph(
                (state.import_detail or state.phase or 'Importing...')
                    .. (state.waiting and '' or ' / ' .. (state.progress or 0) .. '% completed'),
                'hint',
                muted
            )
        else
            paragraph(
                state.loaded
                        and plan
                        and ((plan.total or state.palette_count or 0) .. ' imported / ' .. plan.matched .. ' matched / ' .. math.max(
                            0,
                            (plan.total or state.palette_count or 0) - plan.matched
                        ) .. ' for manual assignment')
                    or 'Color changes apply live. Region label: identify.',
                'hint',
                muted
            )
        end
        if (state.palette_count or 0) > 1 then
            buttons({ { 'Apply Matching LUTs', 'apply_matching', plan and plan.matched > 0 and not state.busy } })
        end
        if state.loaded then
            local document = state.loaded
            add(14, function(drawing, y)
                local size = math.min(28, width / document.height)
                for row = 1, document.height do
                    local at, color = (row - 1) * document.width * 4, {}
                    for channel = 0, 2 do
                        color[#color + 1] =
                            math.floor(math.max(0, math.min(1, document.data[at + channel])) * 255 + 0.5)
                    end
                    drawing.rect(right + (row - 1) * size, y, size - 2, 14, color)
                end
            end)
            choice('palette')
            local source = not state.busy
            local mapping = {
                { 'Map LUTs to Armor', 'imported_map_armor', source },
                { 'Map LUTs to Helmet', 'imported_map_helmet', source },
                { 'Map LUTs to Cape', 'imported_map_cape', source and state.cape_available == true },
            }
            local mapping_width = 0
            for _, item in ipairs(mapping) do
                mapping_width = math.max(mapping_width, measure(item[1], 14) + gap * 4)
            end
            local columns = math.max(1, math.min(3, math.floor((width + gap) / (mapping_width + gap))))
            for start = 1, #mapping, columns do
                local group = {}
                for index = start, math.min(#mapping, start + columns - 1) do
                    group[#group + 1] = mapping[index]
                end
                buttons(group)
            end
        end
        divider_row()
        paragraph('Armory Presets', 'heading')
        choice('outfit_preset')
        buttons({
            {
                'Apply Preset...',
                'outfit_choose_luts',
                not state.busy
                    and state.raw
                    and state.raw.outfit
                    and (#state.raw.outfit.armor + #state.raw.outfit.helmet + #(state.raw.outfit.cape or {})) > 0,
            },
        })
        buttons({ { 'Save to Armory', 'save_setup' } })
        buttons({ { 'Undo', 'undo' }, { 'Redo', 'redo' } })
        if state.loaded then
            buttons(
                { { 'Restore Imported', 'restore_imported' }, { 'Restore Arrowhead LUT (Original)', 'restore' } },
                gap * 2
            )
        else
            buttons({ { 'Restore Arrowhead LUT (Original)', 'restore' } }, gap * 2)
        end
        paragraph(state.status, 'hint', muted, gap * 2)
        divider_row()
        paragraph('Export', 'heading')
        buttons({
            {
                'Name: ' .. (ui.input_value and ui.input_value('save_name') or state.export_name or 'Epic-LUT-edited'),
                'save_name',
            },
        })
        add(control_height, function(drawing, y)
            button(
                right,
                y,
                width * 0.35 - gap / 2,
                'Export...',
                'export_selected',
                (state.editor ~= nil or state.export_format == 3 or bulk_dds) and not state.busy,
                drawing,
                control_height
            )
            drawing.choice('export_format', right + width * 0.35 + gap / 2, y, width * 0.65 - gap / 2)
        end)
        if bulk_dds then
            choice('dds_naming')
        end
        buttons({ { 'Open Export Location', 'open_export' } }, state.dirty and gap * 2 or gap)
        if state.dirty then
            paragraph('Modified - save or export to keep your colors.', 'hint', muted, gap)
        end
        self.action_bounds = { x = right, y = clip_bottom, w = width, h = viewport }
        self.action_maximum = math.max(0, depth - viewport)
        self.action_scroll = math.max(0, math.min(self.action_scroll, self.action_maximum))
        local base_ui, offset = ui, self.action_scroll
        local actions = setmetatable({}, { __index = ui })
        actions.rect = function(x, y, w, height, ...)
            base_ui.rect(x, y + offset, w, height, ...)
        end
        actions.text = function(x, y, ...)
            base_ui.text(x, y + offset, ...)
        end
        actions.bounded = function(x, y, ...)
            base_ui.bounded(x, y + offset, ...)
        end
        actions.hit = function(x, y, ...)
            base_ui.hit(x, y + offset, ...)
        end
        actions.choice = function(id, x, y, ...)
            base_ui.choice(id, x, y + offset, ...)
        end
        actions.hovering = function(x, y, w, h)
            return y + offset < clip_top and y + offset + h > clip_bottom and base_ui.hovering(x, y + offset, w, h)
        end
        ui.decorate(actions)
        local function draw_actions()
            for _, row in ipairs(rows) do
                row.draw(actions, clip_top - row.depth - row.height)
            end
        end
        if ui.viewport then
            ui.viewport(self.action_bounds, draw_actions, { top = top, bottom = mask_bottom, color = theme.background })
        else
            draw_actions()
        end
        if ui.scrollbar then
            ui.scrollbar(
                'basic_actions',
                right + width + 3,
                clip_bottom,
                viewport,
                depth,
                viewport,
                self.action_scroll,
                function(value)
                    self.action_scroll = value
                end
            )
        end
        -- Fixed chrome occupies a measured row below the content masks. Keep
        -- its complete border and native glyph ink above the scrolling plane.
        local finish = ui.surface and ui.surface(130)
        button(
            right + width - footer_width,
            footer_y,
            footer_width,
            'Stop Highlight',
            'stop_identify',
            nil,
            ui,
            control_height
        )
        local portrait = package.loaded['epic.player_preview.v1']
        if portrait and portrait.toggle and (not portrait.is_enabled or portrait.is_enabled()) then
            ui.button(right, footer_y, footer_width, control_height, 'Player Preview', portrait.toggle)
        end
        if finish then
            finish()
        end
    end
    return self
end
return B
