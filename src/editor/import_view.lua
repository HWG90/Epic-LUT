-- Import workspace: source selection and target previews left; actions right.
local V = {}
function V.new(info, tables, select_color, core, help)
    help = help or {}
    local self = {
        scroll = 0,
        gear_scroll = {},
        gear_bounds = {},
        gear_max = {},
        scratch = { 255, 255, 255 },
        hue = 0,
        swatches = {},
    }
    function self.wheel(x, y, delta)
        local imported = self.import_bounds
        if
            imported
            and x >= imported.x
            and x <= imported.x + imported.w
            and y >= imported.y
            and y <= imported.y + imported.h
        then
            self.import_scroll =
                math.max(0, math.min(self.import_max or 0, (self.import_scroll or 0) - delta / 120 * 22))
            return true
        end
        for _, kind in ipairs({ 'armor', 'helmet' }) do
            local b = self.gear_bounds[kind]
            if b and x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
                self.gear_scroll[kind] =
                    math.max(0, math.min(self.gear_max[kind] or 0, (self.gear_scroll[kind] or 0) - delta / 120 * 60))
                return true
            end
        end
    end
    function self.draw(ui)
        local theme = ui.theme
        ui.button(ui.x + ui.w - 150, ui.y - 24, 150, 28, 'Stop Highlight', function()
            ui.activate('stop_identify')
        end)
        local portrait = package.loaded['epic.player_preview.v1']
        if portrait and portrait.toggle and (not portrait.is_enabled or portrait.is_enabled()) then
            ui.button(ui.x + ui.w - 308, ui.y - 24, 150, 28, 'Player Preview', portrait.toggle)
        end
        local state = info()
        local ready = state.palette_ready ~= false
        if not ready then
            self.selected = nil
        end
        local top = ui.y + ui.h
        local gap = 18
        local lw = math.floor(ui.w * 0.55)
        local rx = ui.x + lw + gap
        local rw = ui.w - lw - gap
        local white, muted = theme.white, theme.muted
        local function text(x, y, value)
            ui.text(x, y, value, 14, white)
        end
        local guidance = help.imported or {}
        local function button(x, y, w, label, id, enabled, height)
            height = height or 28
            w = math.max(0, math.min(w, ui.x + ui.w - x - 6))
            if w < 20 then
                return
            end
            local load = id == 'populate_worn' and enabled ~= false
            local featured = load or id == 'save_setup'
            ui.button(x, y, w, height, label, function()
                ui.activate(id)
            end, {
                enabled = enabled,
                accent = featured and (load and ui.load_color(state.load_seen) or { 244, 202, 53 }),
                ink = featured and { 25, 28, 31 },
                size = 15,
                padding = 9,
                help = guidance[id],
            })
        end
        ui.rect(ui.x, ui.y, lw, ui.h, theme.panel)
        ui.rect(rx, ui.y, rw, ui.h, theme.panel)
        local divider = theme.line
        ui.rect(rx - 9, ui.y, 1, ui.h, divider)
        for _, offset in ipairs({ 184 }) do
            ui.rect(rx + 12, top - offset, rw - 24, 1, divider)
        end
        ui.rect(ui.x, top - 30, lw, 30, theme.header)
        ui.rect(rx, top - 30, rw, 30, theme.header)
        text(ui.x + 12, top - 20, 'LUTs and colors')
        text(rx + 12, top - 20, 'Import and apply')
        -- Reserve one toolbar row when labels fit; narrow windows use two rows.
        local function text_width(value)
            return ui.text_width and ui.text_width(value, 15) or #value * 15 * 0.62
        end
        local row_height = math.max(28, (ui.text_size and ui.text_size(15) or 15) + 12)
        local available = lw - 24
        local scratch_width = math.min(available, math.max(140, text_width('Quick Scratch') + 18))
        local load_width = available - scratch_width - 8
        local header_bottom = top - 49 - row_height
        local scratch_y = header_bottom
        if load_width < text_width('Load Current Armor & Helmet') + 18 then
            load_width = available
            scratch_y = header_bottom - row_height - 8
        end
        button(ui.x + 12, header_bottom, load_width, 'Load Current Armor & Helmet', 'populate_worn', nil, row_height)
        local scratch_x = ui.x + lw - 12 - scratch_width
        ui.button(scratch_x, scratch_y, scratch_width, row_height, 'Quick Scratch', function()
            self.scratch_open = not self.scratch_open
        end, {
            selected = self.scratch_open,
            size = 15,
            padding = 9,
            help = 'Open a floating color palette. Right-click a LUT swatch to paint with this color.',
        })
        header_bottom = scratch_y
        if (state.palette_count or 0) > 1 then
            text(ui.x + 12, header_bottom - 24, 'Imported LUT')
            local selector_width = math.min(280, lw * 0.4)
            local selector_y = header_bottom - 62
            ui.choice('palette', ui.x + 12, selector_y, selector_width)
            header_bottom = selector_y
            if state.loaded then
                local document = state.loaded
                local sx = ui.x + selector_width + 24
                local size = math.min(34, (lw - selector_width - 40) / document.height)
                for row = 1, document.height do
                    local at = (row - 1) * document.width * 4
                    local rgb = {}
                    for ch = 0, 2 do
                        rgb[#rgb + 1] = math.floor(math.max(0, math.min(1, document.data[at + ch])) * 255 + 0.5)
                    end
                    ui.rect(sx + (row - 1) * size, selector_y, size - 2, 26, rgb)
                end
            end
        end
        local cliptop, clipbottom = header_bottom - row_height - 12, ui.y + 14
        ui.rect(ui.x + lw / 2, clipbottom, 1, math.max(0, cliptop - clipbottom), divider)
        local function paint()
            if self.selected and ui.set then
                ui.set('quick_color', string.format('#%02X%02X%02X', self.scratch[1], self.scratch[2], self.scratch[3]))
            end
        end
        local function draw_scratch(x, y, width, height)
            local scratchx, scratchw, sh, sy = x, width, height, y
            local scratchtop = y + height
            ui.rect(scratchx, sy, scratchw, sh, theme.panel)
            ui.rect(scratchx, scratchtop - 28, scratchw, 28, theme.header)
            text(scratchx + 8, scratchtop - 20, 'Quick Scratch')
            ui.rect(scratchx + 10, scratchtop - 60, scratchw - 20, 22, self.scratch)
            local gx, gy = scratchx + 10, sy + 110
            local gw, gh = scratchw - 40, sh - 180
            local function choose(key, color)
                self.scratch = color
                -- The scratch area only chooses a color; palette right-click paints it.
            end
            if core then
                for v = 0, 19 do
                    for sat = 0, 19 do
                        local saturation, value = sat / 19, v / 19
                        local x, y = gx + sat * gw / 20, gy + v * gh / 20
                        ui.rect(x, y, gw / 20 + 1, gh / 20 + 1, core.hsv_rgb(self.hue, saturation, value))
                        ui.hit(x, y, gw / 20, gh / 20, function()
                            choose('sv:' .. sat .. ':' .. v, core.hsv_rgb(self.hue, saturation, value))
                        end)
                    end
                end
                for i = 0, 19 do
                    local hue = i / 20
                    local y = gy + i * gh / 20
                    ui.rect(gx + gw + 5, y, 12, gh / 20 + 1, core.hsv_rgb(hue, 1, 1))
                    ui.hit(gx + gw + 5, y, 12, gh / 20, function()
                        self.hue = hue
                        local _, sat, val = core.rgb_hsv(self.scratch)
                        self.scratch = core.hsv_rgb(hue, sat, val)
                    end)
                end
            end
            local bw = (scratchw - 25) / 2
            ui.button(
                scratchx + 10,
                sy + 73,
                bw,
                28,
                'Paint selected RGB',
                paint,
                { enabled = self.selected ~= nil, size = 15, padding = 4 }
            )
            ui.button(scratchx + 15 + bw, sy + 73, bw, 28, 'Save swatch', function()
                local slot
                for i = 1, 10 do
                    if not self.swatches[i] then
                        slot = i
                        break
                    end
                end
                slot = slot or self.next_slot or 1
                self.swatches[slot] = { self.scratch[1], self.scratch[2], self.scratch[3] }
                self.next_slot = slot % 10 + 1
            end, { accent = { 244, 202, 53 }, ink = { 25, 28, 31 }, size = 15, padding = 4 })
            local slotw = (scratchw - 20) / 5
            for i = 1, 10 do
                local x = scratchx + 10 + ((i - 1) % 5) * slotw
                local y = sy + 12 + (1 - math.floor((i - 1) / 5)) * 26
                local color = self.swatches[i]
                ui.rect(x, y, slotw - 4, 22, theme.border)
                ui.rect(x + 2, y + 2, slotw - 8, 18, color or theme.panel)
                if not color then
                    ui.bounded(x + 5, y + 7, 'Empty ' .. i, 10, muted, slotw - 14)
                end
                local slot = i
                ui.hit(x, y, slotw - 4, 22, function()
                    local saved = self.swatches[slot]
                    if saved then
                        self.scratch = { saved[1], saved[2], saved[3] }
                        if core then
                            self.hue = core.rgb_hsv(self.scratch)
                        end
                    end
                end)
            end
        end
        if self.scratch_open and ui.floating then
            ui.floating('quick_scratch', draw_scratch, 260, 330, function()
                self.scratch_open = false
            end)
        end
        if self.selected then
            ui.bounded(
                ui.x + 12,
                cliptop + 12,
                'Editing: '
                    .. (self.selected.label or '')
                    .. ' / Row '
                    .. self.selected.row
                    .. ' / '
                    .. (self.selected.field or self.selected.column),
                13,
                muted,
                lw - 24
            )
        end
        local cols = { 1, 3, 6, 7, 13, 15, 17, 18, 19, 20 }
        local labels = { 'Base', 'D1', 'In', 'Out', 'Curv', 'Tint', 'C1', 'C2', 'C3', 'C4' }
        local fields =
            { 'Base', 'Detail', 'Inner', 'Outer', 'Curvature', 'Tint', 'Camo 1', 'Camo 2', 'Camo 3', 'Camo 4' }
        local function colors(title, kind, offset)
            local x, width = ui.x + offset + 10, lw / 2 - 22
            local font = ui.text_size and ui.text_size(13) or 13
            local heading_height = math.max(23, font + 10)
            local row_step = math.max(18, font + 6)
            local title_height, hash_height, label_height = heading_height, math.max(26, font + 10), row_step
            local listtop = cliptop - heading_height - 8
            local viewport = math.max(0, listtop - clipbottom)
            local entries = ready and ((state.raw and state.raw[kind]) or state[kind]) or {}
            entries = entries or {}
            ui.rect(x, cliptop - heading_height, width, heading_height, theme.header)
            ui.bounded(x + 7, cliptop - heading_height + 5, title, 14, ready and white or muted, 80)
            if state.loaded then
                local target = state[kind .. '_lut']
                    or (ui.input_value and ui.input_value('basic_' .. kind .. '_lut'))
                    or 1
                ui.button(
                    x + 90,
                    cliptop - heading_height,
                    width - 90,
                    heading_height,
                    'Apply to ' .. title .. ' LUT ' .. target,
                    function()
                        ui.activate('apply_import_' .. kind)
                    end,
                    { enabled = ready and #entries > 0 and not state.busy, size = 14 }
                )
            end
            local content = 0
            for _, entry in ipairs(entries) do
                content = content + title_height + hash_height + label_height + entry.height * row_step + 12
            end
            self.gear_bounds[kind] = { x = x, y = clipbottom, w = width, h = viewport }
            self.gear_max[kind] = math.max(0, content - viewport)
            self.gear_scroll[kind] = math.max(0, math.min(self.gear_scroll[kind] or 0, self.gear_max[kind]))
            local cursor = listtop + self.gear_scroll[kind]
            local function visible(y, height)
                return y >= clipbottom and y + height <= listtop
            end
            if #entries == 0 then
                ui.bounded(
                    x + 7,
                    listtop - row_step,
                    ready and 'Current colors unavailable or still loading.' or 'Load current gear or import a LUT.',
                    13,
                    muted,
                    width - 16
                )
            end
            local size = math.min(22, (width - 84) / #cols - 4)
            local step, gx = size + 4, x + 72
            for number, entry in ipairs(entries) do
                local ordinal = entry.lut or number
                local selection_key = kind .. '/' .. tostring(entry.index or entry.resource or ordinal)
                local selected = entry.selected
                if selected == nil then
                    selected = (
                        state[kind .. '_lut'] or (ui.input_value and ui.input_value('basic_' .. kind .. '_lut'))
                    ) == ordinal
                end
                local function choose_table()
                    if ui.set then
                        ui.set('basic_' .. kind .. '_lut', ordinal)
                    end
                    self.selected = nil
                end
                cursor = cursor - title_height
                if visible(cursor, title_height) then
                    ui.button(x + 2, cursor, width - 12, title_height, entry.name, choose_table, {
                        selected = selected,
                        size = 14,
                        help = 'Select this ' .. kind .. ' LUT. Selecting does not apply or change its colors.',
                    })
                end
                cursor = cursor - hash_height
                if visible(cursor, hash_height) and entry.resource then
                    ui.button(x + 2, cursor, width - 12, hash_height, entry.resource, choose_table, {
                        selected = selected,
                        field = false,
                        ink = theme.brass,
                        size = 12,
                        help = 'Select this ' .. kind .. ' LUT by its texture resource ID.',
                    })
                end
                cursor = cursor - label_height
                if visible(cursor, label_height) then
                    for i, label in ipairs(labels) do
                        ui.bounded(gx + (i - 1) * step, cursor + 3, label, 12, muted, size)
                    end
                end
                -- Only inspect pixel data for rows inside this gear's viewport.
                local first = math.max(1, math.ceil((cursor + row_step - 1 - listtop) / row_step))
                local last = math.min(entry.height, math.floor((cursor - clipbottom) / row_step))
                for row = first, last do
                    local y = cursor - row * row_step
                    local pulse = 0.5 + 0.5 * math.sin((state.time or 0) * 3)
                    ui.bounded(
                        x + 7,
                        y + 5,
                        'Row ' .. row,
                        13,
                        { math.floor(175 + 69 * pulse), math.floor(180 + 22 * pulse), math.floor(140 - 87 * pulse) },
                        60
                    )
                    local selected_row = row
                    ui.hit(x + 2, y, 64, row_step - 1, function()
                        choose_table()
                        if select_color then
                            select_color(entry, selected_row, 1, true, kind)
                        end
                        ui.activate('identify_region')
                    end)
                    for i, col in ipairs(cols) do
                        if col <= entry.width then
                            local at = ((row - 1) * entry.width + col - 1) * 4
                            local rgb = {}
                            for ch = 0, 2 do
                                rgb[#rgb + 1] = math.floor(math.max(0, math.min(1, entry.data[at + ch])) * 255 + 0.5)
                            end
                            local sx = gx + (i - 1) * step
                            ui.rect(sx, y, size, row_step - 2, rgb)
                            if
                                self.selected
                                and self.selected.key == selection_key
                                and self.selected.row == row
                                and self.selected.column == col
                            then
                                ui.rect(sx - 2, y - 2, size + 4, 2, { 244, 202, 53 })
                                ui.rect(sx - 2, y + row_step - 2, size + 4, 2, { 244, 202, 53 })
                            end
                            local function select()
                                choose_table()
                                self.selected = {
                                    key = selection_key,
                                    data = entry.data,
                                    row = selected_row,
                                    column = col,
                                    label = title .. ' / ' .. entry.name,
                                    field = fields[i],
                                }
                                if select_color then
                                    select_color(entry, selected_row, col, false, kind)
                                end
                            end
                            ui.hit(
                                sx,
                                y,
                                size,
                                row_step - 2,
                                select,
                                function()
                                    select()
                                    paint()
                                end,
                                function()
                                    self.scratch = { rgb[1], rgb[2], rgb[3] }
                                    if core then
                                        self.hue = core.rgb_hsv(self.scratch)
                                    end
                                    if ui.set then
                                        ui.set('scratch_color', string.format('#%02X%02X%02X', rgb[1], rgb[2], rgb[3]))
                                    end
                                end,
                                'Left-click selects. Double-click edits color. Right-click paints Scratch. Middle-click copies.',
                                function()
                                    select()
                                    ui.activate('quick_color')
                                end
                            )
                        end
                    end
                end
                cursor = cursor - entry.height * row_step - 12
            end
            if ui.scrollbar then
                ui.scrollbar(
                    'import_' .. kind,
                    x + width - 4,
                    clipbottom,
                    viewport,
                    content,
                    viewport,
                    self.gear_scroll[kind],
                    function(value)
                        self.gear_scroll[kind] = value
                    end
                )
            end
        end
        colors('Armor', 'armor', 0)
        colors('Helmet', 'helmet', lw / 2)
        button(rx + 12, top - 77, rw - 24, 'Choose file - DDS / ZIP / RAR...', 'browse')
        if state.loaded then
            local path = (state.loaded.source or 'Imported LUT'):gsub('\\', '/')
            local relative = path:match('/Epic LUT/(.*)') or path:match('[^/]+$') or path
            ui.bounded(rx + 12, top - 98, 'Imported: ' .. (state.import_description or relative), 12, muted, rw - 24)
        end
        local y = top - 117
        if state.busy then
            local spin = math.floor(state.time * 8) % 8
            for i = 0, 7 do
                local angle = i * math.pi / 4
                ui.rect(
                    rx + 29 + math.cos(angle) * 11,
                    y + 8 + math.sin(angle) * 11,
                    4,
                    4,
                    i == spin and { 244, 202, 53 } or { 75, 88, 100 }
                )
            end
            ui.text(
                rx + 55,
                y + 5,
                (state.import_detail and state.import_detail ~= '' and state.import_detail or state.phase)
                    .. (state.waiting and '' or '  ' .. (state.progress or 0) .. '% completed'),
                14,
                white
            )
        else
            ui.bounded(rx + 12, y + 5, state.status, 14, muted, rw - 24)
        end
        if state.busy then
            button(rx + 12, top - 161, (rw - 29) / 2, 'Cancel import', 'cancel_import')
            button(rx + 17 + (rw - 29) / 2, top - 161, (rw - 29) / 2, 'Retry file picker', 'retry_import')
        end
        button(
            rx + 12,
            top - 203,
            rw - 24,
            'Send to LUT Editor',
            'save_palette',
            state.loaded ~= nil and not state.busy
        )
        ui.bounded(rx + 12, top - 224, 'Overwrites the editor table; does not apply to gear.', 13, muted, rw - 24)
        local preview_height = math.max(44, math.min(200, ui.h - ((state.palette_count or 0) > 1 and 670 or 570)))
        local preview_top = top - 246
        local preview_bottom = preview_top - preview_height
        self.import_bounds = { x = rx + 12, y = preview_bottom, w = rw - 24, h = preview_height }
        local imported = state.raw and state.raw.tables or state.tables or {}
        if #imported == 0 and state.loaded then
            imported =
                { { index = 1, width = state.loaded.width, height = state.loaded.height, data = state.loaded.data } }
        end
        text(
            rx + 12,
            top - 238,
            'Imported file: ' .. #imported .. ' LUT' .. (#imported == 1 and '' or 's') .. ' / Column 1'
        )
        self.import_max = math.max(0, #imported * 22 - preview_height)
        self.import_scroll = math.min(self.import_scroll or 0, self.import_max)
        for i, entry in ipairs(imported) do
            local y = preview_top - i * 22 + self.import_scroll
            if y >= preview_bottom and y + 20 <= preview_top then
                ui.bounded(rx + 16, y + 5, 'LUT ' .. (entry.index or i), 12, white, 58)
                local size = math.min(24, (rw - 94) / entry.height)
                for row = 1, entry.height do
                    local at = (row - 1) * entry.width * 4
                    local rgb = {}
                    for ch = 0, 2 do
                        rgb[#rgb + 1] = math.floor(math.max(0, math.min(1, entry.data[at + ch])) * 255 + 0.5)
                    end
                    ui.rect(rx + 82 + (row - 1) * size, y, size - 2, 18, rgb)
                end
                local index = entry.index or i
                ui.hit(rx + 12, y, rw - 24, 20, function()
                    if ui.set then
                        ui.set('palette', index)
                    end
                end)
            end
        end
        if self.import_max > 0 then
            ui.bounded(rx + 12, preview_bottom - 12, 'Scroll for more imported LUTs', 10, muted, rw - 24)
        end
        ui.rect(rx + 12, preview_bottom - 18, rw - 24, 1, divider)
        local actions = preview_bottom - 30
        text(rx + 12, actions, 'Apply Imported LUT ' .. (state.palette_index or 1))
        local apply_width = (rw - 30) / 2
        local matching = state.raw and state.raw.matching
        if (state.palette_count or 0) > 1 then
            button(
                rx + 12,
                actions - 36,
                rw - 24,
                'Apply Matching LUTs',
                'apply_matching',
                matching and matching.matched > 0 and not state.busy
            )
            local summary = matching
                    and (matching.total .. ' imported / ' .. matching.matched .. ' matched / ' .. (matching.unmatched + matching.unidentified + matching.ambiguous) .. ' unmatched or ambiguous')
                or 'Resource IDs unavailable - target individual LUTs manually.'
            if matching and matching.matched == 0 then
                summary = matching.total .. ' imported / 0 matched / ' .. matching.total .. ' for manual assignment'
            end
            ui.bounded(rx + 12, actions - 55, summary, 13, muted, rw - 24)
            ui.choice('palette', rx + 12, actions - 91, rw - 24)
            button(
                rx + 12,
                actions - 125,
                apply_width,
                'Apply LUT ' .. (state.palette_index or 1) .. ' to All Armor LUTs',
                'apply_file_armor',
                state.loaded ~= nil and not state.busy
            )
            button(
                rx + 18 + apply_width,
                actions - 125,
                apply_width,
                'Apply LUT ' .. (state.palette_index or 1) .. ' to All Helmet LUTs',
                'apply_file_helmet',
                state.loaded ~= nil and not state.busy
            )
            actions = actions - 70
        else
            button(
                rx + 12,
                actions - 36,
                apply_width,
                'Apply to All Armor LUTs',
                'apply_file_armor',
                state.loaded ~= nil and not state.busy
            )
            button(
                rx + 18 + apply_width,
                actions - 36,
                apply_width,
                'Apply to All Helmet LUTs',
                'apply_file_helmet',
                state.loaded ~= nil and not state.busy
            )
            ui.bounded(rx + 12, actions - 55, 'Applies to every LUT on that gear.', 13, muted, rw - 24)
        end
        button(
            rx + 12,
            actions - 95,
            rw - 24,
            '[ ' .. (state.preserve_emissives and 'x' or ' ') .. ' ] Preserve Original Emissives',
            'preserve_emissives'
        )
        ui.rect(rx + 12, actions - 109, rw - 24, 1, divider)
        button(rx + 12, actions - 145, (rw - 30) / 2, 'Restore Arrowhead LUT (Original)', 'restore')
        button(
            rx + 18 + (rw - 30) / 2,
            actions - 145,
            (rw - 30) / 2,
            'Restore Imported LUT (editor)',
            'restore_imported'
        )
        button(rx + 12, actions - 183, (rw - 29) / 2, 'Undo Last Action', 'global_undo')
        button(rx + 17 + (rw - 29) / 2, actions - 183, (rw - 29) / 2, 'Redo Last Action', 'global_redo')
        button(rx + 12, actions - 221, rw - 24, 'Save applied setup', 'save_setup')
        ui.text(rx + 12, ui.y + 14, 'RAR requires installed 7-Zip. Match Your Colors should be Off.', 13, muted)
    end
    return self
end
return V
