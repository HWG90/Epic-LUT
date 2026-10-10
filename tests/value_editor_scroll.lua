-- Drive the actual Value Editor and menu scrollbar without native gear calls.
local ffi = require('ffi')
local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local api = Core.new()
local doc = { width = 23, height = 8, data = ffi.new('float[?]', 23 * 8 * 4) }
for i = 0, 23 * 8 * 4 - 1 do
    doc.data[i] = (i % 17) / 16
end
local m = {
    lut_files = dofile('src/presets/lut_files.lua'),
    file_io = dofile('src/core/file_io.lua'),
    lut_editor_controls = dofile('src/editor/lut_editor_controls.lua'),
    lut_editor_view = dofile('src/editor/lut_editor_view.lua'),
    semantics = dofile('src/core/semantics.lua'),
    palette = dofile('src/core/palette.lua'),
    dds = dofile('src/core/dds.lua'),
    ui_core = Core,
    windows = {
        row_presets = function()
            return {}
        end,
    },
}
local editor = dofile('src/editor/lut_editor.lua').new(m, function()
    return doc
end, function(value)
    return value
end, function()
    return true
end, 'tests/tmp/presets')
local handle = api.register({ id = 'value_scroll_test', name = 'Epic LUT', pages = editor.pages() })
editor.attach(api, handle)
api.mods[handle.id].tabs_top = true
local menu = Menu.new(api, function(text, size)
    return #text * size * 0.5
end, dofile('src/platform/text_editor.lua'))
menu.visible, menu.epic_typography = true, true
menu.window_width, menu.window_height = 1500, 980
menu.text_metrics = function(size)
    -- A face with ascenders/descenders taller than the nominal size exposes
    -- font-size-only clipping and baseline guesses at both viewport edges.
    return { min_y = -size * 0.3, max_y = size * 1.2, height = size * 1.5, optical_y = -size * 0.12 }
end
local function compose()
    local commands = menu.compose(1920, 1080)
    for _, c in ipairs(commands) do
        assert(not (c.text and c.text:find('attempt to ', 1, true)), c.text)
    end
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
    })
end
local function tap(x, y)
    input(x, y, true)
    input(x, y, false)
end
local function bounds()
    local v, b = assert(editor.value_viewport), menu.window_bounds
    return { x = b.x + v.x * b.scale, y = b.y + v.y * b.scale, w = v.w * b.scale, h = v.h * b.scale }
end
local function thumb(commands)
    for _, c in ipairs(commands) do
        if c.scrollbar == 'value_editor' then
            return c
        end
    end
    error('Value Editor has no interactive scrollbar')
end
local function body_text(c)
    local text = c.full_text or c.text or ''
    return c.text_role == 'hint'
        or text:match('^[v>] Row %d+$')
        or text:match('^Column %d+:')
        or text:match('^[RGBA]$')
        or text:match('^[%d%.eE+%-]+$')
        or text:match('^Shader mode')
        or text:match('^R%d')
        or text:match('^Pattern %d')
        or text == 'Off / default'
        or text == 'Off'
end
local function contained(commands)
    local v, text_count = bounds(), 0
    for _, c in ipairs(commands) do
        if c.type == 'text' and c.x >= v.x and body_text(c) then
            local ink = menu.text_metrics(c.size, c.full_text or c.text)
            assert(
                c.y + ink.min_y >= v.y - 0.01 and c.y + ink.max_y <= v.y + v.h + 0.01,
                'Value text extends through the fixed header/footer: ' .. tostring(c.full_text or c.text)
            )
            text_count = text_count + 1
        elseif
            c.type == 'rect'
            and c.x >= v.x
            and c.ui_role == 'control_fill'
            and c.y < v.y + v.h
            and c.y + c.h > v.y
        then
            assert(c.y >= v.y - 0.01 and c.y + c.h <= v.y + v.h + 0.01, 'Value control crosses its viewport')
        end
    end
    assert(text_count > 0, 'Value scrolling hid every readable row/control')
