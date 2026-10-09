-- Production floating composer and retained GUI: depth wins before allocation order.
local Core, Menu, View = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua'), dofile('vendor/menu/view.lua')
local api = Core.new()
local h = api.register({
    id = 'stack',
    name = 'Window stack',
    pages = {
        {
            id = 'p',
            name = 'Main',
            controls = {
                {
                    id = 'pick',
                    type = 'choice',
                    presentation = 'dropdown',
                    label = 'Choice',
                    choices = { 'One', 'Two' },
                    default = 1,
                },
                { id = 'color', type = 'color', label = 'Color', default = '#123456' },
            },
        },
    },
})
local mod = api.mods[h.id]
mod.tabs_top = true
local specs = {
    { id = 'pattern', name = 'Pattern', w = 300, h = 280, color = { 11, 22, 33 } },
    { id = 'tools', name = 'Tools', w = 380, h = 340, color = { 44, 55, 66 } },
    { id = 'scratch', name = 'Scratch', w = 220, h = 200, color = { 77, 88, 99 } },
}
local changed, dense, extra_content = false, false, false
local dense_color, extra_color, preview_color = { 151, 61, 17 }, { 3, 9, 11 }, { 105, 17, 99 }
mod.pages[1].render_layout = function(ui)
    if extra_content then
        for i = 1, 5001 do
            ui.rect(ui.x, ui.y, 1, 1, extra_color)
        end
    end
    for _, spec in ipairs(specs) do
        ui.floating(spec.id, function(x, y, w, height)
            ui.rect(x, y, w, height, spec.color)
            if dense and spec.id == 'pattern' then
                for i = 1, 5001 do
                    ui.rect(x + 4, y + 4, 1, 1, dense_color)
                end
            end
            ui.rect(x, y + height - 40, w, 40, ui.theme.header)
            ui.bounded(x + 12, y + height - 26, spec.name .. ' title', 14, ui.theme.white, w - 48)
            ui.bounded(
                x + 100,
                y + 100,
                spec.name .. ' REAR' .. (changed and spec.id == 'pattern' and ' changed' or ''),
                14,
                ui.theme.white,
                w - 110
            )
            if spec.id == 'tools' then
                ui.choice('pick', x + 12, y + height - 92, w - 24)
                ui.button(x + 12, y + 20, w - 24, 28, 'Tools action', function() end, { help = 'Tools action help' })
                ui.button(x + 12, y + 58, w - 24, 28, 'Open picker', function()
                    ui.activate('color')
                end)
            end
        end, spec.w, spec.h, function() end, 40)
    end
end
mod.controls.color.picker_alpha = function()
    return 0.5
end
local menu = Menu.new(api, function(text, size)
    return #text * size * 0.5
end, dofile('src/platform/text_editor.lua'))
menu.visible = true
menu.window_width, menu.window_height = 1400, 960
local world, items, next_id, allocations, guis = {}, {}, 0, 0, {}
local function allocate(gui, item)
    next_id, allocations = next_id + 1, allocations + 1
    item.order, item.gui = next_id, gui
    items[next_id] = item
    return next_id
end
local sr = {
    Application = {
        worlds = function()
            return { world }
        end,
        main_world = function()
            return world
        end,
        can_get = function()
            return false
        end,
    },
    World = {
        create_screen_gui = function()
            local gui = {}
            guis[#guis + 1] = gui
            return gui
        end,
        destroy_gui = function(_, gui)
            for id, item in pairs(items) do
                if item.gui == gui then
                    items[id] = nil
                end
            end
        end,
    },
    Vector3 = function(x, y, z)
        return { x = x, y = y, z = z }
    end,
    Vector2 = function(x, y)
        return { x = x, y = y }
    end,
    Color = function(a, r, g, b)
        return { a = a, r = r, g = g, b = b }
    end,
    Gui = {
        resolution = function()
            return 1920, 1080
        end,
        rect = function(gui, pos, size, color)
            return allocate(gui, { x = pos.x, y = pos.y, z = pos.z, w = size.x, h = size.y, color = color })
        end,
        text = function(gui, label, _, size, _, pos, color)
            return allocate(
                gui,
                { x = pos.x, y = pos.y, z = pos.z, w = #label * size * 0.5, h = size, color = color, text = label }
            )
        end,
        destroy_rect = function(gui, id)
            assert(not items[id] or items[id].gui == gui, 'Rect was destroyed through a different GUI')
            items[id] = nil
        end,
        destroy_text = function(gui, id)
            assert(not items[id] or items[id].gui == gui, 'Text was destroyed through a different GUI')
            items[id] = nil
        end,
    },
}
local view = View.new(sr)
local function compose()
    local commands = menu.compose(1920, 1080)
    view.draw(commands)
    return commands
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
    }, 0)
