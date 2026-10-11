-- Actual Menu ownership and selection for a per-LUT preset application modal.
local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local api = Core.new()
local background_applies, applied, apply_attempts = 0, {}, 0
local handle = api.register({
    id = 'lut_dialog_test',
    name = 'Epic LUT',
    pages = {
        {
            id = 'basic',
            name = 'Basic',
            require_confirmation = false,
            controls = {
                {
                    id = 'background_apply',
                    type = 'button',
                    label = 'Background Apply',
                    on_activate = function()
                        background_applies = background_applies + 1
                    end,
                },
            },
        },
    },
})
api.mods[handle.id].tabs_top = true
local menu = Menu.new(api, function(value, size)
    return #value * size * 0.5
end, dofile('src/platform/text_editor.lua'))
menu.visible, menu.epic_typography = true, true
menu.window_width, menu.window_height = 1500, 1000
api.mods[handle.id].pages[1].render_layout = function(ui)
    ui.button(ui.x + 8, ui.y + 8, 170, 30, 'Background Apply', function()
        handle.activate('background_apply')
    end)
end
local resolution = { 1920, 1080 }
local function compose()
    local commands = menu.compose(unpack(resolution))
    for _, c in ipairs(commands) do
        assert(not (c.text and c.text:find('attempt to ', 1, true)), c.text)
    end
    return commands
end
local function label(value, popup)
    for _, c in ipairs(compose()) do
        if (c.full_text or c.text) == value and (popup == nil or (c.popup == true) == popup) then
            return c
        end
    end
end
local function input(x, y, down, wheel)
    menu.tick({
        down = function(key)
            return down and key == 1
        end,
        mouse = function()
            return x, y
        end,
        wheel = function()
            return wheel or 0
        end,
    })
end
local function click(c)
    input(c.x + 2, c.y + 2, true)
    input(c.x + 2, c.y + 2, false)
