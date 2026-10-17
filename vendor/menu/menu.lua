-- MCM layout/controller. Drawing is isolated from registry and settings storage.

local M = {}
-- Shared MCM surface colors; custom editor actions retain their own accents.
M.palette = {
    background = { 17, 22, 27 },
    panel = { 23, 29, 35 },
    header = { 31, 38, 44 },
    border = { 65, 77, 85 },
    line = { 43, 53, 61 },
    white = { 231, 236, 239 },
    muted = { 153, 166, 175 },
    brass = { 221, 184, 105 },
    focus = { 119, 185, 205 },
    hover = { 35, 46, 55 },
    selected = { 38, 53, 63 },
    text_selection = { 48, 117, 158 },
    field = { 29, 39, 47 },
    field_hover = { 40, 55, 65 },
    enabled = { 118, 207, 177 },
    disabled = { 111, 124, 133 },
}
-- Epic has its own neutral workspace skin. The shared MCM palette stays intact.
M.epic_palette = {
    background = { 12, 14, 16 },
    panel = { 19, 21, 23 },
    header = { 25, 27, 29 },
    border = { 62, 66, 69 },
    border_hover = { 106, 111, 114 },
    line = { 34, 37, 40 },
    white = { 234, 235, 228 },
    muted = { 154, 159, 159 },
    brass = { 221, 184, 105 },
    focus = { 244, 202, 53 },
    hover = { 29, 31, 33 },
    selected = { 43, 39, 24 },
    text_selection = { 48, 117, 158 },
    field = { 29, 31, 34 },
    field_hover = { 39, 42, 45 },
    enabled = { 176, 205, 176 },
    disabled = { 105, 111, 113 },
}
-- Epic typography is opt-in. Other users of this menu keep their original
-- requested sizes, compact-font behavior and global bold preference.
function M.text_size(menu, size, role)
    if menu.epic_typography then
        local ratio = role == 'heading' and 1.15 or role == 'title' and 1.5 or role == 'hint' and 0.88 or 1
        return (menu.font_size or 12) * ratio
    end
    return menu.compact_fonts and (menu.font_size or 12) or (size or 20)
end
function M.text_bold(menu, role)
    return menu.font_bold and (not menu.epic_typography or role == 'heading' or role == 'title') or false
end
-- Native GUI layers are integers. Border geometry must also be safe when its
-- retained allocation changes independently: never paint over the interior.
function M.control_border(ui, x, y, w, h, color)
    local stroke = math.min(2 * (ui.pixel_width or 1), w / 2, h / 2)
    ui.rect(x, y, w, stroke, color, nil, 'control_border')
    ui.rect(x, y + h - stroke, w, stroke, color, nil, 'control_border')
    ui.rect(x, y + stroke, stroke, math.max(0, h - stroke * 2), color, nil, 'control_border')
    ui.rect(x + w - stroke, y + stroke, stroke, math.max(0, h - stroke * 2), color, nil, 'control_border')
end
-- Native checkbox ink is shared by custom workspaces and modal selectors.
-- It stays visible with either the HUD font or the debug-font fallback.
function M.checkbox(ui, x, y, width, height, checked, enabled, callback, help)
    local size = math.min(22, width, height - 4)
    local left, bottom = x + (width - size) / 2, y + (height - size) / 2
    local theme = ui.theme
    local hovered = enabled and ui.hovering and ui.hovering(x, y, width, height)
    local border = not enabled and theme.line
        or checked and theme.focus
        or hovered and (theme.border_hover or theme.focus)
        or theme.muted
    ui.rect(left, bottom, size, size, checked and theme.selected or theme.panel, nil, 'control_fill')
    M.control_border(ui, left, bottom, size, size, border)
    if checked then
        local unit, ink = size / 20, enabled and theme.focus or theme.disabled
        for step = 0, 3 do
            ui.rect(left + (4 + step) * unit, bottom + (10 - step) * unit, 2 * unit, 2 * unit, ink, nil, 'control_icon')
        end
        for step = 0, 8 do
            ui.rect(left + (7 + step) * unit, bottom + (7 + step) * unit, 2 * unit, 2 * unit, ink, nil, 'control_icon')
        end
    end
    if callback then
        ui.hit(x, y, width, height, function()
            if enabled then
                callback(not checked)
            end
        end, nil, nil, help)
    end
end
-- Small decoded pattern masks share the regular popup plane. Merge adjacent
-- pixels so previews remain cheap to retain and never need another GUI.
function M.pattern_thumbnail(preview, emit, x, y, size)
    if
        not preview
        or not preview.width
        or not preview.height
        or not preview.colors
        or preview.width < 1
        or preview.width > 16
        or preview.height < 1
        or preview.height > 16
        or preview.width % 1 ~= 0
        or preview.height % 1 ~= 0
        or #preview.colors ~= preview.width * preview.height
    then
        return
    end
    for row = 0, preview.height - 1 do
        local first = 0
        while first < preview.width do
            local color = preview.colors[row * preview.width + first + 1]
            local last = first + 1
            while last < preview.width do
                local next_color = preview.colors[row * preview.width + last + 1]
                if color[1] ~= next_color[1] or color[2] ~= next_color[2] or color[3] ~= next_color[3] then
                    break
                end
                last = last + 1
            end
            emit(
                x + first * size / preview.width,
                y + (preview.height - row - 1) * size / preview.height,
                (last - first) * size / preview.width,
                size / preview.height,
                color,
                nil,
                'swatch_fill'
            )
            first = last
        end
    end
end
-- Custom workspaces use the same surfaces and interaction feedback as MCM.
-- Accents remain explicit so Load, Save and Export retain their meaning.
function M.width_cap(ui, available, label, kind, options)
    local o = options or {}
    local maximum = 760
    if kind ~= 'field' then
        local size = o.size or 14
        local resolved = ui.text_size and ui.text_size(size, o.role) or size
        local padding = ui.spacing and ui.spacing(o.padding or 8) or o.padding or 8
        local measured = ui.text_width and ui.text_width(tostring(label or ''), size, o.role)
        if not measured then
            measured = 0
            for _ in tostring(label or ''):gmatch('[%z\1-\127\194-\244][\128-\191]*') do
                measured = measured + resolved * 0.62
            end
        end
        maximum = math.min(620, math.max(360, measured + padding * 2))
    end
    return math.max(0, math.min(available, maximum))
end
function M.custom_ui(ui)
    ui.theme = ui.epic_style and M.epic_palette or M.palette
    ui.decorate = M.custom_ui
    function ui.checkbox(...)
        return M.checkbox(ui, ...)
    end
    function ui.width_cap(width, label, kind, options)
        return M.width_cap(ui, width, label, kind, options)
    end
    function ui.surface_color(x, y, w, h, options)
        local o, T = options or {}, ui.theme
        local hovered = o.enabled ~= false and ui.hovering and ui.hovering(x, y, w, h)
        return o.enabled == false and T.panel
            or o.accent
            or (o.selected and T.selected)
            or (hovered and ((ui.epic_style and o.field ~= true or o.field == false) and T.hover or T.field_hover))
            or ((ui.epic_style and o.field ~= true or o.field == false) and T.panel or T.field)
    end
    function ui.button(x, y, w, h, label, callback, options)
        local o, T = options or {}, ui.theme
        w = M.width_cap(ui, w, label, o.field and 'field' or 'action', o)
        if ui.text_button and ui.text_button(x, y, w, h, label, callback, o) then
            return w
        end
        local enabled = o.enabled ~= false
        local color = ui.surface_color(x, y, w, h, o)
        local hovered = enabled and ui.hovering and ui.hovering(x, y, w, h)
        local size, role = o.size or 14, o.role
        local pad = ui.spacing and ui.spacing(o.padding or 8) or o.padding or 8
        if ui.epic_style then
            -- Four narrow strips cannot cover the interior, even if a native
            -- retained allocation is refreshed independently of its siblings.
            ui.rect(x, y, w, h, color, nil, 'control_fill')
            local border = enabled and (o.accent or o.selected and T.focus or hovered and T.border_hover or T.border)
                or T.line
            M.control_border(ui, x, y, w, h, border)
        else
            ui.rect(x, y, w, h, color, nil, 'control_fill')
        end
        ui.bounded(
            x + pad,
            ui.text_y and ui.text_y(y, h, size, label, role)
                or y + math.max(2, (h - (ui.text_size and ui.text_size(size) or size)) / 2),
            label,
            size,
            enabled and (o.ink or T.white) or T.disabled,
            math.max(0, w - pad * 2),
            role
        )
        if enabled and (o.selected or hovered and not ui.epic_style) then
            ui.rect(x, y, ui.epic_style and 2 * (ui.pixel_width or 1) or 2, h, T.focus, nil, 'control_accent')
        end
        ui.hit(x, y, w, h, function(...)
            if enabled and callback then
                callback(...)
            end
        end, nil, nil, o.help)
        return w
    end
    return ui
end
function M.picker_allowed(control, mode)
    if not control or control.disabled or control.read_only then
        return false, 'This value is not editable.'
    end
    if control.can_open_picker then
        local called, allowed, why = pcall(control.can_open_picker, mode)
        if not called then
            return false, 'Color unavailable: ' .. tostring(allowed)
        end
        if allowed ~= true then
            return false, why or 'This value is not editable.'
        end
    end
    return true
