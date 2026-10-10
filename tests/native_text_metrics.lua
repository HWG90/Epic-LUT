-- Real composer/view metrics with narrow glyphs and differing terminal ink bearings.
local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local Text = dofile('src/platform/text_editor.lua')
local View = dofile('vendor/menu/view.lua')
local world, gui = {}, {}
local calls, next_id = 0, 0
local advances = { F = 0.38, M = 0.8, i = 0.2, ['.'] = 0.22, ['#'] = 0.46, [' '] = 0.28, ['0'] = 0.42 }
local game_advances = { F = 0.5, M = 0.72, i = 0.24, ['.'] = 0.19, ['#'] = 0.4, [' '] = 0.22, ['0'] = 0.35 }
local game_face = { font = '1234567890abcdef', material = '234567890abcdef1', atlas = '34567890abcdef12' }
local metric_face = 'debug'
local function advance(label, size, face)
    face = face or metric_face
    local current = face == 'game' and game_advances or advances
    local width = 0
    for glyph in label:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        width = width + (current[glyph] or 0.5) * size
    end
    if face == 'game' then
        local _, pairs = label:gsub('Fi', '')
        width = width - pairs * size * 0.05
    end
    return width
end
local function allocate()
    next_id = next_id + 1
    return next_id
end
local sr = {
    IdString64 = {
        from_hex = function(value)
            return value
        end,
    },
    Material = { set_texture = function() end },
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
        material = function()
            return {}
        end,
        resolution = function()
            return 2560, 1440
        end,
        rect = allocate,
        text = allocate,
        destroy_rect = function() end,
        destroy_text = function() end,
        text_extents = function(_, label, resource, size)
            calls = calls + 1
            local right = label:sub(-1) == 'M' and 0.09 or label:sub(-1) == 'F' and 0.01 or 0.06
            return { x = 0.02 * size, y = -0.2 * size }, {
                x = advance(label, size, resource == game_face.font and 'game' or 'debug') - right * size,
                y = 0.7 * size,
            }
        end,
    },
}
local view = View.new(sr, true)
local cold = View.new(sr, true)
assert(
    math.abs(cold.measure('Fi', 20) - 24.8) < 0.001 and math.abs(cold.measure('éF', 20) - 24.8) < 0.001,
    'Cold fallback measured a full prefix as one glyph'
)
view.draw({ { type = 'rect', x = 0, y = 0, w = 1, h = 1, a = 1, c = { 0, 0, 0 } } })
assert(math.abs(view.measure('F', 20) - 7.6) < 1e-8, 'Native narrow advance was replaced by heuristic width')
assert(math.abs(view.measure('i', 20) - 4) < 1e-8, 'Terminal ink bearing leaked into native advance')
local api = Core.new()
local h = api.register({
    id = 'metrics',
    name = 'Metrics',
    pages = {
        {
            id = 'p',
            name = 'Page',
            require_confirmation = false,
            controls = {
                { id = 'name', type = 'input', label = 'Name', default = 'FFF00Fi' },
            },
        },
    },
})
local mod = api.mods[h.id]
mod.tabs_top = true
mod.pages[1].render_layout = function(ui)
    ui.button(ui.x + 20, ui.y + 100, 180, 40, 'Name: ' .. ui.input_value('name'), function()
        ui.activate('name')
    end)
end
local menu = Menu.new(api, view.measure, Text)
menu.visible, menu.compact_fonts = true, true
menu.text_metrics = view.text_metrics
menu.measure_text = view.measure
menu.window_width, menu.window_height = 1400, 900
local function compose()
    return menu.compose(2560, 1440)
end
local function input(x, y, down)
    menu.tick({
        down = function(k)
            return down and k == 1
        end,
        mouse = function()
            return x, y
        end,
        wheel = function()
            return 0
        end,
    }, 0)
end
local function tap()
    local idle
    for _, c in ipairs(compose()) do
        if c.full_text == 'Name: ' .. h.get('name') then
            idle = c
        end
    end
    assert(idle, 'Missing native-metric field')
    input(idle.x + 2, idle.y + 2, true)
    input(idle.x + 2, idle.y + 2, false)
    return idle
