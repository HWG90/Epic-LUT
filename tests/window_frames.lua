-- Inspect borders emitted by the real composer and move the same hit targets
-- used in-game. Frame bounds are checked against independently rendered bodies.
local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local api = Core.new()
local handle = api.register({
    id = 'frames',
    name = 'Frames',
    pages = {
        {
            id = 'main',
            name = 'Main',
            controls = {
                {
                    id = 'choice',
                    type = 'choice',
                    presentation = 'dropdown',
                    label = 'Choice',
                    choices = { 'One', 'Two' },
                    description = 'Choose the active item.',
                    default = 1,
                },
                { id = 'color', type = 'color', label = 'Color', default = '#FFFFFF' },
                { id = 'name', type = 'input', label = 'Name', default = 'Preset' },
            },
        },
    },
})
local mod = api.mods[handle.id]
mod.tabs_top = true
local floating
mod.pages[1].render_layout = function(ui)
    ui.choice('choice', ui.x + 10, ui.y + 100, 240)
    if floating then
        ui.floating(
            floating,
            function(x, y, w, h)
                ui.rect(x, y, w, h, ui.theme.panel)
                ui.rect(x, y + h - 40, w, 40, ui.theme.header)
                ui.bounded(x + 10, y + h - 27, 'Popup', 14, ui.theme.white, w - 40)
            end,
            400,
            260,
            function()
                floating = nil
            end,
            40
        )
    end
end
local menu = Menu.new(api, function(value, size)
    return #value * size * 0.5
end)
menu.visible, menu.window_width, menu.window_height = true, 1200, 850
local function compose()
    return menu.compose(1920, 1080)
end
local function input(x, y, pressed)
    menu.tick({
        down = function(key)
            return pressed and key == 1
        end,
        mouse = function()
            return x, y
        end,
        wheel = function()
            return 0
        end,
    })
end
local function close(a, b)
    return math.abs(a - b) < 0.001
end
local function body(commands, w, h)
    for _, c in ipairs(commands) do
        if c.type == 'rect' and not c.window_frame and close(c.w, w) and close(c.h, h) then
            return c
        end
    end
    error('Missing independently rendered popup body')
end
local function frame(commands, id, bounds, color, min_layer)
    local edges = {}
    for _, c in ipairs(commands) do
        if c.window_frame == id then
            assert(not edges[c.frame_edge], 'Duplicate window border: ' .. id)
            edges[c.frame_edge] = c
            assert(
                c.type == 'rect'
                    and c.x >= bounds.x - 0.001
                    and c.y >= bounds.y - 0.001
                    and c.x + c.w <= bounds.x + bounds.w + 0.001
                    and c.y + c.h <= bounds.y + bounds.h + 0.001,
                'Border extends outside its window: ' .. id
            )
            assert(
                (not color or (c.c[1] == color[1] and c.c[2] == color[2] and c.c[3] == color[3]))
                    and (c.layer or 0) >= min_layer,
                'Border color/depth mismatch: ' .. id
            )
        end
    end
    for _, edge in ipairs({ 'bottom', 'top', 'left', 'right' }) do
        assert(edges[edge], 'Missing border edge: ' .. id .. ':' .. edge)
    end
    assert(
        close(edges.bottom.x, bounds.x)
            and close(edges.bottom.y, bounds.y)
            and close(edges.bottom.w, bounds.w)
            and close(edges.bottom.h, 2),
        'Bottom border must span the window at two physical pixels'
    )
    assert(
        close(edges.top.x, bounds.x)
            and close(edges.top.y, bounds.y + bounds.h - 2)
            and close(edges.top.w, bounds.w)
            and close(edges.top.h, 2),
        'Top border does not track window size'
    )
    assert(
        close(edges.left.x, bounds.x)
            and close(edges.left.w, 2)
            and close(edges.right.x, bounds.x + bounds.w - 2)
            and close(edges.right.w, 2),
        'Side borders do not track window size'
    )
    return edges