end
local function preset_completion(dialog, draft)
    if not dialog or type(dialog.names) ~= 'table' or type(draft) ~= 'string' or draft == '' then
        return nil
    end
    local prefix, best, best_folded = draft:lower()
    for _, name in ipairs(dialog.names) do
        if type(name) == 'string' and #name > 0 and #name <= 48 then
            local folded = name:lower()
            if
                folded:sub(1, #prefix) == prefix
                and (not best or folded < best_folded or folded == best_folded and name < best)
            then
                best, best_folded = name, folded
            end
        end
    end
    return best ~= draft and best or nil
end
local function picker_channel_allowed(control, channel, mode)
    if not control.picker_channel_enabled then
        return true
    end
    local ok, allowed = pcall(control.picker_channel_enabled, channel, mode)
    return ok and allowed == true
end
local function saved_notice(c, handle)
    if handle and c.id and handle.preview and handle.get then
        local ok, preview = pcall(handle.preview, c.id)
        local got, value = pcall(handle.get, c.id)
        if ok and got then
            return preview ~= value and 'Changes ready to apply' or 'Saved'
        end
    end
    return c and c.page and c.page.require_confirmation and c.require_confirmation ~= false and 'Changes ready to apply'
        or 'Saved'
end
function M.key_name(key)
    if key == 0 then
        return 'Unassigned'
    end
    if key >= 112 and key <= 135 then
        return 'F' .. (key - 111)
    end
    if key >= 48 and key <= 90 then
        return string.char(key)
    end
    if key >= 96 and key <= 105 then
        return 'Numpad ' .. (key - 96)
    end
    local names = {
        [1] = 'Left Mouse',
        [2] = 'Right Mouse',
        [4] = 'Middle Mouse',
        [5] = 'Mouse 4',
        [6] = 'Mouse 5',
        [8] = 'Backspace',
        [9] = 'Tab',
        [13] = 'Enter',
        [16] = 'Shift',
        [17] = 'Ctrl',
        [18] = 'Alt',
        [19] = 'Pause',
        [20] = 'Caps Lock',
        [27] = 'Escape',
        [32] = 'Space',
        [33] = 'Page Up',
        [34] = 'Page Down',
        [35] = 'End',
        [36] = 'Home',
        [37] = 'Left Arrow',
        [38] = 'Up Arrow',
        [39] = 'Right Arrow',
        [40] = 'Down Arrow',
        [44] = 'Print Screen',
        [45] = 'Insert',
        [46] = 'Delete',
        [91] = 'Left Windows',
        [92] = 'Right Windows',
        [93] = 'Menu',
        [106] = 'Numpad *',
        [107] = 'Numpad +',
        [109] = 'Numpad -',
        [110] = 'Numpad .',
        [111] = 'Numpad /',
        [144] = 'Num Lock',
        [145] = 'Scroll Lock',
        [160] = 'Left Shift',
        [161] = 'Right Shift',
        [162] = 'Left Ctrl',
        [163] = 'Right Ctrl',
        [164] = 'Left Alt',
        [165] = 'Right Alt',
        [186] = ';',
        [187] = '=',
        [188] = ',',
        [189] = '-',
        [190] = '.',
        [191] = '/',
        [192] = '`',
        [219] = '[',
        [220] = '\\',
        [221] = ']',
        [222] = "'",
    }
    return names[key] or 'Unknown Key'
end

-- Custom choices honor the same dropdown/selector/combined presentation as MCM.
function M.choice(ui, control, value, x, y, width, change, open)
    local T = ui.theme or M.palette
    local disabled = control.disabled
    local hovered = not disabled and ui.hovering and ui.hovering(x, y, width, 26)
    local color = disabled and T.disabled or T.white
    local field = control.field_color
    local valid = type(field) == 'table' and #field == 3
    if valid then
        for i = 1, 3 do
            local channel = field[i]
            if type(channel) ~= 'number' or channel ~= channel or channel < 0 or channel > 255 then
                valid = false
                break
            end
        end
    end
    local background = hovered and T.field_hover or T.field
    if valid and not disabled then
        background = hovered
                and {
                    math.min(255, field[1] + 12),
                    math.min(255, field[2] + 12),
                    math.min(255, field[3] + 12),
                }
            or field
    end
    ui.rect(x, y, width, 26, disabled and T.panel or background, nil, 'control_fill')
    ui.rect(x, y, 2, 26, disabled and T.line or T.focus, nil, 'control_accent')
    local presentation = control.presentation or 'combined'
    local dropdown, selector = presentation == 'dropdown', presentation == 'selector'
    local step_width = dropdown and 0 or math.min(32, width / (selector and 2 or 3))
    local open_width = math.max(0, width - step_width * 2)
    local indicator_width = selector and 0 or math.min(44, open_width)
    local reserved = step_width * 2 + indicator_width + 16
    local function baseline(size, label)
        return ui.text_y and ui.text_y(y, 26, size, label) or y + 5
    end
    if not dropdown then
        ui.text(x + open_width + (step_width - 10) / 2, baseline(16, '<'), '<', 16, color)
        ui.text(x + open_width + step_width + (step_width - 10) / 2, baseline(16, '>'), '>', 16, color)
        ui.hit(x + open_width, y, step_width, 26, function()
            if not control.disabled then
                change(-1)
            end
        end)
        ui.hit(x + open_width + step_width, y, step_width, 26, function()
            if not control.disabled then
                change(1)
            end
        end)
    end
    if not selector then
        ui.rect(
            x + open_width - indicator_width,
            y,
            indicator_width,
            26,
            disabled and T.panel or T.field_hover,
            nil,
            'control_accent'
        )
        ui.text(x + open_width - (indicator_width + 10) / 2, baseline(16, 'v'), 'v', 16, color)
    end
    local label = tostring(control.choices[value] or '')
    ui.bounded(x + 8, baseline(15, label), label, 15, color, math.max(0, width - reserved))
    ui.hit(
        x,
        y,
        open_width,
        26,
        function()
            if not control.disabled then
                if selector then
                    change(1)
                else
                    open()
                end
            end
        end,
        nil,
        nil,
        control.description
            or (
                dropdown and 'Choose an option from the list.'
                or 'Choose an option. Use the arrows to step through the list.'
            )
    )
end

-- Whole-glyph viewport: never split UTF-8 or draw outside the allotted width.

function M.flow(value, width, size, time, measure)
    local glyphs = {}
    for glyph in tostring(value):gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        glyphs[#glyphs + 1] = glyph
    end

    local widths, total = {}, 0

    for i, g in ipairs(glyphs) do
        widths[i] = (measure and measure(g, size)) or size * 0.62
        total = total + widths[i]
    end

    if total <= width then
        return tostring(value), false
    end

    local last = #glyphs
    local tail = 0

    while last > 1 and tail + widths[last] <= width do
        tail = tail + widths[last]
        last = last - 1
    end

    last = math.min(#glyphs, last + 1)

    local travel = math.max(0, last - 1)
    local duration = travel * 0.25

    local phase = math.max(0, time or 0) % (duration * 2 + 3)

    local offset = phase < 1.5 and 0
        or phase < 1.5 + duration and math.floor((phase - 1.5) / 0.25)
        or phase < 3 + duration and travel
        or travel - math.floor((phase - 3 - duration) / 0.25)

    local first = math.max(1, math.min(last, offset + 1))
    local visible, used = {}, 0

    for i = first, #glyphs do
        if used + widths[i] > width then
            break
        end
        visible[#visible + 1] = glyphs[i]
        used = used + widths[i]
    end

    return table.concat(visible), true
end

-- Fit at most 32 whole glyphs; padding and arrows share the available budget.
function M.control_width(value, minimum, available, padding, size, measure)
    local width, count = 0, 0
    for glyph in tostring(value):gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        if count == 32 then
            break
        end
        count = count + 1
        width = width + ((measure and measure(glyph, size)) or size * 0.62)
    end
    return math.max(0, math.min(available, math.max(minimum, width + padding)))
end

-- Renderer-independent lightweight rich text: paragraphs, lists, headings and emphasis.

function M.rich(value, width, size, measure)
    local lines = {}
    value = tostring(value or ''):gsub('\r\n', '\n')

    for paragraph in (value .. '\n'):gmatch('(.-)\n') do
        local heading, body = paragraph:match('^(#+)%s+(.+)$')
        local font = heading and size + 3 or size

        body = body or paragraph
        body = body:gsub('^%s*[-*]%s+', '- ')

        local spans, line, used = {}, {}, 0
        local strong, emphasis = false, false

        local function flush()
            lines[#lines + 1] = { spans = line, size = font }
            line = {}
            used = 0
        end

        local function add(word, style)
            local glyphs = {}
            for glyph in word:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
                glyphs[#glyphs + 1] = glyph
            end

            for _, glyph in ipairs(glyphs) do
                local gw = (measure and measure(glyph, font)) or font * 0.62

                if used + gw > width and #line > 0 then
                    flush()
                end

                if not (glyph == ' ' and #line == 0) then
                    local last = line[#line]
                    if last and last.style == style then
                        last.text = last.text .. glyph
                        last.width = last.width + gw
                    else
                        line[#line + 1] = { text = glyph, style = style, width = gw }
                    end

                    used = used + gw
                end
            end
        end

        local index = 1

        while index <= #body do
            if body:sub(index, index + 1) == '**' then
                strong = not strong
                index = index + 2
            elseif body:sub(index, index) == '*' then
                emphasis = not emphasis
                index = index + 1
            else
                local stop = body:find('*', index, true) or (#body + 1)
                local chunk = body:sub(index, stop - 1)

                for word in chunk:gmatch('%S+%s*') do
                    local ww = 0
                    for glyph in word:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
                        ww = ww + ((measure and measure(glyph, font)) or font * 0.62)
                    end

                    if used + ww > width and #line > 0 then
                        flush()
                    end

                    add(word, heading and 'heading' or strong and 'strong' or emphasis and 'emphasis' or 'plain')
                end

                index = stop
            end
        end

        flush()
    end

    return lines
end

function M.new(api, measure, Text)
    local self = {
        visible = false,
        focus = 'mods',
        selected = 1,
        page = 1,
        row = 1,
        mod_scroll = 0,
        scroll = 0,
        notice = '',
        capture = false,
    }
    function self.open_dropdown(state)
        self.dropdown = state
        if type(self.on_dropdown_open) == 'function' then
            local id = tostring(state.control.id or 'choice'):gsub('[^%w_-]', '?'):sub(1, 80)
            pcall(self.on_dropdown_open, id, #state.control.choices)
        end
    end
    local console = api.diagnostics and api.diagnostics_surface and api.diagnostics_surface(api.diagnostics)
    function self.release_console()
        if console then
            console.release()
        end
    end

    local tree_expanded = {}
    local tree_scroll = 0
    local tree_manual = false
    local tree_max = 0

    local nav_bounds
    local nav_scroll = 0
    local nav_mod
    local expanded = {}

    local wheel_bounds
    local wheel_remainder = 0
    local manual_scroll = false

    local drag, window_drag, window_resize, color_drag, palette_drag, split_drag, preview_drag, scroll_drag, custom_drag
    local text_repeat
    local function cancel_custom_drag(reason)
        local item = custom_drag
        custom_drag = nil
        if item and item.cancel then
            local ok, why = pcall(item.cancel, reason)
            if not ok then
                self.notice = tostring(why)
            end
        end
    end
    local function numeric_allowed(control, value)
        if api.valid_number then
            return api.valid_number(control, value)
        end
        return type(value) == 'number' and value == value and value >= control.min and value <= control.max
    end
    local choice_bounds = {}

    self.sidebar_width = 330
    self.help_scroll = 0
    local help_bounds
    local help_key

    local hits = {}
    local current
    local held = {}

    function self.is_interacting()
        return self.text_edit ~= nil
            or self.color_picker ~= nil
            or (self.capture ~= false and self.capture ~= nil)
            or drag ~= nil
            or window_drag ~= nil
            or window_resize ~= nil
            or color_drag ~= nil
            or palette_drag ~= nil
            or split_drag ~= nil
            or preview_drag ~= nil
            or scroll_drag ~= nil
            or custom_drag ~= nil
            or self.mouse_held == true
    end

    function self.recover()
        text_repeat = nil
        cancel_custom_drag('recovery')
        self.release_console()

        self.visible = false
        self.capture = false
        self.text_edit = nil
        self.close_color(false)
        self.dropdown = nil
        self.mouse_held = false

        drag = nil
        window_drag = nil
        window_resize = nil
        color_drag = nil
        palette_drag = nil
        split_drag = nil
        preview_drag = nil
        self.preview_window = nil
        self.floating_windows, self.floating_bounds = {}, nil

        self.pointer_x, self.pointer_y = nil, nil
        scroll_drag = nil
        self.notice = 'Menu closed after an error; use the menu shortcut to reopen it'
    end

    local function active()
        local mods = api.list()
        self.selected = math.max(1, math.min(self.selected, #mods))
        current = mods[self.selected]

        if current then
            self.page = math.max(1, math.min(self.page, #current.pages))
            return current, current.pages[self.page]
        end
    end

    local section_state = {}
    local function state_key(page, id)
        return tostring(current and current.id) .. '/' .. page.id .. '/' .. id
    end
    local function section_open(page, c)
        local value = section_state[state_key(page, c.id)]
        if value == nil then
            return not c.collapsed
        end
        return value
    end
    local function visible_controls(page)
        local rows, groups = {}, {}
        for _, c in ipairs(page and page.controls or {}) do
            local visible = true
            for _, parent in ipairs(c.groups or {}) do
                if groups[parent] == false then
                    visible = false
                    break
                end
            end
            if c.collapsible then
                groups[c.id] = section_open(page, c)
            end
            if visible then
                rows[#rows + 1] = c
            end
        end
        return rows
    end
    local function selectable(page)
        local rows = {}
        for _, c in ipairs(visible_controls(page)) do
            if c.tab_stop ~= false and (c.collapsible or (c.type ~= 'text' and c.type ~= 'section')) then
                rows[#rows + 1] = c
            end
        end
        return rows
    end

    local function select_control(c)
        self.shortcut_context = self.shortcut_context or {}
        if c.type ~= 'button' then
            self.shortcut_context.control = c.id
            api.focused_control = c.id
        end
        if c.page.render_layout and c.page.id ~= 'save' then
            return
        end
        for index, control in ipairs(selectable(c.page)) do
            if control == c then
                self.row, self.focus = index, 'settings'
                return
            end
        end
    end

    local function open_picker(owner, control, mode)
        local allowed, why = M.picker_allowed(control, mode)
        if not allowed then
            self.notice = why
            return false
        end
        local got, color = pcall(function()
            return api.color_rgb((owner.handle.preview or owner.handle.get)(control.id))
        end)
        if not got then
            self.notice = 'Color unavailable: ' .. tostring(color)
            return false
        end
        local picker = { mod = owner, control = control, rgb = color, picker_mode = mode }
        if control.picker_preview and control.picker_begin then
            local called, result, reason = pcall(control.picker_begin, mode)
            if not called or result == false then
                self.notice = tostring(called and reason or result)
                return false
            end
            picker.preview_started = true
        end
        self.color_picker = picker
        return true
    end
    local function change(c, direction, picker_mode)
        if not current or c.disabled or c.read_only then
            return
        end
        select_control(c)

        if c.collapsible then
            local key = state_key(c.page, c.id)
            local open = section_open(c.page, c)
            section_state[key] = direction == 0 and not open or direction > 0
            manual_scroll = false
            return
        end
        local h = current.handle
        local ok, err = true

        if c.type == 'button' then
            if direction == 0 then
                ok, err = (h.queue or h.activate)(c.id)
            end
        elseif c.type == 'input' then
            self.text_edit = { mod = current, control = c, text = (h.preview or h.get)(c.id), replace = true }
            self.notice = 'Type name; Enter accepts'
            return
        elseif c.type == 'keybind' then
            self.capture = c
            self.notice = 'Press a key. Escape cancels.'
            return
        elseif c.type == 'choice' and direction == 0 and c.presentation ~= 'selector' then
            local anchor = choice_bounds[c]
                or { x = self.sidebar_width + 50, top = (self.window_height or 820) - 205, width = 280 }
            if anchor.enabled == false then
                return
            end
            if anchor.prepare then
                anchor.prepare()
            end
            local value = (h.preview or h.get)(c.id)
            self.open_dropdown({
                mod = current,
                control = c,
                selected = value,
                scroll = math.max(0, math.min(math.max(0, #c.choices - 8), value - 4)),
                x = anchor.x,
                top = anchor.top,
                width = anchor.width,
                owner = anchor.owner,
                widget = anchor.widget,
            })
            return
        elseif c.type == 'color' then
            picker_mode = picker_mode or c.picker_mode or (self.basic_only and 1)
            open_picker(current, c, picker_mode)
            return
        else
            local v = (h.preview or h.get)(c.id)

            if c.type == 'toggle' then
                v = not v
            elseif c.type == 'choice' then
                v = (v - 1 + (direction == 0 and 1 or direction)) % #c.choices + 1
            elseif c.type == 'slider' then
                v = math.max(c.min, math.min(c.max, v + (direction == 0 and 1 or direction) * c.step))
            else
                return
            end

            ok, err = (h.edit or h.set)(c.id, v)
        end

        self.notice = ok
                and (c.type == 'button' and (c.require_confirmation and 'Action ready to apply' or (type(err) == 'string' and err or 'Action completed')) or saved_notice(
                    c,
                    h
                ))
            or ('Could not save: ' .. tostring(err))
    end

    function self.finish_color_field()
        local e = self.text_edit
        if e and e.color_channel and self.color_picker then
            local channel = e.color_channel == 'alpha' and 4 or e.color_channel
            if channel ~= 'hex' and not picker_channel_allowed(self.color_picker.control, channel) then
                self.text_edit = nil
                self.notice = 'This channel is not editable.'
                return false
            end
        end
        if not e or not e.color_channel then
            return true
        end

        if not self.color_picker then
            self.text_edit = nil
            return true
        end

        if e.color_channel == 'alpha' then
            local n = tonumber(e.text)
            if not n or n ~= n or math.abs(n) > 1e10 then
                self.notice = 'Alpha: enter a finite numeric value'
                return false
            end
            self.color_picker.alpha = n
        elseif e.color_channel == 'hex' then
            local ok, rgb = pcall(api.color_rgb, e.text)

            if not ok then
                self.notice = 'Use six HEX digits'
                return false
            end

            self.color_picker.rgb = rgb
        else
            local n = tonumber(e.text)

            if not n or n % 1 ~= 0 or n < 0 or n > 255 then
                self.notice = 'RGB channels: integers 0-255'
                return false
            end

            self.color_picker.rgb[e.color_channel] = n
        end

        self.color_picker.hue, self.color_picker.saturation, self.color_picker.brightness =
            api.rgb_hsv(self.color_picker.rgb)

        self.text_edit = nil
        self.notice = 'Color preview updated'
        return true
    end

    function self.close_color(commit)
        local p = self.color_picker
        if p and p.preview_started and p.control.picker_end then
            local ok, why = pcall(p.control.picker_end, commit)
            if not ok then
                self.notice = tostring(why)
            end
        end
        self.color_picker = nil
        self.text_edit = nil
        color_drag, palette_drag = nil, nil
    end
    function self.commit_color()
        if not self.finish_color_field() then
            return
        end

        local p = self.color_picker
        if not p then
            return
        end
        local allowed, why = M.picker_allowed(p.control, p.picker_mode)
        if not allowed then
            self.notice = why
            self.close_color(false)
            return
        end

        local called, ok, err
        if p.control.picker_commit then
            called, ok, err = pcall(function()
                local alpha = p.alpha or (p.control.picker_alpha and p.control.picker_alpha()) or 1
                return p.control.picker_commit(p.rgb, alpha)
            end)
        else
            called, ok, err = pcall(p.mod.handle.edit or p.mod.handle.set, p.control.id, p.rgb)
        end

        if called and ok then
            self.notice = saved_notice(p.control, p.mod.handle)
            self.close_color(true)
        else
            self.notice = tostring(called and err or ok)
            p.error = self.notice
        end
    end

    function self.key(code, ctrl, shift)
        if self.visible and self.capture then
            local mod = active()
            local c = self.capture
            self.capture = false
            if code ~= 27 and mod then
                local ok, err = (mod.handle.edit or mod.handle.set)(c.id, code)
                self.notice = ok and saved_notice(c, mod.handle) or tostring(err)
            end
            return
        end
        if self.visible and self.lut_apply_dialog then
            if code == 27 or code == (self.toggle_key or 121) then
                self.lut_apply_dialog = nil
                scroll_drag = nil
                if code == 27 then
                    return
                end
            else
                if code == 13 and self.lut_apply_dialog.apply then
                    self.lut_apply_dialog.apply()
                end
                return
            end
        end
        if
            code == 13
            and self.outfit_dialog
            and self.outfit_dialog.phase == 'name'
            and self.outfit_dialog.on_save
            and self.text_edit
        then
            local dialog = self.outfit_dialog
            local ok, why = pcall(dialog.on_save, self.text_edit.text, dialog.save_kind)
            self.notice = ok and tostring(why or 'Preset saved') or tostring(why)
            if ok and why ~= false then
                self.outfit_dialog = nil
                self.text_edit = nil
            end
            return
        end

        local toggle = code == (self.toggle_key or 121) and not self.text_edit and not self.color_picker
        if toggle then
            text_repeat = nil
            cancel_custom_drag('menu closed')
            drag = nil
            window_drag = nil
            window_resize = nil
            self.dropdown = nil
            scroll_drag = nil
            self.text_edit = nil
            self.close_color(false)
        end

        if toggle then
            self.visible = not self.visible
            self.capture = false
            return
        end -- F10

        if not self.visible then
            return
        end

        if self.text_edit then
            local e = self.text_edit
            if
                code == 9
                and not ctrl
                and not (shift == nil and self.shift or shift)
                and self.outfit_dialog
                and self.outfit_dialog.phase == 'name'
                and e.control == self.outfit_dialog.control
                and type(self.outfit_dialog.names) == 'table'
            then
                local name = preset_completion(self.outfit_dialog, e.text)
                if name then
                    if Text then
                        Text.all(e)
                        Text.insert(e, name, 48)
                    else
                        e.text, e.cursor, e.anchor, e.replace = name, #name, #name, false
                    end
                end
                text_repeat = nil
                return
            end
            if Text then
                Text.ensure(e)
                if code == 27 then
                    self.text_edit = nil
                    text_repeat = nil
                    cancel_custom_drag('text cancelled')
                    return
                end
                if ctrl and code == 65 then
                    Text.all(e)
                    return
                end
                if ctrl and (code == 67 or code == 88) then
                    local value = Text.selected(e)
                    if value == '' then
                        return
                    end
                    if not self.clipboard then
                        self.notice = 'Clipboard unavailable.'
                        return
                    end
                    local called, ok, why = pcall(self.clipboard.set, value)
                    self.notice = called and ok and 'Copied text' or tostring(called and why or ok)
                    if code == 88 and called and ok then
                        Text.delete(e, true)
                    end
                    return
                end
                if ctrl and code == 86 then
                    if not self.clipboard then
                        self.notice = 'Clipboard unavailable.'
                        return
                    end
                    local called, value, why = pcall(self.clipboard.get)
                    if not called or type(value) ~= 'string' then
                        self.notice = tostring(called and why or value)
                        return
                    end
                    Text.insert(e, value:gsub('[\r\n\t]+', ' '), e.control and e.control.type == 'input' and 48 or 24)
                    if e.color_channel then
                        self.finish_color_field()
                        self.text_edit = e
                    elseif e.control and e.control.type ~= 'input' then
                        local number = tonumber(e.text)
                        if
                            numeric_allowed(e.control, number)
                            and not e.control.disabled
                            and not e.control.read_only
                        then
                            local saved, ok, reason = pcall(e.mod.handle.edit or e.mod.handle.set, e.control.id, number)
                            self.notice = saved and ok and 'Value pasted' or tostring(saved and reason or ok)
                        else
                            self.notice = 'Paste a valid number'
                        end
                    end
                    return
                end
                if ctrl and (code == 90 or code == 89) then
                    Text.history(e, code == 89 or not not (shift == nil and self.shift or shift))
                    return
                end
                if Text.move(e, code, shift == nil and self.shift or shift, ctrl) then
                    if not ctrl and not self.repeating_text then
                        text_repeat = {
                            editor = e,
                            code = code,
                            age = 0,
                            next = 0.4,
                            picker = self.color_picker,
                            dialog = self.outfit_dialog,
                            dropdown = self.dropdown,
                        }
                    end
                    return
                end
                if code == 8 or code == 46 then
                    Text.delete(e, code == 8)
                    if not ctrl and not self.repeating_text then
                        text_repeat = {
                            editor = e,
                            code = code,
                            age = 0,
                            next = 0.4,
                            picker = self.color_picker,
                            dialog = self.outfit_dialog,
                            dropdown = self.dropdown,
                        }
                    end
                    return
                end
                local char
                if code >= 48 and code <= 57 then
                    char = string.char(code)
                elseif code >= 96 and code <= 105 then
                    char = tostring(code - 96)
                elseif code == 189 or code == 109 then
                    char = '-'
                elseif code == 190 or code == 110 then
                    char = '.'
                elseif e.control and e.control.type == 'input' then
                    if code >= 65 and code <= 90 then
                        char = string.char(code)
                    elseif code == 32 then
                        char = ' '
                    end
                elseif e.color_channel == 'hex' and code >= 65 and code <= 70 then
                    char = string.char(code)
                elseif e.control and (e.control.raw_numeric or e.control.allow_out_of_range) then
                    if code == 69 then
                        char = 'e'
                    elseif code == 187 or code == 107 then
                        char = '+'
                    end
                end
                if char and not ctrl then
                    Text.insert(e, char, e.control and e.control.type == 'input' and 48 or 24)
                    if not self.repeating_text then
                        text_repeat = {
                            editor = e,
                            code = code,
                            age = 0,
                            next = 0.4,
                            picker = self.color_picker,
                            dialog = self.outfit_dialog,
                            dropdown = self.dropdown,
                        }
                    end
                    return
                end
                -- Commit/Tab keep the existing validation paths below; all
                -- other keys belong to this editor rather than menu navigation.
                if code ~= 13 and code ~= 9 then
                    return
                end
            end

            if code == 27 then
                self.text_edit = nil
                return
            end

            if code == 9 and e.color_channel then
                self.finish_color_field()
                return
            end

            if code == 13 then
                if e.color_channel then
                    self.finish_color_field()
                    return
                end

                local value = e.control.type == 'input' and e.text or tonumber(e.text)

                if e.control.type ~= 'input' and not numeric_allowed(e.control, value) then
                    self.notice = 'Enter a number from ' .. e.control.min .. ' to ' .. e.control.max
                    return
                end

                local called, ok, err = pcall(e.mod.handle.edit or e.mod.handle.set, e.control.id, value)

                if not called or not ok then
                    self.notice = tostring(called and err or ok)
                    return
                end

                self.notice = saved_notice(e.control, e.mod.handle)
                self.text_edit = nil
                return
            end

            if ctrl and code == 65 then
                e.replace = true
                return
            end
            if ctrl and (code == 67 or code == 86) then
                local clipboard = self.clipboard
                if not clipboard then
                    self.notice = 'Clipboard unavailable.'
                    return
                end
                if code == 67 then
                    local called, ok, why = pcall(clipboard.set, e.text)
                    self.notice = called and ok and 'Copied text' or tostring(called and why or ok)
                    return
                end
                local called, value, why = pcall(clipboard.get)
                if not called or type(value) ~= 'string' then
                    self.notice = tostring(called and why or value)
                    return
                end
                value = value:gsub('[\r\n\t]+', ' ')
                local limit = e.control and e.control.type == 'input' and 48 or 24
                local candidate = (e.replace and '' or e.text) .. value
                local out, bytes = {}, 0
                for glyph in candidate:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
                    if bytes + #glyph > limit then
                        break
                    end
                    out[#out + 1] = glyph
                    bytes = bytes + #glyph
                end
                e.text, e.replace = table.concat(out), false
                if e.color_channel then
                    self.finish_color_field()
                    self.text_edit = e
                elseif e.control and e.control.type ~= 'input' then
                    local number = tonumber(e.text)
                    if numeric_allowed(e.control, number) and not e.control.disabled and not e.control.read_only then
                        local saved, ok, reason = pcall(e.mod.handle.edit or e.mod.handle.set, e.control.id, number)
                        self.notice = saved and ok and 'Value pasted' or tostring(saved and reason or ok)
                    else
                        self.notice = 'Paste a valid number from ' .. e.control.min .. ' to ' .. e.control.max
                    end
                end
                return
            end

            if code == 8 then
                if e.replace then
                    e.text = ''
                else
                    e.text = e.text:sub(1, -2)
                end
                e.replace = false
                return
            end

            if code == 46 then
                e.text = ''
                e.replace = false
                return
            end

            local char

            if code >= 48 and code <= 57 then
                char = string.char(code)
            elseif code >= 96 and code <= 105 then
                char = tostring(code - 96)
            elseif code == 189 or code == 109 then
                char = '-'
            elseif code == 190 or code == 110 then
                char = '.'
            end

            if e.control and e.control.type == 'input' then
                if code >= 65 and code <= 90 then
                    char = string.char(code)
                elseif code == 32 then
                    char = ' '
                end
            end

            if e.color_channel == 'hex' and code >= 65 and code <= 70 then
                char = string.char(code)
            end

            if char and not ctrl then
                if e.replace then
                    e.text = ''
                    e.replace = false
                end

                if #e.text < (e.control and e.control.type == 'input' and 48 or 24) then
                    e.text = e.text .. char
                end
            end

            return
        end

        if self.color_picker then
            if code == 27 then
                self.close_color(false)
                return
            end

            if code == 13 then
                self.commit_color()
            end
            return
        end

        if self.dropdown then
            local d = self.dropdown

            if code == 27 then
                self.dropdown = nil
                scroll_drag = nil
                return
            end

            if code == 38 or code == 40 or code == 33 or code == 34 then
                local step = code == 33 and -8 or (code == 34 and 8 or (code == 38 and -1 or 1))

                d.selected = math.max(1, math.min(#d.control.choices, d.selected + step))

                if d.selected <= d.scroll then
                    d.scroll = d.selected - 1
                end

                if d.selected > d.scroll + 8 then
                    d.scroll = d.selected - 8
                end

                return
            end

            if code == 13 then
                local ok, err = (d.mod.handle.edit or d.mod.handle.set)(d.control.id, d.selected)

                self.notice = ok and saved_notice(d.control, d.mod.handle) or tostring(err)

                self.dropdown = nil
                scroll_drag = nil
                if ok and d.control.input_control and d.selected == 1 then
                    change(d.control.input_control, 0)
                end
                return
            end

            return
        end

        manual_scroll = false
        tree_manual = false

        local mod, page = active()
        if not mod then
            if code == 27 then
                self.visible = false
            end
            return
        end

        if self.capture then
            local c = self.capture
            self.capture = false

            if code ~= 27 then
                local ok, err = (mod.handle.edit or mod.handle.set)(c.id, code)
                self.notice = ok and saved_notice(c, mod.handle) or tostring(err)
            end

            return
        end
        if self.outfit_dialog then
            return
        end
        if code == 27 and custom_drag then
            cancel_custom_drag('Escape')
            return
        end
        if page.on_key then
            local context = self.shortcut_context or {}
            context.clipboard = self.clipboard
            local called, handled, notice =
                pcall(page.on_key, code, not not ctrl, not not (shift == nil and self.shift or shift), context)
            if not called then
                self.notice = 'Shortcut failed: ' .. tostring(handled)
                return
            end
            if handled then
                if notice then
                    self.notice = tostring(notice)
                end
                return
            end
        end

        if code == 27 then
            if self.preview_window then
                self.preview_window = nil
                preview_drag = nil
                return
            end
            self.visible = false
            scroll_drag = nil
            return
        end

        if code == 9 then
            self.focus = self.tabbed and 'settings' or (self.focus == 'mods' and 'settings' or 'mods')
            return
        end

        if code == 33 or code == 34 then
            for _ = 1, #mod.pages do
                self.page = (self.page - 1 + (code == 33 and -1 or 1)) % #mod.pages + 1
                if
                    mod.pages[self.page].id == 'weapons'
                    or (mod.pages[self.page].id == 'basic') == not not self.basic_only
                then
                    break
                end
            end
            self.row = 1
            self.scroll = 0
            return
        end

        if self.focus == 'mods' then
            if code == 38 or code == 40 then
                self.selected = math.max(1, math.min(#api.list(), self.selected + (code == 38 and -1 or 1)))
                self.page = 1
                self.row = 1
                self.scroll = 0
            elseif code == 13 or code == 39 then
                self.focus = 'settings'
            end
        else
            local rows = selectable(page)
            self.row = math.max(1, math.min(self.row, #rows))
            local c = rows[self.row]

            if code == 38 or code == 40 then
                self.row = math.max(1, math.min(#rows, self.row + (code == 38 and -1 or 1)))
            elseif c and (code == 37 or code == 39 or code == 13) then
                change(c, code == 13 and 0 or (code == 37 and -1 or 1))
            end
        end
    end

    function self.sidebar()
        local rows = {}

        for index, mod in ipairs(api.list()) do
            local open = tree_expanded[mod.id] == true

            rows[#rows + 1] = { kind = 'mod', mod = mod, index = index, open = open, depth = 0 }

            if open then
                local nodes = self.navigation(mod)

                for _, node in ipairs(nodes) do
                    if
                        not (
                            #(mod.categories or {}) == 1
                            and mod.categories[1].name == 'HUD'
                            and node.kind == 'category'
                            and node.depth == 0
                        )
                    then
                        local item = {}
                        for k, v in pairs(node) do
                            item[k] = v
                        end

                        item.mod = mod
                        item.mod_index = index
                        item.depth = node.depth + 1

                        if #(mod.categories or {}) == 1 and mod.categories[1].name == 'HUD' then
                            item.depth = math.max(1, item.depth - 1)
                        end

                        rows[#rows + 1] = item
                    end
                end
            end
        end

        return rows
    end

    function self.navigation(mod)
        local rows = {}

        local function children(parent, depth)
            for _, category in ipairs(mod.categories or {}) do
                if category.parent == parent then
                    local key = mod.id .. '/' .. category.id
                    local open = expanded[key]
                    if open == nil then
                        open = not category.collapsed
                    end

                    local leaf, leaf_index, count = nil, nil, 0
                    if category.style == 'page' then
                        for index, page in ipairs(mod.pages) do
                            if page.category == category.id then
                                leaf = page
                                leaf_index = index
                                count = count + 1
                            end
                        end
                        for _, child in ipairs(mod.categories or {}) do
                            if child.parent == category.id then
                                count = count + 2
                            end
                        end
                    end
                    if count == 1 then
                        rows[#rows + 1] = { kind = 'page', page = leaf, index = leaf_index, depth = depth }
                    else
                        rows[#rows + 1] =
                            { kind = 'category', category = category, key = key, open = open, depth = depth }

                        if open then
                            children(category.id, depth + 1)
                        end
                    end
                end
            end

            for index, page in ipairs(mod.pages) do
                if page.category == parent then
                    rows[#rows + 1] = { kind = 'page', page = page, index = index, depth = depth }
                end
            end
        end

        children(nil, 0)
        return rows
    end

    function self.wheel(delta, x, y)
        if not self.visible or not x or not y or not delta then
            return
        end
        if self.lut_apply_dialog then
            local b = self.window_bounds
            if b then
                local px, py = (x - b.x) / b.scale, (y - b.y) / b.scale
                for _, column in ipairs(self.lut_apply_dialog.columns or {}) do
                    local bounds = column.scroll_bounds
                    if
                        bounds
                        and px >= bounds.x
                        and px <= bounds.x + bounds.w
                        and py >= bounds.y
                        and py <= bounds.y + bounds.h
                    then
                        column.scroll = math.max(
                            0,
                            math.min(
                                column.maximum or 0,
                                (column.scroll or 0) - delta / 120 * (column.row_height or 32)
                            )
                        )
                        break
                    end
                end
            end
            return
        end
        if
            not self.visible
            or self.capture
            or drag
            or window_drag
            or window_resize
            or not wheel_bounds
            or not x
            or not y
        then
            return
        end

        if self.dropdown then
            local d = self.dropdown
            d.scroll = math.max(0, math.min(math.max(0, #d.control.choices - 8), d.scroll - delta / 120 * 3))
            d.scroll = math.floor(d.scroll)
            return
        end

        local current_mod, current_page = active()
        -- A modal or floating popup owns the pointer; do not scroll the editor underneath.
        if self.color_picker or self.outfit_dialog or self.preview_window then
            return
        end
        if self.floating_at(x, y) then
            return
        end
        if current_page and current_page.on_wheel and self.window_bounds then
            local b = self.window_bounds
            if current_page.on_wheel((x - b.x) / b.scale, (y - b.y) / b.scale, delta) then
                return
            end
        end
        if
            help_bounds
            and x >= help_bounds.x
            and x <= help_bounds.x + help_bounds.w
            and y >= help_bounds.y
            and y <= help_bounds.y + help_bounds.h
        then
            self.help_scroll =
                math.max(0, math.min(help_bounds.maximum, self.help_scroll - math.floor(delta / 120) * 3))
            return
        end

        if
            nav_bounds
            and x >= nav_bounds.x
            and x <= nav_bounds.x + nav_bounds.w
            and y >= nav_bounds.y
            and y <= nav_bounds.y + nav_bounds.h
        then
            nav_scroll = math.max(0, math.min(nav_bounds.maximum, nav_scroll - math.floor(delta / 120) * 3))
            return
        end

        local b = wheel_bounds
        if x < b.x or x > b.x + b.w or y < b.y or y > b.y + b.h then
            return
        end

        wheel_remainder = wheel_remainder + delta

        local steps = wheel_remainder >= 0 and math.floor(wheel_remainder / 120) or math.ceil(wheel_remainder / 120)

        wheel_remainder = wheel_remainder - steps * 120
        if steps == 0 then
            return
        end

        local mod, page = active()
        if not mod then
            return
        end

        if x < b.split then
            tree_scroll = math.max(0, math.min(tree_max, tree_scroll - steps * 3))
            tree_manual = true
        else
            self.scroll = math.max(
                0,
                math.min(
                    math.max(0, (self.display_total or #page.controls) - (self.settings_visible or 12)),
                    self.scroll - steps * 3
                )
            )
            manual_scroll = true
        end
    end

    function self.input_focus(focused, input)
        if not focused then
            text_repeat = nil
            cancel_custom_drag('focus lost')
            if console then
                console.release()
            end
            drag = nil
            window_drag = nil
            window_resize = nil
            scroll_drag, color_drag, palette_drag, split_drag, preview_drag = nil, nil, nil, nil, nil
            self.pointer_x, self.pointer_y = nil, nil
            self.floating_windows, self.floating_bounds = {}, nil
            self.capture = false
            self.mouse_held = false
            self.suspended = true
            return false
        end
        if self.suspended then
            for code = 1, 255 do
                held[code] = input.down(code)
            end
            self.mouse_held = input.down(1)
            self.right_mouse_held = input.down(2)
            self.suspended = false
            return false -- Do not replay keys/clicks held in another application.
        end
        return true
    end
    function self.tick(input, dt)
        self.shift = input.down(16)
        if console then
            input = console.filter(input, self.visible)
        end

        if not self.visible then
            local key = self.toggle_key or 121
            local down = input.down(key)
            if down and not held[key] then
                self.key(key)
            end
            held[key] = down

            return
        end

        if
            not self.color_picker
            and not drag
            and not window_drag
            and not window_resize
            and not scroll_drag
            and not custom_drag
            and not self.text_edit
            and input.wheel
            and input.mouse
        then
            local delta = input.wheel()
            local x, y = input.mouse()
            self.wheel(delta, x, y)
        end

        for code = 1, 255 do
            local down = input.down(code)
            if down and not held[code] and code ~= 1 then
                self.key(code, input.down(17), input.down(16))
            end
            held[code] = down
        end
        if Text then
            if
                input.down(17)
                or (
                    text_repeat
                    and (
                        text_repeat.picker ~= self.color_picker
                        or text_repeat.dialog ~= self.outfit_dialog
                        or text_repeat.dropdown ~= self.dropdown
                    )
                )
            then
                text_repeat = nil
            end
            self.repeating_text = true
            text_repeat = Text.repeat_key(text_repeat, self.text_edit, input.down, dt, function(code)
                self.key(code, false, input.down(16))
            end)
            self.repeating_text = false
        end

        if self.visible and input.mouse then
            local x, y = input.mouse()
            self.pointer_x, self.pointer_y = x, y
            if x and y and input.down(1) and not self.mouse_held then
                local field = Text and self.text_edit and self.text_edit.field_bounds
                if field and x >= field.x and x <= field.x + field.w and y >= field.y and y <= field.y + field.h then
                    local e = self.text_edit
                    local function move(px, py)
                        if self.text_edit ~= e then
                            cancel_custom_drag('field changed')
                            return
                        end
                        local view = e.field_bounds
                        if not view then
                            cancel_custom_drag('field hidden')
                            return
                        end
                        local offset = (px * self.window_bounds.scale + self.window_bounds.x - view.text_x) / view.scale
                            + (e.scroll or 0)
                        e.cursor = Text.at(e, offset, view.measure)
                    end
                    local px = (x - self.window_bounds.x) / self.window_bounds.scale
                    move(px, (y - self.window_bounds.y) / self.window_bounds.scale)
                    if not self.shift then
                        e.anchor = e.cursor
                    end
                    custom_drag = {
                        move = move,
                        text_edit = e,
                        owner = field.owner,
                        finish = function() end,
                        mod = field.mod,
                        page = field.page,
                    }
                    text_repeat = nil
                    self.mouse_held = true
                else
                    local naming_outfit = self.outfit_dialog
                        and self.outfit_dialog.phase == 'name'
                        and self.text_edit
                        and self.text_edit.control == self.outfit_dialog.control
                    local valid = naming_outfit or self.finish_color_field()

                    if self.text_edit and self.text_edit.control and not naming_outfit then
                        -- Numeric fields use the same validation and owner
                        -- callback as Enter, before the clicked control can
                        -- change the row/column. Failed drafts keep focus.
                        self.key(13)

                        valid = self.text_edit == nil
                    end

                    if valid and not naming_outfit then
                        self.text_edit = nil
                    end

                    for i = #hits, 1, -1 do
                        local h = hits[i]
                        if x >= h.x and x <= h.x + h.w and y >= h.y and y <= h.y + h.h then
                            if valid then
                                local now = os.clock()
                                local key = h.x .. ':' .. h.y .. ':' .. h.w .. ':' .. h.h
                                local twice = h.double_click
                                    and self.last_click_key == key
                                    and now - (self.last_click_time or -1) <= 0.35
                                self.shortcut_context = { floating = h.floating_owner }
                                api.shortcut_context = self.shortcut_context
                                h.click(x, y)
                                if twice then
                                    self.last_click_key = nil
                                    h.double_click(x, y)
                                else
                                    self.last_click_key = key
                                    self.last_click_time = now
                                end
                                self.redraw_revision = (self.redraw_revision or 0) + 1
                            end
                            break
                        end
                    end
                end
            end

            if
                x
                and y
                and input.down(2)
                and not self.right_mouse_held
                and not self.color_picker
                and not self.dropdown
                and not self.preview_window
            then
                for i = #hits, 1, -1 do
                    local target = hits[i]
                    if x >= target.x and x <= target.x + target.w and y >= target.y and y <= target.y + target.h then
                        if target.right_click then
                            target.right_click(x, y)
                            self.redraw_revision = (self.redraw_revision or 0) + 1
                        end
                        break
                    end
                end
            end
            self.right_mouse_held = input.down(2)
            if
                x
                and y
                and input.down(4)
                and not self.middle_mouse_held
                and not self.color_picker
                and not self.dropdown
                and not self.preview_window
            then
                for i = #hits, 1, -1 do
                    local target = hits[i]
                    if x >= target.x and x <= target.x + target.w and y >= target.y and y <= target.y + target.h then
                        if target.middle_click then
                            target.middle_click(x, y)
                            self.redraw_revision = (self.redraw_revision or 0) + 1
                        end
                        break
                    end
                end
            end
            self.middle_mouse_held = input.down(4)

            if scroll_drag then
                if not self.visible or not input.down(1) then
                    scroll_drag = nil
                elseif y then
                    scroll_drag.move(y)
                end
            end
            if custom_drag then
                local item = custom_drag
                local bounds = self.window_bounds
                local px, py = x and (x - bounds.x) / bounds.scale, y and (y - bounds.y) / bounds.scale
                if not self.visible then
                    cancel_custom_drag('menu closed')
                elseif x and y and input.down(1) then
                    local ok, why = pcall(item.move, px, py)
                    if not ok then
                        cancel_custom_drag(tostring(why))
                        self.notice = tostring(why)
                    end
                elseif not input.down(1) then
                    custom_drag = nil
                    if item.finish then
                        local ok, why = pcall(item.finish, px, py)
                        if not ok then
                            self.notice = tostring(why)
                        end
                    end
                end
            end

            if palette_drag then
                if not self.color_picker or not input.down(1) then
                    palette_drag = nil
                elseif x and y then
                    palette_drag(x, y)
                end
            end

            if color_drag then
                if not self.color_picker or not input.down(1) then
                    color_drag = nil
                elseif x and y then
                    self.color_picker.x = math.max(
                        0,
                        math.min(
                            math.max(0, (self.window_width or 1500) - 704),
                            (x - color_drag.ox) / color_drag.scale - color_drag.dx
                        )
                    )

                    self.color_picker.y = math.max(
                        0,
                        math.min(
                            math.max(0, (self.window_height or 820) - 434),
                            (y - color_drag.oy) / color_drag.scale - color_drag.dy
                        )
                    )
                end
            end

            if split_drag then
                if not self.visible or not input.down(1) then
                    split_drag = nil
                elseif x then
                    self.sidebar_width = math.max(
                        250,
                        math.min(
                            math.min(650, (self.window_width or 1500) - 700),
                            (x - split_drag.ox) / split_drag.scale
                        )
                    )
                end
            end

            if preview_drag then
                local dragged = preview_drag.window or self.preview_window
                if not self.visible or not dragged or not input.down(1) then
                    preview_drag = nil
                elseif x and y then
                    dragged.x = math.max(0, math.min(preview_drag.max_x, x - preview_drag.dx))
                    dragged.y = math.max(0, math.min(preview_drag.max_y, y - preview_drag.dy))
                end
            end
            if window_resize then
                if not self.visible or not input.down(1) then
                    window_resize = nil
                elseif x and y then
                    local r = window_resize
                    local left, right, bottom, top = r.left, r.right, r.bottom, r.top
                    if r.edge:find('w', 1, true) then
                        left = math.max(0, math.min(right - r.min_w, x))
                    end
                    if r.edge:find('e', 1, true) then
                        right = math.min(r.screen_w, math.max(left + r.min_w, x))
                    end
                    if r.edge:find('s', 1, true) then
                        bottom = math.max(0, math.min(top - r.min_h, y))
                    end
                    if r.edge:find('n', 1, true) then
                        top = math.min(r.screen_h, math.max(bottom + r.min_h, y))
                    end
                    self.window_x, self.window_y = left, bottom
                    self.window_width, self.window_height = (right - left) / r.scale, (top - bottom) / r.scale
                    self.dropdown = nil
                    scroll_drag = nil
                end
            end
            if window_drag then
                if not self.visible or not input.down(1) then
                    window_drag = nil
                elseif x and y then
                    self.window_x = math.max(0, math.min(window_drag.max_x, x - window_drag.dx))

                    self.window_y = math.max(0, math.min(window_drag.max_y, y - window_drag.dy))
                end
            end

            if drag then
                if not self.visible then
                    drag = nil
                elseif input.down(1) then
                    if x then
                        drag.move(x, y)
                        if
                            drag.live
                            and drag.value ~= drag.last_value
                            and (not drag.last_commit or os.clock() - drag.last_commit >= 0.04)
                        then
                            local ok, err = (drag.mod.handle.edit or drag.mod.handle.set)(drag.control.id, drag.value)
                            drag.last_value, drag.last_commit = drag.value, os.clock()
                            if not ok then
                                self.notice = 'Could not apply: ' .. tostring(err)
                            end
                        end
                    end
                else
                    local current = drag.mod.handle.get(drag.control.id)
                    local ok, err = true, nil
                    if not drag.live or math.abs(current - drag.value) > 1e-9 then
                        ok, err = (drag.mod.handle.edit or drag.mod.handle.set)(drag.control.id, drag.value)
                    end

                    self.notice = ok and saved_notice(drag.control, drag.mod.handle)
                        or ('Could not save: ' .. tostring(err))
                    drag = nil
                end
            end

            self.mouse_held = input.down(1)
        else
            self.mouse_held = input.down(1)
            self.right_mouse_held = input.down(2)
        end
    end

    local text_age = {}
    local elapsed = 0

    function self.advance(dt)
        if self.visible then
            elapsed = elapsed + math.max(0, math.min(1, tonumber(dt) or 0))
        else
            elapsed = 0
            text_age = {}
        end
    end

    function self.owns_pointer(x, y)
        if
            drag
            or window_drag
            or window_resize
            or preview_drag
            or color_drag
            or palette_drag
            or split_drag
            or scroll_drag
            or custom_drag
        then
            return true
        end
        if self.color_picker or self.outfit_dialog or self.lut_apply_dialog or self.dropdown then
            return true
        end
        return self.floating_at(x, y) ~= nil
    end
    function self.floating_at(x, y)
        if not x or not y then
            return nil
        end
        for i = #(self.floating_windows or {}), 1, -1 do
            local b = self.floating_windows[i]
            if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
                return b
            end
        end
    end
    function self.compose(w, h)
        if type(w) ~= 'number' or type(h) ~= 'number' or not (w > 0 and h > 0 and w < math.huge and h < math.huge) then
            return {}
        end
        if not self.visible then
            text_repeat = nil
            cancel_custom_drag('menu closed')
            self.release_console()
            hits = {}
            drag = nil
            window_drag = nil
            window_resize = nil
            self.dropdown = nil
            scroll_drag = nil
            self.text_edit = nil
            self.close_color(false)
            self.pointer_x, self.pointer_y = nil, nil
            preview_drag = nil
            self.floating_windows, self.floating_bounds = {}, nil
            return {}
        end

        local commands = {}
        hits = {}
        choice_bounds = {}
        if self.text_edit then
            -- A scrollable host can omit the focused field this frame. Keep
            -- its draft, but do not let an old caret box consume other controls.
            self.text_edit.field_bounds = nil
        end
        local floating_requests, floating_by_id, floating_context = {}, {}, nil
        local choice_widgets = {}
        local function focus_floating(owner)
            self.floating_order = self.floating_order or {}
            self.floating_revision = (self.floating_revision or 0) + 1
            self.floating_order[owner.id] = self.floating_revision
        end
        local selected_mod, selected_page = active()
        if custom_drag and (custom_drag.mod ~= selected_mod or custom_drag.page ~= selected_page) then
            cancel_custom_drag('page changed')
        end
        local scale_id = selected_mod and selected_mod.controls.configuration_ui_scale and 'configuration_ui_scale'
            or (selected_mod and selected_mod.controls.ui_scale and 'ui_scale')
        local scale_value
        if scale_id then
            local ok, value = pcall(selected_mod.handle.preview or selected_mod.handle.get, scale_id)
            if ok and type(value) == 'number' and value == value and value > 0 and value < math.huge then
                scale_value = value
                -- The shared preference alias is authoritative. Legacy standalone
                -- layouts retain their existing externally supplied geometry scale.
                if scale_id == 'configuration_ui_scale' then
                    self.ui_scale = value / 100
                end
            end
        end
        local s = math.min(w / 1920, h / 1080) * (self.ui_scale or 1)
        local minimum_w = selected_page and selected_page.minimum_width
            or selected_mod and selected_mod.minimum_width
            or 1100
        local minimum_h = selected_page and selected_page.minimum_height
            or selected_mod and selected_mod.minimum_height
            or 600
        s = math.min(s, w / minimum_w, h / minimum_h)
        local ww = math.max(minimum_w, math.min(w / s, self.window_width or 1500))
        local wh = math.max(minimum_h, math.min(h / s, self.window_height or 820))
        local ox, oy =
            math.max(0, math.min(w - ww * s, self.window_x or (w - ww * s) / 2)),
            math.max(0, math.min(h - wh * s, self.window_y or (h - wh * s) / 2))
        self.window_width, self.window_height = ww, wh
        self.window_bounds = { x = ox, y = oy, w = ww * s, h = wh * s, scale = s }
        self.sidebar_width = math.max(250, math.min(self.sidebar_width, ww - 700))
        local mods = api.list()
        local mod, page = active()
        local tabbed = mod and mod.tabs_top
        self.tabbed = tabbed
        local rail = tabbed and 0 or self.sidebar_width
        if tabbed then
            self.focus = 'settings'
        end
        local tree_visible = math.max(1, math.floor((wh - 260) / 31))
        local settings_visible = math.max(1, math.floor((wh - 356) / 42))
        self.tree_visible, self.settings_visible = tree_visible, settings_visible

        local visible_text_age = {}

        self.window_x, self.window_y = ox, oy

        local T = self.epic_typography and M.epic_palette or M.palette
        local white, muted, accent, selection_text = T.white, T.muted, { 244, 202, 53 }, T.white
        local text_focus = false
        local function text_metrics(size, label, role, resolved)
            size = resolved and size or M.text_size(self, size, role)
            if Text and self.text_edit and label then
                local ending = self.text_edit.text .. '|'
                if tostring(label):sub(-#ending) == ending then
                    label = tostring(label):sub(1, -2)
                end
            end
            if self.text_metrics then
                local ok, m = pcall(self.text_metrics, size * s, label)
                if
                    ok
                    and m
                    and type(m.min_y) == 'number'
                    and type(m.max_y) == 'number'
                    and m.max_y > m.min_y
                    and m.max_y - m.min_y < size * s * 3
                then
                    local optical = type(m.optical_y) == 'number'
                            and m.optical_y == m.optical_y
                            and math.abs(m.optical_y) < size * s
                            and m.optical_y / s
                        or 0
                    return {
                        min_y = m.min_y / s,
                        max_y = m.max_y / s,
                        height = (m.max_y - m.min_y) / s,
                        optical_y = optical,
                    }
                end
            end
            return { min_y = 0, max_y = size, height = size }
        end
        local function text_y(y, height, size, label, role)
            local m = text_metrics(size, label, role)
            local baseline = y + (height - m.height) / 2 - m.min_y + (m.optical_y or 0)
            if height >= m.height + 2 then
                baseline = math.max(y - m.min_y + 1, math.min(y + height - m.max_y - 1, baseline))
            end
            return baseline
        end
        local active_viewport
        local function hovering(x, y, rw, rh)
            if
                active_viewport
                and self.pointer_x
                and self.pointer_y
                and (
                    self.pointer_x < active_viewport.x
                    or self.pointer_x >= active_viewport.x + active_viewport.w
                    or self.pointer_y < active_viewport.y
                    or self.pointer_y >= active_viewport.y + active_viewport.h
                )
            then
                return false
            end
            return self.pointer_x
                and self.pointer_y
                and self.pointer_x >= ox + x * s
                and self.pointer_x <= ox + (x + rw) * s
                and self.pointer_y >= oy + y * s
                and self.pointer_y <= oy + (y + rh) * s
        end

        local function rect(x, y, rw, rh, color, a, role)
            commands[#commands + 1] = {
                type = 'rect',
                x = ox + x * s,
                y = oy + y * s,
                w = rw * s,
                h = rh * s,
                c = color,
                a = a or 1,
                ui_role = role or 'content_background',
            }
        end
        local function frame(id, x, y, rw, rh, color)
            local thickness = math.min(2 / s, rw / 2, rh / 2)
            local bounds = { x = ox + x * s, y = oy + y * s, w = rw * s, h = rh * s }
            for _, edge in ipairs({
                { 'bottom', x, y, rw, thickness },
                { 'top', x, y + rh - thickness, rw, thickness },
                { 'left', x, y + thickness, thickness, rh - thickness * 2 },
                { 'right', x + rw - thickness, y + thickness, thickness, rh - thickness * 2 },
            }) do
                rect(edge[2], edge[3], edge[4], edge[5], color or T.border, nil, 'window_frame')
                local command = commands[#commands]
                command.window_frame, command.frame_edge, command.frame_bounds = id, edge[1], bounds
                command.layer = 105
            end
        end

        -- Window order and content order are separate. Reserve a bounded range
        -- for each surface; command counts and text offsets cannot escape it.
        local function paint_surface(first, plane, span)
            if commands[first] and commands[first].type == 'rect' then
                commands[first].ui_role = 'window_background'
            end
            for i = first, #commands do
                local command = commands[i]
                local offset = command.surface_offset or 0
                command.layer, command.paint_plane, command.paint_span =
                    plane + offset, plane + offset, offset > 0 and 20 or span
            end
        end

        local draw_field
        local drawing_field = false
        local function is_field(value)
            local e = Text and self.text_edit
            if not e or drawing_field then
                return false
            end
            local ending = e.text .. '|'
            value = tostring(value)
            return value:sub(-#ending) == ending
        end
        local function text(x, y, value, size, color, role, fitted)
            -- Historical internal calls use a boolean sixth argument to emit
            -- an already fitted size. Public role strings never resolve twice.
            if type(role) == 'boolean' then
                fitted, role = role, nil
            end
            size = fitted and size or M.text_size(self, size, role)
            if is_field(value) then
                draw_field(x, y, value, size, color or white)
                return
            end
            commands[#commands + 1] = {
                type = 'text',
                x = ox + x * s,
                y = oy + y * s,
                text = tostring(value),
                size = size * s,
                c = color or white,
                a = 1,
                bold = M.text_bold(self, role),
                text_role = role or 'label',
            }
        end

        local function bounded(x, y, value, size, color, width, role)
            size = M.text_size(self, size, role)
            if is_field(value) then
                draw_field(x, y, value, size, color or white, width)
                return
            end

            local key = tostring(value) .. '|' .. x .. '|' .. y .. '|' .. width

            local animate = text_focus
                or (not self.color_picker and not self.dropdown and hovering(x, y - 5, width, 28))
            local age = text_age[key]
            if not age or age.active ~= animate then
                age = { start = elapsed, active = animate }
            end
            visible_text_age[key] = age

            -- Prefer a readable fitted label; ticker remains for unusually long text.
            local total = 0
            for glyph in tostring(value):gmatch('[%z\1-\127\194-\244][\128-\191]*') do
                total = total + ((measure and measure(glyph, size * s)) or size * s * 0.62)
            end
            if total > width * s then
                size = math.max(8, size * width * s / total)
            end
            local result = M.flow(value, width * s, size * s, animate and (elapsed - age.start) or 0, measure)

            text(x, y, result, size, color, role, true)
            commands[#commands].full_text = tostring(value)
            commands[#commands].text_width = width * s
        end
        draw_field = function(x, y, value, size, color, width)
            local e = Text.ensure(self.text_edit)
            local box
            for i = #commands, 1, -1 do
                local c = commands[i]
                if
                    c.type == 'rect'
                    and c.h >= size * s
                    and c.h <= 50 * s
                    and c.x <= ox + x * s
                    and c.y <= oy + y * s
                    and c.x + c.w >= ox + x * s
                    and c.y + c.h >= oy + y * s
                then
                    box = c
                    break
                end
            end
            box = box or { x = ox + (x - 5) * s, y = oy + (y - 5) * s, w = (width or 180) * s, h = (size + 10) * s }
            -- A bounded editable label owns only its allotted viewport. The
            -- surrounding control may also contain dropdown/step buttons.
            if width then
                box = {
                    x = box.x,
                    y = box.y,
                    w = math.max(1, math.min(box.w, ox + (x + width + 5) * s - box.x)),
                    h = box.h,
                }
            end
            local label = tostring(value)
            local prefix = label:sub(1, #label - #e.text - 1)
            local cache_key = e.text .. ':' .. size .. ':' .. s .. ':' .. (self.font_metric_key or '')
            if e.measure_key ~= cache_key then
                e.measure_key, e.measure_cache, e.glyph_advances = cache_key, {}, {}
            end
            local function length(text_value)
                if text_value == '' then
                    return 0
                end
                local got = e.measure_cache[text_value]
                if not got then
                    if self.measure_text then
                        local ok, width = pcall(self.measure_text, text_value, size * s)
                        if ok and type(width) == 'number' and width >= 0 and width < math.huge then
                            got = width / s
                        end
                    end
                end
                if not got then
                    got = 0
                    for glyph in text_value:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
                        local advance = e.glyph_advances[glyph]
                        if advance == nil then
                            advance = measure and measure(glyph, size * s) / s or size * 0.62
                            e.glyph_advances[glyph] = advance
                        end
                        got = got + advance
                    end
                end
                e.measure_cache[text_value] = got
                return got
            end
            local prefix_width = length(prefix)
            local tx = x + prefix_width
            local available = math.max(1, (box.x + box.w - ox) / s - tx - 5)
            local cursor = length(e.text:sub(1, e.cursor))
            e.scroll = math.max(0, e.scroll or 0)
            if cursor - e.scroll > available - 2 then
                e.scroll = cursor - available + 2
            end
            if cursor - e.scroll < 0 then
                e.scroll = cursor
            end
            e.scroll = math.min(e.scroll, math.max(0, length(e.text) - available + 2))
            local a, b = Text.range(e)
            local low, high = length(e.text:sub(1, a)) - e.scroll, length(e.text:sub(1, b)) - e.scroll
            local ink = text_metrics(size, e.text ~= '' and e.text or nil, nil, true)
            local sy = math.max((box.y - oy) / s + 1, y + ink.min_y - 1)
            local sh = math.min(ink.height + 2, (box.y + box.h - oy) / s - sy - 1)
            if high > low then
                local left, right = math.max(0, low), math.min(available, high)
                if right > left then
                    rect(tx + left, sy, right - left, sh, T.text_selection)
                    commands[#commands].ui_role = 'text_selection'
                end
            end
            local start, at, finish = 0, 0, 0
            while at < #e.text do
                local next_at = Text.next(e.text, at)
                if length(e.text:sub(1, at)) < e.scroll then
                    start = next_at
                end
                if length(e.text:sub(1, next_at)) - e.scroll <= available then
                    finish = next_at
                else
                    break
                end
                at = next_at
            end
            drawing_field = true
            if prefix ~= '' then
                text(x, y, prefix, size, color, true)
            end
            text(
                tx + math.max(0, length(e.text:sub(1, start)) - e.scroll),
                y,
                e.text:sub(start + 1, finish),
                size,
                color,
                true
            )
            commands[#commands].full_text = label
            commands[#commands].text_width = available * s
            commands[#commands].ui_role = 'text_field'
            drawing_field = false
            local cx = tx + math.max(0, math.min(available - 1, cursor - e.scroll))
            rect(cx, sy, 1 / s, sh, T.focus)
            commands[#commands].ui_role = 'text_caret'
            e.field_bounds = {
                x = box.x,
                y = box.y,
                w = box.w,
                h = box.h,
                text_x = ox + tx * s,
                scale = s,
                measure = length,
                owner = floating_context and floating_context.id,
                mod = mod,
                page = page,
            }
        end

        local function hit(x, y, rw, rh, fn, right, middle, tooltip, double)
            local owner = floating_context
            local function owned(callback)
                if not owner or not callback then
                    return callback
                end
                return function(...)
                    focus_floating(owner)
                    local editing = self.text_edit
                    local dragging, scrolling, moving = drag, scroll_drag, preview_drag
                    callback(...)
                    if self.text_edit and self.text_edit ~= editing then
                        self.text_edit.floating_owner = owner.id
                    end
                    if drag and drag ~= dragging then
                        drag.floating_owner = owner.id
                    end
                    if scroll_drag and scroll_drag ~= scrolling then
                        scroll_drag.floating_owner = owner.id
                    end
                    if preview_drag and preview_drag ~= moving then
                        preview_drag.floating_owner = owner.id
                    end
                end
            end
            hits[#hits + 1] = {
                x = ox + x * s,
                y = oy + y * s,
                w = rw * s,
                h = rh * s,
                click = owned(fn),
                right_click = owned(right),
                middle_click = owned(middle),
                tooltip = tooltip,
                double_click = owned(double),
                floating_owner = owner and owner.id,
            }
        end

        local function surface(plane)
            assert(plane == 110 or plane == 130, 'Unsupported custom UI surface plane')
            local first, finished = #commands + 1, false
            return function()
                assert(not finished, 'Custom UI surface already finished')
                finished = true
                for index = first, #commands do
                    local command = commands[index]
                    command.layer, command.paint_plane, command.paint_span = plane, plane, 20
                    command.surface_offset = plane - 100
                end
            end
        end
        local function viewport(bounds, draw, covers)
            local function finite(value)
                return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
            end
            assert(
                type(bounds) == 'table'
                    and finite(bounds.x)
                    and finite(bounds.y)
                    and finite(bounds.w)
                    and finite(bounds.h)
                    and bounds.w > 0
                    and bounds.h > 0
                    and finite(bounds.x + bounds.w)
                    and finite(bounds.y + bounds.h),
                'Invalid custom UI viewport'
            )
            assert(type(draw) == 'function' and not active_viewport, 'Invalid or nested custom UI viewport draw')
            assert(
                type(covers) == 'table'
                    and finite(covers.top)
                    and finite(covers.bottom)
                    and covers.top >= bounds.y + bounds.h
                    and covers.bottom <= bounds.y
                    and type(covers.color) == 'table',
                'Invalid custom UI viewport covers'
            )
            for channel = 1, 3 do
                assert(
                    finite(covers.color[channel]) and covers.color[channel] >= 0 and covers.color[channel] <= 255,
                    'Invalid custom UI viewport cover color'
                )
            end
            local clip = { x = ox + bounds.x * s, y = oy + bounds.y * s, w = bounds.w * s, h = bounds.h * s }
            assert(
                finite(clip.x)
                    and finite(clip.y)
                    and finite(clip.w)
                    and finite(clip.h)
                    and finite(clip.x + clip.w)
                    and finite(clip.y + clip.h),
                'Invalid scaled custom UI viewport'
            )
            local first, hit_first = #commands + 1, #hits + 1
            local editing = self.text_edit
            local old_field = editing and editing.field_bounds
            active_viewport = clip
            local ok, why = pcall(draw)
            active_viewport = nil
            if not ok then
                while #commands >= first do
                    commands[#commands] = nil
                end
                while #hits >= hit_first do
                    hits[#hits] = nil
                end
                if self.text_edit then
                    self.text_edit.field_bounds = self.text_edit == editing and old_field or nil
                end
                error(why, 0)
            end
            local function intersect(rectangle)
                local x, y = math.max(rectangle.x, clip.x), math.max(rectangle.y, clip.y)
                local right = math.min(rectangle.x + rectangle.w, clip.x + clip.w)
                local top = math.min(rectangle.y + rectangle.h, clip.y + clip.h)
                if right > x and top > y then
                    return x, y, right - x, top - y
                end
            end
            local body = {}
            for index = first, #commands do
                local command = commands[index]
                local keep = true
                if command.type == 'rect' then
                    local x, y, width, height = intersect(command)
                    keep = x ~= nil
                    if keep then
                        command.x, command.y, command.w, command.h = x, y, width, height
                    end
                elseif command.type == 'text' then
                    local ink = text_metrics(command.size / s, command.text, command.text_role, true)
                    -- The native text primitive keeps its baseline. Opaque
                    -- edge masks hide only the ink outside this vertical box.
                    keep = command.y + ink.max_y * s > clip.y and command.y + ink.min_y * s < clip.y + clip.h
                end
                if keep then
                    command.layer, command.paint_plane, command.paint_span = 110, 110, 20
                    command.surface_offset = 10
                    command.viewport = clip
                    body[#body + 1] = command
                end
            end
            while #commands >= first do
                commands[#commands] = nil
            end
            for _, command in ipairs(body) do
                commands[#commands + 1] = command
            end
            local visible_hits = {}
            for index = hit_first, #hits do
                local item = hits[index]
                local x, y, width, height = intersect(item)
                if x then
                    item.x, item.y, item.w, item.h, item.viewport = x, y, width, height, clip
                    visible_hits[#visible_hits + 1] = item
                end
            end
            while #hits >= hit_first do
                hits[#hits] = nil
            end
            for _, item in ipairs(visible_hits) do
                hits[#hits + 1] = item
            end
            local field = self.text_edit and self.text_edit.field_bounds
            if field and (self.text_edit ~= editing or field ~= old_field) then
                local x, y, width, height = intersect(field)
                if x then
                    field.x, field.y, field.w, field.h, field.viewport = x, y, width, height, clip
                else
                    self.text_edit.field_bounds = nil
                end
            end
            local function mask(y, height)
                if height <= 0 then
                    return
                end
                rect(bounds.x, y, bounds.w, height, covers.color, 1, 'viewport_mask')
                local command = commands[#commands]
                command.layer, command.paint_plane, command.paint_span, command.viewport = 110, 110, 20, clip
                command.surface_offset = 10
            end
            mask(bounds.y + bounds.h, covers.top - bounds.y - bounds.h)
            mask(covers.bottom, bounds.y - covers.bottom)
        end

        local function scrollbar(role, x, y, height, total, visible, offset, on_scroll)
            if total <= visible or height <= 0 then
                return
            end
            local thumb = math.min(height, math.max(20, height * visible / total))
            local travel, maximum = height - thumb, total - visible
            local progress = math.max(0, math.min(1, offset / maximum))
            local ty = y + travel * (1 - progress)
            rect(x, y, 4, height, T.line, nil, 'slider_track')
            rect(x - 1, ty, 6, thumb, hovering(x - 7, y, 18, height) and T.focus or T.border, nil, 'slider_thumb')
            commands[#commands].scrollbar = role
            local function set(value)
                value = math.max(0, math.min(maximum, math.floor(value + 0.5)))
                if on_scroll then
                    on_scroll(value)
                elseif role == 'mods' then
                    tree_scroll = value
                    tree_manual = true
                elseif role == 'settings' then
                    self.scroll = value
                    manual_scroll = true
                elseif role == 'help' then
                    self.help_scroll = value
                elseif role == 'dropdown' and self.dropdown then
                    self.dropdown.scroll = value
                end
            end
            hit(x - 7, y, 18, height, function(_, my)
                local local_y = (my - oy) / s
                local grab = local_y >= ty and local_y <= ty + thumb and local_y - ty or thumb / 2
                scroll_drag = {
                    move = function(pointer_y)
                        local position = travel > 0 and ((pointer_y - oy) / s - grab - y) / travel or 0
                        set((1 - math.max(0, math.min(1, position))) * maximum)
                    end,
                }
                scroll_drag.move(my)
            end)
        end

        rect(0, 0, ww, wh, T.background, 0.98)
        commands[#commands].layer = 90
        rect(0, wh - 60, ww, 60, T.header)
        commands[#commands].layer = 90
        if not tabbed then
            rect(rail, 60, 2, wh - 120, muted)
        end

        hit(0, wh - 60, ww, 60, function(mx, my)
            if drag or self.capture then
                return
            end

            window_drag =
                { dx = mx - ox, dy = my - oy, max_x = math.max(0, w - ww * s), max_y = math.max(0, h - wh * s) }
        end)

        wheel_bounds = { x = ox, y = oy + 196 * s, w = ww * s, h = (wh - 316) * s, split = ox + rail * s }

        local header_title = self.basic_only and 'EPIC LUT / Basic' or 'EPIC LUT'
        bounded(
            30,
            self.epic_typography and text_y(wh - 60, 60, 28, header_title, 'title') or wh - 43,
            header_title,
            28,
            accent,
            math.max(0, ww - 274),
            'title'
        )
        local mode_switch = self.basic_only and self.open_advanced or self.open_basic
        if mode_switch then
            if self.epic_typography then
                rect(
                    ww - 224,
                    wh - 58,
                    140,
                    30,
                    hovering(ww - 224, wh - 58, 140, 30) and T.hover or T.panel,
                    nil,
                    'control_fill'
                )
                M.control_border({ rect = rect, pixel_width = 1 / s }, ww - 224, wh - 58, 140, 30, T.border)
            else
                rect(ww - 224, wh - 58, 140, 30, { 24, 132, 140 }, nil, 'control_fill')
            end
            local mode_label = self.basic_only and 'Advanced Mode' or 'Basic Mode'
            bounded(
                ww - 214,
                self.epic_typography and text_y(wh - 58, 30, 14, mode_label) or wh - 49,
                mode_label,
                14,
                white,
                120
            )
            hit(ww - 224, wh - 58, 140, 30, mode_switch)
        end

        rect(
            ww - 55,
            wh - 45,
            38,
            30,
            hovering(ww - 55, wh - 45, 38, 30) and T.field_hover or T.field,
            nil,
            'control_fill'
        )
        text(ww - 43, self.epic_typography and text_y(wh - 45, 30, 20, 'X') or wh - 38, 'X', 20, white)

        hit(ww - 55, wh - 45, 38, 30, function()
            self.visible = false
            self.capture = false
            self.dropdown = nil
            scroll_drag = nil
            self.text_edit = nil
            self.close_color(false)
        end)

        if self.warning then
            bounded(25, wh - 155, self.warning, 14, accent, ww - 50)
        end
        if tabbed then
            local count = 0
            for _, entry in ipairs(mod.pages) do
                if entry.id == 'weapons' or (entry.id == 'basic') == not not self.basic_only then
                    count = count + 1
                end
            end
            local width = (ww - 50) / math.max(1, count)
            local position = 0
            for index, entry in ipairs(mod.pages) do
                if entry.id == 'weapons' or (entry.id == 'basic') == not not self.basic_only then
                    local target_page = index
                    local selected = index == self.page
                    local x = 25 + position * width
                    position = position + 1
                    local tab_color = entry.tab_color
                    if self.epic_typography then
                        tab_color = selected and T.selected
                            or hovering(x, wh - 120, width - 6, 38) and T.hover
                            or T.panel
                    elseif tab_color then
                        local level = selected and 1 or (hovering(x, wh - 120, width - 6, 38) and 0.9 or 0.72)
                        tab_color = { tab_color[1] * level, tab_color[2] * level, tab_color[3] * level }
                    end
                    rect(
                        x,
                        wh - 120,
                        width - 6,
                        38,
                        tab_color
                            or (
                                selected and T.selected
                                or (hovering(x, wh - 120, width - 6, 38) and T.field_hover or T.field)
                            ),
                        nil,
                        'control_fill'
                    )
                    if self.epic_typography then
                        if selected then
                            rect(x, wh - 120, width - 6, 2 / s, T.focus, nil, 'control_accent')
                        end
                        if position < count then
                            rect(x + width - 3, wh - 116, 1 / s, 30, T.line, nil, 'control_border')
                        end
                    end
                    local tab_label = entry.name:gsub('^%d+%.%s*', '')
                    bounded(
                        x + 10,
                        self.epic_typography and text_y(wh - 120, 38, 18, tab_label, 'heading') or wh - 108,
                        tab_label,
                        18,
                        self.epic_typography and (selected and white or muted) or white,
                        width - 25,
                        'heading'
                    )
                    hit(x, wh - 120, width - 6, 38, function()
                        self.page = target_page
                        self.row = 1
                        self.scroll = 0
                        self.dropdown = nil
                        self.focus = 'settings'
                        manual_scroll = false
                    end)
                end
            end
        else
            text(25, wh - 105, 'MODS', 18, muted, 'heading')

            local sidebar = self.sidebar()
            tree_max = math.max(0, #sidebar - tree_visible)
            tree_scroll = math.max(0, math.min(tree_scroll, tree_max))

            if not tree_manual then
                for i, node in ipairs(sidebar) do
                    if node.kind == 'mod' and node.index == self.selected then
                        if i <= tree_scroll then
                            tree_scroll = i - 1
                        elseif i > tree_scroll + tree_visible then
                            tree_scroll = i - tree_visible
                        end
                    end
                end
            end

            self.mod_scroll = tree_scroll

            for i = tree_scroll + 1, math.min(#sidebar, tree_scroll + tree_visible) do
                local entry = sidebar[i]
                local y = wh - 149 - (i - tree_scroll - 1) * 31
                local x = 25 + entry.depth * 16

                if entry.kind == 'mod' then
                    local selected = entry.index == self.selected

                    if selected then
                        rect(15, y - 6, rail - 30, 30, accent)
                    end

                    text(x, y, entry.open and 'v' or '>', 20, selected and selection_text or white)
                    bounded(
                        x + 24,
                        y,
                        entry.mod.name,
                        20,
                        selected and selection_text or white,
                        math.max(0, rail - 39 - x)
                    )

                    hit(15, y - 6, rail - 30, 30, function()
                        self.selected = entry.index
                        tree_expanded[entry.mod.id] = not entry.open
                        self.page = 1
                        self.row = 1
                        self.scroll = 0
                        self.focus = 'settings'
                        tree_manual = true
                    end)
                else
                    local last = true

                    for next_index = i + 1, #sidebar do
                        local next_entry = sidebar[next_index]

                        if next_entry.mod ~= entry.mod or next_entry.depth < entry.depth then
                            break
                        end

                        if next_entry.depth == entry.depth then
                            last = false
                            break
                        end
                    end

                    for ancestor_depth = 1, entry.depth - 1 do
                        for next_index = i + 1, #sidebar do
                            local next_entry = sidebar[next_index]
                            if next_entry.mod ~= entry.mod or next_entry.depth < ancestor_depth then
                                break
                            end
                            if next_entry.depth == ancestor_depth then
                                rect(25 + ancestor_depth * 16 - 10, y - 7, 1, 31, muted)
                                break
                            end
                        end
                    end
                    rect(x - 10, last and y + 6 or y - 7, 1, last and 18 or 31, muted)

                    commands[#commands].tree_branch = { last = last, row_y = oy + y * s, junction = oy + (y + 6) * s }

                    rect(x - 10, y + 6, 9, 1, muted)

                    if entry.kind == 'category' then
                        rect(x - 4, y - 6, rail - 15 - x + 4, 30, { 53, 48, 32 })
                        rect(x - 4, y - 6, 3, 30, accent, nil, 'control_accent')
                        text(x + 5, y, entry.open and 'v' or '>', 20, { 255, 225, 120 })
                        bounded(x + 29, y, entry.category.name, 20, { 255, 225, 120 }, math.max(0, rail - 44 - x))

                        hit(15, y - 6, rail - 30, 30, function()
                            expanded[entry.key] = not entry.open
                            tree_manual = true
                        end)
                    else
                        local selected = entry.mod_index == self.selected and entry.index == self.page

                        rect(x - 4, y - 6, rail - 15 - x + 4, 30, selected and { 79, 62, 28 } or { 40, 39, 31 })
                        rect(x - 4, y - 6, 3, 30, selected and { 255, 225, 120 } or accent, nil, 'control_accent')
                        bounded(
                            x + 5,
                            y,
                            entry.page.name,
                            20,
                            selected and { 255, 225, 120 } or white,
                            math.max(0, rail - 20 - x)
                        )

                        hit(15, y - 6, rail - 30, 30, function()
                            self.selected = entry.mod_index
                            self.page = entry.index
                            self.row = 1
                            self.scroll = 0
                            manual_scroll = false
                            self.focus = 'settings'
                            tree_manual = true
                        end)
                    end
                end
            end

            scrollbar('mods', rail - 10, 140, wh - 262, #sidebar, tree_visible, tree_scroll)
        end

        if not mod then
            text(rail + 35, wh - 150, 'No mods registered. See the author example.', 24)
        else
            if not tabbed then
                bounded(rail + 35, wh - 108, mod.name, 28, accent, ww - 55 - rail, 'title')
                bounded(rail + 35, wh - 146, page.name, 22, white, ww - 55 - rail, 'heading')
            end

            -- Sections are named in the sidebar; no redundant ordinal footer.

            if next(page.pending) or next(page.actions) then
                local pending = 0
                for _ in pairs(page.pending) do
                    pending = pending + 1
                end
                for _ in pairs(page.actions) do
                    pending = pending + 1
                end

                text(
                    rail + 35,
                    91,
                    pending .. (pending == 1 and ' change ready to apply' or ' changes ready to apply'),
                    16,
                    accent
                )

                rect(ww - 340, 79, 135, 34, accent, nil, 'control_fill')
                text(ww - 319, 89, 'APPLY', 18, T.background)

                rect(
                    ww - 190,
                    79,
                    135,
                    34,
                    hovering(ww - 190, 79, 135, 34) and T.field_hover or T.field,
                    nil,
                    'control_fill'
                )
                text(ww - 176, 89, 'DISCARD', 18, white)

                hit(ww - 340, 79, 135, 34, function()
                    local ok, err = mod.handle.confirm(page.id)
                    self.notice = ok and ('Confirmed and saved' .. (err and '; ' .. tostring(err) or ''))
                        or tostring(err)
                end)

                hit(ww - 190, 79, 135, 34, function()
                    mod.handle.discard(page.id)
                    self.notice = 'Pending edits discarded'
                end)
            end

            -- Settings defaults use an explicit action, leaving F9 to Basic Mode.
            -- LUT workspaces retain their own row/cell and original-table resets.
            if type(page.render_layout) ~= 'function' or page.id == 'save' then
                local rows = selectable(page)
                self.row = math.max(1, math.min(self.row, #rows))
                local selected = rows[self.row]
                local authoritative, seen = selected, {}
                while authoritative and authoritative.source_mod_id and not seen[authoritative] do
                    seen[authoritative] = true
                    local owner = api.mods[authoritative.source_mod_id]
                    authoritative = owner and owner.controls[authoritative.source_control_id]
                end
                local resettable = selected
                    and authoritative
                    and authoritative.default ~= nil
                    and not selected.disabled
                    and not authoritative.disabled
                    and not self.text_edit
                    and not self.color_picker
                    and not self.capture
                    and not self.dropdown
                local rw = tabbed and 190 or math.max(160, rail - 40)
                rect(20, 79, rw, 34, resettable and T.field or T.panel, nil, 'control_fill')
                bounded(32, 89, 'RESET SETTING', 16, resettable and white or T.disabled, rw - 24)
                hit(
                    20,
                    79,
                    rw,
                    34,
                    function()
                        if not resettable then
                            return
                        end
                        local called, ok, reason =
                            pcall(mod.handle.edit or mod.handle.set, selected.id, authoritative.default)
                        self.notice = called and ok and ('Default restored; ' .. saved_notice(selected, mod.handle))
                            or tostring(called and reason or ok)
                    end,
                    nil,
                    nil,
                    selected and ('Restore the default for ' .. selected.label .. '.')
                        or 'Select a setting to restore its default.'
                )
            end

            if type(page.render_layout) == 'function' then
                local layout_floor = self.epic_typography
                        and page.id == 'colors'
                        and math.max(
                            80,
                            64 + text_metrics(15, self.notice, 'hint').max_y + 6 * (self.font_size or 12) / 12
                        )
                    or 110
                local primitives = {
                    rect = rect,
                    text = text,
                    hit = hit,
                    bounded = bounded,
                    hovering = hovering,
                    text_y = text_y,
                    theme = T,
                    epic_style = self.epic_typography,
                    pixel_width = 1 / s,
                }
                local ok, why = pcall(
                    page.render_layout,
                    M.custom_ui({
                        basic_only = self.basic_only,
                        epic_style = self.epic_typography,
                        pixel_width = 1 / s,
                        x = rail + 20,
                        y = layout_floor,
                        w = ww - rail - 40,
                        h = wh - 170 - layout_floor,
                        rect = rect,
                        text = text,
                        hit = hit,
                        bounded = bounded,
                        hovering = function(x, y, rw, rh)
                            -- Modal controls own feedback as well as input. A covered
                            -- workspace must not appear to react through a popup.
                            if self.color_picker or self.dropdown then
                                return false
                            end
                            local f = self.floating_at(self.pointer_x, self.pointer_y)
                            if f and (not floating_context or floating_context.id ~= f.id) then
                                return false
                            end
                            return hovering(x, y, rw, rh)
                        end,
                        scrollbar = scrollbar,
                        surface = surface,
                        viewport = viewport,
                        text_size = function(size, role)
                            return M.text_size(self, size, role)
                        end,
                        spacing = function(value)
                            return value * (self.epic_typography and (self.font_size or 12) / 12 or 1)
                        end,
                        text_metrics = text_metrics,
                        text_y = text_y,
                        control_height = function(size, padding, minimum, role)
                            local resolved = M.text_size(self, size, role)
                            local label = type(minimum) == 'string' and minimum or nil
                            local ratio = self.epic_typography and (self.font_size or 12) / 12 or resolved / size
                            local height = text_metrics(size, label, role).height + 2 * (padding or 5) * ratio
                            return math.max(type(minimum) == 'number' and minimum or 0, height)
                        end,
                        text_width = function(value, size, role)
                            size = M.text_size(self, size, role)
                            local width = 0
                            for glyph in tostring(value):gmatch('[%z\1-\127\194-\244][\128-\191]*') do
                                width = width + (measure and measure(glyph, size * s) / s or size * 0.62)
                            end
                            return width
                        end,
                        shift = function()
                            return self.shift
                        end,
                        clipboard = self.clipboard,
                        begin_drag = function(move, finish, cancel)
                            assert(type(move) == 'function', 'Drag movement callback required')
                            cancel_custom_drag('replaced')
                            local item = {
                                move = move,
                                finish = finish,
                                cancel = cancel,
                                owner = floating_context and floating_context.id,
                                mod = mod,
                                page = page,
                            }
                            custom_drag = item
                            api.focused_control = nil
                            if self.shortcut_context then
                                self.shortcut_context.control = nil
                            end
                            return function(reason)
                                if custom_drag == item then
                                    cancel_custom_drag(reason or 'cancelled')
                                end
                            end
                        end,
                        load_color = function(seen)
                            local glow = seen and 1 or (0.82 + 0.18 * math.sin(elapsed * 4))
                            return { math.floor(244 * glow), math.floor(202 * glow), math.floor(53 * glow) }
                        end,
                        input_value = function(id)
                            local control = mod.controls[id]
                            if not control then
                                return nil
                            end
                            local editing = self.text_edit
                                and self.text_edit.mod == mod
                                and self.text_edit.control == control
                            return editing and (self.text_edit.text .. '|') or mod.handle.get(id)
                        end,
                        activate = function(id, direction, picker_mode)
                            change(assert(mod.controls[id]), direction or 0, picker_mode)
                        end,
                        vertical = function(id, x, y, width, height)
                            local control = assert(mod.controls[id])
                            local value = drag and drag.control == control and drag.value or mod.handle.get(id)
                            hit(x, y, width, height, function(mx, my)
                                if control.disabled then
                                    return
                                end
                                local item = { mod = mod, control = control, value = value }
                                function item.move(px, py)
                                    if not py then
                                        return
                                    end
                                    local ratio = math.max(0, math.min(1, (py - (oy + y * s)) / (height * s)))
                                    item.value = control.min
                                        + math.floor(ratio * (control.max - control.min) / control.step + 0.5)
                                            * control.step
                                end
                                drag = item
                                item.move(mx, my)
                            end, nil, nil, 'Scratch alpha: checkerboard is transparent; solid color is opaque.')
                            return value
                        end,
                        number = function(id, x, y, width, value, prepare, enabled, lo, hi, selected)
                            width = M.width_cap(primitives, width, nil, 'field')
                            local control = assert(mod.controls[id])
                            if drag and drag.control == control and drag.widget_x == x and drag.widget_y == y then
                                value = drag.value
                            end
                            local track = width - 92
                            local font = self.compact_fonts and (self.font_size or 12) or 14
                            local height = math.max(21, font + 8)
                            value = tonumber(value) or tonumber(mod.handle.get(id)) or tonumber(control.default) or 0
                            lo = tonumber(lo) or control.min
                            hi = tonumber(hi) or control.max
                            prepare = prepare or function() end
                            if enabled == nil then
                                enabled = not control.disabled
                            end
                            local ratio = math.max(0, math.min(1, (value - lo) / math.max(1e-12, hi - lo)))
                            local editing = selected
                                and self.text_edit
                                and self.text_edit.mod == mod
                                and self.text_edit.control == control
                            rect(x, y, width, height, T.panel, nil, 'control_fill')
                            rect(
                                x,
                                y + height / 2 - 3.5,
                                track,
                                7,
                                enabled and { 31, 76, 84 } or T.line,
                                nil,
                                'slider_track'
                            )
                            rect(
                                x,
                                y + height / 2 - 2.5,
                                track * ratio,
                                5,
                                enabled and T.focus or T.disabled,
                                nil,
                                'slider_fill'
                            )
                            rect(
                                x + track * ratio - 5,
                                y + (height - 17) / 2,
                                10,
                                17,
                                enabled and T.focus or T.disabled,
                                nil,
                                'slider_thumb'
                            )
                            rect(
                                x + track,
                                y,
                                92,
                                height,
                                enabled and (editing or hovering(x + track, y, 92, height)) and T.field_hover or T.field
                            )
                            bounded(
                                x + track + 5,
                                text_y(y, height, 14, editing and self.text_edit.text or string.format('%.7g', value)),
                                editing and self.text_edit.text .. '|' or string.format('%.7g', value),
                                14,
                                enabled and white or T.disabled,
                                85
                            )
                            hit(x, y, track, height, function(mx)
                                if not enabled then
                                    return
                                end
                                select_control(control)
                                prepare()
                                local item = {
                                    mod = mod,
                                    control = control,
                                    value = value,
                                    live = true,
                                    widget_x = x,
                                    widget_y = y,
                                }
                                function item.move(px)
                                    local fraction = math.max(0, math.min(1, (px - (ox + x * s)) / (track * s)))
                                    item.value = math.min(
                                        hi,
                                        lo + math.floor(fraction * (hi - lo) / control.step + 0.5) * control.step
                                    )
                                end
                                drag = item
                                item.move(mx)
                            end)
                            hit(x + track, y, 92, height, function()
                                if not enabled then
                                    return
                                end
                                select_control(control)
                                prepare()
                                self.text_edit = {
                                    mod = mod,
                                    control = control,
                                    text = tostring(mod.handle.get(id)),
                                    replace = true,
                                }
                                self.notice = 'Type value; Enter saves, Escape cancels'
                            end)
                        end,
                        floating = function(id, draw, width, height, close, header_height, raise, header_buttons_width)
                            self.floating_positions = self.floating_positions or {}
                            local position = self.floating_positions[id]
                                or {
                                    x = math.max(0, w - (width + 30 + #floating_requests * 32) * s),
                                    y = math.max(0, (h - height * s) / 2 + #floating_requests * 24 * s),
                                }
                            self.floating_positions[id] = position
                            local request = {
                                id = id,
                                position = position,
                                draw = draw,
                                width = width,
                                height = height,
                                close = close,
                                header_height = header_height or 28,
                                header_buttons_width = header_buttons_width or 0,
                            }
                            local found = false
                            for _, b in ipairs(self.floating_windows or {}) do
                                if b.id == id then
                                    found = true
                                end
                            end
                            if not found or raise then
                                focus_floating(request)
                            end
                            if floating_by_id[id] then
                                floating_requests[floating_by_id[id]] = request
                            else
                                floating_requests[#floating_requests + 1] = request
                                floating_by_id[id] = #floating_requests
                            end
                        end,
                        set = function(id, value)
                            local control = assert(mod.controls[id])
                            if id == 'quick_color' and mod.handle.get(id) == value and control.on_change then
                                control.on_change(value)
                                return true
                            end
                            return mod.handle.set(id, value)
                        end,
                        preview = function(render)
                            self.preview_window = {
                                mod = mod,
                                page = { render_preview = render },
                                title = 'PALETTE PREVIEW - RGBA values',
                                width = 1000,
                                height = 620,
                                x = math.max(0, (w - 1000 * s) / 2),
                                y = math.max(0, (h - 620 * s) / 2),
                            }
                        end,
                        preset = function(input_id, choice_id, x, y, width)
                            width = M.width_cap(primitives, width, nil, 'field')
                            local input = assert(mod.controls[input_id])
                            local choice = assert(mod.controls[choice_id])
                            local popup_width =
                                M.width_cap(primitives, math.max(width, choice.dropdown_width or 0), nil, 'field')
                            local value = mod.handle.get(choice_id)
                            local editing = self.text_edit
                                and self.text_edit.mod == mod
                                and self.text_edit.control == input
                            local owner = floating_context
                            if self.dropdown and self.dropdown.control == choice and self.dropdown.mod == mod then
                                self.dropdown.x, self.dropdown.top = x, y - 4
                                self.dropdown.width, self.dropdown.owner = popup_width, owner
                            end
                            choice_bounds[choice] = {
                                x = x,
                                top = y - 4,
                                width = popup_width,
                                owner = owner,
                            }
                            choice.input_control = input
                            local name = editing and self.text_edit.text or mod.handle.get(input_id)
                            local size = M.text_size(self, 14)
                            local measured
                            if self.measure_text or measure then
                                local ok, pixels = pcall(self.measure_text or measure, name .. '|', size * s)
                                if ok and type(pixels) == 'number' and pixels >= 0 and pixels < math.huge then
                                    measured = pixels / s
                                end
                            end
                            if not measured then
                                measured = 0
                                for _ in tostring(name .. '|'):gmatch('[%z\1-\127\194-\244][\128-\191]*') do
                                    measured = measured + size * 0.62
                                end
                            end
                            local step_width = math.min(32, width / 4)
                            local available = math.max(0, width - step_width * 2)
                            local min_open = math.min(44, available / 2)
                            local name_width = math.min(available - min_open, math.max(64, measured + 24))
                            local open_x, open_width = x + name_width, available - name_width
                            local indicator_width = math.min(44, open_width)
                            rect(x, y, name_width, 26, editing and T.field_hover or T.field, nil, 'control_fill')
                            rect(x, y, 2, 26, T.focus, nil, 'control_accent')
                            bounded(
                                x + 8,
                                text_y(y, 26, 14, name),
                                editing and name .. '|' or name,
                                14,
                                white,
                                math.max(0, name_width - 13)
                            )
                            rect(
                                open_x,
                                y,
                                open_width,
                                26,
                                hovering(open_x, y, open_width, 26) and T.field_hover or T.field,
                                nil,
                                'control_fill'
                            )
                            rect(open_x, y, 1 / s, 26, T.line, nil, 'control_border')
                            if open_width >= 100 then
                                bounded(
                                    open_x + 10,
                                    text_y(y, 26, 14, 'Presets'),
                                    'Presets',
                                    14,
                                    muted,
                                    open_width - 54
                                )
                            end
                            rect(
                                x + available - indicator_width,
                                y,
                                indicator_width,
                                26,
                                T.field_hover,
                                nil,
                                'control_accent'
                            )
                            text(x + available - (indicator_width + 10) / 2, text_y(y, 26, 16, 'v'), 'v', 16, white)
                            text(x + available + (step_width - 10) / 2, text_y(y, 26, 16, '<'), '<', 16, white)
                            text(
                                x + available + step_width + (step_width - 10) / 2,
                                text_y(y, 26, 16, '>'),
                                '>',
                                16,
                                white
                            )
                            hit(x, y, name_width, 26, function()
                                change(input, 0)
                            end)
                            hit(open_x, y, open_width, 26, function()
                                if choice.disabled or choice.read_only then
                                    return
                                end
                                self.open_dropdown({
                                    mod = mod,
                                    control = choice,
                                    selected = value,
                                    scroll = math.max(0, value - 4),
                                    x = x,
                                    top = y - 4,
                                    width = popup_width,
                                    owner = owner,
                                })
                            end)
                            hit(x + available, y, step_width, 26, function()
                                change(choice, -1)
                            end)
                            hit(x + available + step_width, y, step_width, 26, function()
                                change(choice, 1)
                            end)
                        end,
                        choice = function(id, x, y, width, prepare, display)
                            local control = assert(mod.controls[id], 'Editor control missing: ' .. id)
                            display = display or {}
                            width = M.width_cap(primitives, width, nil, 'field')
                            local anchor_x = display.anchor_x or x
                            local anchor_width = M.width_cap(
                                primitives,
                                math.max(display.anchor_width or width, control.dropdown_width or 0),
                                nil,
                                'field'
                            )
                            local owner = floating_context
                            local key = tostring(owner and owner.id or 'main') .. ':' .. id
                            choice_widgets[key] = (choice_widgets[key] or 0) + 1
                            local widget = key .. ':' .. choice_widgets[key]
                            if
                                self.dropdown
                                and self.dropdown.control == control
                                and self.dropdown.mod == mod
                                and self.dropdown.widget == widget
                            then
                                if display.enabled == false or control.disabled or control.read_only then
                                    self.dropdown = nil
                                else
                                    self.dropdown.x, self.dropdown.top = anchor_x, y - 4
                                    self.dropdown.width, self.dropdown.owner = anchor_width, owner
                                end
                            end
                            local anchor = {
                                x = anchor_x,
                                top = y - 4,
                                width = anchor_width,
                                owner = owner,
                                widget = widget,
                                prepare = prepare,
                                enabled = display.enabled,
                            }
                            if
                                not choice_bounds[control]
                                or not self.choice_focus
                                or self.choice_focus.control ~= control
                                or self.choice_focus.widget == widget
                            then
                                choice_bounds[control] = anchor
                            end
                            local value = mod.handle.get(id)
                            local function open()
                                if control.disabled or control.read_only or display.enabled == false then
                                    return
                                end
                                select_control(control)
                                self.choice_focus = { control = control, widget = widget }
                                if prepare then
                                    prepare()
                                    value = mod.handle.get(id)
                                end
                                self.open_dropdown({
                                    mod = mod,
                                    owner = owner,
                                    widget = widget,
                                    control = control,
                                    selected = value,
                                    scroll = math.max(0, math.min(math.max(0, #control.choices - 8), value - 4)),
                                    x = anchor_x,
                                    top = y - 4,
                                    width = anchor_width,
                                })
                            end
                            if display.button then
                                M.custom_ui(primitives).button(x, y, width, display.height or 28, 'v', open, {
                                    enabled = not control.disabled
                                        and not control.read_only
                                        and display.enabled ~= false,
                                    padding = width * 0.35,
                                    size = 16,
                                    help = display.help or control.description,
                                })
                            else
                                local visual_control = display.enabled == false
                                        and setmetatable({ disabled = true }, { __index = control })
                                    or control
                                M.choice(primitives, visual_control, value, x, y, width, function(direction)
                                    if prepare then
                                        prepare()
                                    end
                                    change(control, direction)
                                end, open)
                            end
                        end,
                    })
                )
                if not ok then
                    text(rail + 35, wh - 200, tostring(why), 18, muted)
                end
            else
                local rows = selectable(page)
                self.row = math.max(1, math.min(self.row, #rows))
                local selected = rows[self.row]

                local compact = ww - rail < 1135
                local preview_popout = page.preview_popout or compact
                local wide = type(page.render_preview) ~= 'function' or preview_popout
                for _, control in ipairs(page.controls) do
                    if control.column and not compact then
                        wide = false
                    end
                end
                local settings_x = rail + 35
                local available = ww - 25 - settings_x
                local row_width = wide and available or available / 2 - 30
                local display = {}
                local selected_at = 1
                local ordinal = 0
                for _, control in ipairs(visible_controls(page)) do
                    if control.collapsible or (control.type ~= 'text' and control.type ~= 'section') then
                        ordinal = ordinal + 1
                    end
                    if control == selected then
                        selected_at = #display + 1
                    end
                    if control.type == 'text' and control.text_role ~= 'title' and control.text_role ~= 'selection' then
                        for _, line in
                            ipairs(
                                M.rich(
                                    control.label,
                                    row_width * s,
                                    (self.epic_typography and M.text_size(self, 20) or 20) * s,
                                    measure
                                )
                            )
                        do
                            local parts = {}
                            for _, span in ipairs(line.spans) do
                                parts[#parts + 1] = span.text
                            end
                            display[#display + 1] =
                                { control = control, label = table.concat(parts), body = true, row = ordinal }
                        end
                    else
                        display[#display + 1] = { control = control, label = control.label or '', row = ordinal }
                    end
                end
                self.display_total = #display
                if not manual_scroll and selected and selected_at <= self.scroll then
                    self.scroll = selected_at - 1
                end
                if not manual_scroll and selected and selected_at > self.scroll + settings_visible then
                    self.scroll = selected_at - settings_visible
                end
                self.scroll = math.max(0, math.min(self.scroll, math.max(0, #display - settings_visible)))
                local columns = { 0, 0 }
                for i, entry in ipairs(display) do
                    local c = entry.control

                    if i > self.scroll and i <= self.scroll + settings_visible then
                        local col = compact and 1 or (c.column or 1)
                        columns[col] = columns[col] + 1

                        local x = settings_x + (col - 1) * (available / 2)
                        local y = wh - 197 - (columns[col] - 1) * 42
                        local row_index = entry.row
                        local row_hover = not self.dropdown
                            and not self.color_picker
                            and hovering(x - 5, y - 7, row_width + 5, 34)
                        text_focus = c == selected and self.focus == 'settings'
                        rect(
                            x - 5,
                            y - 7,
                            row_width + 5,
                            34,
                            c == selected and T.selected
                                or (row_hover and T.hover or (i % 2 == 0 and T.panel or T.background))
                        )
                        commands[#commands].ui_role = 'setting_row'
                        commands[#commands].layer = 95
                        commands[#commands].hovered, commands[#commands].focused = row_hover == true, text_focus
                        rect(
                            x - 5,
                            y - 7,
                            2,
                            34,
                            c == selected and (text_focus and T.focus or T.border) or T.background
                        )

                        local color = c.disabled and muted or accent

                        local informational = c.type == 'text' or c.type == 'section'

                        local label = string.rep('  ', c.depth or 0)
                            .. (c.collapsible and (section_open(page, c) and 'v ' or '> ') or '')
                            .. entry.label

                        local value_label, value_width
                        if c.type == 'choice' or c.type == 'button' then
                            local current = (mod.handle.preview or mod.handle.get)(c.id)
                            value_label = c.type == 'choice' and tostring(c.choices[current])
                                or (c.button_label or c.label or 'Activate')
                            local presentation = c.presentation or 'combined'
                            local arrows = c.type == 'choice' and presentation ~= 'dropdown' and 68 or 0
                            local padding = c.type == 'button' and 24 or (presentation == 'selector' and 20 or 55)
                            local minimum = c.type == 'button' and 175 or (presentation == 'dropdown' and 280 or 220)
                            -- Width budgets are logical units; native measurements are pixels.
                            value_width = M.control_width(
                                value_label,
                                minimum * s,
                                math.max(0, row_width - 12 - arrows) * s,
                                padding * s,
                                18 * s,
                                measure
                            ) / s
                        end
                        local reserved = value_width
                                and (value_width + (c.type == 'choice' and (c.presentation or 'combined') ~= 'dropdown' and 68 or 0) + 12)
                            or 290
                        local label_width = informational and row_width or math.max(0, row_width - reserved)

                        if c.type == 'text' and type(c.swatches) == 'table' then
                            if c.swatch_label then
                                bounded(x, y, label, 20, white, math.max(40, row_width - 110))
                            end
                            local count = math.min(8, #c.swatches)
                            local size = math.max(12, math.min(34, (row_width - 12) / math.max(1, count) - 8))
                            for slot = 1, count do
                                local swatch = c.swatches[slot]
                                local color = swatch.rgb
                                if type(color) == 'table' and #color == 3 then
                                    local rgb = {}
                                    for ch = 1, 3 do
                                        rgb[ch] = math.max(0, math.min(255, tonumber(color[ch]) or 0))
                                    end
                                    local sx = c.swatch_label and x + row_width - 100 + (slot - 1) * (size + 8)
                                        or x + (slot - 1) * (size + 8)
                                    rect(sx, y - 4, size, size, rgb, nil, 'swatch_fill')
                                    text(sx + 3, y + 3, tostring(swatch.row or slot), 14, { 255, 255, 255 })
                                    if swatch.control and swatch.owner and swatch.prepare then
                                        local item = swatch
                                        hit(sx, y - 4, size, size, function()
                                            item.prepare()
                                            if item.control.disabled then
                                                return
                                            end
                                            self.row = row_index
                                            self.focus = 'settings'
                                            open_picker(item.owner, item.control)
                                        end)
                                    end
                                end
                            end
                        elseif entry.body then
                            text(x, y, label, 20, c.disabled and muted or white)
                        else
                            bounded(
                                x,
                                y,
                                label,
                                20,
                                c.disabled and muted or (c.type == 'section' and accent or white),
                                label_width
                            )
                        end

                        if c.collapsible then
                            local header = c
                            hit(x - 5, y - 7, row_width + 5, 34, function()
                                self.row = row_index
                                self.focus = 'settings'
                                change(header, 0)
                            end)
                        end
                        if c.type ~= 'text' and c.type ~= 'section' then
                            local value = (mod.handle.preview or mod.handle.get)(c.id)
                            local control = c
                            local owner = mod

                            local vx = x + row_width - 525

                            local function select()
                                self.row = row_index
                                self.focus = 'settings'
                            end

                            hit(x - 5, y - 7, row_width + 5, 34, function()
                                select()
                                if control.type == 'toggle' and not control.disabled then
                                    change(control, 0)
                                end
                            end)

                            if c.type == 'slider' then
                                if drag and drag.mod == mod and drag.control == c then
                                    value = drag.value
                                end

                                local track = vx + 245
                                local width = 180
                                local fraction = math.max(0, math.min(1, (value - c.min) / (c.max - c.min)))

                                -- Cyan sliders are distinct from gold choice selectors.
                                local slider_fill = c.disabled and T.disabled or T.focus
                                local slider_thumb = c.disabled and { 137, 148, 151 }
                                    or (c == selected and { 196, 251, 255 } or { 115, 231, 240 })
                                rect(
                                    track,
                                    y + 4,
                                    width,
                                    7,
                                    c.disabled and { 51, 59, 64 } or { 31, 76, 84 },
                                    nil,
                                    'slider_track'
                                )
                                rect(track, y + 5, width * fraction, 5, slider_fill, nil, 'slider_fill')
                                rect(
                                    track + width * fraction - 7,
                                    y - 3,
                                    14,
                                    21,
                                    c.disabled and { 64, 74, 80 } or { 17, 56, 65 },
                                    nil,
                                    'slider_thumb_border'
                                )
                                rect(track + width * fraction - 5, y - 1, 10, 17, slider_thumb, nil, 'slider_thumb')

                                local editing = self.text_edit
                                    and self.text_edit.mod == mod
                                    and self.text_edit.control == c

                                rect(vx + 435, y - 5, 90, 29, editing and T.field_hover or T.field, nil, 'control_fill')
                                rect(vx + 435, y - 5, 90, 1, editing and T.focus or T.border, nil, 'control_accent')

                                local display = editing and self.text_edit.text .. '|'
                                    or string.format('%.3f', value):gsub('0+$', ''):gsub('%.$', '')

                                bounded(vx + 440, y, display, 18, c.disabled and T.disabled or white, 80)

                                hit(vx + 435, y - 5, 90, 29, function()
                                    if control.disabled then
                                        return
                                    end
                                    select()

                                    self.text_edit = {
                                        mod = owner,
                                        control = control,
                                        text = tostring((owner.handle.preview or owner.handle.get)(control.id)),
                                        replace = true,
                                    }

                                    self.notice = 'Type value; Enter saves, Escape cancels'
                                end)

                                hit(track - 8, y - 7, width + 16, 34, function(mx)
                                    if control.disabled then
                                        return
                                    end
                                    select()

                                    local d = {
                                        mod = owner,
                                        control = control,
                                        value = (owner.handle.preview or owner.handle.get)(control.id),
                                    }

                                    function d.move(px)
                                        local f = math.max(0, math.min(1, (px - (ox + track * s)) / (width * s)))

                                        d.value = math.min(
                                            control.max,
                                            control.min
                                                + math.floor(f * (control.max - control.min) / control.step + 0.5)
                                                    * control.step
                                        )
                                    end

                                    drag = d
                                    d.move(mx)
                                end)
                            elseif c.type == 'input' then
                                local editing = self.text_edit and self.text_edit.control == c

                                hit(vx + 275, y - 5, 250, 29, function()
                                    select()
                                    change(control, 0)
                                end)

                                rect(
                                    vx + 275,
                                    y - 5,
                                    250,
                                    29,
                                    not c.disabled and editing and T.field_hover or T.field,
                                    nil,
                                    'control_fill'
                                )
                                bounded(
                                    vx + 285,
                                    y,
                                    editing and self.text_edit.text .. '|' or value,
                                    18,
                                    c.disabled and T.disabled or white,
                                    230
                                )
                            elseif c.type == 'color' then
                                rect(vx + 300, y - 3, 34, 23, api.color_rgb(value), nil, 'swatch_fill')
                                rect(vx + 350, y - 5, 175, 29, T.field, nil, 'control_fill')
                                bounded(vx + 360, y, value, 18, c.disabled and T.disabled or white, 155)

                                hit(vx + 295, y - 7, 230, 34, function()
                                    if control.disabled then
                                        return
                                    end
                                    select()
                                    open_picker(owner, control)
                                end)
                            elseif c.type == 'toggle' then
                                hit(vx + 350, y - 5, 175, 29, function()
                                    select()
                                    change(control, 0)
                                end)

                                rect(vx + 350, y - 5, 175, 29, T.field, nil, 'control_fill')
                                rect(
                                    vx + 354,
                                    y - 1,
                                    36,
                                    21,
                                    c.disabled and T.line or (value and { 42, 82, 72 } or T.border),
                                    nil,
                                    'slider_track'
                                )
                                rect(
                                    vx + (value and 374 or 356),
                                    y + 2,
                                    14,
                                    15,
                                    c.disabled and T.disabled or (value and T.enabled or muted),
                                    nil,
                                    'slider_thumb'
                                )
                                text(
                                    vx + 405,
                                    y,
                                    c.disabled and 'UNAVAILABLE' or (value and 'ON' or 'OFF'),
                                    c.disabled and 14 or 19,
                                    c.disabled and T.disabled or (value and T.enabled or muted)
                                )
                            elseif c.type == 'choice' then
                                local presentation = c.presentation or 'combined'

                                local chosen = c.disabled and T.disabled or white
                                local symbol = c.disabled and T.disabled or muted
                                local value_bg = T.field
                                local arrow_bg = c.disabled and T.line or T.field_hover

                                local cw = value_width
                                local cx = vx + 525 - (presentation ~= 'dropdown' and 68 or 0) - cw
                                choice_bounds[c] = { x = cx, top = y - 8, width = cw }

                                if presentation ~= 'dropdown' then
                                    rect(cx + cw + 2, y - 5, 32, 29, arrow_bg, nil, 'control_fill')
                                    text(cx + cw + 13, y, '<', 18, symbol)

                                    rect(cx + cw + 36, y - 5, 32, 29, arrow_bg, nil, 'control_fill')
                                    text(cx + cw + 47, y, '>', 18, symbol)

                                    hit(cx + cw + 2, y - 5, 32, 29, function()
                                        select()
                                        change(control, -1)
                                    end)

                                    hit(cx + cw + 36, y - 5, 32, 29, function()
                                        select()
                                        change(control, 1)
                                    end)
                                end

                                if c == selected and not c.disabled then
                                    M.control_border(
                                        { rect = rect, pixel_width = 1 / s },
                                        cx - 2,
                                        y - 7,
                                        cw + 4,
                                        33,
                                        T.border
                                    )
                                end
                                rect(cx, y - 5, cw, 29, value_bg, nil, 'control_fill')

                                bounded(
                                    cx + 9,
                                    y,
                                    tostring(c.choices[value]),
                                    18,
                                    chosen,
                                    cw - (presentation == 'selector' and 20 or 55)
                                )

                                if presentation ~= 'selector' then
                                    -- Reserve an opaque indicator cell above the value text.

                                    rect(cx + cw - 44, y - 5, 44, 29, arrow_bg, nil, 'control_accent')
                                    text(cx + cw - 28, y, 'v', 18, symbol)

                                    hit(cx, y - 5, cw, 29, function()
                                        if control.disabled then
                                            return
                                        end
                                        select()

                                        self.open_dropdown({
                                            mod = owner,
                                            control = control,
                                            selected = value,
                                            scroll = math.max(
                                                0,
                                                math.min(math.max(0, #control.choices - 8), value - 4)
                                            ),
                                            x = cx,
                                            top = y - 8,
                                            width = cw,
                                        })
                                    end)
                                end
                            else
                                local valid_key = c.type == 'keybind'
                                    and type(value) == 'number'
                                    and value == value
                                    and value % 1 == 0
                                    and value >= 0
                                    and value <= 255
                                local label = c.type == 'button' and (c.button_label or c.label or 'Activate')
                                    or (valid_key and (M.key_name(value)) or 'UNAVAILABLE')
                                local bw = value_width or 175
                                local bx = vx + 525 - bw
                                hit(bx, y - 5, bw, 29, function()
                                    select()
                                    change(control, 0)
                                end)
                                M.control_border(
                                    { rect = rect, pixel_width = 1 / s },
                                    bx - 1,
                                    y - 6,
                                    bw + 2,
                                    31,
                                    c == selected and not c.disabled and T.border or T.line
                                )
                                rect(
                                    bx,
                                    y - 5,
                                    bw,
                                    29,
                                    c.disabled and T.panel or (hovering(bx, y - 5, bw, 29) and T.field_hover or T.field),
                                    nil,
                                    'control_fill'
                                )
                                bounded(bx + 12, y, label, 18, c.disabled and muted or white, math.max(0, bw - 24))
                            end
                        end
                    end
                end

                text_focus = false
                scrollbar('settings', ww - 20, 196, wh - 364, #display, settings_visible, self.scroll)

                -- The scrollbar communicates position without debug row counts.

                if type(page.render_preview) == 'function' and preview_popout then
                    rect(ww - 365, wh - 130, 300, 32, { 55, 63, 70 }, nil, 'control_fill')
                    text(ww - 355, wh - 121, 'OPEN HUD PREVIEW', 17, accent)
                    hit(ww - 365, wh - 130, 300, 32, function()
                        self.window_x = 0
                        self.preview_window =
                            { mod = mod, page = page, x = math.max(0, w - 420 * s), y = math.max(0, (h - 450 * s) / 2) }
                    end)
                elseif type(page.render_preview) == 'function' then
                    local ok, preview = pcall(page.render_preview, {
                        x = ox + (settings_x + available / 2 + 15) * s,
                        y = oy + 220 * s,
                        w = (available / 2 - 40) * s,
                        h = (wh - 470) * s,
                        scale = s,
                    })

                    if ok and type(preview) == 'table' then
                        for _, command in ipairs(preview) do
                            command.layer = 110
                            command.hud_preview = true
                            commands[#commands + 1] = command
                        end
                    end
                end

                local help = selected and selected.description or mod.description

                local key = mod.id .. '/' .. page.id .. '/' .. tostring(help)

                if help_key ~= key then
                    self.help_scroll = 0
                    help_key = key
                end

                local hx = rail + 35
                local hw = ww - 40 - hx

                local help_size = self.epic_typography and M.text_size(self, 18, 'hint') or 18
                local help_step = self.epic_typography and help_size + 5 or 22
                local lines = M.rich(help, hw * s, help_size * s, measure)
                local visible = self.epic_typography and math.max(1, math.min(3, math.floor(64 / help_step))) or 3

                self.help_scroll = math.min(self.help_scroll, math.max(0, #lines - visible))

                help_bounds = {
                    x = ox + hx * s,
                    y = oy + 126 * s,
                    w = hw * s,
                    h = 64 * s,
                    maximum = math.max(0, #lines - visible),
                }

                for index = self.help_scroll + 1, math.min(#lines, self.help_scroll + visible) do
                    local line = lines[index]
                    local tx = hx
                    local ty = 177 - (index - self.help_scroll - 1) * help_step

                    for _, span in ipairs(line.spans) do
                        text(
                            tx,
                            ty,
                            span.text,
                            line.size / s,
                            span.style == 'plain' and muted or (span.style == 'emphasis' and white or accent),
                            span.style == 'heading' and 'heading' or 'hint',
                            self.epic_typography
                        )
                        tx = tx + span.width / s
                    end
                end

                scrollbar('help', ww - 30, 126, 64, #lines, visible, self.help_scroll)
            end
        end

        if not tabbed then
            hit(rail - 6, 196, 12, wh - 310, function()
                split_drag = { ox = ox, scale = s }
            end)
        end

        rect(0, 0, ww, 55, { 18, 23, 27 })
        rect(0, 55, ww, 1, { 110, 88, 35 })
        bounded(
            25,
            32,
            (self.menu_key_label or 'F10')
                .. ' / Esc Close   Tab Focus   Arrows Navigate / Change   Enter Select   PgUp / PgDn Sections',
            14,
            muted,
            ww - 380,
            'hint'
        )
        bounded(ww - 320, 36, 'Epic LUT / Goose', 16, { 255, 225, 120 }, 295)
        local portrait = package.loaded['epic.player_preview.v1']
        if portrait then
            local label = portrait.key_label or 'F6'
            local key = tonumber(label:match('^VK (%d+)$'))
            if key then
                label = M.key_name(key)
            end
            bounded(
                25,
                12,
                label .. ' Player Preview  |  Left-drag pan  /  Right-drag rotate  /  Wheel zoom',
                12,
                muted,
                ww - 380,
                'hint'
            )
        end
        if mod and scale_id and scale_value then
            local control = mod.controls[scale_id]
            local value = scale_value
            bounded(ww - 320, 12, 'UI Scale: ' .. value .. '%', 14, muted, 210, 'hint')
            rect(ww - 100, 6, 32, 22, T.field, nil, 'control_fill')
            text(ww - 89, 12, '<', 14, white)
            rect(ww - 62, 6, 32, 22, T.field, nil, 'control_fill')
            text(ww - 51, 12, '>', 14, white)
            local function step(direction)
                if control.disabled then
                    return
                end
                local requested = math.max(control.min, math.min(control.max, value + direction * control.step))
                local called, ok, why = pcall(mod.handle.set, scale_id, requested)
                if called and ok then
                    self.ui_scale = (mod.handle.preview or mod.handle.get)(scale_id) / 100
                    self.notice = 'Saved'
                else
                    self.notice = 'Could not save: ' .. tostring(called and why or ok)
                end
            end
            hit(ww - 100, 6, 32, 22, function()
                step(-1)
            end)
            hit(ww - 62, 6, 32, 22, function()
                step(1)
            end)
        end
        -- A readable URL; no external browser is opened by menu rendering.

        -- Show the actual status, not a fixed character slice of a Lua error.

        local notice = self.notice:gsub('[%w_./\\-]+%.lua:%d+:%s*', '')

        local lines, line = {}, ''

        for word in notice:gmatch('%S+') do
            if #line > 0 and #line + #word + 1 > 58 then
                lines[#lines + 1] = line
                line = word
            else
                line = #line == 0 and word or line .. ' ' .. word
            end
        end

        if #line > 0 then
            lines[#lines + 1] = line
        end

        if #notice > 0 then
            bounded(25, 64, notice, 15, accent, ww - 50, 'hint')
        end

        local function resize_hit(edge, x, y, rw, rh)
            hit(x, y, rw, rh, function()
                if drag or self.capture then
                    return
                end
                window_drag = nil
                split_drag = nil
                window_resize = {
                    edge = edge,
                    left = ox,
                    right = ox + ww * s,
                    bottom = oy,
                    top = oy + wh * s,
                    min_w = minimum_w * s,
                    min_h = minimum_h * s,
                    screen_w = w,
                    screen_h = h,
                    scale = s,
                }
            end)
        end
        resize_hit('w', 0, 14, 6, wh - 28)
        resize_hit('e', ww - 6, 14, 6, wh - 28)
        resize_hit('s', 14, 0, ww - 28, 6)
        resize_hit('n', 14, wh - 6, ww - 28, 6)
        for _, corner in ipairs({
            { 'sw', 0, 0 },
            { 'se', ww - 14, 0 },
            { 'nw', 0, wh - 14 },
            { 'ne', ww - 14, wh - 14 },
        }) do
            resize_hit(corner[1], corner[2], corner[3], 14, 14)
            rect(corner[2] + 4, corner[3] + 4, 6, 6, muted)
            commands[#commands].resize_handle = corner[1]
        end
        frame('main', 0, 0, ww, wh)
        local pv = self.preview_window
        if pv and api.mods[pv.mod.id] ~= pv.mod then
            self.preview_window = nil
            pv = nil
        end
        if pv then
            local vw, vh = pv.width or 420, pv.height or 450
            local pw, ph = vw * s, vh * s
            pv.x = math.max(0, math.min(w - pw, pv.x))
            pv.y = math.max(0, math.min(h - ph, pv.y))
            local px, py = pv.x, pv.y
            local vx, vy = (px - ox) / s, (py - oy) / s
            local first = #commands + 1
            rect(vx, vy, vw, vh, { 20, 25, 30 }, 0.98)
            rect(vx, vy + vh - 40, vw, 40, { 35, 42, 48 })
            text(
                vx + 14,
                self.epic_typography and text_y(vy + vh - 40, 40, 18, pv.title or 'HUD PREVIEW', 'heading')
                    or vy + vh - 27,
                pv.title or 'HUD PREVIEW',
                18,
                accent,
                'heading'
            )
            text(vx + vw - 33, vy + vh - 28, 'X', 20, white)
            hit(vx, vy, vw, vh, function() end)
            hit(vx, vy + vh - 40, vw - 50, 40, function(mx, my)
                preview_drag = { dx = mx - px, dy = my - py, max_x = math.max(0, w - pw), max_y = math.max(0, h - ph) }
            end)
            hit(vx + vw - 43, vy + vh - 40, 43, 40, function()
                self.preview_window = nil
                preview_drag = nil
            end)
            local ok, preview = pcall(
                pv.page.render_preview,
                { x = px + 20 * s, y = py + 35 * s, w = (vw - 40) * s, h = (vh - 105) * s, scale = s }
            )
            if ok and type(preview) == 'table' then
                for _, command in ipairs(preview) do
                    commands[#commands + 1] = command
                end
            else
                text((px - ox) / s + 15, (py - oy) / s + 200, 'Preview unavailable', 18, muted)
            end
            text((px - ox) / s + 14, (py - oy) / s + 14, 'Updates live with your settings', 15, muted, 'hint')
            frame('preview', vx, vy, vw, vh)
            paint_surface(first, 180, 20)
            for i = first, #commands do
                commands[i].hud_preview = true
            end
        end

        table.sort(floating_requests, function(a, b)
            return self.floating_order[a.id] < self.floating_order[b.id]
        end)
        self.floating_windows, self.floating_bounds = {}, nil
        for _, f in ipairs(floating_requests) do
            local p = f.position
            local fw, fh = f.width * s, f.height * s
            p.x = math.max(0, math.min(w - fw, p.x))
            p.y = math.max(0, math.min(h - fh, p.y))
            self.floating_windows[#self.floating_windows + 1] = { id = f.id, x = p.x, y = p.y, w = fw, h = fh }
            self.floating_bounds = self.floating_windows[#self.floating_windows]
        end
        if self.dropdown and self.dropdown.owner and not floating_by_id[self.dropdown.owner.id] then
            self.dropdown = nil
            scroll_drag = nil
        end
        if self.text_edit and self.text_edit.floating_owner and not floating_by_id[self.text_edit.floating_owner] then
            self.text_edit = nil
        end
        if drag and drag.floating_owner and not floating_by_id[drag.floating_owner] then
            drag = nil
        end
        if scroll_drag and scroll_drag.floating_owner and not floating_by_id[scroll_drag.floating_owner] then
            scroll_drag = nil
        end
        if preview_drag and preview_drag.floating_owner and not floating_by_id[preview_drag.floating_owner] then
            preview_drag = nil
        end
        if custom_drag and custom_drag.owner and not floating_by_id[custom_drag.owner] then
            cancel_custom_drag('owner closed')
        end
        local floating_plane = 210
        for _, f in ipairs(floating_requests) do
            local p = f.position
            local fw, fh = f.width * s, f.height * s
            local fx, fy = (p.x - ox) / s, (p.y - oy) / s
            local first = #commands + 1
            floating_context = f
            hit(fx, fy, f.width, f.height, function() end)
            f.draw(fx, fy, f.width, f.height)
            local frame_first = #commands + 1
            local expanded = false
            for index = first, frame_first - 1 do
                expanded = expanded or commands[index].surface_offset ~= nil
            end
            frame('floating:' .. tostring(f.id), fx, fy, f.width, f.height)
            local header_height = f.header_height or 28
            hit(
                fx,
                fy + f.height - header_height,
                math.max(0, f.width - 32 - (f.header_buttons_width or 0)),
                header_height,
                function(mx, my)
                    preview_drag = { window = p, dx = mx - p.x, dy = my - p.y, max_x = w - fw, max_y = h - fh }
                end
            )
            text(
                fx + f.width - 20,
                self.epic_typography and text_y(fy + f.height - header_height, header_height, 14, 'X')
                    or fy + f.height - 26,
                'X',
                14,
                white
            )
            hit(fx + f.width - 32, fy + f.height - header_height, 32, header_height, function()
                if self.dropdown and self.dropdown.owner and self.dropdown.owner.id == f.id then
                    self.dropdown = nil
                    scroll_drag = nil
                end
                if self.text_edit and self.text_edit.floating_owner == f.id then
                    self.text_edit = nil
                end
                f.close()
            end)
            floating_context = nil
            -- Child viewports occupy +10..+25 and fixed chrome +30..+45.
            -- The owned outer frame sits above both and below the next window.
            if expanded then
                for index = frame_first, #commands do
                    commands[index].surface_offset = 40
                end
            end
            local span = expanded and 60 or 20
            paint_surface(first, floating_plane, span)
            floating_plane = floating_plane + span
            for i = first, #commands do
                commands[i].popup = true
                commands[i].floating_id = f.id
            end
        end
        -- Reuse the native draw-layer region that rendered earlier releases.
        -- Floating windows reserve their complete child viewport/chrome range.
        -- Ordinary dropdown/picker/dialog surfaces still require twenty layers.
        local last_floating_top = #floating_requests > 0 and floating_plane or 200
        local popup_planes = { dropdown = math.max(300, last_floating_top) }
        popup_planes.picker = math.max(340, popup_planes.dropdown + 20)
        popup_planes.dialog = math.max(380, popup_planes.picker + 20)
        popup_planes.tooltip = math.max(420, popup_planes.dialog + 20)
        if self.dropdown then
            local overlay_start = #commands + 1

            local d = self.dropdown
            local count = math.min(8, #d.control.choices)
            local height = count * 31 + 8

            local top = math.max(height + 8, math.min(wh - 68, d.top))
            local dw = math.min(ww - 16, d.width or 250)
            local x = math.max(8, math.min(ww - dw - 8, d.x))
            if d.owner or d.screen_anchor then
                top = math.max(-oy / s + height + 8, math.min((h - oy) / s - 8, d.top))
                dw = math.min(w / s - 16, d.width or 250)
                x = math.max(-ox / s + 8, math.min((w - ox) / s - dw - 8, d.x))
            end

            -- Overlay hit regions take priority and consume outside clicks.

            hit(-ox / s, -oy / s, w / s, h / s, function(mx, my)
                local owner = d.owner
                local p = owner and owner.position
                local header = owner and owner.header_height or 28
                if
                    p
                    and mx >= p.x
                    and mx < p.x + (owner.width - 32) * s
                    and my >= p.y + (owner.height - header) * s
                    and my <= p.y + owner.height * s
                then
                    preview_drag = {
                        window = p,
                        floating_owner = owner.id,
                        dx = mx - p.x,
                        dy = my - p.y,
                        max_x = math.max(0, w - owner.width * s),
                        max_y = math.max(0, h - owner.height * s),
                    }
                else
                    self.dropdown = nil
                    scroll_drag = nil
                end
            end)

            rect(x, top - height, dw, height, T.panel)

            for index = d.scroll + 1, math.min(#d.control.choices, d.scroll + count) do
                local y = top - 29 - (index - d.scroll - 1) * 31
                local choice = index

                rect(
                    x + 3,
                    y - 4,
                    dw - 16,
                    30,
                    index == d.selected and T.selected or (hovering(x + 3, y - 4, dw - 16, 30) and T.hover or T.panel),
                    nil,
                    'control_fill'
                )
                rect(x + 3, y - 4, 2, 30, index == d.selected and accent or T.panel, nil, 'selection_outline')
                text_focus = index == d.selected

                local preview = d.control.choice_previews and d.control.choice_previews[index]
                local pattern_preview = d.control.choice_pattern_previews and d.control.choice_pattern_previews[index]
                local detail = d.control.choice_details and d.control.choice_details[index]
                local can_delete = index > 1
                    and type(d.control.on_delete_choice) == 'function'
                    and not d.control.disabled
                    and not d.control.read_only
                local delete_width = can_delete and 36 or 0
                local choice_label = tostring(d.control.choices[index])
                bounded(
                    x + 8,
                    y + (detail and 12 or 0),
                    choice_label,
                    detail and 13 or 18,
                    index == d.selected and selection_text or white,
                    math.max(0, dw - (preview and 138 or pattern_preview and 56 or 24) - delete_width)
                )
                if detail then
                    bounded(
                        x + 8,
                        y - 1,
                        detail,
                        10,
                        index == d.selected and selection_text or accent,
                        math.max(0, dw - 24 - delete_width)
                    )
                end
                if preview then
                    local kinds = { 'armor', 'helmet' }
                    if preview.weapon and #preview.weapon > 0 then
                        kinds[#kinds + 1] = 'weapon'
                    end
                    local lane = 108 / #kinds
                    local strip_width = lane - 6
                    for n, kind in ipairs(kinds) do
                        local colors = preview[kind] or {}
                        local sx = x + dw - 122 - delete_width + (n - 1) * lane
                        if #colors == 0 then
                            rect(sx, y, strip_width, 12, { 65, 76, 85 }, nil, 'swatch_fill')
                        else
                            for i, color in ipairs(colors) do
                                rect(
                                    sx + (i - 1) * strip_width / #colors,
                                    y,
                                    math.max(0, strip_width / #colors - 1),
                                    12,
                                    color,
                                    nil,
                                    'swatch_fill'
                                )
                            end
                        end
                    end
                    for n = 1, #kinds - 1 do
                        rect(
                            x + dw - 122 - delete_width + n * lane - 2,
                            y - 2,
                            1,
                            16,
                            { 145, 156, 165 },
                            nil,
                            'swatch_fill'
                        )
                    end
                end
                if pattern_preview then
                    M.pattern_thumbnail(pattern_preview, rect, x + dw - 44 - delete_width, y - 1, 24)
                end

                hit(x + 3, y - 4, dw - 16, 30, function()
                    local ok, err = (d.mod.handle.edit or d.mod.handle.set)(d.control.id, choice)

                    self.notice = ok and saved_notice(d.control, d.mod.handle) or tostring(err)
                    self.dropdown = nil
                    scroll_drag = nil
                    if ok and d.control.input_control and choice == 1 then
                        change(d.control.input_control, 0)
                    end
                end)
                if can_delete then
                    local dx = x + dw - 48
                    rect(
                        dx,
                        y - 4,
                        30,
                        30,
                        hovering(dx, y - 4, 30, 30) and T.field_hover or T.panel,
                        nil,
                        'control_fill'
                    )
                    text(dx + 10, text_y(y - 4, 30, 14, 'X'), 'X', 14, muted)
                    -- Register after the option body so removal cannot select or
                    -- apply the row first. Keep the chooser open after refresh.
                    hit(dx, y - 4, 30, 30, function()
                        self.dropdown = nil
                        self.outfit_dialog = {
                            phase = 'delete',
                            title = 'Delete Preset?',
                            preset_name = choice_label,
                            description = 'Delete this saved preset? Applied colors stay unchanged.',
                            on_save = function()
                                assert(
                                    d.control.choices[choice] == choice_label,
                                    'Preset list changed; reopen it before deleting'
                                )
                                local ok, notice = d.control.on_delete_choice(choice, choice_label)
                                assert(ok, notice or 'Could not remove preset')
                                self.redraw_revision = (self.redraw_revision or 0) + 1
                                return notice or 'Preset removed'
                            end,
                        }
                    end, nil, nil, 'Remove this saved preset. Applied colors stay unchanged.')
                end
            end

            text_focus = false
            scrollbar('dropdown', x + dw - 7, top - height + 4, height - 8, #d.control.choices, count, d.scroll)
            frame('dropdown', x, top - height, dw, height)
            paint_surface(overlay_start, popup_planes.dropdown, 20)

            for index = overlay_start, #commands do
                commands[index].popup = true
            end
        end

        if self.color_picker then
            local allowed, why = M.picker_allowed(self.color_picker.control, self.color_picker.picker_mode)
            if not allowed then
                self.notice = why
                self.close_color(false)
            end
        end
        if self.color_picker then
            local p = self.color_picker
            if p.control.picker_preview then
                if not p.preview_started then
                    local ok, why = pcall(p.control.picker_begin, p.picker_mode)
                    if ok then
                        p.preview_started = true
                    else
                        p.error = tostring(why)
                    end
                end
                if p.control.picker_channel_enabled then
                    p.initial_rgb = p.initial_rgb or { p.rgb[1], p.rgb[2], p.rgb[3] }
                    p.initial_alpha = p.initial_alpha or (p.control.picker_alpha and p.control.picker_alpha()) or 1
                    for ch = 1, 3 do
                        if not picker_channel_allowed(p.control, ch, p.picker_mode) then
                            p.rgb[ch] = p.initial_rgb[ch]
                        end
                    end
                    if not picker_channel_allowed(p.control, 4, p.picker_mode) then
                        p.alpha = p.initial_alpha
                    end
                end
                local alpha = p.alpha or (p.control.picker_alpha and p.control.picker_alpha()) or 1
                local signature = table.concat(p.rgb, ',') .. ':' .. tostring(alpha)
                if
                    p.preview_started
                    and signature ~= p.preview_signature
                    and (not p.next_preview or os.clock() >= p.next_preview)
                then
                    local ok, why = pcall(p.control.picker_preview, p.rgb, alpha)
                    if not ok then
                        p.error = tostring(why)
                    end
                    p.preview_signature, p.next_preview = signature, os.clock() + 0.04
                end
            end
            local start = #commands + 1
            local px, py = math.max(0, math.min(ww - 704, p.x or 400)), math.max(0, math.min(wh - 434, p.y or 195))

            hit(-ox / s, -oy / s, w / s, h / s, function()
                self.close_color(false)
                self.text_edit = nil
            end)

            hit(px - 2, py - 2, 704, 434, function() end)

            hit(px, py + 385, 700, 45, function(mx, my)
                color_drag = { ox = ox, oy = oy, scale = s, dx = (mx - ox) / s - px, dy = (my - oy) / s - py }
            end)

            rect(px, py, 700, 430, T.panel)
            rect(px, py + 385, 700, 45, T.header)

            rect(px + 650, py + 389, 32, 30, { 65, 73, 80 }, nil, 'control_fill')
            text(px + 660, py + 396, 'X', 20, white)

            hit(px + 650, py + 389, 32, 30, function()
                self.close_color(false)
                self.text_edit = nil
            end)

            text(
                px + 20,
                self.epic_typography and text_y(py + 385, 45, 22, 'COLOR - RGB / HEX / SWATCHES', 'heading') or py + 397,
                'COLOR - RGB / HEX / SWATCHES',
                22,
                accent,
                'heading'
            )

            local hue, saturation, brightness = api.rgb_hsv(p.rgb)

            p.hue = p.hue or hue
            p.saturation = p.saturation or saturation
            p.brightness = p.brightness or brightness

            for col = 0, 15 do
                for row = 0, 11 do
                    rect(
                        px + 20 + col * 14,
                        py + 160 + row * 17,
                        15,
                        18,
                        api.hsv_rgb(col / 15, row / 11, p.brightness),
                        nil,
                        'swatch_fill'
                    )
                end
            end

            for row = 0, 15 do
                rect(
                    px + 262,
                    py + 160 + row * 12.75,
                    25,
                    13.75,
                    api.hsv_rgb(p.hue, p.saturation, row / 15),
                    nil,
                    'swatch_fill'
                )
            end

            rect(px + 17 + p.hue * 224, py + 157 + p.saturation * 204, 6, 6, white, nil, 'marker_fill')

            rect(px + 259, py + 158 + p.brightness * 204, 31, 3, white, nil, 'marker_fill')

            local function spectrum(mx, my)
                p.hue = math.max(0, math.min(1, ((mx - ox) / s - px - 20) / 224))

                p.saturation = math.max(0, math.min(1, ((my - oy) / s - py - 160) / 204))
                p.rgb = api.hsv_rgb(p.hue, p.saturation, p.brightness)
            end

            local function value_slider(mx, my)
                p.brightness = math.max(0, math.min(1, ((my - oy) / s - py - 160) / 204))
                p.rgb = api.hsv_rgb(p.hue, p.saturation, p.brightness)
            end

            hit(px + 20, py + 160, 224, 204, function(mx, my)
                palette_drag = spectrum
                spectrum(mx, my)
            end)

            hit(px + 262, py + 160, 25, 204, function(mx, my)
                palette_drag = value_slider
                value_slider(mx, my)
            end)

            if p.control.picker_alpha then
                if p.alpha == nil then
                    p.alpha = p.control.picker_alpha()
                end
                local ax, ay, ah = px + 292, py + 160, 204
                for row = 0, 19 do
                    local opacity = row / 19
                    for col = 0, 1 do
                        local background = (row + col) % 2 == 0 and 220 or 125
                        local color = {}
                        for ch = 1, 3 do
                            color[ch] = math.floor(background * (1 - opacity) + p.rgb[ch] * opacity + 0.5)
                        end
                        rect(ax + col * 8, ay + row * ah / 20, 8, ah / 20 + 1, color, nil, 'swatch_fill')
                    end
                end
                local marker = ay + math.max(0, math.min(1, p.alpha)) * ah
                rect(ax - 2, marker - 2, 20, 4, { 15, 15, 15 }, nil, 'marker_border')
                rect(ax - 2, marker - 1, 20, 2, white, nil, 'marker_fill')
                text(ax - 2, ay - 21, 'A', 16, white)
                local function alpha_slider(mx, my)
                    p.alpha = math.floor(math.max(0, math.min(1, ((my - oy) / s - ay) / ah)) * 1000 + 0.5) / 1000
                end
                hit(
                    ax,
                    ay,
                    16,
                    ah,
                    function(mx, my)
                        if not picker_channel_allowed(p.control, 4, p.picker_mode) then
                            return
                        end
                        if not self.finish_color_field() then
                            return
                        end
                        palette_drag = alpha_slider
                        alpha_slider(mx, my)
                    end,
                    nil,
                    nil,
                    'Alpha: checkerboard is transparent; solid color is opaque. Numeric A accepts raw values.'
                )
            end

            rect(px + 595, py + 287, 85, 65, p.rgb, nil, 'swatch_fill')

            local fields = {
                { key = 1, label = 'R', value = p.rgb[1] },
                { key = 2, label = 'G', value = p.rgb[2] },
                { key = 3, label = 'B', value = p.rgb[3] },
                { key = 'hex', label = 'HEX', value = api.color_hex(p.rgb) },
            }

            if p.control.picker_alpha then
                if p.alpha == nil then
                    p.alpha = p.control.picker_alpha()
                end
                fields[#fields + 1] = { key = 'alpha', label = 'A', value = p.alpha }
            end
            for index, field in ipairs(fields) do
                local fy = py + 343 - (index - 1) * 42
                local enabled = field.key == 'hex'
                        and (picker_channel_allowed(p.control, 1, p.picker_mode) or picker_channel_allowed(
                            p.control,
                            2,
                            p.picker_mode
                        ) or picker_channel_allowed(p.control, 3))
                    or picker_channel_allowed(p.control, field.key == 'alpha' and 4 or field.key, p.picker_mode)

                text(px + 315, fy, field.label, 20, white)
                rect(px + 370, fy - 5, 210, 30, enabled and T.field or T.panel, nil, 'control_fill')

                local editing = self.text_edit and self.text_edit.color_channel == field.key

                text(
                    px + 380,
                    fy,
                    editing and self.text_edit.text .. '|' or tostring(field.value),
                    20,
                    editing and accent or white
                )

                hit(px + 370, fy - 5, 210, 30, function()
                    if not enabled then
                        return
                    end
                    -- Click-away finalizes the previous field before this
                    -- callback runs; read its newly updated RGB/HEX value.
                    local value = field.key == 'hex' and api.color_hex(p.rgb)
                        or field.key == 'alpha' and p.alpha
                        or p.rgb[field.key]
                    self.text_edit = { color_channel = field.key, text = tostring(value), replace = true }
                end)
            end

            if p.error then
                bounded(px + 315, py + 153, p.error, 12, accent, 365)
            end

            text(px + 20, py + 126, 'CUSTOM SWATCHES', 17, muted)

            for index, hex in ipairs(api.swatches()) do
                local sx = px + 20 + (index - 1) * 43

                if p.selected_swatch == index then
                    rect(sx - 3, py + 76, 41, 36, accent, nil, 'swatch_border')
                end

                rect(sx, py + 79, 35, 30, api.color_rgb(hex), nil, 'swatch_fill')

                hit(sx, py + 79, 35, 30, function()
                    p.selected_swatch = index
                    p.rgb = api.color_rgb(hex)
                    p.hue, p.saturation, p.brightness = api.rgb_hsv(p.rgb)
                end)
            end

            rect(px + 550, py + 78, 130, 32, { 65, 73, 80 }, nil, 'control_fill')
            bounded(px + 560, py + 88, 'SAVE SWATCH', 16, accent, 110)

            hit(px + 550, py + 78, 130, 32, function()
                local ok, err = api.save_swatch(p.rgb)
                self.notice = ok and 'Custom swatch saved' or tostring(err)
            end)

            rect(px + 550, py + 119, 130, 32, { 65, 73, 80 }, nil, 'control_fill')
            text(px + 557, py + 129, 'REPLACE', 16, p.selected_swatch and accent or muted)

            hit(px + 550, py + 119, 130, 32, function()
                if not p.selected_swatch then
                    self.notice = 'Select a saved swatch first'
                    return
                end

                local ok, err = api.replace_swatch(p.selected_swatch, p.rgb)
                self.notice = ok and 'Selected swatch replaced' or tostring(err)
            end)

            rect(px + 20, py + 20, 300, 32, accent, nil, 'control_fill')
            text(px + 35, py + 29, 'USE COLOR', 18, T.background)

            hit(px + 20, py + 20, 300, 32, function()
                self.commit_color()
            end)

            rect(px + 370, py + 20, 310, 32, { 65, 73, 80 }, nil, 'control_fill')
            text(px + 390, py + 29, 'CANCEL', 18, white)

            hit(px + 370, py + 20, 310, 32, function()
                self.close_color(false)
                self.text_edit = nil
            end)

            frame('color_picker', px, py, 700, 430, accent)
            paint_surface(start, popup_planes.picker, 20)
            for index = start, #commands do
                commands[index].popup = true
            end
        end

        if self.dropdown then
            -- Popup primitives follow ordinary content and occupy a higher plane.

            for _, command in ipairs(commands) do
                if command.popup then
                    command.layer = math.max(200, command.layer or 200)
                end
            end
        end

        if self.outfit_dialog then
            local dialog = self.outfit_dialog
            local dialog_height = dialog.phase == 'scope' and dialog.weapon_options and 238 or 190
            local px, py = (ww - 440) / 2, (wh - dialog_height) / 2
            hits = {} -- This confirmation owns mouse input until saved or canceled.
            local first = #commands + 1
            rect(px, py, 440, dialog_height, { 20, 25, 30 }, 0.99)
            rect(px, py + dialog_height - 36, 440, 36, T.field)
            local dialog_title = dialog.title
                or (
                    dialog.phase == 'scope' and 'Save to Armory'
                    or dialog.phase == 'confirm' and 'Keep This Preset?'
                    or 'Name This Preset'
                )
            text(
                px + 14,
                self.epic_typography and text_y(py + dialog_height - 36, 36, 18, dialog_title, 'heading')
                    or py + dialog_height - 26,
                dialog_title,
                18,
                accent,
                'heading'
            )
            local function cancel()
                self.outfit_dialog = nil
                self.text_edit = nil
            end
            if dialog.phase == 'delete' then
                bounded(px + 14, py + 116, dialog.preset_name or 'Selected preset', 14, white, 412)
                bounded(
                    px + 14,
                    py + 90,
                    dialog.description or 'Remove from Armory? Existing gear stays unchanged.',
                    12,
                    white,
                    412
                )
                if dialog.on_suppress then
                    local check_ui = M.custom_ui({
                        rect = rect,
                        bounded = bounded,
                        hit = hit,
                        hovering = hovering,
                        text_y = text_y,
                        epic_style = self.epic_typography,
                        pixel_width = 1 / s,
                    })
                    check_ui.checkbox(px + 14, py + 58, 22, 26, dialog.dont_show_again == true, true, function(value)
                        dialog.dont_show_again = value
                    end)
                    bounded(px + 42, py + 63, "Don't show this again", 12, white, 380)
                end
                rect(px + 14, py + 22, 198, 30, { 90, 45, 40 }, nil, 'control_fill')
                bounded(px + 22, py + 30, dialog.action_label or 'Delete Preset', 14, white, 180)
                hit(px + 14, py + 22, 198, 30, function()
                    local ok, why = pcall(dialog.on_save)
                    self.notice = tostring(why)
                    if ok and why ~= false then
                        if dialog.dont_show_again and dialog.on_suppress then
                            local saved, reason = pcall(dialog.on_suppress)
                            if not saved or reason == false then
                                self.notice = 'Preset saved; warning preference could not be saved: '
                                    .. tostring(reason)
                            end
                        end
                        cancel()
                    end
                end)
            elseif dialog.phase == 'scope' then
                bounded(px + 14, py + dialog_height - 74, 'What do you want to save?', 14, white, 412)
                if type(dialog.save_kind) ~= 'table' then
                    local kind = dialog.save_kind
                    dialog.save_kind = { armor = kind ~= 'helmet', helmet = kind ~= 'armor', cape = kind ~= 'helmet' }
                end
                local check_ui = M.custom_ui({
                    rect = rect,
                    bounded = bounded,
                    hit = hit,
                    hovering = hovering,
                    text_y = text_y,
                    epic_style = self.epic_typography,
                    pixel_width = 1 / s,
                })
                local any = false
                for i, option in ipairs({ { 'armor', 'Armor' }, { 'helmet', 'Helmet' }, { 'cape', 'Cape' } }) do
                    local bx = px + 14 + (i - 1) * 140
                    local kind, label = option[1], option[2]
                    local checked = dialog.save_kind[kind] == true
                    any = any or checked
                    local by = py + dialog_height - 120
                    check_ui.checkbox(bx, by, 28, 32, checked, true)
                    bounded(bx + 34, text_y(by, 32, 14, label), label, 14, white, 98)
                    hit(bx, by, 132, 32, function()
                        dialog.save_kind[kind] = not checked
                    end)
                end
                if dialog.weapon_options then
                    local selected = dialog.save_kind
                    selected.weapon_slots = selected.weapon_slots or {}
                    for slot, label in ipairs({ 'Primary', 'Secondary', 'Support' }) do
                        local bx, checked = px + 14 + (slot - 1) * 140, selected.weapon_slots[slot] == true
                        any = any or checked
                        check_ui.checkbox(bx, py + 70, 28, 32, checked, true)
                        bounded(bx + 34, text_y(py + 70, 32, 14, label), label, 14, white, 98)
                        hit(bx, py + 70, 132, 32, function()
                            selected.weapon_slots[slot] = not checked
                            selected.weapon = selected.weapon_slots[1]
                                or selected.weapon_slots[2]
                                or selected.weapon_slots[3]
                                or false
                        end)
                    end
                end
                check_ui.button(px + 14, py + 22, 198, 30, 'Save', function()
                    if dialog.on_scope then
                        local ok, why = pcall(dialog.on_scope, dialog.save_kind)
                        if not ok or why == false then
                            self.notice = tostring(why or 'Could not select save targets')
                        end
                        return
                    end
                    dialog.phase = 'name'
                    self.text_edit = { mod = dialog.mod, control = dialog.control, text = '', replace = true }
                end, { enabled = any, accent = any and accent, ink = T.background })
            elseif dialog.phase == 'confirm' then
                bounded(
                    px + 14,
                    py + 116,
                    dialog.description or 'Save the current gear as a named preset.',
                    14,
                    white,
                    412
                )
                rect(px + 14, py + 22, 198, 30, T.field, nil, 'control_fill')
                bounded(px + 22, py + 30, 'Yes', 14, white, 180)
                hit(px + 14, py + 22, 198, 30, function()
                    if dialog.on_confirm then
                        local ok, why = pcall(dialog.on_confirm)
                        self.notice = tostring(why or 'Preset saved')
                        if ok and why ~= false then
                            cancel()
                        end
                        return
                    end
                    dialog.phase = 'name'
                    dialog.save_kind = 'both'
                    self.text_edit = { mod = dialog.mod, control = dialog.control, text = '', replace = true }
                end)
            else
                if not dialog.title then
                    local scopes = {}
                    local selected = dialog.save_kind
                    if type(selected) ~= 'table' then
                        selected =
                            { armor = selected ~= 'helmet', helmet = selected ~= 'armor', cape = selected ~= 'helmet' }
                    end
                    for _, option in ipairs({ { 'armor', 'Armor' }, { 'helmet', 'Helmet' }, { 'cape', 'Cape' } }) do
                        if selected[option[1]] then
                            scopes[#scopes + 1] = option[2]
                        end
                    end
                    if selected.weapon then
                        for slot, label in ipairs({ 'Primary', 'Secondary', 'Support' }) do
                            if not selected.weapon_slots or selected.weapon_slots[slot] then
                                scopes[#scopes + 1] = label
                            end
                        end
                    end
                    bounded(px + 14, py + 130, 'Saving: ' .. table.concat(scopes, ' + '), 14, accent, 412)
                elseif dialog.description then
                    bounded(px + 14, py + 130, dialog.description, 12, muted, 412)
                end
                local editing = self.text_edit and self.text_edit.control == dialog.control
                rect(px + 14, py + 89, 412, 30, { 24, 39, 52 }, nil, 'control_fill')
                bounded(
                    px + 22,
                    py + 98,
                    editing and self.text_edit.text .. '|' or dialog.placeholder or 'Click to enter a preset name',
                    14,
                    white,
                    396
                )
                hit(px + 14, py + 89, 412, 30, function()
                    if not editing then
                        self.text_edit = {
                            mod = dialog.mod,
                            control = dialog.control,
                            text = dialog.initial_text or '',
                            replace = true,
                        }
                    end
                end)
                local suggestion = editing and preset_completion(dialog, self.text_edit.text)
                if suggestion then
                    local hint = 'Tab: ' .. suggestion
                    bounded(px + 22, text_y(py + 55, 30, 12, hint, 'hint'), hint, 12, muted, 396, 'hint')
                end
                rect(px + 14, py + 22, 198, 30, T.field, nil, 'control_fill')
                bounded(px + 22, py + 30, dialog.action_label or 'Save Preset', 14, white, 180)
                hit(px + 14, py + 22, 198, 30, function()
                    if self.text_edit then
                        self.key(13)
                    end
                end)
            end
            rect(px + 228, py + 22, 198, 30, T.field, nil, 'control_fill')
            bounded(px + 236, py + 30, dialog.phase == 'confirm' and 'No' or 'Cancel', 14, white, 180)
            hit(px + 228, py + 22, 198, 30, cancel)
            frame('outfit_dialog', px, py, 440, dialog_height)
            paint_surface(first, popup_planes.dialog, 20)
            for i = first, #commands do
                commands[i].popup = true
            end
        end
        if self.lut_apply_dialog then
            local dialog = self.lut_apply_dialog
            local mapping = dialog.mode == 'mapping'
            local gear_columns = mapping and dialog.gear_columns == true
            local column_count = gear_columns and 4 or 2
            local pad = 14
            local dw, dh = math.min(gear_columns and 1140 or 800, ww - 48), math.min(580, wh - 64)
            local px, py = (ww - dw) / 2, (wh - dh) / 2
            local bh = math.max(30, text_metrics(14).height + 10)
            local hint_height = text_metrics(12, nil, 'hint').height + 6
            local row_height = math.max(32, bh + 4)
            local header_height = math.max(36, text_metrics(18, nil, 'heading').height + 12)
            local first = #commands + 1
            hits = {}
            local drawing = M.custom_ui({
                rect = rect,
                bounded = bounded,
                hit = hit,
                hovering = hovering,
                text_y = text_y,
                epic_style = self.epic_typography,
                pixel_width = 1 / s,
            })
            local function cancel()
                self.lut_apply_dialog = nil
                scroll_drag = nil
            end
            local function selected_ids()
                local selected, any = {}, false
                for _, column in ipairs(dialog.columns or {}) do
                    for _, item in ipairs(column.items or {}) do
                        if item.enabled ~= false and item.checked == true then
                            selected[item.id], any = true, true
                        end
                    end
                end
                return selected, any
            end
            local function apply()
                local selected, any = selected_ids()
                if not any or self.lut_apply_dialog ~= dialog then
                    return
                end
                local called, ok, status = pcall(dialog.on_apply, selected)
                if called and ok ~= false then
                    self.notice = tostring(status or 'Selected LUTs applied')
                    cancel()
                else
                    dialog.error = tostring(called and status or ok)
                    self.notice = dialog.error
                end
            end
            dialog.apply = not mapping and apply or nil
            local function map_call(callback, ...)
                if self.lut_apply_dialog ~= dialog or type(callback) ~= 'function' then
                    return
                end
                local called, ok, status = pcall(callback, ...)
                if called and ok ~= false then
                    dialog.error = nil
                    dialog.status = tostring(status or 'Mapping applied')
                    self.notice = dialog.status
                else
                    dialog.status = nil
                    dialog.error = tostring(called and status or ok)
                    self.notice = dialog.error
                end
            end
            rect(px, py, dw, dh, T.panel, 0.99)
            rect(px, py + dh - header_height, dw, header_height, T.header)
            bounded(
                px + pad,
                text_y(py + dh - header_height, header_height, 18, dialog.title or 'Apply Preset LUTs', 'heading'),
                dialog.title or 'Apply Preset LUTs',
                18,
                accent,
                dw - pad * 2 - 30,
                'heading'
            )
            drawing.button(px + dw - pad - 26, py + dh - header_height + 4, 26, header_height - 8, 'X', cancel)
            local toolbar_y = py + dh - header_height - bh - 8
            local function select_all(value)
                for _, column in ipairs(dialog.columns or {}) do
                    for _, item in ipairs(column.items or {}) do
                        item.checked = value and item.enabled ~= false
                    end
                end
            end
            local function auto_mask()
                local mask, any = {}, false
                for ci, column in ipairs(dialog.columns or {}) do
                    if
                        ci > 1
                        and column.enabled ~= false
                        and column.checked == true
                        and (
                            column.kind == 'armor'
                            or column.kind == 'helmet'
                            or column.kind == 'cape'
                            or dialog.weapon_columns == true
                                and (column.kind == 'primary' or column.kind == 'secondary' or column.kind == 'support')
                        )
                    then
                        mask[column.kind], any = true, true
                    end
                end
                return mask, any
            end
            if mapping then
                local _, any = auto_mask()
                local enabled = type(dialog.on_auto_map) == 'function' and (not gear_columns or any)
                drawing.button(px + pad, toolbar_y, 140, bh, 'Auto-map', function()
                    if gear_columns then
                        local mask, checked = auto_mask()
                        if checked then
                            map_call(dialog.on_auto_map, mask)
                        end
                    else
                        map_call(dialog.on_auto_map)
                    end
                end, {
                    enabled = enabled,
                    accent = enabled and accent,
                    ink = enabled and T.background,
                })
            else
                drawing.button(px + pad, toolbar_y, 140, bh, 'Select All', function()
                    select_all(true)
                end)
                drawing.button(px + pad + 148, toolbar_y, 140, bh, 'Clear All', function()
                    select_all(false)
                end)
            end
            local caption_y = toolbar_y - hint_height - 4
            bounded(
                px + pad,
                caption_y,
                gear_columns and 'Choose an imported LUT, then its destination. Auto-map uses the checked gear columns.'
                    or mapping and 'Choose an imported LUT, then click its destination. Auto-map repeats imports in slot order.'
                    or 'Matching Pattern LUTs are always included.',
                12,
                muted,
                dw - pad * 2,
                'hint'
            )
            local column_top = caption_y - hint_height - 4
            local body_top = column_top - bh
            local toggle_y = py + bh + hint_height + pad * 2
            local body_bottom = toggle_y + (gear_columns and bh + 8 or 0)
            local viewport = math.max(1, body_top - body_bottom)
            local gap = 16
            local column_width = (dw - pad * 2 - gap * (column_count - 1)) / column_count
            for ci, column in ipairs(dialog.columns or {}) do
                local cx = px + pad + (ci - 1) * (column_width + gap)
                bounded(
                    cx,
                    text_y(column_top - bh, bh, 14, column.title or '', 'heading'),
                    column.title or '',
                    14,
                    white,
                    column_width,
                    'heading'
                )
                column.maximum = math.max(0, #(column.items or {}) * row_height - viewport)
                column.scroll = math.max(0, math.min(column.scroll or 0, column.maximum))
                column.row_height = row_height
                column.scroll_bounds = { x = cx, y = body_bottom, w = column_width, h = viewport }
                for index, item in ipairs(column.items or {}) do
                    local y = body_top + column.scroll - index * row_height
                    if y >= body_bottom - 0.01 and y + bh <= body_top + 0.01 then
                        local enabled = item.enabled ~= false
                        if mapping and ci > 1 then
                            rect(cx, y, column_width - 10, bh, T.header)
                        else
                            drawing.checkbox(
                                cx,
                                y,
                                28,
                                bh,
                                enabled
                                    and (
                                        mapping and dialog.source_id == item.id
                                        or not mapping and item.checked == true
                                    ),
                                enabled
                            )
                        end
                        local label_offset = mapping and ci > 1 and 8 or 34
                        local detail_width = item.detail
                                and math.min(
                                    column_width * 0.4,
                                    text_metrics(12, item.detail, 'hint').width or #item.detail * 6
                                )
                            or 0
                        bounded(
                            cx + label_offset,
                            text_y(y, bh, 14, item.label or item.id),
                            item.label or item.id,
                            14,
                            enabled and white or muted,
                            column_width - label_offset - 12 - detail_width
                        )
                        if item.detail then
                            bounded(
                                cx + column_width - detail_width - 10,
                                text_y(y, bh, 12, item.detail, 'hint'),
                                item.detail,
                                12,
                                muted,
                                detail_width,
                                'hint'
                            )
                        end
                        hit(cx, y, column_width - 10, bh, function()
                            if enabled then
                                if mapping then
                                    if ci == 1 then
                                        dialog.source_id = item.id
                                    elseif dialog.source_id then
                                        map_call(dialog.on_map, dialog.source_id, item.id)
                                    else
                                        dialog.error = 'Choose an imported LUT first.'
                                    end
                                else
                                    item.checked = item.checked ~= true
                                end
                            end
                        end, nil, nil, item.detail)
                    end
                end
                if column.maximum > 0 then
                    scrollbar(
                        'lut_apply_column_' .. ci,
                        cx + column_width - 6,
                        body_bottom,
                        viewport,
                        #(column.items or {}) * row_height,
                        viewport,
                        column.scroll,
                        function(value)
                            column.scroll = value <= 1 and 0 or value >= column.maximum - 1 and column.maximum or value
                        end
                    )
                end
                column.auto_bounds = nil
                if gear_columns and ci > 1 then
                    local enabled = column.enabled ~= false
                    local checked = enabled and column.checked == true
                    column.auto_bounds = { x = cx, y = toggle_y, w = column_width - 10, h = bh }
                    drawing.checkbox(cx, toggle_y, 28, bh, checked, enabled)
                    bounded(
                        cx + 34,
                        text_y(toggle_y, bh, 14, 'Auto-map'),
                        'Auto-map',
                        14,
                        enabled and white or muted,
                        column_width - 44
                    )
                    hit(
                        cx,
                        toggle_y,
                        column_width - 10,
                        bh,
                        function()
                            if enabled then
                                column.checked = not checked
                            end
                        end,
                        nil,
                        nil,
                        'Include ' .. (column.title or column.kind or 'this gear') .. ' when Auto-map is pressed.'
                    )
                end
            end
            if dialog.error or dialog.status then
                bounded(px + pad, py + bh + pad + 4, dialog.error or dialog.status, 12, muted, dw - pad * 2, 'hint')
            end
            local _, any = selected_ids()
            if mapping then
                drawing.button(px + pad, py + pad, 140, bh, 'Close', cancel)
            else
                drawing.button(
                    px + pad,
                    py + pad,
                    (dw - pad * 2 - 8) / 2,
                    bh,
                    'Apply',
                    apply,
                    { enabled = any, accent = any and accent, ink = T.background }
                )
                drawing.button(px + dw / 2 + 4, py + pad, (dw - pad * 2 - 8) / 2, bh, 'Cancel', cancel)
            end
            dialog.bounds = { x = px, y = py, w = dw, h = dh }
            frame('lut_apply_dialog', px, py, dw, dh)
            paint_surface(first, popup_planes.dialog, 20)
            for index = first, #commands do
                commands[index].popup = true
            end
        end
        if
            self.pointer_x
            and self.pointer_y
            and not self.dropdown
            and not self.color_picker
            and not self.text_edit
            and not self.outfit_dialog
        then
            local target
            for i = #hits, 1, -1 do
                local h = hits[i]
                if
                    self.pointer_x >= h.x
                    and self.pointer_x <= h.x + h.w
                    and self.pointer_y >= h.y
                    and self.pointer_y <= h.y + h.h
                then
                    target = h
                    break
                end
            end
            local tip = target and target.tooltip
            if type(tip) == 'function' then
                local ok, value = pcall(tip)
                tip = ok and value or nil
            end
            if type(tip) ~= 'string' or not tip:find('%S') then
                tip = nil
            end
            local key = tip and (target.x .. ':' .. target.y .. ':' .. tip)
            if key ~= self.tooltip_key then
                self.tooltip_key = key
                self.tooltip_started = elapsed
            end
            if key and elapsed - (self.tooltip_started or elapsed) >= 0.45 then
                local lines = {}
                local line = ''
                local width = math.min(360, ww - 24)
                local size = M.text_size(self, 12, 'hint')
                local step = size + 5
                local maximum = math.max(1, math.floor((wh - 40) / step))
                for paragraph in (tip .. '\n'):gmatch('(.-)\n') do
                    for word in paragraph:gmatch('%S+') do
                        local candidate = line == '' and word or line .. ' ' .. word
                        local measured = 0
                        for glyph in candidate:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
                            measured = measured + (measure and measure(glyph, size * s) or size * s * 0.62)
                        end
                        if line ~= '' and measured > (width - 24) * s then
                            lines[#lines + 1] = line
                            line = word
                        else
                            line = candidate
                        end
                    end
                    if line ~= '' then
                        lines[#lines + 1], line = line, ''
                    end
                end
                if #lines > maximum then
                    for i = #lines, maximum + 1, -1 do
                        lines[i] = nil
                    end
                    lines[maximum] = '...'
                end
                local height = 16 + #lines * step
                local x = math.max(12, math.min(ww - width - 12, (self.pointer_x - ox) / s + 16))
                local y = math.max(12, math.min(wh - height - 12, (self.pointer_y - oy) / s - height - 12))
                local first = #commands + 1
                rect(x, y, width, height, T.panel, 0.98)
                rect(x, y + height - 2, width, 2, accent, nil, 'control_accent')
                for i, line in ipairs(lines) do
                    bounded(x + 10, y + height - 10 - i * step, line, 12, white, width - 20, 'hint')
                end
                frame('tooltip', x, y, width, height, accent)
                paint_surface(first, popup_planes.tooltip, 20)
                for i = first, #commands do
                    commands[i].popup = true
                end
            end
        else
            self.tooltip_key = nil
        end
        text_age = visible_text_age
        if console then
            for _, command in ipairs(console.compose(w, h, self.window_bounds, true)) do
                commands[#commands + 1] = command
            end
        end

        return commands
    end

    return self
end

return M
