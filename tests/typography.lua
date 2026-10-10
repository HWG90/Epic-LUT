-- Production composer typography uses one size for ink, layout and field hits.
local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local Text = dofile('src/platform/text_editor.lua')
local api = Core.new()
local handle = api.register({
    id = 'typography',
    name = 'Epic LUT',
    pages = {
        {
            id = 'p',
            name = 'Editor',
            controls = {
                { id = 'hex', type = 'input', label = 'HEX', default = 'FFFi00' },
            },
        },
    },
})
local mod = api.mods[handle.id]
mod.tabs_top = true
local function advance(value, size)
    local width = 0
    for glyph in value:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        width = width + (glyph == 'i' and 0.2 or glyph == 'F' and 0.38 or 0.5) * size
    end
    return width
end
local menu = Menu.new(api, advance, Text)
menu.visible, menu.compact_fonts, menu.font_bold = true, true, true
menu.window_width, menu.window_height = 1420, 960
menu.text_metrics = function(size)
    return { min_y = -size * 0.2, max_y = size * 0.7, height = size * 0.9 }
end
local geometry = {}
local guidance = 'Edit the current brush color. Scratch tools also include alpha and retain every copied channel value.'
mod.pages[1].render_layout = function(ui)
    local y = ui.y + 260
    for _, role in ipairs({ 'title', 'heading', 'label', 'hint' }) do
        local text = 'Typography ' .. role
        local height = ui.control_height(14, 5, 26, role)
        local baseline = ui.text_y(y, height, 14, text, role)
        geometry[role] = { size = ui.text_size(14, role), width = ui.text_width(text, 14, role), y = y, h = height }
        ui.bounded(ui.x + 20, baseline, text, 14, ui.theme.white, 500, role)
        y = y - height - 8
    end
    local height = ui.control_height(14, 5, 26)
    geometry.field = { x = ui.x + 20, y = ui.y + 30, w = 320, h = height }
    ui.button(geometry.field.x, geometry.field.y, 320, height, 'HEX: #' .. ui.input_value('hex'), function()
        ui.activate('hex')
    end, { help = guidance, field = true })
    ui.floating('typography_popup', function(x, py, w, h)
        ui.rect(x, py, w, h, ui.theme.panel)
        ui.rect(x, py + h - 40, w, 40, ui.theme.header)
        ui.bounded(
            x + 12,
            ui.text_y(py + h - 40, 40, 14, 'Popup heading', 'heading'),
            'Popup heading',
            14,
            ui.theme.white,
            w - 48,
            'heading'
        )
    end, 260, 180, function() end, 40)
end
local function compose()
    return menu.compose(2560, 1440)
end
local function command(commands, value)
    for _, c in ipairs(commands) do
        if c.full_text == value or c.text == value then
            return c
        end
    end
    error('Missing typography text: ' .. value)
end
local function input(x, y, down)
    menu.tick({
        down = function(key)
            return down and key == 1
        end,
        mouse = function()
            return x, y
        end,
        wheel = function()
            return 0
        end,
    })
end
local function close(a, b, message)
    assert(math.abs(a - b) < 0.01, message)
