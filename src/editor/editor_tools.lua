-- Optional editor tools. Only the active tab composes controls; document actions
-- remain in the editor registry so Basic and Advanced share the same behavior.
local T = {}
T.MAX_CONTENT_WIDTH, T.MAX_TAB_WIDTH = 760, 180
local tabs = { 'import', 'rows', 'export', 'options' }
local labels = { import = 'Import', rows = 'Rows', export = 'Export', options = 'Options' }
local accent, ink = { 244, 202, 53 }, { 25, 28, 31 }

local function dock_icon(ui, x, y, width, height, undock)
    local w = math.min(width - 10, (height - 10) * 1.25)
    local h, stroke = w / 1.25, math.max(ui.pixel_width or 1, w * 0.12)
    local left, bottom = x + (width - w) / 2, y + (height - h) / 2
    local function strip(px, py, sw, sh)
        -- Mirroring the two windows gives the opposing action the same shape
        -- and weight. Native rectangle strokes avoid a font-symbol dependency.
        if undock then
            px = w - px - sw
        end
        ui.rect(left + px, bottom + py, sw, sh, ui.theme.white, nil, 'control_icon')
    end
    strip(0, 0, w * 0.8, stroke)
    strip(0, stroke, stroke, h * 0.75 - stroke)
    local fx, fy, fw, fh = w * 0.2, h * 0.25, w * 0.8, h * 0.75
    strip(fx, fy, fw, stroke)
    strip(fx, fy + fh - stroke, fw, stroke)
    strip(fx, fy + stroke, stroke, fh - stroke * 2)
    strip(fx + fw - stroke, fy + stroke, stroke, fh - stroke * 2)
end

