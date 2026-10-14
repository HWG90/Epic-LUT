-- Real menu/host integration. Pattern rendering and native sampling have their
-- own fixture; this mock makes geometry and input ownership observable.
local ffi = require('ffi')
local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local api = Core.new()
local documents = {}
for index, kind in ipairs({ 'armor', 'helmet' }) do
    local d = { width = 23, height = 8, data = ffi.new('float[736]'), source = kind .. '-draft.dds', revision = 0 }
    for i = 0, 735 do
        d.data[i] = (i % 19) / 18 + (i % 4 == 3 and index or 0)
    end
    documents[kind] = d
end
local document = documents.armor
local writes, restores, loads = 0, 0, { armor = 0, helmet = 0 }
local modules = {
    ui_core = Core,
    semantics = dofile('src/core/semantics.lua'),
    palette = dofile('src/core/palette.lua'),
    dds = dofile('src/core/dds.lua'),
    lut_files = dofile('src/presets/lut_files.lua'),
    file_io = dofile('src/core/file_io.lua'),
    lut_editor_controls = dofile('src/editor/lut_editor_controls.lua'),
    lut_editor_view = dofile('src/editor/lut_editor_view.lua'),
    editor_tools = dofile('src/editor/editor_tools.lua'),
    windows = {
        row_presets = function()
            return {}
        end,
    },
    engine = {
        create_texture = function()
            writes = writes + 1
        end,
        bind = function()
            writes = writes + 1
        end,
    },
}
local editor = dofile('src/editor/lut_editor.lua').new(modules, function()
    return document
end, function(value)
    return value
end, function()
    writes = writes + 1
end, 'tests/tmp/pattern-host')
local quick_bounds, workspace_bounds, quick_kind, portrait_bounds
local pattern = { opened = false, hosted = false, scroll = 0, maximum = 0, shows = 0, dismisses = 0 }
function pattern.set_workspace_host(value)
    pattern.hosted = value == true
end
function pattern.is_open()
    return pattern.opened
end
function pattern.show(kind)
    pattern.gear, pattern.opened = kind or editor.gear, true
    pattern.shows = pattern.shows + 1
    return true
end
function pattern.dismiss()
    if pattern.pending then
        return false
    end
    pattern.opened, pattern.bounds = false, nil
    pattern.dismisses = pattern.dismisses + 1
    return true
end
function pattern.close()
    restores = restores + 1
    pattern.opened = false
    return true
end
function pattern.quick_height(ui, cell_height)
    return (ui.text_size and ui.text_size(13, 'heading') or 13)
        + (ui.text_size and ui.text_size(11, 'hint') or 11)
        + (ui.spacing and ui.spacing(6) or 6) * 3
        + math.max(0, math.min(40, cell_height or 28))
end
function pattern.quick(ui, bounds, kind)
    quick_bounds, quick_kind = bounds, kind
    local gap = ui.spacing and ui.spacing(6) or 6
    local width = math.min(40, bounds.cell_width, (bounds.w - gap * 2) / 3)
    ui.bounded(bounds.x, bounds.y + bounds.h - 18, 'Quick Pattern Host', 13, ui.theme.white, bounds.w, 'heading')
    for column = 1, 3 do
        ui.bounded(
            bounds.x + (column - 1) * (width + gap),
            bounds.y + 2 + bounds.row_height + gap,
            ({ 'Color', 'Mat/Opac', 'Roughness' })[column],
            11,
            ui.theme.white,
            width,
            'hint'
        )
        ui.rect(
            bounds.x + (column - 1) * (width + gap),
            bounds.y + 2,
            width,
            bounds.row_height,
            { 30 * column, 50, 80 },
            nil,
            'pattern_quick_swatch'
        )
    end
end
function pattern.workspace(ui, bounds)
    workspace_bounds, pattern.bounds = bounds, bounds
    local step, total = 34, 34 * 24
    pattern.maximum = math.max(0, total - bounds.h)
    pattern.scroll = math.min(pattern.scroll, pattern.maximum)
    local function draw()
        for row = 1, 24 do
            ui.bounded(
                bounds.x + 8,
                bounds.y + bounds.h - row * step + pattern.scroll,
                'Pattern Option ' .. row,
                13,
                ui.theme.white,
                bounds.w - 16
            )
        end
    end
    if ui.viewport then
        ui.viewport(bounds, draw, { top = bounds.y + bounds.h, bottom = bounds.y, color = ui.theme.panel })
    else
        draw()
    end