end
for _, font in ipairs({ 12, 20 }) do
    for _, scale in ipairs({ 0.85, 1.3 }) do
        menu.font_size, menu.ui_scale, menu.epic_typography = font, scale, true
        local commands = compose()
        local bounds, sizes = menu.window_bounds, {}
        for _, role in ipairs({ 'title', 'heading', 'label', 'hint' }) do
            local c = command(commands, 'Typography ' .. role)
            sizes[role] = c.size
            close(c.size, geometry[role].size * bounds.scale, 'Role rendered at a different size from its layout')
            close(
                advance(c.text, c.size),
                geometry[role].width * bounds.scale,
                'Role width measurement differs from rendered ink'
            )
            assert(c.bold == (role == 'title' or role == 'heading'), 'Body/hint inherited global bold')
            local bottom = c.y - 0.2 * c.size - bounds.y - geometry[role].y * bounds.scale
            local top = bounds.y + (geometry[role].y + geometry[role].h) * bounds.scale - c.y - 0.7 * c.size
            close(bottom, top, 'Role visible ink is not centered')
            assert(bottom >= 0, 'Role ink escaped its control height')
        end
        assert(
            sizes.title > sizes.heading and sizes.heading > sizes.label and sizes.label > sizes.hint,
            'Typography hierarchy flattened'
        )
        local tab = command(commands, 'Editor')
        assert(tab.text_role == 'heading' and tab.bold, 'Main tabs lost heading style')
        local popup = command(commands, 'Popup heading')
        local f = menu.floating_windows[1]
        assert(
            popup.y - popup.size * 0.2 >= f.y + f.h - 40 * bounds.scale and popup.y + popup.size * 0.7 <= f.y + f.h,
            'Large popup heading escaped its fixed header'
        )
        local idle = command(commands, 'HEX: #' .. handle.get('hex'))
        close(
            idle.x - bounds.x - geometry.field.x * bounds.scale,
            8 * font / 12 * bounds.scale,
            'Horizontal button padding failed to scale'
        )
        input(idle.x + 2, idle.y + 2, true)
        input(idle.x + 2, idle.y + 2, false)
        commands = compose()
        local field, caret
        for _, c in ipairs(commands) do
            if c.ui_role == 'text_field' then
                field = c
            end
            if c.ui_role == 'text_caret' then
                caret = c
            end
        end
        assert(
            field and caret and not field.bold and field.size == font * bounds.scale,
            'Field size/weight differs from its idle label'
        )
        close(menu.text_edit.field_bounds.text_x, idle.x + advance('HEX: #', field.size), 'Focus moved the text origin')
        Text.all(menu.text_edit)
        commands = compose()
        local selection
        for _, c in ipairs(commands) do
            if c.ui_role == 'text_selection' then
                selection = c
            end
            if c.ui_role == 'text_caret' then
                caret = c
            end
        end
        assert(selection, 'Field selection disappeared')
        close(selection.w, advance(handle.get('hex'), field.size), 'Field selection measured a different font size')
        close(
            caret.x,
            menu.text_edit.field_bounds.text_x + advance(handle.get('hex'), field.size),
            'Caret drifted from rendered characters'
        )
        local x = menu.text_edit.field_bounds.text_x + advance('FFF', field.size)
        input(x, field.y + 1, true)
        input(x, field.y + 1, false)
        assert(menu.text_edit.cursor == 3, 'Pointer selected a different character boundary')
        menu.key(27)
        compose()
        menu.advance(0.6)
        local tooltip_lines = {}
        for _, c in ipairs(compose()) do
            if c.paint_plane and c.paint_plane >= 5000 and c.text then
                tooltip_lines[#tooltip_lines + 1] = c.text
                close(c.size, font * 0.88 * bounds.scale, 'Tooltip wrapped and rendered at different hint sizes')
                assert(
                    not c.bold and c.text == c.full_text,
                    'Tooltip inherited bold weight or truncated a wrapped word'
                )
            end
        end
        assert(table.concat(tooltip_lines, ' ') == guidance, 'Epic hint wrapping lost a character or word')
        menu.font_bold = false
        commands = compose()
        assert(
            not command(commands, 'Typography heading').bold and not command(commands, 'Typography label').bold,
            'Bold heading preference ignored'
        )
        menu.font_bold = true
    end
end
-- The reusable menu remains unchanged until Epic opts into roles.
menu.epic_typography, menu.font_size, menu.ui_scale = false, 12, 1
for _, c in ipairs(compose()) do
    if c.text and c.text:match('^Typography ') then
        assert(c.size == 12 * menu.window_bounds.scale and c.bold, 'Legacy compact typography changed')
    end
end
menu.compact_fonts = false
for _, c in ipairs(compose()) do
    if c.text and c.text:match('^Typography ') then
        assert(c.size == 14 * menu.window_bounds.scale and c.bold, 'Legacy requested font size changed')
    end
end
-- A game-font measurement source may include pair kerning. Cache the complete
-- string advance and invalidate it when the selected face changes in place.
menu.epic_typography, menu.compact_fonts, menu.font_size, menu.ui_scale = true, true, 12, 1
assert(handle.set('hex', 'AVA'))
local measure_calls, face = 0, 1
menu.font_metric_key = 'game-face-one'
menu.measure_text = function(value, size)
    measure_calls = measure_calls + 1
    local _, pairs = value:gsub('AV', '')
    return (advance(value, size) - pairs * size * 0.2) * face
end
local idle = command(compose(), 'HEX: #AVA')
input(idle.x + 2, idle.y + 2, true)
input(idle.x + 2, idle.y + 2, false)
Text.all(menu.text_edit)
local function measured_field()
    local field, selection, caret
    for _, c in ipairs(compose()) do
        if c.ui_role == 'text_field' then
            field = c
        end
        if c.ui_role == 'text_selection' then
            selection = c
        end
        if c.ui_role == 'text_caret' then
            caret = c
        end
    end
    assert(field and selection and caret)
    local width = (advance('AVA', field.size) - field.size * 0.2) * face
    close(selection.w, width, 'Selection discarded whole-string kerning')
    close(caret.x, menu.text_edit.field_bounds.text_x + width, 'Caret discarded whole-string kerning')
    return width
end
local first_width = measured_field()
local cached = measure_calls
menu.text_edit.field_bounds.measure('AVA')
menu.text_edit.field_bounds.measure('AVA')
assert(measure_calls == cached, 'Whole-string field measurements missed their cache')
face, menu.font_metric_key = 1.2, 'game-face-two'
local second_width = measured_field()
assert(second_width > first_width and measure_calls > cached, 'Changing font face retained stale caret metrics')
menu.key(27)
print(
    'PASS typography: Epic roles, regular fields, retained bold preference, matched metrics/caret, scaled padding, popup containment, legacy rendering and game-face kerning/cache invalidation'
)