end
local function tap(x, y)
    input(x, y, true)
    input(x, y, false)
end
local function label(commands, wanted, owner)
    for _, c in ipairs(commands) do
        if (c.full_text or c.text) == wanted and (owner == nil or c.floating_id == owner) then
            return c
        end
    end
    error('Missing window label: ' .. wanted)
end
local function pixel(x, y)
    local winner
    for _, item in pairs(items) do
        if
            x >= item.x
            and x < item.x + item.w
            and y >= item.y
            and y < item.y + item.h
            and (not winner or item.z > winner.z or item.z == winner.z and item.order > winner.order)
        then
            winner = item
        end
    end
    return assert(winner, 'No native primitive at sampled window pixel')
end
local function body_wins(x, y, color, why)
    local item = pixel(x, y)
    assert(
        not item.text and item.color.r == color[1] and item.color.g == color[2] and item.color.b == color[3],
        why .. '; actual=' .. tostring(item.text or item.color.r)
    )
end
compose()
menu.floating_positions.pattern = { x = 260, y = 240 }
menu.floating_positions.tools = { x = 300, y = 220 }
menu.floating_positions.scratch = { x = 760, y = 250 }
local commands = compose()
local rear = label(commands, 'Pattern REAR', 'pattern')
body_wins(rear.x + 2, rear.y + 2, specs[2].color, 'Rear Pattern text crossed foreground Tools body')
-- Recreating only rear text must not defeat the retained front background.
changed = true
commands = compose()
rear = label(commands, 'Pattern REAR changed', 'pattern')
body_wins(rear.x + 2, rear.y + 2, specs[2].color, 'New rear text allocation defeated retained Tools background')
-- Clicking an exposed rear title raises that window; dragging preserves order.
tap(280, 505)
commands = compose()
assert(menu.floating_bounds.id == 'pattern', 'Exposed Pattern title did not raise its window')
local tools_text = label(commands, 'Tools REAR', 'tools')
body_wins(tools_text.x + 2, tools_text.y + 2, specs[1].color, 'Raised Pattern body failed to occlude Tools text')
local title = label(commands, 'Pattern title', 'pattern')
input(title.x + 8, title.y + 3, true)
input(title.x + 28, title.y + 13, true)
input(title.x + 28, title.y + 13, false)
commands = compose()
assert(menu.floating_bounds.id == 'pattern', 'Dragging a window lost its foreground order')
menu.floating_positions.scratch = { x = 280, y = 210 }
compose()
tap(290, 220)
commands = compose()
assert(menu.floating_bounds.id == 'scratch', 'Exposed Scratch background did not raise its window')
tools_text = label(commands, 'Tools REAR', 'tools')
body_wins(
    tools_text.x + #tools_text.text * tools_text.size * 0.5 - 2,
    tools_text.y + 2,
    specs[3].color,
    'Raised Scratch body failed to occlude Tools text'
)
-- Raise Tools via its exposed header, then open its owned dropdown.
tap(650, 545)
commands = compose()
assert(menu.floating_bounds.id == 'tools', 'Tools header did not regain foreground order')
local choice = label(commands, 'One', 'tools')
local accent
for _, c in ipairs(commands) do
    if
        c.floating_id == 'tools'
        and c.type == 'rect'
        and c.w == 2 * menu.window_bounds.scale
        and c.h == 26 * menu.window_bounds.scale
        and c.c == Menu.palette.focus
    then
        accent = c
    end
