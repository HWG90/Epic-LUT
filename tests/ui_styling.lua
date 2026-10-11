-- Theme source: DBF-MCM src/ui/theme.lua, inspected 2026-10-09.
-- Source SHA256: 7179FAEB1F3122E575BA3FD1F638589B87C14093384A6723BFB6E8F8644F3A82.
-- The owning MCM checkout may have uncommitted work, so compare current bytes
-- when it exists, with the recorded palette contract for standalone/CI runs.
local Menu = dofile('vendor/menu/menu.lua')
local expected = {
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
    field = { 29, 39, 47 },
    field_hover = { 40, 55, 65 },
    enabled = { 118, 207, 177 },
    disabled = { 111, 124, 133 },
}
local function same(a, b)
    return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end
local reference = '../DBF-MCM/src/ui/theme.lua'
local file = io.open(reference, 'rb')
if file then
    file:close()
    expected = dofile(reference).palette
end
for key, color in pairs(expected) do
    assert(same(Menu.palette[key], color), 'MCM palette drift: ' .. key)
end

local Core = dofile('vendor/menu/core.lua')
local writes, clicks = 0, {}
local api = Core.new({
    load = function()
        return {}
    end,
    save = function()
        writes = writes + 1
        return true
    end,
})
local state = { armor = {}, helmet = {}, palette_count = 0, status = 'Ready', time = 0, load_seen = false }
local view = dofile('src/editor/import_view.lua').new(function()
    return state
end, nil, nil, Core)
local controls = {}
for _, id in ipairs({
    'populate_worn',
    'stop_identify',
    'browse',
    'save_palette',
    'apply_file_armor',
    'apply_file_helmet',
    'preserve_emissives',
    'restore',
    'restore_imported',
    'global_undo',
    'global_redo',
    'save_setup',
}) do
    local key = id
    controls[#controls + 1] = {
        id = id,
        type = 'button',
        label = id,
        on_activate = function()
            clicks[key] = (clicks[key] or 0) + 1
            return true
        end,
    }
end
local h = api.register({
    id = 'style',
    name = 'Epic LUT',
    pages = {
        { id = 'import', name = 'Import', controls = controls },
        {
            id = 'surfaces',
            name = 'Surfaces',
            controls = {
                { id = 'style_color', type = 'color', label = 'Color', default = '#FFFFFF' },
            },
        },
    },
})
local mod = api.mods[h.id]
mod.tabs_top = true
mod.pages[2].tab_color = { 110, 69, 155 }
mod.pages[1].render_layout = view.draw
mod.pages[2].render_layout = function(ui)
    -- A color helper used as the final rect argument must not leak a second
    -- boolean return into renderer opacity when the pointer enters the surface.
    ui.rect(ui.x + 10, ui.y + 100, 220, 32, ui.surface_color(ui.x + 10, ui.y + 100, 220, 32))
    ui.button(ui.x + 10, ui.y + 100, 220, 32, 'Action', function()
        clicks.action = (clicks.action or 0) + 1
    end)
    ui.button(ui.x + 10, ui.y + 60, 220, 32, 'Unavailable', function()
        error('Disabled action ran')
    end, { enabled = false })
    ui.button(ui.x + 250, ui.y + 100, 220, 32, 'Selected', function() end, { selected = true })
    ui.button(ui.x + 250, ui.y + 60, 220, 32, 'Export', function()
        clicks.export = (clicks.export or 0) + 1
    end, { accent = { 244, 202, 53 }, ink = { 25, 28, 31 } })
    ui.button(ui.x + 10, ui.y + 20, 220, 32, 'Field input', function()
        clicks.field = (clicks.field or 0) + 1
    end, { field = true })
end
local menu = Menu.new(api, function(text, size)
    return #text * size * 0.5
end)
menu.visible = true
local function compose()
    return menu.compose(1920, 1080)
end
local function button(commands, label)
    for i, c in ipairs(commands) do
        if c.full_text == label then
            for j = i - 1, 1, -1 do
                local body = commands[j]
                if
                    body.type == 'rect'
                    and body.ui_role == 'control_fill'
                    and body.x <= c.x
                    and body.x + body.w >= c.x
                    and body.y <= c.y
                    and body.y + body.h >= c.y
                then
                    return body, c
                end
            end
        end
    end
    error('Missing composed control: ' .. label)
end
local function input(rect, down)
    menu.tick({
        down = function(key)
            return down and key == 1
        end,
        mouse = function()
            return rect.x + rect.w / 2, rect.y + rect.h / 2
        end,
        wheel = function()
            return 0
        end,
    })
end
local function tap(rect)
    input(rect, true)
    input(rect, false)
end

local commands = compose()
local load = button(commands, 'Load Current Gear')
local scratch = button(commands, 'Quick Scratch')
assert(load.x + load.w <= scratch.x or scratch.y + scratch.h < load.y, 'Import toolbar collision returned')
local before = writes
input(scratch, false)
local hovered = button(compose(), 'Quick Scratch')
assert(
    same(hovered.c, Menu.palette.field_hover) and writes == before,
    'Custom Import action has no passive hover feedback'
)
tap(load)
assert(clicks.populate_worn == 1 and not view.scratch_open, 'Load hit was intercepted by Quick Scratch')
local unavailable = button(compose(), 'Send to LUT Editor')
tap(unavailable)
assert(not clicks.save_palette, 'Empty Import workspace submitted a nonexistent table')

