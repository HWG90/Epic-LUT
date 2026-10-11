local core = dofile('vendor/menu/core.lua')
local api = core.new({
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
})
local handle = api.register({
    id = 'floating_test',
    name = 'Floating',
    pages = {
        {
            id = 'main',
            name = 'Main',
            controls = {
                {
                    id = 'floating_selector',
                    type = 'choice',
                    label = 'Choice',
                    choices = { 'Alpha', 'Beta' },
                    default = 1,
                },
            },
        },
    },
})
local page = api.mods[handle.id].pages[1]
page.render_layout = function(ui)
    ui.floating('test_popup', function(x, y, w, h)
        ui.rect(x, y, w, h, { 24, 30, 35 })
        ui.rect(x, y + h - 40, w, 40, { 35, 62, 90 })
        ui.bounded(x + 10, y + h - 27, 'Floating title', 14, { 255, 255, 255 }, w - 40)
        ui.choice('floating_selector', x + 15, y + h - 110, w - 30)
    end, 400, 260, function() end, 40)
end
local menu = dofile('vendor/menu/menu.lua').new(api, function(text, size)
    return #text * size * 0.5
end)
menu.visible = true
menu.window_width, menu.window_height = 1200, 880
local openings = {}
local function record_open(id, count)
    assert(id == 'floating_selector' and count == 2, 'Dropdown diagnostic reported a different control/count')
    openings[#openings + 1] = id
end
menu.on_dropdown_open = record_open
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
local commands = menu.compose(1920, 1080)
local selector
for _, c in ipairs(commands) do
    if c.full_text == 'Alpha' then
        selector = c
    end
end
assert(selector, 'Floating selector not rendered')
input(selector.x + 12, selector.y + 5, true)
input(selector.x + 12, selector.y + 5, false)
assert(menu.dropdown and menu.dropdown.owner, 'Floating dropdown has no owner')
assert(#openings == 1, 'Dropdown opening diagnostic was omitted or repeated')
commands = menu.compose(1920, 1080)
local above = false
for _, c in ipairs(commands) do
    if c.popup and c.text == 'Alpha' and c.paint_plane and c.paint_plane >= 300 then
        above = true
    end
end
assert(above, 'Dropdown is behind floating window')
assert(#openings == 1, 'Composing an open dropdown spammed its diagnostic')
local position = menu.floating_positions.test_popup
local oldx, oldtop = menu.dropdown.x, menu.dropdown.top
position.x = position.x - 50
position.y = position.y + 20
menu.compose(1920, 1080)
assert(menu.dropdown.x < oldx and menu.dropdown.top > oldtop, 'Dropdown anchor did not follow popup')
local owner = menu.dropdown.owner
local scale = (menu.window_bounds and menu.window_bounds.scale) or 1
-- The rendered title text supplies physical coordinates independent of UI scale.
local title
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.text == 'Floating title' then
        title = c
    end
end
assert(title)
local before = position.x
input(title.x + 30, title.y + 5, true)
input(title.x - 10, title.y + 5, true)
input(title.x - 10, title.y + 5, false)
assert(position.x < before, 'Open dropdown blocked title-bar dragging')
assert(menu.dropdown, 'Dragging title unexpectedly discarded dropdown')
print('PASS floating dropdown: foreground layer, moving anchor and accessible title drag')

-- Retained drawing uses semantic content depths inside a bounded window range,
-- rather than command-index offsets that can escape it. Native overlap and
-- partial-redraw behavior are exercised in window_render_order.lua.
local bounded_window = false
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.floating_id == 'test_popup' then
        assert(
            c.paint_plane >= 210 and c.paint_span == 20 and c.paint_plane + c.paint_span < 300,
            'Floating content escaped its reserved window range'
        )
        bounded_window = true
    end
end
assert(bounded_window, 'Floating window did not receive its draw range')

local underlying = 0
page.on_wheel = function()
    underlying = underlying + 1
    return true
end
menu.dropdown = nil
menu.compose(1920, 1080)
local floating = assert(menu.floating_bounds)
menu.wheel(-120, floating.x + 20, floating.y + 20)
assert(underlying == 0, 'Floating popup scrolled underlying page')
menu.color_picker = {}
menu.wheel(-120, menu.window_bounds.x + 200, menu.window_bounds.y + 250)
assert(underlying == 0, 'Color picker scrolled underlying page')
menu.color_picker = nil

-- One control appears at two authored locations. Each actual hit must anchor
-- its dropdown locally, including subsequent redraws and moving popup owners.
page.render_layout = function(ui)
    ui.choice('floating_selector', ui.x + 20, ui.y + 200, 180)
    ui.choice('floating_selector', ui.x + 420, ui.y + 200, 180)
end
local function duplicate_labels(commands)
    local labels = {}
    for _, c in ipairs(commands) do
        if c.full_text == 'Alpha' then
            labels[#labels + 1] = c
        end
    end
    assert(#labels == 2)
    return labels
end
local duplicate = duplicate_labels(menu.compose(1920, 1080))
input(duplicate[1].x + 3, duplicate[1].y + 3, true)
input(duplicate[1].x + 3, duplicate[1].y + 3, false)
assert(menu.dropdown and menu.dropdown.widget)
local left_anchor = menu.dropdown.x
menu.compose(1920, 1080)
assert(menu.dropdown.x == left_anchor, 'Redrawing the right duplicate stole the left dropdown anchor')
menu.key(27)
duplicate = duplicate_labels(menu.compose(1920, 1080))
input(duplicate[2].x + 3, duplicate[2].y + 3, true)
input(duplicate[2].x + 3, duplicate[2].y + 3, false)
assert(menu.dropdown.x > left_anchor + 200, 'Right duplicate opened below the left widget')
menu.key(27)
page.render_layout = function(ui)
    ui.floating('test_popup', function(x, y, w, h)
        ui.rect(x, y, w, h, ui.theme.panel)
        ui.choice('floating_selector', x + 10, y + 100, 180)
        ui.choice('floating_selector', x + 210, y + 100, 180)
    end, 420, 260, function() end, 40)
end
duplicate = duplicate_labels(menu.compose(1920, 1080))
input(duplicate[1].x + 3, duplicate[1].y + 3, true)
input(duplicate[1].x + 3, duplicate[1].y + 3, false)
left_anchor = menu.dropdown.x
position = menu.floating_positions.test_popup
position.x = position.x - 50
menu.compose(1920, 1080)
assert(
    menu.dropdown.owner.id == 'test_popup' and menu.dropdown.x < left_anchor,
    'Duplicate dropdown lost its own moving window anchor'
)
print('PASS duplicate choice anchors: left/right hits keep separate anchors and follow their own popup')
assert(#openings == 4, 'Actual choice openings were not reported exactly once')

-- Logging is optional and cannot prevent the control from opening.
menu.key(27)
menu.on_dropdown_open = function()
    error('Unavailable diagnostic sink')
end
duplicate = duplicate_labels(menu.compose(1920, 1080))
input(duplicate[1].x + 3, duplicate[1].y + 3, true)
input(duplicate[1].x + 3, duplicate[1].y + 3, false)
assert(menu.dropdown, 'Diagnostic failure prevented dropdown opening')
menu.key(27)
menu.on_dropdown_open = record_open

-- Keep small and larger window stacks in the prior working native region,
-- while reserving all sixteen integer content roles for each window.
for _, count in ipairs({ 3, 8 }) do
    page.render_layout = function(ui)
        for n = 1, count do
            ui.floating('range_' .. n, function(x, y, w, h)
                ui.rect(x, y, w, h, ui.theme.panel)
                ui.choice('floating_selector', x + 10, y + 40, w - 20)
            end, 250, 150, function() end, 40)
        end
    end
    local last
    for _, c in ipairs(menu.compose(1920, 1080)) do
        if c.floating_id == 'range_' .. count and c.full_text == 'Alpha' then
            last = c
        end
        if c.floating_id then
            assert(c.paint_plane % 1 == 0 and c.paint_span == 20)
        end
    end
    assert(last)
    input(last.x + 3, last.y + 3, true)
    input(last.x + 3, last.y + 3, false)
    local expected = math.max(300, 210 + (count - 1) * 20 + 20)
    local seen
    for _, c in ipairs(menu.compose(1920, 1080)) do
        if c.popup and not c.floating_id and c.full_text == 'Alpha' then
            assert(
                c.paint_plane == expected and c.paint_span == 20,
                'Dropdown escaped the compact integer overlay contract'
            )
            seen = true
        end
    end
    assert(
        seen and menu.dropdown.owner.id == 'range_' .. count,
        'Topmost stack selector failed to open its visible dropdown'
    )
    menu.key(27)
end
assert(#openings == 6, 'Stacked window openings logged per-frame instead of per-open')
print(
    'PASS dropdown visibility contract: prior working layer region, three/eight window stacks and bounded once-per-open diagnostics'
)

-- The native Player Preview is a separate surface, so its pose chooser has no
-- menu floating owner. Its explicit screen anchor must still open outside the
-- editor, with selection routed through the transient pose handle.
do
    menu.on_dropdown_open = nil
    local selected, changes = 1, 0
    local pose_handle = api.register({
        id = 'preview_pose_transient',
        name = 'Player Preview Pose',
        hidden = true,
        pages = {
            {
                id = 'pose',
                name = 'Pose',
                require_confirmation = false,
                controls = {
                    {
                        id = 'preview_pose',
                        type = 'choice',
                        label = 'Pose',
                        choices = { 'Idle', 'Salute', 'Hug' },
                        default = 1,
                        on_change = function(value)
                            selected, changes = value, changes + 1
                        end,
                    },
                },
            },
        },
    })
    local pose_mod = api.mods[pose_handle.id]
    menu.compose(1920, 1080)
    local b = menu.window_bounds
    local preview = { x = 1780, y = 950, w = 130, h = 120 }
    assert(
        preview.x > b.x + b.w and preview.x + preview.w <= 1920 and preview.y + preview.h <= 1080,
        'Preview anchor fixture must be outside the editor and inside the display'
    )
    local function open_pose(screen_anchor)
        menu.open_dropdown({
            mod = pose_mod,
            control = pose_mod.controls.preview_pose,
            selected = pose_handle.get('preview_pose'),
            scroll = 0,
            x = (preview.x + preview.w / 3 - b.x) / b.scale,
            top = (preview.y + 20 - b.y) / b.scale,
            width = 220 / b.scale,
            owner = nil,
            screen_anchor = screen_anchor,
            preview_owner = 'player_preview',
        })
    end
    local function dropdown_frame(commands)
        for _, c in ipairs(commands) do
            if c.window_frame == 'dropdown' then
                return assert(c.frame_bounds)
            end
        end
        error('Preview pose dropdown has no visible frame')
    end
    open_pose(true)
    local pose_commands = menu.compose(1920, 1080)
    local frame = dropdown_frame(pose_commands)
    assert(
        frame.x > b.x + b.w and frame.x + frame.w <= 1920 and frame.y >= 0 and frame.y + frame.h <= 1080,
        'Screen-anchored pose list was clamped into the editor or outside the display'
    )
    assert(menu.dropdown.owner == nil and menu.dropdown.preview_owner == 'player_preview')
    local salute
    for _, c in ipairs(pose_commands) do
        if c.full_text == 'Salute' then
            salute = c
        end
    end
    assert(salute and salute.x > b.x + b.w, 'Pose choice is not visible beside the floating preview')
    input(salute.x + 3, salute.y + 3, true)
    input(salute.x + 3, salute.y + 3, false)
    assert(
        not menu.dropdown and pose_handle.get('preview_pose') == 2 and selected == 2 and changes == 1,
        'External pose list did not commit exactly one choice to its transient handle'
    )
    open_pose(true)
    menu.key(40)
    menu.key(27)
    assert(
        menu.visible and not menu.dropdown and pose_handle.get('preview_pose') == 2 and changes == 1,
        'Escape committed the preview pose or closed the editor'
    )
    open_pose(false)
    local normal_frame = dropdown_frame(menu.compose(1920, 1080))
    assert(
        normal_frame.x >= b.x
            and normal_frame.x + normal_frame.w <= b.x + b.w
            and normal_frame.y >= b.y
            and normal_frame.y + normal_frame.h <= b.y + b.h,
        'Normal ownerless dropdown escaped its existing editor-frame clamp'
    )
    menu.key(27)
    pose_handle.unregister()
    print(
        'PASS preview pose dropdown: external screen anchor/display clamp, transient choice commit, Escape cancellation and unchanged normal frame clamp'
    )
end