end
local function drag_to(bottom)
    local current = thumb(compose())
    local v = bounds()
    local x, start = current.x + current.w / 2, current.y + current.h / 2
    input(x, start, true)
    input(x, bottom and v.y + 1 or v.y + v.h - 1, true)
    input(x, bottom and v.y + 1 or v.y + v.h - 1, false)
end
local original = ffi.string(doc.data, doc.width * doc.height * 16)
local selection = { r1 = 2, r2 = 3, c1 = 1, c2 = 23 }
editor.selection = selection
local original_row, original_col, original_revision = handle.get('edit_row'), handle.get('edit_column'), doc.revision
editor.open_row, editor.focus_column = 1, nil
for _, scenario in ipairs({ { 12, 0.85 }, { 20, 1 }, { 20, 0.7 }, { 12, 1.15 } }) do
    menu.font_size, menu.ui_scale = scenario[1], scenario[2]
    editor.value_scroll = 0
    local commands = compose()
    contained(commands)
    local top_thumb = thumb(commands)
    local v = bounds()
    assert(top_thumb.y + top_thumb.h <= v.y + v.h + 0.01, 'Thumb overhangs the Value Editor header')
    local wheel_step = assert(editor.value_wheel_step)
    assert(wheel_step >= 8 and wheel_step <= 24, 'Value wheel retained its coarse 90px step')
    menu.wheel(-120, v.x + v.w / 2, v.y + v.h / 2)
    assert(math.abs(editor.value_scroll - wheel_step) < 0.01, 'Value wheel did not use the measured fine step')
    contained(compose())
    menu.wheel(120, v.x + v.w / 2, v.y + v.h / 2)
    assert(editor.value_scroll == 0, 'Fine upward wheel did not return to the top')
    drag_to(true)
    assert(editor.value_scroll >= editor.value_max - 1, 'Dragging thumb down did not reach the last values')
    commands = compose()
    contained(commands)
    local last_row = false
    for _, c in ipairs(commands) do
        if (c.full_text or c.text) == '> Row 8' then
            last_row = true
        end
    end
    assert(last_row, 'Bottom scrollbar position cannot show the final row header')
    local low_thumb = thumb(commands)
    assert(low_thumb.y < top_thumb.y, 'Downward drag did not move the thumb down')
    drag_to(false)
    assert(editor.value_scroll <= 1, 'Dragging thumb up did not return to the first values')
    commands = compose()
    contained(commands)
    v = bounds()
    local current = thumb(commands)
    tap(current.x + current.w / 2, v.y + v.h * 0.3)
    assert(
        editor.value_scroll > 0 and editor.value_scroll < editor.value_max,
        'Scrollbar track did not navigate into the values'
    )
    contained(compose())
    for _, fraction in ipairs({ 0, 0.05, 0.37, 0.7, 1 }) do
        editor.value_scroll = editor.value_max * fraction
        contained(compose())
    end
    assert(
        ffi.string(doc.data, doc.width * doc.height * 16) == original and doc.revision == original_revision,
        'Scrolling changed LUT bytes/revision'
    )
    assert(
        editor.selection == selection
            and handle.get('edit_row') == original_row
            and handle.get('edit_column') == original_col,
        'Scrolling changed the editing selection'
    )
end
for _, flag in ipairs({ 'read_only', 'stale' }) do
    doc[flag] = true
    editor.value_scroll = 0
    compose()
    drag_to(true)
    assert(
        editor.value_scroll > 0 and ffi.string(doc.data, doc.width * doc.height * 16) == original,
        'Protected LUT could not scroll without editing'
    )
    doc[flag] = nil
end
assert(handle.set('value_editor_visible', false))
compose()
assert(not editor.value_bounds and not editor.value_viewport, 'Collapsed Value Editor retained scroll ownership')
print(
    'PASS Value Editor scroll: measured whole-ink viewport, fixed header clearance, bidirectional thumb/track drag, fine wheel, fonts/scales, read-only/stale browsing and unchanged LUT/selection'
)