menu.page = 2
commands = compose()
local action = button(commands, 'Action')
assert(same(action.c, Menu.palette.field), 'Action does not use the MCM value surface')
input(action, false)
commands = compose()
assert(same(button(commands, 'Action').c, Menu.palette.field_hover) and writes == before, 'Hover publishes settings')
for _, command in ipairs(commands) do
    assert(type(command.a) == 'number', 'Surface hover leaked a boolean into renderer opacity')
end
tap(action)
assert(clicks.action == 1, 'Styled custom button changed its callback routing')
local disabled, text = button(compose(), 'Unavailable')
assert(
    same(disabled.c, Menu.palette.panel) and same(text.c, Menu.palette.disabled),
    'Disabled custom control is not gray'
)
tap(disabled)
assert(same(button(compose(), 'Selected').c, Menu.palette.selected), 'Selected custom tab lost its state feedback')
local export, export_text = button(compose(), 'Export')
assert(same(export.c, { 244, 202, 53 }) and same(export_text.c, { 25, 28, 31 }), 'Semantic Export accent changed')
input(export, false)
assert(same(button(compose(), 'Export').c, { 244, 202, 53 }), 'Hover removed the Export accent')
tap(export)
assert(clicks.export == 1, 'Export accent blocks pointer activation')
menu.color_picker = { mod = mod, control = mod.controls.style_color, rgb = { 255, 255, 255 } }
input(action, false)
assert(same(button(compose(), 'Action').c, Menu.palette.field), 'Covered action reacts through a modal picker')
menu.color_picker = nil
for _, font in ipairs({ 12, 20 }) do
    menu.compact_fonts, menu.font_size = true, font
    local rect, label = button(compose(), 'Action')
    assert(label.y >= rect.y and label.y + label.size <= rect.y + rect.h, 'Styled label clips after font resize')
end

-- Epic uses a visibly distinct skin while the legacy checks above continue to
-- enforce the shared MCM colors and original button behavior.
menu.epic_typography, menu.font_size, menu.page = true, 12, 2
local function border(commands, fill)
    for _, c in ipairs(commands) do
        if
            c.ui_role == 'control_border'
            and math.abs(c.x - fill.x) < 0.01
            and math.abs(c.y - fill.y) < 0.01
            and math.abs(c.w - fill.w) < 0.01
            and math.abs(c.h - 2) < 0.01
        then
            return c
        end
    end
    error('Missing retained two-pixel outline')
end
local function find_text(commands, text)
    for _, c in ipairs(commands) do
        if c.full_text == text then
            return c
        end
    end
    error('Missing styled text: ' .. text)
end
for _, scale in ipairs({ 0.85, 1.3 }) do
    menu.ui_scale = scale
    menu.pointer_x, menu.pointer_y = nil, nil
    commands = compose()
    local action, action_text = button(commands, 'Action')
    assert(same(action.c, Menu.epic_palette.panel), 'Epic secondary action retained a large blue fill')
    assert(same(border(commands, action).c, Menu.epic_palette.border), 'Quiet action outline missing')
    assert(not action_text.bold and same(action_text.c, Menu.epic_palette.white), 'Epic body weight/ink changed')
    local fields = button(commands, 'Field input')
    assert(
        same(fields.c, Menu.epic_palette.field) and not same(fields.c, action.c),
        'Editable field lost its recognizable fill'
    )
    input(action, false)
    local old_writes = writes
    commands = compose()
    local hovered = button(commands, 'Action')
    assert(
        same(hovered.c, Menu.epic_palette.hover) and same(border(commands, hovered).c, Menu.epic_palette.border_hover),
        'Epic hover did not subtly brighten its outline'
    )
    assert(writes == old_writes, 'Epic hover wrote settings')
    tap(hovered)
    local selected = button(compose(), 'Selected')
    assert(
        same(selected.c, Menu.epic_palette.selected) and same(border(compose(), selected).c, Menu.epic_palette.focus),
        'Selected control lost its warm gold tint/outline'
    )
    local primary, ink = button(compose(), 'Export')
    assert(
        same(primary.c, Menu.epic_palette.focus) and same(ink.c, { 25, 28, 31 }),
        'Primary action lost its gold fill'
    )
    tap(primary)
    tap(fields)
    commands = compose()
    local import_tab, selected_tab = find_text(commands, 'Import'), find_text(commands, 'Surfaces')
    assert(
        same(import_tab.c, Menu.epic_palette.muted) and same(selected_tab.c, Menu.epic_palette.white),
        'Segmented tab ink does not distinguish active navigation'
    )
    local underline = false
    local b = menu.window_bounds
    for _, c in ipairs(commands) do
        assert(not same(c.c, { 110, 69, 155 }), 'Configuration-style purple fill leaked into the Epic tab strip')
        if
            c.ui_role == 'control_accent'
            and same(c.c, Menu.epic_palette.focus)
            and math.abs(c.h - 2) < 0.01
            and c.x <= selected_tab.x
            and c.x + c.w >= selected_tab.x
            and math.abs(c.y - (b.y + (menu.window_height - 120) * b.scale)) < 0.01
        then
            underline = true
        end
        assert(type(c.a) == 'number', 'Epic skin changed opacity type')
    end
    assert(underline, 'Selected navigation segment has no two-pixel gold underline')
    -- Modal coverage suppresses both fill and outline hover without losing clicks.
    menu.color_picker = { mod = mod, control = mod.controls.style_color, rgb = { 255, 255, 255 } }
    input(action, false)
    commands = compose()
    local covered = button(commands, 'Action')
    assert(
        same(covered.c, Menu.epic_palette.panel) and same(border(commands, covered).c, Menu.epic_palette.border),
        'Covered Epic outline responds through a picker'
    )
    menu.color_picker = nil
