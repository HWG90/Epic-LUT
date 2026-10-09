-- Two independent settings columns. Registered controls retain their normal
-- callbacks, persistence and preference-owner routing; this is presentation only.
local V = {}
local purple = { 110, 69, 155 }
local columns = {
    {
        {
            label = 'Appearance',
            ids = { 'configuration_ui_scale', 'configuration_font_size', 'configuration_font_bold' },
        },
        {
            label = 'Shortcuts',
            ids = {
                'configuration_basic_key',
                'configuration_menu_key',
                'configuration_preview_key',
                'configuration_reset_key',
            },
        },
        { label = 'Window size', ids = { 'configuration_window_width', 'configuration_window_height' } },
    },
    {
        {
            label = 'Gear and Player Preview',
            ids = { 'auto_populate_worn', 'disable_player_preview', 'resource_format' },
        },
        { label = 'Exports', ids = { 'include_capes_in_armor_exports' } },
        { label = 'Squad sharing', ids = { 'share_appearance', 'sharing_status' } },
        { label = 'Updates', ids = { 'update_status', 'check_updates', 'auto_updates', 'open_updates' } },
        { label = 'Manual file fallback', fallback = true },
    },
}

function V.new(deps)
    local api, handle, page = deps.api, deps.handle, deps.page
    local self = { scroll = { 0, 0 }, maximum = { 0, 0 }, bounds = {} }
    local manual_open = false
    local function value(control)
        local owner = control.source_mod_id and api.mods[control.source_mod_id]
        if owner then
            return owner.handle.get(control.source_control_id)
        end
        return handle.get(control.id)
    end
    function self.wheel(x, y, delta)
        for i, b in ipairs(self.bounds) do
            if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
                self.scroll[i] = math.max(0, math.min(self.maximum[i], self.scroll[i] - delta / 120 * 48))
                return true
            end
        end
    end
    function self.draw(ui)
        local theme = ui.theme
        local white, muted, dark = theme.white, theme.muted, theme.panel
        local controls = api.mods[handle.id].controls
        -- Text controls do not live in the registry map; sharing/status labels
        -- can change after registration, so read the actual page each composition.
        local texts = {}
        for _, control in ipairs(page.controls) do
            if control.id and control.type == 'text' then
                texts[control.id] = control
            end
        end
        local size = ui.text_size and ui.text_size(14) or 14
        local bh, line = math.max(28, size + 12), size + 5
        local gap, width = 20, (ui.w - 20) / 2
        local low, high = ui.y + 24, ui.y + ui.h - 12
        local function lines(text, w)
            local result, current = {}, ''
            for word in tostring(text):gmatch('%S+') do
                local candidate = current == '' and word or current .. ' ' .. word
                local measured = ui.text_width and ui.text_width(candidate, 14) or #candidate * size * 0.62
                if current ~= '' and measured > w then
                    result[#result + 1], current = current, word
                else
                    current = candidate
                end
            end
            result[#result + 1] = current
            return result
        end
        local function full(y, h)
            return y >= low and y + h <= high
        end
        local function button(x, y, w, label, control, click, color)
            if not full(y, bh) then
                return
            end
            local enabled = not control or not control.disabled
            ui.button(x, y, w, bh, label, click, {
                enabled = enabled,
                accent = color,
                size = 14,
                help = control and control.description,
                ink = control and control.type == 'toggle' and enabled and value(control) and theme.enabled,
            })
        end
        for column, sections in ipairs(columns) do
            local x, w = ui.x + (column - 1) * (width + gap), width - 12
            self.bounds[column] = { x = x, y = ui.y, w = width, h = ui.h }
            ui.rect(x, ui.y, width, ui.h, dark)
            local cursor, total = high + self.scroll[column], 0
            local function space(h)
                cursor, total = cursor - h, total + h
                return cursor
            end
            local function row(control)
                if control.type == 'text' then
                    local wrapped = lines(control.label, w - 16)
                    local h = #wrapped * line + 8
                    local y = space(h)
                    for i, text in ipairs(wrapped) do
                        local py = y + h - 8 - i * line
                        if full(py, size) then
                            ui.bounded(x + 8, py, text, 14, muted, w - 16)
                        end
                    end
                elseif control.type == 'slider' or control.type == 'choice' then
                    local h = line + math.max(26, bh) + 10
                    local y = space(h)
                    if full(y, h) then
                        ui.bounded(x + 8, y + h - line, control.label, 14, white, w - 16)
                        if control.type == 'slider' then
                            ui.number(
                                control.id,
                                x + 8,
                                y + 5,
                                w - 16,
                                value(control),
                                nil,
                                not control.disabled,
                                nil,
                                nil,
                                true
                            )
                            -- Slider hit targets also expose the meaning of the setting.
                            ui.hit(x + 8, y + 28, w - 16, line, function() end, nil, nil, control.description)
                        else
                            ui.choice(control.id, x + 8, y + 5, w - 16)
                        end
                    end
                elseif control.type ~= 'section' then
                    local label = control.label
                    if control.type == 'toggle' then
                        label = '[ ' .. (value(control) and 'x' or ' ') .. ' ] ' .. label
                    elseif control.type == 'keybind' then
                        label = label
                            .. ': '
                            .. (deps.key_name and deps.key_name(value(control)) or tostring(value(control)))
                    elseif control.type == 'input' then
                        label = label .. ': ' .. (ui.input_value and ui.input_value(control.id) or value(control))
                    end
                    local y = space(bh + 8)
                    button(x + 8, y + 4, w - 8, label, control, function()
                        ui.activate(control.id)
                    end)
                end
            end
            for _, section in ipairs(sections) do
                local items = {}
                if section.fallback then
                    for _, control in ipairs(page.controls) do
                        for _, group in ipairs(control.groups or {}) do
                            if group == 'manual_fallback' then
                                items[#items + 1] = control
                                break
                            end
                        end
                    end
                else
                    for _, id in ipairs(section.ids) do
                        if controls[id] or texts[id] then
                            items[#items + 1] = controls[id] or texts[id]
                        end
                    end
                end
                if #items > 0 then
                    local y = space(bh + 8)
                    if section.fallback then
                        button(x + 8, y + 4, w - 8, (manual_open and 'v ' or '> ') .. section.label, nil, function()
                            manual_open = not manual_open
                        end, purple)
                    elseif full(y + 4, bh) then
                        ui.rect(x + 8, y + 4, w - 8, bh, theme.header)
                        ui.bounded(x + 16, y + 4 + (bh - size) / 2, section.label, 14, white, w - 24)
                    end
                    if not section.fallback or manual_open then
                        for _, control in ipairs(items) do
                            row(control)
                        end
                    end
                    space(10)
                end
            end
            self.maximum[column] = math.max(0, total - (high - low))
            self.scroll[column] = math.min(self.scroll[column], self.maximum[column])
            if self.maximum[column] > 0 then
                ui.bounded(x + 8, ui.y + 4, 'Scroll for more settings', 12, muted, w - 16)
                ui.scrollbar(
                    'configuration_' .. column,
                    x + width - 8,
                    low,
                    high - low,
                    total,
                    high - low,
                    self.scroll[column],
                    function(offset)
                        self.scroll[column] = offset
                    end
                )
            end
        end
    end
    return self
end
return V
