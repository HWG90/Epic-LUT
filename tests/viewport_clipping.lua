local Core = dofile('vendor/menu/core.lua')
local Menu = dofile('vendor/menu/menu.lua')
local View = dofile('vendor/menu/view.lua')
local api = Core.new()
local page = {
    id = 'clip',
    name = 'Clip',
    controls = {
        { id = 'field', type = 'input', label = 'Field', default = 'Draft' },
        { id = 'pick', type = 'choice', label = 'Pick', choices = { 'Popup one', 'Popup two' }, default = 1 },
    },
}
local handle = api.register({ id = 'viewport_fixture', name = 'Clip test', pages = { page } })
local mod = api.mods[handle.id]
mod.tabs_top = true
local menu = Menu.new(api, function(text, size)
    return #text * size * 0.5
end, dofile('src/platform/text_editor.lua'))
menu.visible, menu.epic_typography = true, true
menu.window_width, menu.window_height = 1500, 980
local function metrics(size)
    return { min_y = -0.3 * size, max_y = 1.2 * size, height = 1.5 * size }
end
menu.text_metrics = metrics
local clicks, invalid_draws = 0, 0
local outside_field, floating_mode, ordinary_open = false, false, false
local logical, captured
local colors = { panel = { 19, 21, 23 }, header = { 30, 50, 70 }, front = { 90, 30, 20 }, white = { 235, 236, 230 } }
local function draw(ui, x, y)
    logical = { x = x + 25, y = y + 60, w = 380, h = 120 }
    local b, top = logical, logical.y + logical.h
    ui.rect(b.x, b.y - 40, b.w, 220, colors.panel)
    local finish = ui.surface(130)
    ui.rect(b.x, top + 12, b.w, 48, colors.header, 1, 'control_fill')
    ui.text(b.x + 5, top + 25, 'Header', 14, colors.white)
    ui.choice('pick', b.x + 210, top + 20, 160)
    finish()
    local size = ui.text_size(14)
    local baseline_top, baseline_bottom = top - 0.45 * size, b.y - 0.45 * size
    ui.viewport(b, function()
        ui.rect(b.x, top - 6, 110, 30, colors.header, 1, 'control_fill')
        ui.text(b.x + 5, baseline_top, 'Partial top', 14, colors.white)
        ui.text(b.x + 5, baseline_bottom, 'Partial bottom', 14, colors.white)
        ui.text(b.x + 5, top + 0.31 * size, 'Fully above', 14, colors.white)
        ui.text(b.x + 5, b.y - 1.21 * size, 'Fully below', 14, colors.white)
        ui.hit(b.x, top - 6, 110, 30, function()
            clicks = clicks + 1
        end)
        ui.rect(b.x + 220, top + (outside_field and 40 or -12), 150, 34, colors.header, 1, 'control_fill')
        ui.bounded(
            b.x + 225,
            outside_field and top + 50 or baseline_top,
            ui.input_value('field'),
            14,
            colors.white,
            140
        )
    end, { top = top + 60, bottom = b.y - 40, color = colors.panel })
end
mod.pages[1].render_layout = function(ui)
    captured = ui
    if floating_mode then
        ui.floating('embedded_clip', function(x, y)
            draw(ui, x, y)
        end, 450, 280, function() end, 28)
        if ordinary_open then
            ui.floating(
                'ordinary_clip',
                function(x, y, w, h)
                    ui.rect(x, y, w, h, colors.front)
                end,
                450,
                280,
                function()
                    ordinary_open = false
                end,
                28
            )
        end
    else
        draw(ui, ui.x, ui.y)
    end
end
local world, items, next_id, allocations = {}, {}, 0, 0
local function allocate(item)
    assert(item.z == math.floor(item.z), 'Fractional viewport native layer')
    next_id, allocations = next_id + 1, allocations + 1
    item.order = next_id
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
    },
    World = {
        create_screen_gui = function()
            return {}
        end,
        destroy_gui = function() end,
    },
    Vector2 = function(x, y)
        return { x = x, y = y }
    end,
    Vector3 = function(x, y, z)
        return { x = x, y = y, z = z }
    end,
    Color = function(a, r, g, b)
        return { a = a, r = r, g = g, b = b }
    end,
    Gui = {
        rect = function(_, p, size, color)
            return allocate({ x = p.x, y = p.y, w = size.x, h = size.y, z = p.z, color = color })
        end,
        text = function(_, text, _, size, _, p, color)
            local ink = metrics(size)
            return allocate({
                x = p.x,
                y = p.y + ink.min_y,
                w = #text * size * 0.5,
                h = ink.height,
                z = p.z,
                color = color,
                text = text,
            })
        end,
        destroy_rect = function(_, id)
            items[id] = nil
        end,
        destroy_text = function(_, id)
            items[id] = nil
        end,
    },
}
local renderer = View.new(sr, true)
local function compose()
    local commands = menu.compose(1920, 1080)
    for _, c in ipairs(commands) do
        assert(not (c.text and c.text:find('Invalid custom', 1, true)), c.text)
    end
    renderer.draw(commands)
    return commands
end
local function physical()
    local wb = menu.window_bounds
    return {
        x = wb.x + logical.x * wb.scale,
        y = wb.y + logical.y * wb.scale,
        w = logical.w * wb.scale,
        h = logical.h * wb.scale,
    }