function T.new(deps)
    local editor, document = deps.editor, deps.document
    local self = { tab = 'import', docked = true, scroll = 0 }
    local opened = false

    function self.open(tab)
        assert(tab == nil or labels[tab], 'Unknown editor tools tab')
        if tab and self.tab ~= tab then
            self.scroll = 0
        end
        self.tab, opened = tab or self.tab, true
        self.raise_pending = true
    end
    function self.close()
        opened = false
        self.bounds = nil
    end
    function self.is_open()
        return opened
    end
    function self.is_docked()
        return self.docked
    end
    function self.mount_preferences(preferences)
        self.preferences = preferences
        if preferences and preferences.tools_docked then
            self.docked = preferences.tools_docked() ~= false
            self.bounds = nil
        end
    end
    function self.set_docked(value)
        value = not not value
        if value == self.docked then
            return true
        end
        if self.preferences and self.preferences.save_tools_docked then
            local ok, why = self.preferences.save_tools_docked(value)
            if not ok then
                if deps.note then
                    deps.note('Could not save Tools layout: ' .. tostring(why))
                end
                return false, why
            end
        end
        self.docked = value
        self.bounds = nil
        return true
    end
    function self.wheel(x, y, delta)
        local b = self.bounds
        if opened and self.docked and b and x and y and x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
            self.scroll = math.max(0, math.min(self.maximum or 0, self.scroll - delta / 120 * (self.scroll_step or 90)))
            return true
        end
    end
    local function metrics(ui)
        local heading = ui.text_size and ui.text_size(14, 'heading') or 14
        local header = math.max(40, heading + (ui.spacing and ui.spacing(16) or 16))
        local button = ui.control_height and ui.control_height(14, 6, 28)
            or math.max(28, (ui.text_size and ui.text_size(14) or 14) + 12)
        return heading, header, button, ui.spacing and ui.spacing(10) or 10
    end
    function self.minimum_height(ui)
        local _, _, button, gap = metrics(ui)
        return button * 2 + gap * 3 + 12
    end
    local function draw(ui, x, y, w, ht, docked)
        local h = editor.handle
        local controls = editor.api.mods[h.id].controls
        local d = document()
        local heading_size, header_height, bh, gap = metrics(ui)
        if docked then
            header_height = 0
        end
        local theme = ui.theme
        local white, muted = theme.white, theme.muted
        local bx, frame_width = x + 14, w - 36
        local width = math.min(T.MAX_CONTENT_WIDTH, frame_width)
        local dock_label = docked and 'Undock' or 'Dock'
        local dock_width = math.max(36, bh)
        local dock_x = docked and bx + frame_width - dock_width - math.max(28, bh) - 6 or x + w - 38 - dock_width
        local tab_y = y + ht - header_height - gap - bh
        local close_width = docked and math.max(28, bh) or 0
        local tab_available = frame_width - (docked and dock_width + close_width + 18 or 0)
        local tab_rows, tab_cursor = 1, 0
        local tab_layout = {}
        for _, tab in ipairs(tabs) do
            local measured = ui.text_width and ui.text_width(labels[tab], 14)
                or #labels[tab] * (ui.text_size and ui.text_size(14) or 14) * 0.62
            local tw =
                math.min(T.MAX_TAB_WIDTH, tab_available, math.max(72, measured + (ui.spacing and ui.spacing(20) or 20)))
            if tab_cursor > 0 and tab_cursor + tw > tab_available then
                tab_rows, tab_cursor = tab_rows + 1, 0
            end
            tab_layout[#tab_layout + 1] =
                { tab = tab, x = bx + tab_cursor, y = tab_y - (tab_rows - 1) * (bh + 6), w = tw }
            tab_cursor = tab_cursor + tw + 6
        end
        local body_tab_y = tab_y - (tab_rows - 1) * (bh + 6)
        local top = body_tab_y - math.max(40, (ui.text_size and ui.text_size(14, 'hint') or 14) + gap * 2)
        local step = bh + gap
        local clip_bottom, clip_top = y + 12, body_tab_y - gap
        local offset = docked and self.scroll or 0
        local lowest = top
        local function visible(py, height)
            lowest = math.min(lowest, py - offset)
            return not docked or (py >= clip_bottom and py + height <= clip_top)
        end
        local function label(py, text, color, role)
            local size = ui.text_size and ui.text_size(14, role) or 14
            local ink = ui.text_metrics and ui.text_metrics(14, text, role) or { min_y = 0, height = size }
            py = py + offset
            if visible(py + ink.min_y, ink.height) then
                ui.bounded(bx, py, text, 14, color or white, width, role)
            end
        end
        local function button(px, py, bw, text, id, enabled, callback, help)
            if id and not controls[id] then
                return
            end
            py = py + offset
            if not visible(py, bh) then
                return
            end
            enabled = enabled ~= false and (not id or not controls[id].disabled)
            local loading = id == 'populate_worn'
            local featured = enabled
                and (
                    loading
                    or id == 'load_debug_lut'
                    or id == 'export_selected'
                    or id == 'save_row'
                    or id == 'save_setup'
                )
            local color = loading and ui.load_color and ui.load_color(editor.load_seen and editor.load_seen()) or accent
            ui.button(px, py, bw, bh, text, function()
                if callback then
                    callback()
                else
                    ui.activate(id)
                end
            end, {
                enabled = enabled,
                accent = featured and color,
                ink = featured and ink,
                help = help,
                field = id and controls[id].type == 'input',
            })
        end
        local function natural_width(text, field)
            local measured = ui.text_width and ui.text_width(text, 14)
                or #text * (ui.text_size and ui.text_size(14) or 14) * 0.62
            local wanted =
                math.min(width, math.max(field and 260 or 100, measured + (ui.spacing and ui.spacing(24) or 24)))
            return ui.width_cap and ui.width_cap(wanted, text, field and 'field' or 'action') or wanted
        end
        local function action(py, text, id, enabled, help)
            button(
                bx,
                py,
                natural_width(text, id and controls[id] and controls[id].type == 'input'),
                text,
                id,
                enabled,
                nil,
                help
            )
        end
        local function choice(id, py, bw, px)
            py = py + offset
            if ui.choice and controls[id] and visible(py, 26) then
                ui.choice(id, px or bx, py, bw or width)
            end
        end
        local function divider(py)
            py = py + offset
            if visible(py, 1) then
                ui.rect(bx, py, width, 1, theme.line)
            end
        end
        local function action_row(py, entries)
            local px, line = bx, py
            for _, entry in ipairs(entries) do
                local bw =
                    natural_width(entry[1], entry[2] and controls[entry[2]] and controls[entry[2]].type == 'input')
                if px > bx and px + bw > bx + width then
                    line, px = line - step, bx
                end
                button(px, line, bw, entry[1], entry[2], entry[3], entry[4], entry[5])
                px = px + bw + gap
            end
            return line - step
        end
        local function preview(live)
            if ui.preview then
                ui.preview(function(bounds)
                    return editor.preview(bounds, live)
                end)
            end
        end
        ui.rect(x, y, w, ht, theme.panel)
        if not docked then
            ui.rect(x, y + ht - header_height, w, header_height, theme.header)
            local title_y = ui.text_y
                    and ui.text_y(y + ht - header_height, header_height, 14, 'LUT Editor Tools', 'heading')
                or y + ht - header_height + (header_height - heading_size) / 2
            ui.bounded(bx, title_y, 'LUT Editor Tools', 14, white, dock_x - bx - 8, 'heading')
        end
        self.tab_bounds = tab_layout
        self.content_bounds = { x = bx, y = clip_bottom, w = width, h = math.max(0, clip_top - clip_bottom) }
        for _, layout in ipairs(tab_layout) do
            local tab = layout.tab
            ui.button(layout.x, layout.y, layout.w, bh, labels[tab], function()
                self.open(tab)
            end, { selected = self.tab == tab })
        end
        local dock_y = docked and tab_y or y + ht - header_height + (header_height - bh) / 2
        ui.button(dock_x, dock_y, dock_width, bh, '', function()
            self.set_docked(not docked)
        end, {
            help = dock_label
                .. (
                    docked and ': open Tools in its own window.'
                    or ': place Tools below the swatches inside the LUT Editor.'
                ),
        })
        dock_icon(ui, dock_x, dock_y, dock_width, bh, docked)
        if docked then
            ui.button(
                bx + frame_width - close_width,
                tab_y,
                close_width,
                bh,
                'X',
                self.close,
                { help = 'Close Tools.' }
            )
        end

        local function choice_width(id)
            local control = controls[id]
            local value = control and control.choices and control.choices[h.get(id)] or ''
            local measured = ui.text_width and ui.text_width(value, 14) or #tostring(value) * 8
            return math.min(width, math.max(240, measured + 112))
        end
        local function mapping_actions()
            local entries = {}
            for _, kind in ipairs({ 'armor', 'helmet', 'cape' }) do
                if controls['imported_map_' .. kind] then
                    entries[#entries + 1] = {
                        'Map LUTs to ' .. kind:sub(1, 1):upper() .. kind:sub(2),
                        'imported_map_' .. kind,
                        true,
                    }
                end
            end
            return entries
        end
        if self.tab == 'import' then
            label(top, 'Import a palette, then choose the table to edit or apply.', muted, 'hint')
            local first = { { 'Import DDS / ZIP / RAR...', 'browse', true } }
            if controls.populate_worn then
                first[#first + 1] = {
                    'Load Current Gear',
                    'populate_worn',
                    true,
                    nil,
                    'Read every worn LUT slot without changing its colors.',
                }
            end
            local cursor = action_row(top - step, first)
            choice('palette', cursor, choice_width('palette'))
            cursor = action_row(cursor - step, {
                {
                    'Preview Palette',
                    nil,
                    editor.preview ~= nil,
                    function()
                        preview(false)
                    end,
                },
                {
                    'Send to LUT Editor',
                    'save_palette',
                    true,
                    nil,
                    'Replace the editor table with the selected imported LUT. Gear is unchanged until applied.',
                },
            })
            divider(cursor + gap / 2)
            cursor = cursor - gap
            if controls.editor_load_armor then
                local gear = editor.gear or 'armor'
                local selector = controls['basic_' .. gear .. '_lut']
                local selected = selector and selector.choices[h.get('basic_' .. gear .. '_lut')]
                local target = selected and selected:match('^Cape') and selected
                    or (gear == 'armor' and 'Armor' or 'Helmet') .. ' LUT ' .. h.get('basic_' .. gear .. '_lut')
                local mapping = mapping_actions()
                if #mapping > 0 then
                    action(cursor, 'Apply to ' .. target, 'editor_apply_' .. gear, d ~= nil)
                    action_row(cursor - step, mapping)
                else
                    action_row(cursor, {
                        { 'Apply to ' .. target, 'editor_apply_' .. gear, d ~= nil },
                        {
                            'Apply to All ' .. (gear == 'armor' and 'Armor' or 'Helmet') .. ' LUTs',
                            'editor_all_' .. gear,
                            d ~= nil,
                            nil,
                            'Apply the current editor table to every LUT on this gear. Send an imported LUT to the editor first.',
                        },
                    })
                end
            else
                choice('lut', cursor, choice_width('lut'))
                action_row(cursor - step, {
                    {
                        'Preview Live LUT',
                        nil,
                        editor.preview ~= nil,
                        function()
                            preview(true)
                        end,
                    },
                    { 'Apply to checked targets', 'apply_editor', d ~= nil },
                })
            end
        elseif self.tab == 'rows' then
            local selected = editor.selection
            local multiple = d and selected and selected.c1 == 1 and selected.r1 < selected.r2
            local target = multiple and ('Selected rows: ' .. selected.r1 .. '-' .. selected.r2)
                or ('Selected row: ' .. h.get('edit_row'))
            label(top, target .. (d and ' / ' .. d.height or ' / Load a LUT first'), nil, 'heading')
            local cursor = top - step
            if ui.preset then
                local py = cursor + offset
                if visible(py, 26) then
                    local name = h.get('row_preset') or ''
                    local measured = ui.text_width and ui.text_width(name, 14) or #name * 8
                    ui.preset('row_preset', 'row_preset_select', bx, py, math.min(width, math.max(360, measured + 240)))
                end
            else
                action(cursor, 'Preset: ' .. h.get('row_preset'), 'row_preset', true)
            end
            cursor = action_row(cursor - step, {
                { 'Save selected row', 'save_row', d ~= nil },
                { multiple and 'Apply preset to rows' or 'Apply preset to row', 'load_row', d ~= nil },
            })
            divider(cursor + gap / 2)
            cursor = action_row(cursor - gap, {
                { 'Copy row', 'copy_row', d ~= nil },
                { 'Paste row', 'paste_row', d ~= nil and editor.row_clip ~= nil },
            })
            cursor = action_row(cursor, {
                { 'Reset row', 'reset_row', d ~= nil },
                { 'Reset cell', 'reset_cell', d ~= nil },
            })
            action(cursor, 'Import Paydex JSON...', 'import_paydex_rows', true)
        elseif self.tab == 'export' then
            label(top, 'Choose what to export. A timestamp is added to each filename.', muted, 'hint')
            local cursor = top - step
            local name = 'Name: ' .. (ui.input_value and ui.input_value('save_name') or h.get('save_name'))
            local name_width, format_width = natural_width(name, true), choice_width('export_format')
            button(bx, cursor, name_width, name, 'save_name', true)
            if name_width + gap + format_width <= width then
                choice('export_format', cursor, format_width, bx + name_width + gap)
            else
                cursor = cursor - step
                choice('export_format', cursor, format_width)
            end
            cursor = cursor - step
            if h.get('export_format') == 4 then
                choice('dds_naming', cursor, choice_width('dds_naming'))
                cursor = cursor - step
            end
            cursor = action_row(cursor, {
                { 'Export...', 'export_selected', d ~= nil or h.get('export_format') >= 3 },
                { 'Open Export Location', 'open_export', true },
            })
            divider(cursor + gap / 2)
            if controls.include_capes_in_armor_exports then
                action(
                    cursor - gap,
                    '[ '
                        .. (h.get('include_capes_in_armor_exports') and 'x' or ' ')
                        .. ' ] Include Capes in Armor Exports',
                    'include_capes_in_armor_exports',
                    true,
                    controls.include_capes_in_armor_exports.description
                )
            end
        else
            label(top, 'Apply and restoration options for the current gear.', muted, 'hint')
            local cursor = action_row(top - step, {
                { 'Load Debug LUT', 'load_debug_lut', true },
                {
                    '[ '
                        .. (controls.preserve_emissives and h.get('preserve_emissives') and 'x' or ' ')
                        .. ' ] Preserve Original Emissives',
                    'preserve_emissives',
                    true,
                },
            })
            if controls.editor_load_armor then
                local mapping = mapping_actions()
                cursor = action_row(cursor, #mapping > 0 and mapping or {
                    { 'All Armor LUTs', 'editor_all_armor', d ~= nil },
                    { 'All Helmet LUTs', 'editor_all_helmet', d ~= nil },
                })
            else
                cursor = action_row(cursor, {
                    { '[ ' .. (h.get('target_helmet') and 'x' or ' ') .. ' ] Helmet', 'target_helmet', true },
                    { '[ ' .. (h.get('target_armor') and 'x' or ' ') .. ' ] Armor', 'target_armor', true },
                })
            end
            divider(cursor + gap / 2)
            cursor = action_row(cursor - gap, {
                { 'Restore Arrowhead LUT (Original)', 'restore', true },
                { 'Reset imported table', 'reset_custom', d ~= nil },
            })
            action(cursor, 'Save applied setup', 'save_setup', true)
        end
        if docked then
            local viewport = math.max(0, clip_top - clip_bottom)
            local content = math.max(viewport, clip_top - lowest + 12)
            self.maximum = math.max(0, content - viewport)
            self.scroll = math.min(self.scroll, self.maximum)
            -- Whole controls stay inside the viewport. Small viewports need
            -- small steps so the wheel cannot jump past a control entirely.
            self.scroll_step = math.max(1, math.min(gap * 3, viewport - bh))
            if ui.scrollbar and viewport > 0 then
                ui.scrollbar(
                    'editor_tools_docked',
                    x + w - 8,
                    clip_bottom,
                    viewport,
                    content,
                    viewport,
                    self.scroll,
                    function(value)
                        self.scroll = value
                    end
                )
            end
        end
    end
    function self.dock(ui, bounds)
        self.bounds = nil
        if not opened or not self.docked or not bounds then
            return
        end
        self.bounds = bounds
        draw(ui, bounds.x, bounds.y, bounds.w, bounds.h, true)
    end
    function self.popup(ui)
        if not opened or self.docked or not ui.floating then
            return
        end
        self.bounds = nil
        local _, header_height, button_height = metrics(ui)
        ui.floating('editor_tools', function(x, y, w, ht)
            draw(ui, x, y, w, ht, false)
        end, 620, 540, self.close, header_height, self.raise_pending, math.max(36, button_height) + 6)
        self.raise_pending = false
    end
    return self
end
return T