end
function pattern.wheel(x, y, delta)
    local b = pattern.bounds
    if pattern.opened and b and x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
        pattern.scroll = math.max(0, math.min(pattern.maximum, pattern.scroll - delta / 120 * 34))
        return true
    end
end
function pattern.popup(ui)
    if pattern.opened and not pattern.hosted then
        ui.floating('pattern_host_test', function(x, y, w, h)
            ui.bounded(x + 10, y + h - 30, 'Legacy Pattern Popup', 13, ui.theme.white, w - 20)
        end, 600, 500, pattern.dismiss)
    end
end
local pages = editor.pages()
for _, kind in ipairs({ 'armor', 'helmet' }) do
    local target = kind
    pages[1].controls[#pages[1].controls + 1] = {
        id = 'editor_load_' .. target,
        type = 'button',
        label = 'Load ' .. target,
        on_activate = function()
            loads[target] = loads[target] + 1
            if document ~= documents[target] then
                document = documents[target]
                editor.sync()
            end
            return true
        end,
    }
    pages[1].controls[#pages[1].controls + 1] = {
        id = 'basic_' .. target .. '_lut',
        type = 'choice',
        label = target,
        choices = { 'LUT 1' },
        default = 1,
    }
end
for _, id in ipairs({ 'populate_worn', 'editor_apply_armor', 'editor_apply_helmet' }) do
    pages[1].controls[#pages[1].controls + 1] = {
        id = id,
        type = 'button',
        label = id,
        on_activate = function()
            writes = writes + 1
        end,
    }
end
pages[1].controls[#pages[1].controls + 1] = {
    id = 'pattern_open',
    type = 'button',
    label = 'Open Pattern',
    on_activate = function()
        return pattern.show(editor.gear)
    end,
}
local handle = api.register({ id = 'pattern_host_layout', name = 'Epic LUT', pages = pages })
editor.attach(api, handle)
editor.pattern_editor = pattern
api.mods[handle.id].tabs_top = true
local prior_preview = package.loaded['epic.player_preview.v1']
package.loaded['epic.player_preview.v1'] = {
    is_docked = function()
        return true
    end,
    dock = function(bounds)
        portrait_bounds = bounds
    end,
}
local menu = Menu.new(api, function(text, size)
    return #text * size * 0.5
end)
menu.visible, menu.epic_typography = true, true
menu.window_width, menu.window_height, menu.ui_scale = 1800, 1200, 0.8
editor.tools.open('rows')
editor.tools.set_docked(true)
local function compose()
    quick_bounds, workspace_bounds = nil, nil
    local commands = menu.compose(1920, 1080)
    for _, c in ipairs(commands) do
        assert(not (c.text and (c.text:find('%.lua:%d+:') or c.text:find('Editor control missing:', 1, true))), c.text)
    end
    return commands
end
local function label(commands, value)
    for _, c in ipairs(commands) do
        if c.full_text == value or c.text == value then
            return c
        end
    end
end
local function selected_button(commands, value)
    local text = assert(label(commands, value))
    for _, c in ipairs(commands) do
        if
            c.ui_role == 'control_accent'
            and c.h > text.size
            and c.h <= text.size * 4
            and c.x <= text.x
            and text.x - c.x < text.size * 1.5
            and c.y <= text.y
            and c.y + c.h >= text.y + text.size * 0.5
        then
            return true
        end
    end
    return false
end
local function point(x, y)
    local b = menu.window_bounds
    return b.x + x * b.scale, b.y + y * b.scale
end
local function tap(text)
    local c = assert(label(compose(), text), 'Missing host action: ' .. text)
    for _, down in ipairs({ true, false }) do
        menu.tick({
            down = function(key)
                return down and key == 1
            end,
            mouse = function()
                return c.x + 2, c.y + 2
            end,
            wheel = function()
                return 0
            end,
        })
    end
    return compose()
end
local function wheel(bounds, delta)
    local x, y = point(bounds.x + bounds.w / 2, bounds.y + bounds.h / 2)
    menu.wheel(delta, x, y)
    return compose()
end
local function no_pattern_popup()
    for _, window in ipairs(menu.floating_windows or {}) do
        assert(window.id ~= 'pattern_host_test', 'Hosted Pattern retained a separate floating window')
    end