end
local function geometry()
    local field, caret, selection
    for _, c in ipairs(compose()) do
        if c.ui_role == 'text_field' then
            field = c
        elseif c.ui_role == 'text_caret' then
            caret = c
        elseif c.ui_role == 'text_selection' then
            selection = c
        end
    end
    local e = menu.text_edit
    local b = e.field_bounds
    assert(field and caret, 'Missing native text/caret geometry')
    local expected = b.text_x + advance(e.text:sub(1, e.cursor), field.size) - (e.scroll or 0) * b.scale
    assert(math.abs(caret.x - expected) < 0.01, 'Caret accumulated width drift from native advances')
    if selection then
        local a, z = Text.range(e)
        local left = math.max(b.text_x, b.text_x + advance(e.text:sub(1, a), field.size) - (e.scroll or 0) * b.scale)
        local right = b.text_x + advance(e.text:sub(1, z), field.size) - (e.scroll or 0) * b.scale
        assert(
            math.abs(selection.x - left) < 0.01 and math.abs(selection.x + selection.w - right) < 0.01,
            'Selection drifted beyond the native character boundaries'
        )
    end
    if e.cursor == #e.text then
        assert(
            math.abs(caret.x - field.x - advance(field.text, field.size)) < 0.01,
            'Caret did not match visible native text after scrolling/deletion'
        )
    end
    return e, b, field, caret
end
for _, font in ipairs({ 12, 20 }) do
    for _, scale in ipairs({ 0.8, 0.85, 1 }) do
        menu.font_size, menu.ui_scale = font, scale
        assert(h.set('name', 'FFF00Fi'))
        local idle = tap()
        local e, b, field = geometry()
        assert(
            math.abs(b.text_x - idle.x - advance('Name: ', field.size)) < 0.01,
            'Native prefix moved the focused text origin'
        )
        local cached = calls
        b.measure(e.text)
        b.measure(e.text)
        assert(calls == cached, 'Repeated field measurement missed cache')
        local target = 3
        local x = b.text_x + advance(e.text:sub(1, target), field.size)
        input(x, b.y + b.h / 2, true)
        input(x, b.y + b.h / 2, false)
        assert(e.cursor == target, 'Native proportional glyph click selected the wrong character')
        Text.all(e)
        geometry()
        for i = 1, 48 do
            menu.key(70, false, true)
        end
        e, b, field = geometry()
        assert(e.text == string.rep('F', 48) and e.scroll > 0, 'Repeated F fixture did not enter long-field scrolling')
        Text.all(e)
        geometry()
        local hidden = 0
        while hidden < #e.text and advance(e.text:sub(1, hidden), field.size) < e.scroll * b.scale do
            hidden = Text.next(e.text, hidden)
        end
        target = math.min(#e.text, hidden + 2)
        x = b.text_x + advance(e.text:sub(1, target), field.size) - e.scroll * b.scale
        input(x, b.y + b.h / 2, true)
        input(x, b.y + b.h / 2, false)
        assert(e.cursor == target, 'Scrolled mouse hit differed from native visible character boundaries')
        menu.key(35, false, false)
        for i = 1, 32 do
            menu.key(8, false, false)
        end
        e, b, field = geometry()
        assert(e.text == string.rep('F', 16), 'Backspace did not retain correct native-metric draft')
        for i = 1, 16 do
            menu.key(8, false, false)
        end
        e, b, field = geometry()
        assert(e.text == '' and e.scroll == 0, 'Empty field retained stale caret/scroll width')
        menu.key(27)
    end
end
-- Switch the same focused draft, size and scale across proportional/kerning
-- faces. The native metric identity must invalidate its prefix-width cache.
menu.font_size, menu.ui_scale = 20, 1
assert(h.set('name', 'FFF00Fi'))
tap()
local e = menu.text_edit
Text.all(e)
geometry()
view.set_font_source({
    resolve = function()
        return metric_face == 'game' and game_face or nil
    end,
})
for _, face in ipairs({ 'game', 'debug', 'game' }) do
    metric_face = face
    assert(view.refresh_font(), 'Face change did not invalidate metrics')
    menu.font_metric_key = view.metric_key
    assert(math.abs(view.measure('#F', 20) - advance('#F', 20)) < 0.001, 'Hash-prefix metrics retained another face')
    e.cursor = #e.text
    e.anchor = 0
    local _, b, field = geometry()
    local target = 3
    input(b.text_x + advance(e.text:sub(1, target), field.size), b.y + b.h / 2, true)
    input(b.text_x + advance(e.text:sub(1, target), field.size), b.y + b.h / 2, false)
    assert(e.cursor == target, 'Face change left stale caret hit metrics')
end
assert(
    math.abs(view.measure(string.rep('F', 256), 20) - advance(string.rep('F', 256), 20)) < 0.001,
    'Long prefix lost native advance to single-glyph limit'
)
menu.key(27)
print(
    'PASS native text metrics: bearings, proportional/kerning font switches, caret/selection/hits at12/20 fonts and80/85/100 scales, repeated F scrolling, cold fallback and long prefixes'
)
