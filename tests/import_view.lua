local ffi = require('ffi')
local core = dofile('vendor/menu/core.lua')
local menu_factory = dofile('vendor/menu/menu.lua')
local api = core.new({
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
})
local a, b = ffi.new('float[?]', 23 * 8 * 4), ffi.new('float[?]', 23 * 8 * 4)
for i = 0, 23 * 8 * 4 - 1 do
    a[i] = (i % 7) / 6
    b[i] = (i % 11) / 10
end
local state = {
    loaded = { width = 23, height = 8, data = a },
    armor = { { name = 'Armor LUT 1', width = 23, height = 8, data = a } },
    helmet = { { name = 'Helmet LUT 2', width = 23, height = 8, data = b } },
    palette_count = 2,
    status = 'Import ready',
    busy = true,
    phase = 'Reading archive...',
    time = 1,
    elapsed = 2,
    armor_checked = true,
    helmet_checked = false,
    palette_name = 'my-palette',
}
local picked
local pick_calls = 0
local view = dofile('src/editor/import_view.lua').new(
    function()
        return state
    end,
    dofile('src/core/table_groups.lua'),
    function(entry, row, col, flash, kind)
        pick_calls = pick_calls + 1
        picked = { entry = entry, row = row, col = col, flash = flash, kind = kind }
    end,
    core
)
local controls = {}
local load_actions = 0
for _, id in ipairs({ 'palette', 'lut', 'basic_armor_lut', 'basic_helmet_lut' }) do
    controls[#controls + 1] = { id = id, type = 'choice', label = id, choices = { 'LUT 1', 'LUT 2' }, default = 1 }
end
for _, id in ipairs({ 'target_armor', 'target_helmet' }) do
    controls[#controls + 1] = { id = id, type = 'toggle', label = id, default = true }
end
controls[#controls + 1] =
    { id = 'ui_scale', type = 'slider', label = 'UI scale (%)', min = 70, max = 130, step = 5, default = 100 }
controls[#controls + 1] = { id = 'quick_color', type = 'color', label = 'Quick Scratch', default = '#FFFFFF' }
controls[#controls + 1] =
    { id = 'preserve_emissives', type = 'toggle', label = 'Preserve Original Emissives', default = false }
for _, id in ipairs({
    'populate_worn',
    'apply_matching',
    'global_undo',
    'global_redo',
    'apply_file_armor',
    'apply_file_helmet',
    'apply_file_both',
    'apply_import_armor',
    'apply_import_helmet',
    'refresh',
    'browse',
    'cancel_import',
    'retry_import',
    'save_palette',
    'apply_checked',
    'restore',
    'restore_imported',
    'save_setup',
    'undo',
    'redo',
}) do
    controls[#controls + 1] = {
        id = id,
        type = 'button',
        label = id,
        on_activate = function()
            if id == 'populate_worn' then
                load_actions = load_actions + 1
            end
            return true
        end,
    }
end
api.register({
    id = 'import_test',
    name = 'Epic LUT',
    pages = { { id = 'direct', name = 'Import / Apply', require_confirmation = false, controls = controls } },
})
api.mods.import_test.tabs_top = true
local page = api.mods.import_test.pages[1]
page.render_layout = view.draw
page.on_wheel = view.wheel
local menu = menu_factory.new(api, function(t, size)
    return #t * size * 0.5
end)
menu.visible = true
menu.window_width = 1800
menu.window_height = 1000
menu.compact_fonts = true
local first = menu.compose(1920, 1080)
local texts = {}
for _, c in ipairs(first) do
    if c.text then
        texts[c.full_text or c.text] = c
    end
end
assert(
    texts['Quick Scratch'] and texts['Quick Scratch'].x > texts['Armor LUT 1'].x,
    'Quick Scratch is not beside palette tables'
)
assert(
    texts['Send to LUT Editor']
        and texts['Apply Matching LUTs']
        and not texts['Apply to All Armor & Helmet LUTs']
        and texts['Restore Imported LUT (editor)'],
    'Import layout did not complete'
)
assert(
    texts['Apply LUT 1 to All Armor LUTs'] and texts['Apply LUT 1 to All Helmet LUTs'],
    'Multi-LUT selected-source broadcast controls missing'
)
assert(
    texts.Armor and texts.Helmet and texts['Armor LUT 1'] and texts['Helmet LUT 2'],
    'Target color previews were not grouped'
)
assert(texts['LUT 1'].x < texts['Choose file - DDS / ZIP / RAR...'].x, 'LUT selectors are not on the left')
assert(not texts['Refresh live LUTs'], 'Advanced refresh visible by default')
-- Compose and click real header targets at small/large fonts and reduced window scale.
local function button_rectangle(commands, value)
    for i, command in ipairs(commands) do
        if command.full_text == value then
            local rectangle = commands[i - 1]
            assert(rectangle and rectangle.type == 'rect', 'Missing button background: ' .. value)
            return rectangle
        end
    end
    error('Missing header control: ' .. value)
end
local function overlap(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end
local function tap(x, y)
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
local saved_document = state.loaded
local compact, stacked = false, false
for _, font in ipairs({ 12, 20 }) do
    for _, dimensions in ipairs({
        { 1800, 1000, 1920, 1080 },
        { 1420, 960, 1920, 1080 },
        { 1100, 720, 1280, 720 },
        { 850, 720, 1280, 720 },
    }) do
        for _, count in ipairs({ 0, 1, 2 }) do
            state.loaded = count > 0 and saved_document or nil
            state.palette_count = count
            page.minimum_width = dimensions[1] < 1100 and dimensions[1] or nil
            menu.window_width, menu.window_height = dimensions[1], dimensions[2]
            menu.font_size, menu.ui_scale = font, 0.85
            view.selected = count == 1 and { label = 'Armor / Armor LUT 1', row = 1, column = 1 } or nil
            view.scratch_open = false
            local commands = menu.compose(dimensions[3], dimensions[4])
            for _, command in ipairs(commands) do
                assert(not (command.text and command.text:find('Editor control missing:', 1, true)), command.text)
                assert(not (command.text and command.text:find('attempt to ', 1, true)), command.text)
            end
            local load = button_rectangle(commands, 'Load Current Armor & Helmet')
            local scratch = button_rectangle(commands, 'Quick Scratch')
            assert(not overlap(load, scratch), 'Quick Scratch overlaps Load Current in import header')
            compact = compact or math.abs(load.y - scratch.y) < 0.1
            stacked = stacked or scratch.y + scratch.h < load.y
            assert(load.h >= (font + 10) * menu.window_bounds.scale, 'Header row clips large fonts')
            if view.selected then
                for _, command in ipairs(commands) do
                    if command.full_text and command.full_text:find('Editing:', 1, true) == 1 then
                        assert(
                            command.y + command.size < math.min(load.y, scratch.y),
                            'Selected-cell hint overlaps header buttons'
                        )
                    end
                end
            end
            -- The former shared edge must now activate only the load button.
            local before = load_actions
            tap(load.x + load.w - 3, load.y + 3)
            assert(load_actions == before + 1 and not view.scratch_open, 'Load header hit opens Scratch instead')
            tap(scratch.x + scratch.w / 2, scratch.y + scratch.h / 2)
            assert(view.scratch_open and load_actions == before + 1, 'Quick Scratch header hit activates Load instead')
            view.scratch_open = false
        end
    end
end
assert(compact and stacked, 'Header layout did not adapt to available label space')
state.loaded, state.palette_count = saved_document, 2
page.minimum_width = nil
view.selected = nil
menu.window_width, menu.window_height, menu.font_size, menu.ui_scale = 1800, 1000, 12, 1
menu.compose(1920, 1080)
view.advanced = true
local advanced = false
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text == 'Refresh live LUTs' then
        advanced = true
    end
end
assert(not advanced, 'Obsolete manual refresh section remains visible')
local advanced_complete = false
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.text then
        assert(not c.text:find('nil value', 1, true), 'Advanced layout errored')
    end
    if c.full_text == 'Send to LUT Editor' then
        advanced_complete = true
    end
end
assert(advanced_complete, 'Advanced expansion stopped rendering the panel')
view.advanced = false
state.palette_count = 1
local single = menu.compose(1920, 1080)
local selectors = 0
for _, c in ipairs(single) do
    if c.full_text == 'LUT 1' then
        selectors = selectors + 1
    end
end
assert(selectors == 1, 'Gear table selection retained the obsolete per-gear dropdowns')
state.palette_count = 2
-- Floating scratch opens independently, displays ten empty slots and closes cleanly.
view.scratch_open = true
local floating = menu.compose(1920, 1080)
local empty_count = 0
local close_button
for _, c in ipairs(floating) do
    if c.full_text and c.full_text:match('^Empty %d+$') then
        empty_count = empty_count + 1
    end
    if c.text == 'X' and c.popup then
        close_button = c
    end
end
assert(empty_count == 10 and close_button, 'Floating scratch missing slots or close')
menu.tick({
    down = function(k)
        return k == 1
    end,
    mouse = function()
        return close_button.x + 2, close_button.y + 2
    end,
    wheel = function()
        return 0
    end,
})
menu.tick({
    down = function()
        return false
    end,
    mouse = function()
        return close_button.x + 2, close_button.y + 2
    end,
    wheel = function()
        return 0
    end,
})
assert(not view.scratch_open, 'Floating scratch close did not return to table interaction')
assert(next(view.swatches) == nil, 'Empty fresh-session slots unexpectedly populated')
state.time = 1.13
local second = menu.compose(1920, 1080)
local changed = false
for i, c in ipairs(first) do
    local other = second[i]
    if c.type == 'rect' and other and c.c[1] ~= other.c[1] then
        changed = true
    end
end
assert(changed, 'Loader throbber did not animate')
state.tables = { { name = 'Table 1', width = 23, height = 8, data = a } }
local dedup = menu.compose(1920, 1080)
local primary_rows = 0
local linked = false
for _, c in ipairs(dedup) do
    if c.text == 'Row 1' then
        primary_rows = primary_rows + 1
    end
    if c.full_text and c.full_text:find('shared preview', 1, true) then
        linked = true
    end
end
assert(primary_rows == 2 and not linked, 'Armor/Helmet previews should remain visible without the imported grid')
-- Real swatch click routes exact RGB cell to the simple color picker.
local swatch
for _, c in ipairs(dedup) do
    if c.type == 'rect' and c.w == 22 * menu.window_bounds.scale and c.h == 16 * menu.window_bounds.scale then
        swatch = c
        break
    end
end
assert(swatch, 'Table swatches missing')
menu.tick({
    down = function(k)
        return k == 1
    end,
    mouse = function()
        return swatch.x + 2, swatch.y + 2
    end,
    wheel = function()
        return 0
    end,
})
menu.tick({
    down = function()
        return false
    end,
    mouse = function()
        return swatch.x + 2, swatch.y + 2
    end,
    wheel = function()
        return 0
    end,
})
assert(picked and picked.row == 1 and picked.col == 1, 'Swatch selection routed wrong cell')
assert(not menu.color_picker, 'Left click unexpectedly opened the color picker')
local highlights = 0
for _, c in ipairs(menu.compose(1920, 1080)) do
    if
        c.type == 'rect'
        and c.w == 26 * menu.window_bounds.scale
        and c.h == 2 * menu.window_bounds.scale
        and c.c[1] == 244
    then
        highlights = highlights + 1
    end
end
assert(highlights == 2, 'Selection highlighted shared data in multiple sections')

-- Selecting another cell must not replace the held scratch color.
view.scratch = { 12, 34, 56 }
state.time = state.time + 0.5
menu.tick({
    down = function(k)
        return k == 1
    end,
    mouse = function()
        return swatch.x + 2, swatch.y + 2
    end,
    wheel = function()
        return 0
    end,
})
menu.tick({
    down = function()
        return false
    end,
    mouse = function()
        return swatch.x + 2, swatch.y + 2
    end,
    wheel = function()
        return 0
    end,
})
assert(view.scratch[1] == 12, 'Palette selection replaced scratch color')
assert(
    menu.color_picker and menu.color_picker.control.id == 'quick_color',
    'Double-click did not open the swatch color picker'
)
menu.color_picker = nil
menu.compose(1920, 1080)
menu.tick({
    down = function(k)
        return k == 2
    end,
    mouse = function()
        return swatch.x + 2, swatch.y + 2
    end,
    wheel = function()
        return 0
    end,
})
menu.tick({
    down = function()
        return false
    end,
    mouse = function()
        return swatch.x + 2, swatch.y + 2
    end,
    wheel = function()
        return 0
    end,
})
assert(api.mods.import_test.handle.get('quick_color') == '#0C2238', 'Right click did not paint scratch color')
assert(not menu.color_picker, 'Right click unexpectedly opened the color picker')
menu.color_picker = nil
state.raw = { tables = state.tables, armor = state.armor, helmet = state.helmet }
assert(menu.compose(1920, 1080))
state.tables = nil
-- The raw lists contain every gear table, not the selected-only Basic summary.
local original_armor, original_helmet, original_raw = state.armor, state.helmet, state.raw
local many_armor, many_helmet = {}, {}
for _, kind in ipairs({ 'armor', 'helmet' }) do
    local entries = kind == 'armor' and many_armor or many_helmet
    for number = 1, (kind == 'armor' and 11 or 4) do
        local height = number == 11 and 32 or 8
        local data = ffi.new('float[?]', 23 * height * 4)
        for i = 0, 23 * height * 4 - 1 do
            data[i] = i % 4 == 3 and 1 or number / 16
        end
        entries[#entries + 1] = {
            name = (kind == 'armor' and 'Armor' or 'Helmet') .. ' LUT ' .. number,
            resource = string.format('[0x%016x]', (kind == 'armor' and 100 or 200) + number),
            lut = number,
            index = 500 + number * 7,
            width = 23,
            height = height,
            data = data,
        }
    end
    local choice = api.mods.import_test.controls['basic_' .. kind .. '_lut']
    choice.choices = {}
    for number = 1, #entries do
        choice.choices[number] = 'LUT ' .. number
    end
end
state.raw = { armor = many_armor, helmet = many_helmet, tables = {} }
state.armor, state.helmet = { many_armor[1] }, { many_helmet[1] }
state.palette_ready = true
state.busy = false
state.palette_count = 1
view.selected, view.gear_scroll = nil, {}
local function find_label(commands, value)
    for _, command in ipairs(commands) do
        if command.full_text == value or command.text == value then
            return command
        end
    end
end
local function compose()
    return menu.compose(1920, 1080)
end
local function wheel_at(kind, delta)
    local b, w = view.gear_bounds[kind], menu.window_bounds
    local x = w.x + (b.x + b.w / 2) * w.scale
    local y = w.y + (b.y + b.h / 2) * w.scale
    menu.tick({
        down = function()
            return false
        end,
        mouse = function()
            return x, y
        end,
        wheel = function()
            return delta
        end,
    })
end
local commands = compose()
assert(
    find_label(commands, 'Armor LUT 2') and find_label(commands, 'Helmet LUT 2'),
    'Raw gear lists were reduced to their selected tables'
)
assert(not find_label(commands, 'Armor LUT 11'), 'Off-screen table rendered despite bounded viewport')
local seen, last_title = {}, nil
for _ = 1, math.ceil(view.gear_max.armor / 60) + 1 do
    commands = compose()
    for number = 1, #many_armor do
        local label = find_label(commands, 'Armor LUT ' .. number)
        if label then
            seen[number] = true
            if number == 11 then
                last_title = label
            end
        end
    end
    if last_title then
        break
    end
    wheel_at('armor', -120)
end
for number = 1, #many_armor do
    assert(seen[number], 'A loaded Armor table could not be reached by scrolling: ' .. number)
end
assert(last_title and view.gear_scroll.helmet == 0, 'Armor scrolling moved Helmet or missed final table')
local calls_before, data_before = pick_calls, many_armor[11].data[0]
tap(last_title.x + 3, last_title.y + 2)
assert(
    api.mods.import_test.handle.get('basic_armor_lut') == 11,
    'Table title selected a group index instead of its gear ordinal'
)
assert(
    pick_calls == calls_before and many_armor[11].data[0] == data_before and not view.selected,
    'Title selection edited/applied a table'
)
commands = compose()
local hash = assert(find_label(commands, many_armor[11].resource), 'Final table resource ID missing')
assert(api.mods.import_test.handle.set('basic_armor_lut', 1))
tap(hash.x + 3, hash.y + 2)
assert(
    api.mods.import_test.handle.get('basic_armor_lut') == 11 and pick_calls == calls_before,
    'Resource ID click did not select the exact gear table'
)
-- A swatch on the last table still routes to that exact document and kind.
local last_swatch
for _ = 1, 8 do
    commands = compose()
    for _, command in ipairs(commands) do
        if
            command.type == 'rect'
            and command.w == 22 * menu.window_bounds.scale
            and command.h == 16 * menu.window_bounds.scale
            and command.c[1] == 175
        then
            last_swatch = command
            break
        end
    end
    if last_swatch then
        break
    end
    wheel_at('armor', -120)
end
assert(last_swatch, 'Visible final-table swatches missing')
tap(last_swatch.x + 2, last_swatch.y + 2)
assert(
    picked.entry == many_armor[11] and picked.kind == 'armor' and picked.col == 1,
    'Last table swatch selected another document/kind'
)
view.selected = nil
wheel_at('armor', -120000)
commands = compose()
assert(find_label(commands, 'Row 32'), '32-row table could not reach its final row')
local count = #commands
assert(count < 700, 'Off-screen gear rows still generated draw commands')
local armor_scroll = view.gear_scroll.armor
wheel_at('helmet', -120000)
commands = compose()
assert(
    view.gear_scroll.armor == armor_scroll and find_label(commands, many_helmet[4].resource),
    'Helmet scroll moved Armor or could not reach its final table'
)
local helmet_hash = assert(find_label(commands, many_helmet[4].resource))
tap(helmet_hash.x + 3, helmet_hash.y + 2)
assert(api.mods.import_test.handle.get('basic_helmet_lut') == 4, 'Helmet resource selected an Armor/global ordinal')
-- Large fonts at 85 percent scale retain reachable tables and bounded swatch rows.
menu.font_size, menu.ui_scale = 20, 0.85
menu.window_width, menu.window_height = 1420, 960
view.gear_scroll = {}
commands = compose()
assert(
    find_label(commands, 'Armor LUT 1') and find_label(commands, 'Helmet LUT 1'),
    'Large font hides the gear table headings'
)
wheel_at('armor', -120000)
commands = compose()
assert(find_label(commands, 'Row 32') and #commands < 700, 'Large font cannot reach row32 or renders off-screen rows')
state.palette_ready = false
view.selected = { key = 'armor/577', row = 32, column = 1 }
commands = compose()
assert(not view.selected, 'Unloaded palette retained an editable Scratch target')
assert(
    not find_label(commands, 'Armor LUT 1') and not find_label(commands, 'Helmet LUT 4'),
    'Unloaded palettes still show interactive gear tables'
)
assert(view.gear_max.armor == 0 and view.gear_max.helmet == 0, 'Unloaded tables retained scrolling')
assert(find_label(commands, 'Load current gear or import a LUT.'), 'Unloaded gear lacks guidance')
state.armor, state.helmet, state.raw = original_armor, original_helmet, original_raw
state.palette_ready, state.palette_count, state.busy = true, 2, true
view.gear_scroll, view.selected = {}, nil
menu.font_size, menu.ui_scale, menu.window_width, menu.window_height = 12, 1, 1800, 1000
local function esc(t)
    return tostring(t):gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;')
end
local f = assert(io.open('dist/import-menu-preview.svg', 'wb'))
f:write(
    '<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080"><rect width="1920" height="1080" fill="#101114"/>'
)
for _, c in ipairs(second) do
    local color = string.format('#%02X%02X%02X', c.c[1], c.c[2], c.c[3])
    if c.type == 'rect' then
        f:write(
            string.format(
                '<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s"/>',
                c.x,
                1080 - c.y - c.h,
                c.w,
                c.h,
                color
            )
        )
    else
        f:write(
            string.format(
                '<text x="%.2f" y="%.2f" font-family="Segoe UI" font-size="%.2f" fill="%s">%s</text>',
                c.x,
                1080 - c.y,
                c.size,
                color,
                esc(c.text)
            )
        )
    end
end
f:write('</svg>')
f:close()
print(
    'PASS Import view: responsive toolbar, all loaded gear LUTs, exact title/hash selection, independent scroll, bounded custom rows, safe readiness and swatch editing'
)

assert(
    menu_factory.key_name(45) == 'Insert'
        and menu_factory.key_name(120) == 'F9'
        and menu_factory.key_name(32) == 'Space'
        and menu_factory.key_name(162) == 'Left Ctrl',
    'Readable shortcut names missing'
)