end
local function contained(bounds)
    local tools = assert(editor.tools.bounds)
    assert(bounds.w > 0 and bounds.h > 0)
    assert(bounds.y >= tools.y + tools.h, 'Pattern surface overlaps docked Tools')
    assert(bounds.x + bounds.w <= portrait_bounds.x - 6, 'Pattern surface has no gap before Player Preview')
    local footer = assert(label(compose(), 'Brush'))
    local bottom = select(2, point(bounds.x, bounds.y))
    assert(bottom >= footer.y + footer.size, 'Pattern surface overlaps the material footer')
    local header = assert(label(compose(), 'Pattern LUT Editor'))
    local top = select(2, point(bounds.x, bounds.y + bounds.h))
    assert(top <= header.y, 'Pattern surface overlaps the gear navigation')
end
local function borders(commands)
    local count, bottom = 0, math.huge
    for _, c in ipairs(commands) do
        if c.ui_role == 'swatch_border' and not c.popup then
            count, bottom = count + 1, math.min(bottom, c.y)
        end
    end
    return count, bottom
end
local function quick_gap(commands, scrolling)
    local _, bottom = borders(commands)
    local top = select(2, point(quick_bounds.x, quick_bounds.y + quick_bounds.h))
    local measured = (bottom - top) / menu.window_bounds.scale
    local expected = (scrolling and 30 or 0) + 6 * (menu.font_size or 12) / 12
    assert(math.abs(measured - expected) < 0.01, 'Quick Pattern is detached from the last rendered LUT row')
end
compose()
editor.focus_cell(3, 1)
assert(handle.set('cell_r', 0.271))
editor.selection = { r1 = 2, r2 = 3, c1 = 1, c2 = 4 }
local selection, undo = editor.selection, editor.undo
local first_undo, undo_count = editor.undo[1], #editor.undo
local pixels = {}
for kind, d in pairs(documents) do
    pixels[kind] = ffi.string(d.data, d.width * d.height * 16)
end
local function unchanged()
    for kind, d in pairs(documents) do
        assert(
            ffi.string(d.data, d.width * d.height * 16) == pixels[kind],
            'Pattern navigation changed a material draft'
        )
    end
    assert(
        editor.undo == undo and #editor.undo == undo_count and editor.undo[1] == first_undo,
        'Pattern navigation reset material Undo'
    )
    assert(writes == 0 and restores == 0, 'Pattern navigation applied/restored native bindings')
end
local commands = compose()
assert(
    pattern.hosted and quick_bounds and not workspace_bounds,
    'Closed Pattern did not mount its quick strip in the host'
)
contained(quick_bounds)
local count, bottom = borders(commands)
assert(count == 23 * 8 and editor.grid_max == 0, 'Pattern quick strip hid ordinary eight-row material swatches')
assert(
    bottom >= select(2, point(quick_bounds.x, quick_bounds.y + quick_bounds.h)),
    'Quick Pattern overlaps the material grid'
)
quick_gap(commands, false)
local swatches = 0
for _, c in ipairs(commands) do
    if c.ui_role == 'pattern_quick_swatch' then
        swatches = swatches + 1
    end
end
assert(swatches == 3 and quick_kind == 'armor')
assert(quick_bounds.x == editor.grid_bounds.x + 82, 'Quick Pattern does not align with the first material cell')
assert(
    math.abs(quick_bounds.w - quick_bounds.cell_width * 23) < 0.01,
    'Quick Pattern width does not track the material table'
)
assert(
    quick_bounds.row_height == editor.tools_splitter.cell and quick_bounds.row_height <= 40,
    'Quick Pattern does not track compact material cell size'
)
no_pattern_popup()
menu.font_size, menu.ui_scale, menu.window_height = 20, 0.65, 1300
commands = compose()
contained(quick_bounds)
assert(borders(commands) == 23 * 8 and editor.grid_max == 0, 'Roomy large-font host lost an ordinary material row')
quick_gap(commands, false)
unchanged()
menu.font_size, menu.ui_scale, menu.window_height = 12, 0.8, 1200
commands = tap('Pattern LUT Editor')
assert(
    pattern.opened and workspace_bounds and not quick_bounds and not editor.grid_bounds,
    'Open Pattern did not replace the material grid and quick strip'
)
contained(workspace_bounds)
no_pattern_popup()
assert(
    selected_button(commands, 'Pattern LUT Editor')
        and not selected_button(commands, 'Armor LUT')
        and not selected_button(commands, 'Helmet LUT'),
    'Hosted Pattern navigation did not own the selected header state'
)
assert(editor.selection == selection, 'Opening Pattern changed material selection')
unchanged()
pattern.pending = true
tap('Helmet LUT')
assert(
    pattern.opened and document == documents.armor and editor.gear == 'armor' and loads.helmet == 0,
    'Pending Pattern flash restoration allowed a material gear switch'
)
unchanged()
pattern.pending = false
local old_grid, old_tools = editor.grid_first, editor.tools.scroll
wheel(workspace_bounds, -120)
assert(
    pattern.scroll > 0 and editor.grid_first == old_grid and editor.tools.scroll == old_tools,
    'Pattern wheel leaked to grid/Tools'
)
for _ = 1, 30 do
    commands = wheel(workspace_bounds, -120)