end
local function label(commands, text)
    for _, c in ipairs(commands) do
        if c.text == text or c.full_text == text then
            return c
        end
    end
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
    return assert(winner, 'Missing viewport pixel')
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
local function tap(x, y)
    input(x, y, true)
    input(x, y, false)
end
for _, scenario in ipairs({ { 12, 0.85 }, { 20, 1 }, { 20, 0.7 }, { 12, 1.15 } }) do
    menu.font_size, menu.ui_scale, menu.font_bold = scenario[1], scenario[2], true
    menu.text_edit = { mod = mod, control = mod.controls.field, text = 'Draft' }
    local commands = compose()
    local p = physical()
    local top = p.y + p.h
    local step = menu.window_bounds.scale
    local partial_top, partial_bottom =
        assert(label(commands, 'Partial top')), assert(label(commands, 'Partial bottom'))
    assert(partial_top.viewport and partial_bottom.viewport)
    assert(
        not label(commands, 'Fully above') and not label(commands, 'Fully below'),
        'Fully outside ink remained drawn'
    )
    assert(pixel(p.x + 7 * step, top - 0.5).text == 'Partial top', 'Partial upper ink vanished at viewport edge')
    assert(pixel(p.x + 7 * step, p.y + 0.5).text == 'Partial bottom', 'Partial lower ink vanished at viewport edge')
    assert(
        not pixel(p.x + 7 * step, top + 0.5).text and pixel(p.x + 7 * step, top + 0.5).color.r == 19,
        'Upper ink escaped mask'
    )
    assert(
        not pixel(p.x + 7 * step, p.y - 0.5).text and pixel(p.x + 7 * step, p.y - 0.5).color.r == 19,
        'Lower ink escaped mask'
    )
    assert(pixel(p.x + 180 * step, top + 14 * step).color.b == 70, 'Header fill was erased by viewport mask')
    assert(pixel(p.x + 7 * step, top + 27 * step).text == 'Header', 'Header text was erased by viewport mask')
    local field = assert(menu.text_edit.field_bounds)
    assert(
        field.viewport and field.y >= p.y and field.y + field.h <= top + 0.001,
        'Active field retained unclipped hit bounds'
    )
    local before = clicks
    tap(p.x + 7 * step, top + 3 * step)
    assert(clicks == before, 'Invisible control fragment consumed header clicks')
    tap(p.x + 7 * step, top - 2 * step)
    assert(clicks == before + 1, 'Visible control fragment lost its hit target')
    menu.text_edit = { mod = mod, control = mod.controls.field, text = 'Draft' }
    outside_field = true
    compose()
    assert(not menu.text_edit.field_bounds, 'Fully hidden field kept caret-selection ownership')
    outside_field = false
    commands = compose()
    local allocation_count = allocations
    compose()
    assert(allocations == allocation_count, 'Identical clipping frame recreated retained primitives')
    local pick = assert(label(commands, 'Popup one'))
    tap(pick.x + 3, pick.y + 3)
    assert(menu.dropdown, 'Clipped chrome dropdown did not open')
    commands = compose()
    assert(pixel(p.x + 225 * step, top - 1).z >= 300, 'Dropdown rendered below viewport text/masks')
    menu.key(27)
end
-- Preserve nested surface offsets within a floating window, while an ordinary
-- raised window still occupies only its original twenty-layer reservation.
menu.font_size, menu.ui_scale, floating_mode = 12, 1, true
menu.text_edit = nil
compose()
local embedded_position = menu.floating_positions.embedded_clip
menu.floating_positions.ordinary_clip = { x = embedded_position.x, y = embedded_position.y }
ordinary_open = true
local commands = compose()
local p = physical()
local embedded = assert(label(commands, 'Partial top'))
assert(embedded.paint_plane == 220 and embedded.paint_span == 20, 'Embedded viewport fell behind its owning window')
local ordinary
for _, c in ipairs(commands) do
    if c.floating_id == 'ordinary_clip' and c.ui_role == 'window_background' then
        ordinary = c
        break
    end
end
assert(
    ordinary and ordinary.paint_plane == 270 and ordinary.paint_span == 20,
    'Ordinary floating window lost bounded layering'
)
assert(pixel(p.x + 7, p.y + p.h - 1).color.r == 90, 'Raised ordinary window failed to cover embedded text')
ordinary_open = false
commands = compose()
p = physical()
local pick = assert(label(commands, 'Popup one'))
tap(pick.x + 3, pick.y + 3)
assert(menu.dropdown)
compose()
assert(pixel(p.x + 225, p.y + p.h - 1).z >= 300, 'Embedded dropdown failed to cover its expanded owning surface')
menu.key(27)
-- Reject malformed bounds before invoking an untrusted drawing callback.
for _, invalid in ipairs({
    { x = 0, y = 0, w = 1, h = 0 },
    { x = 0, y = 0, w = -1, h = 1 },
    { x = 0 / 0, y = 0, w = 1, h = 1 },
}) do
    assert(not pcall(captured.viewport, invalid, function()
        invalid_draws = invalid_draws + 1
    end, { top = 100, bottom = 0, color = colors.panel }))
end
assert(invalid_draws == 0)
renderer.release()
print(
    'PASS native viewport clipping: partial upper/lower ink, clipped rectangles/hits/fields, opaque masks, fixed chrome, retained bold/fonts/scales and nested floating/dropdown ordering'
)
