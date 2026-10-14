-- Compact weapon workspace. Editing, mappings and persistence use the host's
-- existing editor/picker/runtime actions through weapon_controller.
local V = { minimum_width = 700, minimum_height = 620 }
local SLOT_NAMES = { 'Primary', 'Secondary', 'Support' }
local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end
local function rgb(document, row, column, alpha)
    local start = ((row - 1) * document.width + column - 1) * 4
    local color = {}
    for channel = 0, 2 do
        local value = tonumber(document.data[start + (alpha and 3 or channel)]) or 0
        if value ~= value or math.abs(value) == math.huge then
            value = 0
        end
        color[channel + 1] = math.floor(clamp(value, 0, 1) * 255 + 0.5)
    end
    return color
end
function V.new(controller)
    assert(controller and type(controller.state) == 'function', 'Weapon controller unavailable')
    local self = { action_scroll = 0, table_scroll = 0 }
    function self.wheel(x, y, delta)
        for _, region in ipairs({
            { self.action_bounds, 'action_scroll', self.action_maximum },
            { self.table_bounds, 'table_scroll', self.table_maximum },
        }) do
            local bounds = region[1]
            if bounds and x >= bounds.x and x <= bounds.x + bounds.w and y >= bounds.y and y <= bounds.y + bounds.h then
                self[region[2]] = clamp(self[region[2]] - delta / 120 * 36, 0, region[3] or 0)
                return true
            end
        end
    end
    function self.draw(ui)
        controller.sync()
        local state, theme = controller.state(), ui.theme
        local basic = ui.basic_only and state.quick_ready
        local gap = ui.spacing and ui.spacing(6) or 6
        local height = ui.control_height and ui.control_height(14, 4, 28) or 28
        local hint_height = ui.control_height and ui.control_height(12, 1, 16, 'hint') or 16
        local function measure(label, role)
            return ui.text_width and ui.text_width(label, 14, role) or #label * 8
        end
        local function bounded(x, y, label, width, role, ink)
            if width > 0 then
                ui.bounded(x, y, label, 14, ink or theme.white, width, role)
            end
        end
        local function button(x, y, available, label, action, callback, enabled, short, drawing)
            local canvas = drawing or ui
            local wanted = measure(label) + gap * 2 + 8
            if wanted > available and short then
                label = short
                wanted = measure(label) + gap * 2 + 8
            end
            local width = math.max(0, math.min(available, wanted))
            if width < 20 or height <= 0 then
                return width
            end
            canvas.button(x, y, width, height, label, callback, {
                enabled = enabled ~= false,
                action = action,
                help = label,
                accent = action == 'weapon_load' and { 244, 202, 53 } or nil,
            })
            return width
        end
        local top = ui.y + ui.h - gap
        local slot_width = math.min(300, math.max(1, (ui.w - gap * 4) / 3))
        for slot = 1, 3 do
            local x = ui.x + gap + (slot - 1) * (slot_width + gap)
            local weapon = state.weapons[slot]
            local availability = weapon and weapon.status or 'absent'
            local chosen = slot
            button(x, top - height, slot_width, SLOT_NAMES[slot], 'weapon_slot_' .. slot, function()
                controller.choose_slot(chosen)
            end, true)
            if slot == state.weapon_slot then
                ui.rect(
                    x,
                    top - height - 2,
                    math.min(slot_width, measure(SLOT_NAMES[slot]) + gap * 2 + 8),
                    2,
                    theme.accent or theme.white
                )
            end
            bounded(
                x,
                top - height - hint_height - gap,
                weapon and weapon.name or SLOT_NAMES[slot] .. ' unavailable',
                slot_width,
                'hint'
            )
            bounded(
                x,
                top - height - hint_height * 2 - gap,
                availability == 'ready' and 'Detected' or availability,
                slot_width,
                'hint',
                theme.muted
            )
        end
        local body_top = top - height - hint_height * 2 - gap * 3
        local body_bottom = ui.y + gap + hint_height
        bounded(
            ui.x + gap,
            ui.y + gap,
            controller.error or state.status or 'Choose a weapon and LUT table.',
            ui.w - gap * 2,
            'hint',
            theme.muted
        )
        local action_width = math.min(
            basic and 520 or 340,
            math.max(180, ui.w * (basic and 0.44 or 0.30), measure('Pattern Editor') + gap * 4 + 8)
        )
        action_width = math.min(action_width, math.max(80, ui.w * 0.42))
        local main_width = math.max(1, ui.w - action_width - gap * 4)
        local main_x, action_x = ui.x + gap, ui.x + gap * 3 + main_width
        local body_height = math.max(0, body_top - body_bottom)
        ui.rect(action_x - gap, body_bottom, 1, body_height, theme.line)
        local ready = state.target ~= nil and not state.busy
        local family_x = main_x
        if not basic then
            family_x = family_x
                + button(family_x, body_top - height, main_width, 'Material LUTs', 'weapon_main', function()
                    controller.choose_family('main')
                end, not state.busy, 'Material')
                + gap
            button(
                family_x,
                body_top - height,
                math.max(0, main_x + main_width - family_x),
                'Pattern LUTs',
                'weapon_pattern',
                function()
                    controller.choose_family('pattern')
                end,
                not state.busy,
                'Pattern'
            )
        end
        local choice_y = body_top - height * (basic and 1 or 2) - gap
        local choice_width = math.min(
            main_width,
            math.max(180, measure(state.group and state.group.label or 'Weapon LUT') + gap * 4 + 40)
        )
        ui.choice('weapon_lut', main_x, choice_y, choice_width, nil, { enabled = ready, height = height })
        local table_top = choice_y - hint_height - gap * 2
        local label = state.group
                and ((state.group.label or 'Weapon LUT') .. ' / ' .. #state.target.bindings .. ' bindings')
            or (state.weapon and state.weapon.status or 'absent')
        if state.document and state.document.mixed then
            label = label .. ' / Mixed LOD palettes'
        end
        bounded(main_x, table_top, label, main_width, 'heading')
        table_top = table_top - hint_height - gap
        local pattern_band = height + hint_height * 2 + gap * 4 + (basic and height + hint_height + gap * 3 or 0)
        local table_available = math.max(0, table_top - body_bottom - pattern_band)
        local document = state.document
        local row_height = basic and math.max(29, math.min(56, table_available / math.max(1, document.height)))
            or math.max(18, math.min(40, height))
        local label_width = math.min(
            main_width * 0.65,
            measure(basic and 'Region 64' or 'Row 64', 'hint') + gap * 4 + (basic and 24 or 0)
        )
        local columns = document and document.width or 0
        local rows = document and document.height or 0
        local data_ready = document
            and document.data ~= nil
            and columns >= 1
            and columns <= 64
            and rows >= 1
            and rows <= 64
        local cell_width = data_ready
                and (basic and math.max(1, main_width - label_width - gap) or math.min(
                    40,
                    math.max(1, (main_width - label_width - gap) / columns)
                ))
            or 0
        local content_height = data_ready and rows * row_height or hint_height * 2
        local table_height = math.min(table_available, content_height)
        self.table_maximum = math.max(0, content_height - table_height)
        self.table_scroll = clamp(self.table_scroll, 0, self.table_maximum)
        self.table_bounds = { x = main_x, y = table_top - table_height, w = main_width, h = table_height }
        self.grid = { cell_width = cell_width, row_height = row_height, rows = rows, columns = columns }
        local function draw_table()
            if not data_ready then
                bounded(
                    main_x,
                    table_top - hint_height,
                    state.weapon and state.weapon.status == 'loading' and 'Reading weapon LUTs...'
                        or 'Load Current Weapons to read LUT tables.',
                    main_width,
                    'hint',
                    theme.muted
                )
                return
            end
            for row = 1, rows do
                local y = table_top - row * row_height + self.table_scroll
                if y >= self.table_bounds.y and y + row_height <= table_top + 0.01 then
                    local selected_row, expected = row, state.target
                    local camo = state.quick_ready and controller.available('apply_camo')
                    local box = camo and math.min(20, row_height - 6) or 0
                    if camo and ui.checkbox then
                        local selected_rows = controller.camo_selection()
                        ui.checkbox(
                            main_x,
                            y + (row_height - box) / 2,
                            box,
                            box,
                            selected_rows[row] == true,
                            not state.busy,
                            function(value)
                                return controller.toggle_camo_row(selected_row, value)
                            end
                        )
                    end
                    bounded(
                        main_x + (camo and box + gap or 0),
                        ui.text_y and ui.text_y(y, row_height, 14, 'Row ' .. row, 'hint') or y + 3,
                        (basic and 'Region ' or 'Row ') .. row,
                        label_width - (camo and box + gap or 0),
                        'hint'
                    )
                    for column = 1, (basic and 1 or columns) do
                        local x, selected_column = main_x + label_width + (column - 1) * cell_width, column
                        ui.rect(
                            x,
                            y + 1,
                            math.max(1, cell_width - 1),
                            row_height - 2,
                            rgb(document, row, column, state.family == 'pattern' and column == 3)
                        )
                        if ui.hit and ready and not document.stale and not document.read_only then
                            ui.hit(x, y + 1, math.max(1, cell_width - 1), row_height - 2, function()
                                if state.quick_ready and selected_column == 1 and controller.available('edit_rgb') then
                                    return controller.edit_rgb(selected_row, expected)
                                end
                                if
                                    state.quick_ready
                                    and selected_column >= 17
                                    and selected_column <= 20
                                    and controller.available('edit_camo')
                                then
                                    return controller.edit_camo(selected_row, selected_column - 16, expected)
                                end
                                return controller.open_editor(selected_row, selected_column, expected)
                            end, nil, nil, 'Edit Row ' .. row .. ', column ' .. column .. ' in the LUT table.')
                        end
                    end
                end
            end
        end
        if ui.viewport then
            ui.viewport(
                self.table_bounds,
                draw_table,
                { top = table_top, bottom = self.table_bounds.y, color = theme.panel }
            )
        else
            draw_table()
        end
        if ui.scrollbar and self.table_maximum > 0 then
            ui.scrollbar(
                'weapon_table',
                main_x + main_width - 4,
                self.table_bounds.y,
                table_height,
                content_height,
                table_height,
                self.table_scroll,
                function(value)
                    self.table_scroll = clamp(value, 0, self.table_maximum)
                end
            )
        end
        local pattern_top = self.table_bounds.y - gap * 2
        if basic then
            bounded(main_x, pattern_top - hint_height, 'Camo: check regions above', main_width, 'heading')
            local rows_selected = controller.camo_selection()
            local first
            for row = 1, document.height do
                if rows_selected[row] then
                    first = row
                    break
                end
            end
            local lane = (main_width - gap * 3) / 4
            for color = 1, 4 do
                local x, selected_color = main_x + (color - 1) * (lane + gap), color
                local y = pattern_top - hint_height - gap - height
                ui.rect(x, y, lane, height, rgb(document, first or 1, 16 + color))
                if ui.hit and first and ready then
                    ui.hit(x, y, lane, height, function()
                        return controller.edit_camo(first, selected_color, state.target)
                    end, nil, nil, 'Edit checked Camo color ' .. color)
                end
            end
            pattern_top = pattern_top - hint_height - height - gap * 3
        end
        bounded(main_x, pattern_top - hint_height, 'Quick Editor: Pattern LUT', main_width, 'heading')
        local captions = { 'Color', 'Mat/Opac', 'Roughness' }
        local short = { 'Color', 'Mat/Op', 'Rough.' }
        local smallest = { 'Clr', 'Mat', 'Rgh' }
        local lane = math.min(160, math.max(1, (main_width - gap * 2) / 3))
        local swatch = math.max(1, math.min(40, height, lane - gap))
        if state.pattern_ready then
            for column = 1, 3 do
                local x, chosen = main_x + (column - 1) * (lane + gap), column
                local caption = measure(captions[column], 'hint') <= lane and captions[column] or short[column]
                if measure(caption, 'hint') > lane then
                    caption = smallest[column]
                end
                if measure(caption, 'hint') > lane then
                    caption = ({ 'C', 'M', 'R' })[column]
                end
                bounded(x, pattern_top - hint_height * 2 - gap, caption, lane, 'hint')
                local y = pattern_top - hint_height * 2 - gap * 2 - swatch
                if y >= body_bottom then
                    ui.rect(x, y, swatch, swatch, rgb(state.pattern_document, 1, column, column == 3))
                    if ui.hit and not state.busy and controller.available('edit_pattern') then
                        ui.hit(x, y, swatch, swatch, function()
                            return controller.edit_pattern(chosen, state.pattern_target)
                        end, nil, nil, captions[column])
                    end
                end
            end
        else
            bounded(
                main_x,
                pattern_top - hint_height * 2 - gap,
                'No Pattern LUT for this table.',
                main_width,
                'hint',
                theme.muted
            )
        end
        local actions = {}
        local function heading(value)
            actions[#actions + 1] = { kind = 'heading', label = value, height = hint_height + gap }
        end
        local function action(label, id, fn, enabled, short_label)
            actions[#actions + 1] = {
                kind = 'action',
                label = label,
                id = id,
                callback = fn,
                enabled = enabled,
                short = short_label,
                height = height + gap,
            }
        end
        action(
            'Load Current Weapons',
            'weapon_load',
            controller.load_current,
            not state.busy and controller.available('load_current'),
            'Load Weapons'
        )
        action(
            'Open LUT Table / Values',
            'weapon_editor',
            function()
                return controller.open_editor(nil, nil, state.target)
            end,
            ready and controller.available(state.family == 'pattern' and 'open_pattern' or 'load_editor'),
            'Table/Values'
        )
        action('Pattern LUT Editor', 'weapon_pattern_editor', function()
            return controller.open_pattern(state.pattern_target)
        end, not state.busy and state.pattern_target and controller.available('open_pattern'), 'Pattern Editor')
        action('Apply LUT', 'weapon_apply', function()
            return controller.apply(state.target)
        end, ready and controller.available('apply'))
        action('Restore LUT', 'weapon_restore', function()
            return controller.restore(state.target)
        end, ready and controller.available('restore'))
        if controller.available('apply_camo') then
            heading('Camo: checked rows')
            action('Select all Camo rows', 'weapon_camo_all', function()
                return controller.select_camo_rows(true)
            end, state.quick_ready, 'Check rows')
            action('Clear Camo rows', 'weapon_camo_clear', function()
                return controller.select_camo_rows(false)
            end, state.quick_ready, 'Clear rows')
            actions[#actions + 1] = { kind = 'choice', id = 'weapon_camo_pattern', height = height + gap }
            actions[#actions + 1] = { kind = 'choice', id = 'weapon_camo_colorway', height = height + gap }
        end
        heading('Selected weapons')
        for slot = 1, 3 do
            actions[#actions + 1] = { kind = 'target', slot = slot, label = SLOT_NAMES[slot], height = height + gap }
        end
        heading('Import and mapping')
        action(
            'Import DDS / ZIP / RAR...',
            'weapon_import',
            controller.import,
            not state.busy and controller.available('import'),
            'Import...'
        )
        action('Map LUTs to Weapons', 'weapon_map', function()
            return controller.map_imports(false)
        end, ready and controller.available('map_imports'), 'Map LUTs')
        action('Auto-map LUTs', 'weapon_auto_map', function()
            return controller.map_imports(true)
        end, ready and controller.available('map_imports'), 'Auto-map')
        heading('Armory Presets')
        actions[#actions + 1] = { kind = 'choice', id = 'outfit_preset', height = height + gap }
        action(
            'Map selected Armory preset',
            'weapon_apply_preset',
            controller.apply_preset,
            ready and controller.available('apply_preset'),
            'Apply Preset'
        )
        action(
            'Save to Armory',
            'weapon_preset',
            controller.save_preset,
            ready and controller.available('save_preset'),
            'Save Preset'
        )
        action(
            'Export Weapon LUTs...',
            'weapon_export',
            controller.export,
            ready and controller.available('export'),
            'Export...'
        )
        action('Shared LUT', 'weapon_share', controller.share, ready and controller.available('share'))
        local depth = 0
        for _, item in ipairs(actions) do
            item.depth = depth
            depth = depth + item.height
        end
        self.action_bounds = { x = action_x, y = body_bottom, w = action_width - gap, h = body_height }
        self.action_maximum = math.max(0, depth - body_height)
        self.action_scroll = clamp(self.action_scroll, 0, self.action_maximum)
        local function draw_actions()
            for _, item in ipairs(actions) do
                local y = body_top - item.depth - item.height + self.action_scroll
                if y >= body_bottom - 0.01 and y + item.height <= body_top + 0.01 then
                    if item.kind == 'heading' then
                        bounded(action_x, y + gap, item.label, action_width - gap * 2, 'heading')
                    elseif item.kind == 'choice' then
                        ui.choice(
                            item.id,
                            action_x,
                            y,
                            action_width - gap * 2,
                            nil,
                            { enabled = not state.busy, height = height }
                        )
                    elseif item.kind == 'target' then
                        local slot, weapon = item.slot, state.weapons[item.slot]
                        local enabled = weapon and weapon.status == 'ready' and not state.busy
                        if ui.checkbox then
                            ui.checkbox(
                                action_x,
                                y,
                                height,
                                height,
                                state.selected_weapons[slot] == true,
                                enabled,
                                function(value)
                                    return controller.toggle_weapon(slot, value)
                                end
                            )
                        end
                        bounded(
                            action_x + height + gap,
                            ui.text_y and ui.text_y(y, height, 14, item.label) or y + 3,
                            item.label,
                            math.max(0, action_width - height - gap * 2)
                        )
                    else
                        button(
                            action_x,
                            y,
                            action_width - gap * 2,
                            item.label,
                            item.id,
                            item.callback,
                            item.enabled,
                            item.short
                        )
                    end
                end
            end
        end
        if ui.viewport then
            ui.viewport(self.action_bounds, draw_actions, { top = body_top, bottom = body_bottom, color = theme.panel })
        else
            draw_actions()
        end
        if ui.scrollbar and self.action_maximum > 0 then
            ui.scrollbar(
                'weapon_actions',
                action_x + action_width - gap - 4,
                body_bottom,
                body_height,
                depth,
                body_height,
                self.action_scroll,
                function(value)
                    self.action_scroll = clamp(value, 0, self.action_maximum)
                end
            )
        end
    end
    return self
end
return V
