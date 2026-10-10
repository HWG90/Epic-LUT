local Core = dofile('vendor/menu/core.lua')
local Menu = dofile('vendor/menu/menu.lua')
local Text = dofile('src/platform/text_editor.lua')
local api = Core.new()
local changes = 0
local h = api.register({
    id = 'presets',
    name = 'Presets',
    pages = {
        {
            id = 'main',
            name = 'Main',
            require_confirmation = false,
            controls = {
                { id = 'name', type = 'input', label = 'Name', default = '2', allow_empty = true },
                {
                    id = 'saved',
                    type = 'choice',
                    label = 'Preset',
                    choices = { 'New preset...', '2', 'Alpha' },
                    default = 2,
                },
                {
                    id = 'regular',
                    type = 'choice',
                    label = 'Choice',
                    choices = { 'Alpha', 'Beta' },
                    default = 1,
                    on_change = function()
                        changes = changes + 1
                    end,
                },
            },
        },
    },
})
local mod = api.mods[h.id]
mod.tabs_top = true
local widget
local popup_width = 720
mod.pages[1].render_layout = function(ui)
    ui.floating('preset_popup', function(x, y, width, height)
        ui.rect(x, y, width, height, ui.theme.panel)
        widget = { x = x + 12, y = y + height - 92, width = width - 24 }
        ui.preset('name', 'saved', widget.x, widget.y, widget.width)
        ui.choice('regular', widget.x, widget.y - 70, widget.width)
    end, popup_width, 270, function() end, 40)
end
local function measure(value, size)
    -- Whole-string metrics include kerning; name hit areas must use this face.
    local _, pairs = value:gsub('AV', '')
    return #value * size * 0.5 - pairs * size * 0.2
end
local menu = Menu.new(api, measure, Text)
menu.measure_text = measure
menu.epic_typography = true
menu.visible = true
menu.window_width, menu.window_height = 1400, 900
local clipboard = ''
menu.clipboard = {
    get = function()
        return clipboard
    end,
    set = function(value)
        clipboard = value
        return true
    end,
}
local function compose()
    return menu.compose(1920, 1080)
end
local function click(x, y)
    for _, down in ipairs({ true, false }) do
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
end
local function label(commands, value, popup)
    for _, command in ipairs(commands) do
        if
            command.type == 'text'
            and (command.full_text or command.text) == value
            and ((command.paint_plane or 0) >= 300) == not not popup
        then
            return command
        end
    end
    error('Missing label: ' .. value)
end
local function row_arrows(commands, field)
    local out = {}
    for _, command in ipairs(commands) do
        if
            command.type == 'text'
            and (command.paint_plane or 0) < 300
            and command.y == field.y
            and (command.text == 'v' or command.text == '<' or command.text == '>')
        then
            out[command.text] = command
        end
    end
    return out
end
for _, scenario in ipairs({ { 0.65, 12, 720 }, { 1, 20, 720 }, { 1.15, 12, 240 } }) do
    menu.ui_scale, menu.font_size, popup_width = scenario[1], scenario[2], scenario[3]
    h.set('name', '2')
    h.set('saved', 2)
    local commands = compose()
    local name = label(commands, '2')
    local arrows = row_arrows(commands, name)
    local scale = menu.window_bounds.scale
    click(name.x + 2 * scale, name.y + 2 * scale)
    compose()
    local edit = assert(menu.text_edit, 'Preset name did not start editing')
    local small = assert(edit.field_bounds).w
    assert(small < widget.width * scale * 0.55, 'Short name captured most of the selector')
    clipboard = 'AV preset name'
    menu.key(86, true)
    commands = compose()
    local larger = assert(menu.text_edit.field_bounds)
    assert(larger.w > small, 'Editable name hit area did not grow with its text')
    assert(larger.x + larger.w < arrows.v.x, 'Caret captured the dropdown indicator')
    local field = label(commands, clipboard .. '|')
    arrows = row_arrows(commands, field)
    -- A click in the remaining selector body commits the name and opens the
    -- list, even while the name has focus. It must not move the caret.
    local open_x = (larger.x + larger.w + arrows.v.x) / 2
    click(open_x, field.y + 2 * scale)
    assert(menu.dropdown and menu.dropdown.control.id == 'saved', 'Name caret swallowed a dropdown-body click')
    assert(not menu.text_edit and h.get('name') == clipboard, 'Dropdown click lost the pending name edit')
    commands = compose()
    local option = label(commands, 'Alpha', true)
    click(option.x + 2 * scale, option.y + 2 * scale)
    assert(h.get('saved') == 3 and not menu.dropdown, 'Saved preset option could not be selected')
    commands = compose()
    field = label(commands, clipboard)
    arrows = row_arrows(commands, field)
    click(arrows['<'].x - 9 * scale, arrows['<'].y + 2 * scale)
    assert(h.get('saved') == 2 and not menu.dropdown, 'Expanded preset step button did not step')
    -- Long names use a bounded viewport while preserving the open target.
    click(field.x + 2 * scale, field.y + 2 * scale)
    clipboard = string.rep('AV', 180)
    menu.key(86, true)
    commands = compose()
    local bounds = assert(menu.text_edit.field_bounds)
    assert(
        bounds.w + (64 + math.min(44, (widget.width - 64) / 2)) * scale <= widget.width * scale + 0.01,
        'Long name consumed the dropdown/step targets'
    )
    local caret
    for _, command in ipairs(commands) do
        if command.ui_role == 'text_caret' then
            caret = command
        end
    end
    assert(
        caret and caret.x >= bounds.x and caret.x + caret.w <= bounds.x + bounds.w + 0.01,
        'Long-name caret escaped the fitted name field'
    )
    menu.key(27)
    mod.controls.saved.disabled = true
    commands = compose()
    field = label(commands, h.get('name'))
    arrows = row_arrows(commands, field)
    click(arrows.v.x + 2 * scale, arrows.v.y + 2 * scale)
    assert(not menu.dropdown, 'Disabled preset dropdown opened')
    mod.controls.saved.disabled = false