end
local commands = compose()
frame(commands, 'main', menu.window_bounds, Menu.palette.border, 105)
local b = menu.window_bounds
input(b.x + 60, b.y + b.h - 30, true)
input(b.x + 110, b.y + b.h - 10, true)
input(b.x + 110, b.y + b.h - 10, false)
commands = compose()
assert(menu.window_bounds.x > b.x and menu.window_bounds.y > b.y, 'Main title did not drag')
frame(commands, 'main', menu.window_bounds, Menu.palette.border, 105)
b = menu.window_bounds
input(b.x + b.w - 2, b.y + b.h / 2, true)
input(b.x + b.w + 60, b.y + b.h / 2, true)
input(b.x + b.w + 60, b.y + b.h / 2, false)
commands = compose()
assert(menu.window_bounds.w > b.w, 'Main resize handle did not resize')
frame(commands, 'main', menu.window_bounds, Menu.palette.border, 105)

for _, scale in ipairs({ 0.85, 1.2 }) do
    menu.ui_scale = scale
    for _, id in ipairs({ 'quick_scratch', 'pattern_lut_editor', 'lut_editor_tools' }) do
        floating = id
        commands = compose()
        b = menu.floating_bounds
        frame(commands, 'floating:' .. id, b, Menu.palette.border, 210)
        local oldx = b.x
        input(b.x + 20, b.y + b.h - 18, true)
        input(b.x - 35, b.y + b.h - 10, true)
        input(b.x - 35, b.y + b.h - 10, false)
        commands = compose()
        assert(menu.floating_bounds.x < oldx, 'Floating window failed to move: ' .. id)
        frame(commands, 'floating:' .. id, menu.floating_bounds, Menu.palette.border, 210)
    end
end
floating = nil
menu.ui_scale = 1
commands = compose()
local label
for _, c in ipairs(commands) do
    if c.full_text == 'One' then
        label = c
    end
end
input(label.x + 3, label.y + 3, true)
input(label.x + 3, label.y + 3, false)
assert(menu.dropdown)
commands = compose()
local dropdown_body = body(commands, 240 * menu.window_bounds.scale, 70 * menu.window_bounds.scale)
frame(commands, 'dropdown', dropdown_body, Menu.palette.border, 230)
menu.key(27)

menu.color_picker = { mod = mod, control = mod.controls.color, rgb = { 255, 255, 255 } }
commands = compose()
local s = menu.window_bounds.scale
local picker_body = body(commands, 700 * s, 430 * s)
local picker_edges = frame(commands, 'color_picker', picker_body, nil, 300)
assert(picker_edges.top.c[1] == 244 and picker_edges.top.c[2] == 202, 'Picker lost its gold outline')
local picker_x = picker_body.x
input(picker_body.x + 100, picker_body.y + picker_body.h - 20, true)
input(picker_body.x + 140, picker_body.y + picker_body.h - 20, true)
input(picker_body.x + 140, picker_body.y + picker_body.h - 20, false)
commands = compose()
picker_body = body(commands, 700 * s, 430 * s)
assert(picker_body.x > picker_x, 'Picker title did not drag')
frame(commands, 'color_picker', picker_body, picker_edges.top.c, 300)
menu.color_picker = nil

menu.preview_window = {
    mod = mod,
    page = {
        render_preview = function()
            return {}
        end,
    },
    title = 'Palette Preview',
    width = 1000,
    height = 620,
    x = 200,
    y = 100,
}
commands = compose()
frame(commands, 'preview', body(commands, 1000 * s, 620 * s), Menu.palette.border, 110)
menu.preview_window = nil
for _, phase in ipairs({ 'confirm', 'scope', 'name' }) do
    menu.outfit_dialog = {
        mod = mod,
        control = mod.controls.name,
        phase = phase,
        on_save = function()
            return true
        end,
    }
    commands = compose()
    frame(commands, 'outfit_dialog', body(commands, 440 * s, 190 * s), Menu.palette.border, 400)
end
menu.outfit_dialog = nil
menu.text_edit = nil
commands = compose()
for _, c in ipairs(commands) do
    if c.full_text == 'One' then
        label = c
    end
end
input(label.x + 3, label.y + 3, false)
compose()
menu.advance(0.6)
commands = compose()
local tooltip_body
for _, c in ipairs(commands) do
    if c.type == 'rect' and not c.window_frame and c.layer == 450 and c.c == Menu.palette.panel then
        tooltip_body = c
    end
end
assert(tooltip_body, 'Guidance tooltip did not open')
frame(commands, 'tooltip', tooltip_body, nil, 450)
print(
    'PASS window frames: four two-pixel edges, main move/resize, scaled floating tools, single dropdown outline, gold picker drag, palette preview, preset dialogs and guidance tooltip'
)