end
assert(clicks.action == 3 and clicks.export == 3 and clicks.field == 2, 'Epic skin changed existing action callbacks')
-- Exercise the unchanged native renderer: the retained outline must sit above
-- its parent surface while the inset fill and text keep their original order.
commands = compose()
local filled, ink = button(commands, 'Action')
local outlined = border(commands, filled)
local selected_body = button(commands, 'Selected')
local primary_body = button(commands, 'Export')
local edges = 0
for _, c in ipairs(commands) do
    if
        c.ui_role == 'control_border'
        and c.x >= selected_body.x
        and c.y >= selected_body.y
        and c.x + c.w <= selected_body.x + selected_body.w + 0.01
        and c.y + c.h <= selected_body.y + selected_body.h + 0.01
    then
        edges = edges + 1
        local cx, cy = selected_body.x + selected_body.w / 2, selected_body.y + selected_body.h / 2
        assert(
            not (c.x <= cx and c.x + c.w >= cx and c.y <= cy and c.y + c.h >= cy),
            'Gold outline covers the selected control interior'
        )
    end
end
assert(edges == 4, 'Selected outline must consist of exactly four narrow border strips')
local world, gui, rendered, next_id = {}, {}, {}, 0
local function allocate(kind, position, dimensions, color)
    assert(position.z == math.floor(position.z), 'Native GUI received a fractional draw layer')
    next_id = next_id + 1
    rendered[#rendered + 1] = { kind = kind, position = position, dimensions = dimensions, color = color }
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
            return gui
        end,
        destroy_gui = function() end,
    },
    Vector3 = function(x, y, z)
        return { x = x, y = y, z = z }
    end,
    Vector2 = function(x, y)
        return { x = x, y = y }
    end,
    Color = function(a, r, g, b)
        return { a, r, g, b }
    end,
    Gui = {
        resolution = function()
            return 1920, 1080
        end,
        rect = function(_, position, dimensions, color)
            return allocate('rect', position, dimensions, color)
        end,
        text = function(_, _, _, _, _, position)
            return allocate('text', position)
        end,
        destroy_rect = function() end,
        destroy_text = function() end,
    },
}
dofile('vendor/menu/view.lua').new(sr, true).draw(commands)
local function native_depth(command)
    local depth
    for _, primitive in ipairs(rendered) do
        local p, d = primitive.position, primitive.dimensions
        if
            primitive.kind == command.type
            and math.abs(p.x - command.x) < 0.01
            and math.abs(p.y - command.y) < 0.01
            and (command.type == 'text' or primitive.color[2] == command.c[1] and primitive.color[3] == command.c[2] and primitive.color[4] == command.c[3])
            and (command.type == 'text' or math.abs(d.x - command.w) < 0.01 and math.abs(d.y - command.h) < 0.01)
        then
            depth = math.max(depth or p.z, p.z)
        end
    end
    return assert(depth, 'Styled command did not reach the native renderer')
end
assert(
    native_depth(filled) == 110 and native_depth(outlined) == 111,
    'Main body/outline no longer occupy distinct integer draw layers'
)
assert(
    native_depth(filled) < 119 and native_depth(filled) < native_depth(ink),
    'Styled fill covered field selection or text'
)
local function interior(body)
    local x, y = body.x + body.w / 2, body.y + body.h / 2
    local top
    for _, primitive in ipairs(rendered) do
        local p, d = primitive.position, primitive.dimensions
        if
            primitive.kind == 'rect'
            and p.x <= x
            and p.x + d.x >= x
            and p.y <= y
            and p.y + d.y >= y
            and (not top or p.z >= top.position.z)
        then
            top = primitive
        end
    end
    assert(top)
    return { top.color[2], top.color[3], top.color[4] }
end
assert(
    same(interior(selected_body), Menu.epic_palette.selected),
    'Integer native sorting replaced selected dark RGB with its gold outline'
)
assert(
    same(interior(primary_body), Menu.epic_palette.focus),
    'Integer native sorting erased the primary action gold fill'
)
print(
    'PASS custom UI styling: unchanged MCM palette/legacy behavior, Epic neutral surfaces, retained two-pixel outlines, hover/modal feedback, gold selection/primary/nav accents and callback parity'
)