end
assert(pattern.scroll == pattern.maximum, 'Hosted Pattern cannot scroll to its final option')
local last = assert(label(commands, 'Pattern Option 24'))
local floor = select(2, point(workspace_bounds.x, workspace_bounds.y))
local ceiling = select(2, point(workspace_bounds.x, workspace_bounds.y + workspace_bounds.h))
assert(
    last.y >= floor - 0.01 and last.y + last.size <= ceiling + 0.01,
    'Final Pattern option remains outside its host viewport'
)
local old_pattern = pattern.scroll
wheel(editor.tools.bounds, -120)
assert(editor.tools.scroll > old_tools and pattern.scroll == old_pattern, 'Tools wheel leaked into Pattern')
commands = tap('Armor LUT')
assert(not pattern.opened and quick_bounds and not workspace_bounds and document == documents.armor)
assert(editor.selection == selection, 'Leaving Pattern for the same gear lost its selection')
assert(loads.armor == 0, 'Leaving Pattern reloaded the same material document and discarded its draft')
assert(selected_button(commands, 'Armor LUT') and not selected_button(commands, 'Pattern LUT Editor'))
unchanged()
tap('Pattern LUT Editor')
tap('Helmet LUT')
assert(not pattern.opened and editor.gear == 'helmet' and quick_kind == 'helmet' and document == documents.helmet)
assert(loads.helmet == 1, 'Helmet navigation did not load its independent material table')
assert(restores == 0 and writes == 0, 'Helmet navigation restored Pattern/native gear')
-- A short table must not leave its Quick strip anchored at the viewport floor.
local previous = document
document = { width = 23, height = 3, data = ffi.new('float[276]'), source = 'three-rows.dds' }
editor.sync()
for _, ratio in ipairs({ 0.2, 0.6, 0.85 }) do
    editor.tools.split_ratio = ratio
    commands = compose()
    contained(quick_bounds)
    local visible_rows = document.height - editor.grid_max
    assert(borders(commands) == 23 * visible_rows and visible_rows >= 2, 'Quick strip hid readable short-table rows')
    quick_gap(commands, editor.grid_max > 0)
end
editor.tools.split_ratio, document = nil, previous
editor.sync()
-- A long material table keeps its own row wheel; the quick strip is not a row viewport.
documents.helmet = { width = 23, height = 64, data = ffi.new('float[?]', 23 * 64 * 4), source = 'helmet-64.dds' }
document = documents.helmet
editor.sync()
commands = compose()
quick_gap(commands, true)
local hint = assert(label(commands, 'Rows 1-' .. (document.height - editor.grid_max) .. ' of 64 / scroll here'))
local quick_top = select(2, point(quick_bounds.x, quick_bounds.y + quick_bounds.h))
assert(hint.y >= quick_top and hint.y + hint.size <= select(2, borders(commands)), 'Row hint overlaps Quick Pattern')
old_pattern, old_tools = pattern.scroll, editor.tools.scroll
wheel(assert(editor.grid_bounds), -120)
assert(
    editor.grid_first > 1 and pattern.scroll == old_pattern and editor.tools.scroll == old_tools,
    'Material grid wheel leaked into Pattern/Tools'
)
old_grid = editor.grid_first
wheel(assert(quick_bounds), -120)
assert(
    editor.grid_first == old_grid and editor.tools.scroll == old_tools,
    'Quick strip scrolled the material rows or Tools'
)
-- Legacy Pattern integrations without the workspace API retain their popup path.
editor.pattern_editor = {
    popup = function(ui)
        ui.floating('legacy_pattern_test', function(x, y, w, h)
            ui.bounded(x + 10, y + h - 30, 'Legacy fallback', 13, ui.theme.white, w - 20)
        end, 600, 450, function() end)
    end,
}
compose()
local legacy = false
for _, window in ipairs(menu.floating_windows or {}) do
    legacy = legacy or window.id == 'legacy_pattern_test'
end
assert(legacy, 'Old Pattern integrations lost their floating fallback')
package.loaded['epic.player_preview.v1'] = prior_preview
print(
    'PASS Pattern host workspace: quick strip, eight-row grid, bounded docked surfaces, independent scrolling, material state preservation and legacy popup fallback'
)