end
local function descriptor()
    return {
        title = 'Apply Preset LUTs',
        columns = {
            {
                title = 'Armor / Cape',
                items = {
                    {
                        id = 'armor1',
                        label = 'Armor LUT 1',
                        enabled = true,
                        checked = true,
                        detail = 'Pattern included',
                    },
                    { id = 'cape1', label = 'Cape LUT 1', enabled = true, checked = true },
                    { id = 'armor_unavailable', label = 'Unavailable Armor LUT', enabled = false, checked = false },
                },
            },
            {
                title = 'Helmet',
                items = {
                    {
                        id = 'helmet1',
                        label = 'Helmet LUT 1',
                        enabled = true,
                        checked = true,
                        detail = 'Pattern included',
                    },
                },
            },
        },
        on_apply = function(selected)
            apply_attempts = apply_attempts + 1
            local snapshot = {}
            for id, value in pairs(selected) do
                snapshot[id] = value
            end
            applied[#applied + 1] = snapshot
            return true, 'Selected LUTs applied'
        end,
    }
end
local function open(dialog)
    menu.lut_apply_dialog = dialog or descriptor()
    compose()
    return menu.lut_apply_dialog
end
local function checked(dialog, id)
    for _, column in ipairs(dialog.columns) do
        for _, item in ipairs(column.items) do
            if item.id == id then
                return item.checked
            end
        end
    end
end
local dialog = open()
assert(label('Armor / Cape', true) and label('Helmet', true), 'Per-LUT preset modal did not show its two gear columns')
assert(label('Pattern included', true), 'Associated Pattern was omitted from the preset row information')
local before = apply_attempts
click(assert(label('Unavailable Armor LUT', true)))
assert(
    not checked(dialog, 'armor_unavailable') and apply_attempts == before,
    'Unavailable LUT row could be selected or applied'
)
click(assert(label('Clear All', true)))
for _, id in ipairs({ 'armor1', 'cape1', 'helmet1' }) do
    assert(not checked(dialog, id), 'Clear All left an enabled LUT selected')
end
click(assert(label('Apply', true)))
assert(menu.lut_apply_dialog == dialog and apply_attempts == before, 'Empty per-LUT selection invoked Apply')
menu.key(13)
assert(menu.lut_apply_dialog == dialog and apply_attempts == before, 'Empty per-LUT Enter invoked Apply')
click(assert(label('Select All', true)))
assert(
    checked(dialog, 'armor1')
        and checked(dialog, 'cape1')
        and checked(dialog, 'helmet1')
        and not checked(dialog, 'armor_unavailable'),
    'Select All did not include exactly the enabled material LUTs'
)
click(assert(label('Cape LUT 1', true)))
assert(
    not checked(dialog, 'cape1') and checked(dialog, 'armor1') and checked(dialog, 'helmet1'),
    'LUT checkbox changed another row'
)
click(assert(label('Apply', true)))
assert(not menu.lut_apply_dialog and apply_attempts == before + 1, 'Nonempty per-LUT Apply did not finish once')
assert(
    applied[#applied].armor1 == true
        and applied[#applied].helmet1 == true
        and not applied[#applied].cape1
        and not applied[#applied].armor_unavailable,
    'Per-LUT Apply lost its exact selected-ID mask'
)
for id in pairs(applied[#applied]) do
    assert(
        id == 'armor1' or id == 'cape1' or id == 'helmet1' or id == 'armor_unavailable',
        'Pattern detail became an optional selection ID'
    )
end
dialog = open()
click(assert(label('Cancel', true)))
assert(not menu.lut_apply_dialog and apply_attempts == before + 1, 'Per-LUT Cancel applied a preset')
dialog = open()
click(assert(label('Background Apply', false)))
assert(
    background_applies == 0 and menu.lut_apply_dialog == dialog,
    'Modal clicks leaked into the Basic page underneath'
)
menu.key(40)
assert(
    background_applies == 0 and menu.lut_apply_dialog == dialog,
    'Modal keyboard navigation changed the underlying Basic page'
)
menu.key(27)
assert(
    not menu.lut_apply_dialog and menu.visible and apply_attempts == before + 1,
    'Per-LUT Escape applied or closed the main editor'
)
dialog = descriptor()
dialog.on_apply = function()
    apply_attempts = apply_attempts + 1
    error('Gear changed; choose the preset again')
end
open(dialog)
click(assert(label('Apply', true)))
assert(
    menu.lut_apply_dialog == dialog and checked(dialog, 'armor1') and checked(dialog, 'helmet1'),
    'Failed/stale per-LUT application dismissed the dialog or lost the selection'
)
assert(
    dialog.error:find('Gear changed; choose the preset again', 1, true) and label(dialog.error, true),
    'Per-LUT stale application error was not shown inside the dialog'
)
click(assert(label('Cancel', true)))
assert(not menu.lut_apply_dialog, 'Per-LUT application error prevented Cancel')
dialog = descriptor()
dialog.on_apply = function()
    return false, 'Current LUT family is unavailable'
end
open(dialog)
click(assert(label('Apply', true)))
assert(
    menu.lut_apply_dialog == dialog and label('Current LUT family is unavailable', true),
    'Explicitly refused per-LUT Apply was reported as successful'
)
menu.key(27)
local NativeView = dofile('vendor/menu/view.lua')
local items, next_id = {}, 0
local function allocate(item)
    next_id = next_id + 1
    item.order = next_id
    assert(item.z == math.floor(item.z), 'Per-LUT modal emitted a fractional native layer')
    items[next_id] = item
    return next_id
end
local function metrics(size)
    return { min_y = -0.2 * size, max_y = 0.85 * size, height = 1.05 * size }
end
local world = {}
local renderer = NativeView.new({
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
        text = function(_, value, _, size, _, p, color)
            local m = metrics(size)
            return allocate({
                x = p.x,
                y = p.y + m.min_y,
                w = #value * size * 0.5,
                h = m.height,
                z = p.z,
                color = color,
                text = value,
            })
        end,
        destroy_rect = function(_, id)
            items[id] = nil
        end,
        destroy_text = function(_, id)
            items[id] = nil
        end,
    },
}, true)
local function pixel(x, y)
    local result
    for _, item in pairs(items) do
        if
            x >= item.x
            and x < item.x + item.w
            and y >= item.y
            and y < item.y + item.h
            and (not result or item.z > result.z or item.z == result.z and item.order > result.order)
        then
            result = item
        end
    end
    return assert(result, 'Per-LUT native modal pixel is missing')
end
local function square(commands, row, checked)
    local s = menu.window_bounds.scale
    local cx, cy = row.x - 20 * s, row.y + 0.325 * row.size
    local frame
    for _, c in ipairs(commands) do
        if
            c.popup
            and c.type == 'rect'
            and c.ui_role == 'control_fill'
            and math.abs(c.x + c.w / 2 - cx) < 0.01
            and math.abs(c.y + c.h / 2 - cy) < 0.01
            and math.abs(c.w - c.h) < 0.01
        then
            frame = c
        end
    end
    assert(frame and math.abs(frame.w / s - 22) < 0.01, 'Per-LUT checkbox square is not beside its row label')
    local ticks = {}
    for _, c in ipairs(commands) do
        if
            c.popup
            and c.type == 'rect'
            and c.ui_role == 'control_icon'
            and c.x > frame.x
            and c.y > frame.y
            and c.x + c.w < frame.x + frame.w
            and c.y + c.h < frame.y + frame.h
        then
            ticks[#ticks + 1] = c
        end
    end
    assert((#ticks > 0) == checked, 'Per-LUT checkbox visual differs from enabled selection')
    renderer.draw(commands)
    assert(pixel(row.x + row.size * 0.1, row.y + row.size * 0.3).text == row.text, 'Per-LUT native row label is hidden')
    for _, tick in ipairs(ticks) do
        local p = pixel(tick.x + tick.w / 2, tick.y + tick.h / 2)
        assert(
            not p.text and p.color.r == tick.c[1] and p.color.g == tick.c[2] and p.color.b == tick.c[3],
            'Per-LUT native check mark is covered'
        )
    end
    return { x = cx - 2, y = cy - 2 }
end
local function large_dialog()
    local result = descriptor()
    result.columns[1].items = {}
    result.columns[2].items = {}
    for ci, count in ipairs({ 73, 41 }) do
        for i = 1, count do
            result.columns[ci].items[i] = {
                id = ci .. ':' .. i,
                label = (ci == 1 and 'Armor / Cape LUT ' or 'Helmet LUT ') .. i,
                detail = i % 2 == 1 and 'Pattern included' or nil,
                enabled = i ~= 3,
                checked = i ~= 3,
            }
        end
    end
    return result
end
menu.text_metrics = metrics
for _, font in ipairs({ 12, 20 }) do
    for _, scale in ipairs({ 0.7, 1, 1.15 }) do
        for _, size in ipairs({ { 1280, 720 }, { 1920, 1080 } }) do
            resolution = size
            menu.font_size, menu.ui_scale, menu.window_width, menu.window_height = font, scale, 1100, 680
            dialog = open(large_dialog())
            local commands = compose()
            local b, w = dialog.bounds, menu.window_bounds
            local physical = { x = w.x + b.x * w.scale, y = w.y + b.y * w.scale, w = b.w * w.scale, h = b.h * w.scale }
            assert(
                physical.x >= 0
                    and physical.y >= 0
                    and physical.x + physical.w <= size[1] + 0.01
                    and physical.y + physical.h <= size[2] + 0.01,
                'Per-LUT modal frame escaped a small screen'
            )
            for _, c in ipairs(commands) do
                if c.popup then
                    assert(c.paint_plane >= 380, 'Per-LUT modal painted below the Basic page')
                    if c.type == 'rect' then
                        assert(
                            c.x >= physical.x - 0.01
                                and c.y >= physical.y - 0.01
                                and c.x + c.w <= physical.x + physical.w + 0.01
                                and c.y + c.h <= physical.y + physical.h + 0.01,
                            'Per-LUT native rectangle escaped its modal frame'
                        )
                    elseif c.type == 'text' then
                        local m = metrics(c.size)
                        assert(
                            c.y + m.min_y >= physical.y - 0.01 and c.y + m.max_y <= physical.y + physical.h + 0.01,
                            'Per-LUT native glyph ink escaped its modal frame'
                        )
                    end
                end
            end
            local first = assert(label('Armor / Cape LUT 1', true))
            local point = square(commands, first, true)
            click(point)
            assert(
                dialog.columns[1].items[1].checked == false and dialog.columns[2].items[1].checked == true,
                'Per-LUT square click changed the other column'
            )
            local cb = dialog.columns[1].scroll_bounds
            menu.wheel(-120000, w.x + (cb.x + cb.w / 2) * w.scale, w.y + (cb.y + cb.h / 2) * w.scale)
            commands = compose()
            assert(
                dialog.columns[1].scroll == dialog.columns[1].maximum and dialog.columns[2].scroll == 0,
                'Per-LUT wheel did not scroll only its own column to the endpoint'
            )
            assert(not label('Armor / Cape LUT 1', true), 'Per-LUT fully hidden first row still renders or owns clicks')
            local last = assert(label('Armor / Cape LUT 73', true), 'Per-LUT final row was lost at the wheel endpoint')
            square(commands, last, true)
            click(last)
            assert(dialog.columns[1].items[73].checked == false, 'Scrolled per-LUT label toggled the wrong row')
            commands = compose()
            local thumb
            for _, c in ipairs(commands) do
                if c.scrollbar == 'lut_apply_column_2' then
                    thumb = c
                end
            end
            assert(thumb, 'Per-LUT second-column scrollbar is missing')
            local sb = dialog.columns[2].scroll_bounds
            local tx, ty = thumb.x + thumb.w / 2, thumb.y + thumb.h / 2
            input(tx, ty, true)
            input(tx, w.y + sb.y * w.scale - 40, true)
            input(tx, w.y + sb.y * w.scale - 40, false)
            commands = compose()
            assert(
                dialog.columns[2].scroll == dialog.columns[2].maximum
                    and dialog.columns[1].scroll == dialog.columns[1].maximum,
                'Per-LUT thumb endpoint was not independent or exact'
            )
            local helmet = assert(label('Helmet LUT 41', true), 'Per-LUT final row was lost at the thumb endpoint')
            click(square(commands, helmet, true))
            assert(
                dialog.columns[2].items[41].checked == false,
                'Per-LUT final checkbox lost its original selection ID'
            )
            local calls = apply_attempts
            menu.key(13)
            assert(
                not menu.lut_apply_dialog and apply_attempts == calls + 1,
                'Per-LUT Enter did not apply its current checked IDs'
            )
            local ids = applied[#applied]
            assert(
                not ids['1:1'] and not ids['1:73'] and not ids['2:41'] and not ids['1:3'] and not ids['2:3'],
                'Per-LUT Apply reintroduced unchecked or disabled rows after scrolling'
            )
            assert(ids['1:72'] == true and ids['2:40'] == true, 'Per-LUT Apply discarded unchanged enabled rows')
            for id in pairs(ids) do
                assert(id:match('^[12]:%d+$'), 'Per-LUT informational Pattern added an optional ID')
            end
        end
    end
end
renderer.release()
resolution = { 1920, 1080 }
dialog = open()
menu.key(121)
assert(not menu.visible and not menu.lut_apply_dialog, 'F10 retained an orphan per-LUT modal after closing Basic')
print(
    'PASS per-LUT native/scroll layout: two independent wheel/drag endpoints, last-row ID hits, enabled-only Enter masks, Pattern detail invariants and bounded frames/glyphs across fonts/scales/screens'
)
print(
    'PASS per-LUT modal: enabled-only selection masks, required Pattern information, empty/Cancel/Escape guards, Basic-page ownership and stale/error retention'
)