end
assert(accent, 'Missing retained choice accent')
local retained_accent = pixel(accent.x + accent.w / 2, accent.y + accent.h / 2)
input(choice.x + 3, choice.y + 3, false)
commands = compose()
assert(
    pixel(accent.x + accent.w / 2, accent.y + accent.h / 2) == retained_accent,
    'Choice hover background covered/recreated its retained accent'
)
tap(choice.x + 3, choice.y + 3)
commands = compose()
assert(menu.dropdown and menu.dropdown.owner.id == 'tools', 'Dropdown lost its floating owner')
local second
for _, c in ipairs(commands) do
    if c.text == 'Two' and c.popup and not c.floating_id then
        second = c
    end
end
assert(second, 'Missing dropdown overlay row')
assert(pixel(second.x + 2, second.y + 2).text == 'Two', 'Dropdown text was behind floating windows')
input(second.x + 2, second.y + 2, false)
commands = compose()
assert(pixel(second.x + 2, second.y + 2).text == 'Two', 'Recreated dropdown hover row covered its retained text')
menu.dropdown = nil
commands = compose()
local action = label(commands, 'Tools action', 'tools')
input(action.x + 3, action.y + 3, false)
compose()
menu.advance(0.6)
commands = compose()
local tooltip = label(commands, 'Tools action help')
assert(pixel(tooltip.x + 2, tooltip.y + 2).text == 'Tools action help', 'Tooltip text was behind popup surfaces')
-- A context color picker must cover every independent tool window.
input(0, 0, false)
compose()
local picker = label(compose(), 'Open picker', 'tools')
tap(picker.x + 3, picker.y + 3)
commands = compose()
assert(menu.color_picker, 'Context picker did not open')
local hex = label(commands, 'HEX')
assert(pixel(hex.x + 2, hex.y + 2).text == 'HEX', 'Context picker text was behind independent windows')
local markers = {}
local s = menu.window_bounds.scale
for _, c in ipairs(commands) do
    if
        c.type == 'rect'
        and c.c == Menu.palette.white
        and (c.w == 6 * s and c.h == 6 * s or c.w == 31 * s and c.h == 3 * s or c.w == 20 * s and c.h == 2 * s)
    then
        markers[#markers + 1] = c
    end
end
assert(#markers == 3, 'Missing hue/value/alpha picker markers')
local function assert_marker(c)
    local item = pixel(c.x + c.w / 2, c.y + c.h / 2)
    assert(
        item.color.r == c.c[1] and item.color.g == c.c[2] and item.color.b == c.c[3],
        'Picker gradient covered its marker'
    )
end
for _, c in ipairs(markers) do
    assert_marker(c)
end
-- Change gradient RGB while leaving its marker positions unchanged. Existing
-- marker IDs are older than newly allocated gradient cells.
menu.color_picker.rgb = { 105, 125, 145 }
menu.color_picker.brightness = math.min(0.9, menu.color_picker.brightness + 0.1)
commands = compose()
markers = {}
for _, c in ipairs(commands) do
    if
        c.type == 'rect'
        and c.c == Menu.palette.white
        and (c.w == 6 * s and c.h == 6 * s or c.w == 31 * s and c.h == 3 * s or c.w == 20 * s and c.h == 2 * s)
    then
        markers[#markers + 1] = c
    end
end
for _, c in ipairs(markers) do
    assert_marker(c)
end
hex = label(commands, 'HEX')
tap(hex.x + 60 * s, hex.y + 3)
commands = compose()
assert(menu.text_edit and menu.text_edit.color_channel == 'hex', 'HEX field did not open actual text editor')
local field, selection, caret
for _, c in ipairs(commands) do
    if c.ui_role == 'text_field' then
        field = c
    elseif c.ui_role == 'text_selection' then
        selection = c
    elseif c.ui_role == 'text_caret' then
        caret = c
    end
end
assert(field and selection and caret, 'Missing text selection/caret planes')
assert(pixel(field.x + 2, field.y + 2).text == field.text, 'Selection fill covered text glyphs')
local selected = pixel(selection.x + selection.w / 2, selection.y + 0.2)
assert(
    selected.color.r == selection.c[1] and selected.color.g == selection.c[2] and selected.color.b == selection.c[3],
    'Text selection is behind its field background'
)
local cursor = pixel(caret.x + caret.w / 2, caret.y + 0.2)
assert(
    cursor.color.r == caret.c[1] and cursor.color.g == caret.c[2] and cursor.color.b == caret.c[3],
    'Text caret is behind background/selection'
)
local stable = allocations
view.draw(commands)
assert(allocations == stable, 'Unchanged window stack reallocated retained primitives')
menu.close_color(false)
-- Dense producers must remain within their surface's range. An unrelated
-- 5,001-command page/preview cannot change floating-window depth.
input(0, 0, false)
commands = compose()
local tool = label(commands, 'Tools REAR', 'tools')
local depth = pixel(tool.x + 2, tool.y + 2).z
dense = true
commands = compose()
local plane, span, count
count = 0
for _, c in ipairs(commands) do
    if c.c == dense_color then
        count = count + 1
        assert(c.paint_plane and c.paint_span, 'Dense window lost its paint range')
        plane, span = c.paint_plane, c.paint_span
    end
end
assert(count == 5001, 'Dense floating producer did not emit its full command set')
for _, item in pairs(items) do
    if item.color.r == dense_color[1] and item.color.g == dense_color[2] and item.color.b == dense_color[3] then
        assert(item.z >= plane and item.z < plane + span, 'Dense floating commands escaped their own range')
    end
end
assert(pixel(tool.x + 2, tool.y + 2).z == depth, 'Dense rear window changed foreground text depth')
extra_content = true
mod.pages[1].render_preview = function(bounds)
    local result = {}
    for i = 1, 5001 do
        result[i] = { type = 'rect', x = bounds.x, y = bounds.y, w = 1, h = 1, a = 1, c = preview_color }
    end
    return result
end
menu.preview_window =
    { mod = mod, page = mod.pages[1], x = 20, y = 20, width = 420, height = 450, title = 'Dense preview' }
commands = compose()
count = 0
for _, c in ipairs(commands) do
    if c.c == preview_color then
        count = count + 1
        plane, span = c.paint_plane, c.paint_span
    end
end
assert(count == 5001 and plane and span, 'Dense preview lost its bounded surface')
for _, item in pairs(items) do
    if item.color.r == preview_color[1] and item.color.g == preview_color[2] and item.color.b == preview_color[3] then
        assert(item.z >= plane and item.z < plane + span, 'Dense preview escaped into floating/overlay ranges')
    end
end
assert(pixel(tool.x + 2, tool.y + 2).z == depth, 'Unrelated page/preview commands changed floating depth')
menu.visible = false
compose()
assert(next(items) == nil, 'Closing menu retained native popup primitives')
-- Plain rect/text commands with a preview role must allocate and retire in
-- their role GUI, not allocate in the base GUI and destroy through another.
local role_view = View.new(sr, true)
local role_commands = {
    { type = 'rect', x = 1100, y = 1000, w = 20, h = 20, a = 1, c = { 123, 65, 17 }, preview_role = 'owned_role' },
    {
        type = 'text',
        x = 1100,
        y = 1023,
        text = 'OWNED ROLE',
        size = 12,
        a = 1,
        c = { 255, 255, 255 },
        preview_role = 'owned_role',
    },
}
role_view.draw(role_commands)
local role_gui = guis[#guis]
local old_rect
for id, item in pairs(items) do
    assert(item.gui == role_gui, 'Role primitive allocated in base GUI')
    if not item.text then
        old_rect = id
    end
end
assert(old_rect, 'Role rect was not created')
role_commands[1].c = { 124, 65, 17 }
role_view.draw(role_commands)
assert(not items[old_rect], 'Recreated role rect leaked its old primitive')
role_view.release()
assert(next(items) == nil, 'Role GUI retirement left native primitives')
print(
    'PASS native window ordering: independent surfaces, retained accents/markers/text planes, dense range bounds, unchanged depth, focus/drag overlays and correct GUI ownership'
)