end
-- The common choice renderer opens from its entire body and larger indicator;
-- explicit selector presentations still step and never acquire a dropdown.
menu.ui_scale, menu.font_size, popup_width = 0.85, 16, 720
h.set('name', '2')
for _, presentation in ipairs({ 'combined', 'dropdown', 'selector' }) do
    mod.controls.regular.presentation = presentation
    h.set('regular', 1)
    local commands = compose()
    local chosen = label(commands, 'Alpha')
    local arrows = row_arrows(commands, chosen)
    local scale = menu.window_bounds.scale
    click(chosen.x + 2 * scale, chosen.y + 2 * scale)
    if presentation == 'selector' then
        assert(h.get('regular') == 2 and not menu.dropdown, 'Selector presentation acquired a dropdown')
    else
        assert(menu.dropdown and menu.dropdown.control.id == 'regular', 'Choice body did not open its dropdown')
        menu.key(27)
        commands = compose()
        chosen = label(commands, 'Alpha')
        arrows = row_arrows(commands, chosen)
        click(arrows.v.x - 12 * scale, arrows.v.y + 2 * scale)
        assert(menu.dropdown and menu.dropdown.control.id == 'regular', 'Expanded dropdown indicator did not open')
        menu.key(27)
    end
    if presentation ~= 'dropdown' then
        h.set('regular', 1)
        commands = compose()
        chosen = label(commands, 'Alpha')
        arrows = row_arrows(commands, chosen)
        click(arrows['>'].x - 9 * scale, arrows['>'].y + 2 * scale)
        assert(h.get('regular') == 2 and not menu.dropdown, 'Expanded choice step button did not step')
    end
end
assert(changes > 0)
-- Standard registry rows use the same larger indicator/step targets, and
-- opening a focused choice by keyboard keeps its anchored list.
mod.pages[1].render_layout = nil
mod.controls.regular.presentation = 'combined'
h.set('regular', 1)
local commands = compose()
local regular = label(commands, 'Alpha')
local arrows = row_arrows(commands, regular)
local scale = menu.window_bounds.scale
click(regular.x + 2 * scale, regular.y + 2 * scale)
assert(menu.dropdown and menu.dropdown.control.id == 'regular', 'Standard choice body did not open')
menu.key(27)
compose()
menu.key(13)
assert(menu.dropdown and menu.dropdown.control.id == 'regular', 'Keyboard choice opening lost its anchor')
menu.key(27)
commands = compose()
regular = label(commands, 'Alpha')
arrows = row_arrows(commands, regular)
click(arrows['>'].x - 9 * scale, arrows['>'].y + 2 * scale)
assert(h.get('regular') == 2 and not menu.dropdown, 'Expanded standard step button did not step')
print(
    'PASS preset dropdown: content-sized editable hit area, pending-name commit, large open/step targets, bounded long names, scale/font variants and disabled controls'
)
