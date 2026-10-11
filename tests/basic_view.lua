local ffi = require('ffi')
local core = dofile('vendor/menu/core.lua')
local api = core.new({
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
})
local data = ffi.new('float[?]', 23 * 8 * 4)
for i = 0, 23 * 8 * 4 - 1 do
    data[i] = 0.5
end
local state = {
    editor = { data = data, width = 23, height = 8 },
    palette_count = 1,
    status = 'Ready',
    armor_checked = true,
    helmet_checked = false,
}
state.raw = { basic = { armor = { document = state.editor }, helmet = { document = state.editor } } }
for _, kind in ipairs({ 'armor', 'helmet' }) do
    state.raw.basic[kind].camo_rows = {}
    for row = 1, 64 do
        state.raw.basic[kind].camo_rows[row] = true
    end
end
local selected, selected_kind
local selected_calls, identify_calls = 0, 0
local camo_toggles = {}
local export_hits = 0
local Basic = dofile('src/editor/basic_view.lua')
local view = Basic.new(
    function()
        return state
    end,
    function(row, kind)
        selected_calls = selected_calls + 1
        selected, selected_kind = row, kind
    end,
    nil,
    function(row, kind, checked, expected_rows)
        local panel = state.raw.basic[kind]
        if expected_rows and panel.camo_rows ~= expected_rows then
            return false
        end
        camo_toggles[#camo_toggles + 1] = { row = row, kind = kind, checked = checked, expected_rows = expected_rows }
        panel.camo_rows = panel.camo_rows or {}
        panel.camo_rows[row] = checked
        local any = false
        for index = 1, panel.document.height do
            any = any or panel.camo_rows[index] == true
        end
        local registry = api.mods.basic_test.controls
        registry['basic_' .. kind .. '_camo'].disabled = not any
        registry['basic_' .. kind .. '_camo_colorway'].disabled = not any
        for color = 1, 4 do
            registry['basic_' .. kind .. '_camo_color_' .. color].disabled = not any
        end
    end
)
local controls = {
    { id = 'palette', type = 'choice', label = 'Imported LUT', choices = { 'Import first', 'LUT 2' }, default = 1 },
    {
        id = 'outfit_preset',
        type = 'choice',
        label = 'Saved outfit',
        choices = { 'Choose saved outfit...', 'Example' },
        default = 1,
    },
    {
        id = 'export_format',
        type = 'choice',
        label = 'Export format',
        choices = { 'DDS', 'Selected LUT Patch', 'Entire Palette Patch', 'All Custom LUTs (DDS)' },
        default = 1,
        on_change = function(value)
            state.export_format = value
        end,
    },
    {
        id = 'dds_naming',
        type = 'choice',
        presentation = 'dropdown',
        label = 'DDS filenames',
        choices = { 'LUT# + HEX', 'LUT# + Decimal', 'LUT#', 'HEX', 'Decimal' },
        default = 1,
    },
    { id = 'basic_target', type = 'choice', label = 'Worn gear', choices = { 'Armor', 'Helmet' }, default = 1 },
    { id = 'cell_color', type = 'color', label = 'Primary color', default = '#808080' },
    { id = 'basic_preset_name', type = 'input', label = 'Preset name', default = 'test' },
    { id = 'basic_preset', type = 'choice', label = 'Presets', choices = { 'New preset...', 'Saved' }, default = 1 },
}
for _, kind in ipairs({ 'armor', 'helmet' }) do
    controls[#controls + 1] =
        { id = 'basic_' .. kind .. '_lut', type = 'choice', label = kind .. ' LUT', choices = { 'LUT 1' }, default = 1 }
    controls[#controls + 1] = {
        id = 'basic_' .. kind .. '_camo',
        type = 'choice',
        presentation = 'dropdown',
        label = kind .. ' Camo',
        choices = { 'Off', 'Pattern 0', 'Pattern 1' },
        default = 1,
    }
    controls[#controls + 1] = {
        id = 'basic_' .. kind .. '_camo_colorway',
        type = 'choice',
        presentation = 'dropdown',
        label = kind .. ' Camo colorway',
        choices = { 'Current / custom', 'Jungle', 'Desert', 'Urban', 'Arctic' },
        default = 1,
    }
    for color = 1, 4 do
        controls[#controls + 1] = {
            id = 'basic_' .. kind .. '_camo_color_' .. color,
            type = 'color',
            label = 'Camo color ' .. color,
            default = '#808080',
        }
    end
end
for _, kind in ipairs({ 'armor', 'helmet' }) do
    controls[#controls + 1] = {
        id = 'basic_apply_' .. kind,
        type = 'button',
        label = 'Apply ' .. kind,
        on_activate = function()
            return true
        end,
    }
end
for _, id in ipairs({
    'apply_import_armor',
    'apply_import_helmet',
    'apply_file_armor',
    'apply_file_helmet',
    'identify_region',
    'stop_identify',
    'apply_matching',
    'outfit_apply_armor',
    'outfit_apply_helmet',
    'save_setup',
    'save_patch_all',
    'save_dds',
    'export_selected',
    'open_export',
}) do
    controls[#controls + 1] = {
        id = id,
        type = 'button',
        label = id,
        on_activate = function()
            if id == 'export_selected' then
                export_hits = export_hits + 1
            elseif id == 'identify_region' then
                identify_calls = identify_calls + 1
            end
            return true
        end,
    }
end
for _, id in ipairs({ 'basic_advanced', 'basic_copy_helmet', 'basic_copy_helmet_all', 'basic_copy_armor' }) do
    controls[#controls + 1] = {
        id = id,
        type = 'button',
        label = id,
        on_activate = function()
            return true
        end,
    }
end
for _, id in ipairs({
    'browse',
    'populate_worn',
    'target_helmet',
    'target_armor',
    'apply_editor',
    'basic_save',
    'basic_export',
    'undo',
    'redo',
    'restore_imported',
    'restore',
}) do
    controls[#controls + 1] = {
        id = id,
        type = 'button',
        label = id,
        on_activate = function()
            return true
        end,
    }
end
api.register({
    id = 'basic_test',
    name = 'Epic LUT',
    pages = {
        {
            id = 'basic',
            name = 'Basic',
            min_width = 1100,
            min_height = Basic.minimum_height,
            require_confirmation = false,
            controls = controls,
            render_layout = view.draw,
        },
    },
})
api.mods.basic_test.tabs_top = true
api.mods.basic_test.pages[1].render_layout = view.draw
api.mods.basic_test.pages[1].minimum_width = 1100
api.mods.basic_test.pages[1].minimum_height = Basic.minimum_height
local menu = dofile('vendor/menu/menu.lua').new(api, function(t, size)
    return #t * size * 0.5
end)
menu.epic_typography = true
menu.visible = true
menu.window_width = 1100
menu.window_height = Basic.minimum_height
local function region_point(commands, label)
    local window = menu.window_bounds
    local bounds
    for _, b in pairs(view.region_bounds) do
        local lower, upper = window.x + b.x * window.scale, window.x + (b.x + b.w) * window.scale
        if label.x >= lower and label.x < upper then
            bounds = { x = lower, right = upper, color_x = window.x + b.color_x * window.scale }
        end
    end
    assert(bounds, 'Region color hit lacks a gear-column owner')
    for _, c in ipairs(commands) do
        if
            c.type == 'rect'
            and math.abs(c.x - bounds.color_x) < 0.01
            and c.x >= bounds.x
            and c.x + c.w <= bounds.right + 0.01
            and c.y <= label.y
            and c.y + c.h > label.y
            and c.w > 0
        then
            return { x = c.x + c.w / 2 - 2, y = c.y + c.h / 2 - 2 }
        end
    end
    error('Region color swatch is not present beside its label')
end
local commands = menu.compose(1920, 1080)
local regions = 0
local row8
for _, c in ipairs(commands) do
    if c.full_text and c.full_text:match('^Region %d+$') then
        regions = regions + 1
        if c.full_text == 'Region 8' then
            row8 = c
        end
    end
    assert(c.text ~= 'Value Editor - grouped by rows', 'Advanced editor leaked into Basic')
end
local apply_labels = {}
for _, c in ipairs(commands) do
    if c.full_text then
        apply_labels[c.full_text] = true
    end
end
assert(
    not apply_labels['Apply LUT 1 to All Armor']
        and not apply_labels['Restore Imported']
        and not apply_labels['Apply Imported Texture'],
    'Unused import controls should be hidden'
)
state.loaded = state.editor
local imported_labels = {}
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text then
        imported_labels[c.full_text] = true
    end
end
assert(
    imported_labels['Apply LUT 1 to All Armor']
        and imported_labels['Apply LUT 1 to All Helmet']
        and imported_labels['Apply Imported Texture'],
    'Loaded import controls missing'
)
assert(regions == 16 and row8, 'Basic did not show all eight regions in both gear columns: ' .. regions)
-- Ordinary eight-row LUTs fit together. Wheels and stale saved offsets must
-- not turn a standard gear table into a scroll-only list.
for _, kind in ipairs({ 'armor', 'helmet' }) do
    local bounds = view.region_bounds[kind]
    view.wheel(bounds.x + 5, bounds.y + 5, -12000)
    local last = false
    for _, c in ipairs(menu.compose(1920, 1080)) do
        if c.full_text == 'Region 8' then
            last = true
            row8 = c
        end
    end
    assert(
        last and view.region_maximum[kind] == 0 and view.region_scroll[kind] == 0,
        'Standard eight-row Basic table requires region scrolling'
    )
end
state.palette_count = 2
state.raw.matching = { matched = 1, unmatched = 1, unidentified = 0, ambiguous = 0 }
local matching = false
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text == 'Apply Matching LUTs' then
        matching = true
    end
end
assert(matching, 'Basic matching-import action missing')
-- Compact Basic keeps the actions above the footer and scrolls independently of regions.
local armor_scroll, helmet_scroll = view.region_scroll.armor, view.region_scroll.helmet
assert(view.wheel(view.action_bounds.x + 10, view.action_bounds.y + 10, -1200), 'Basic action pane ignored wheel input')
assert(
    view.action_scroll == view.action_maximum
        and view.region_scroll.armor == armor_scroll
        and view.region_scroll.helmet == helmet_scroll,
    'Action scrolling moved primary regions'
)
for _, resolution in ipairs({ { 1920, 1080 }, { 1280, 720 } }) do
    for _, font in ipairs({ 12, 20 }) do
        menu.compact_fonts, menu.font_size = true, font
        menu.compose(unpack(resolution))
        view.action_scroll = view.action_maximum
        local export_labels = {}
        for _, c in ipairs(menu.compose(unpack(resolution))) do
            if c.full_text then
                export_labels[c.full_text] = c
            end
        end
        assert(
            export_labels['Export']
                and export_labels['Export...']
                and export_labels['DDS']
                and export_labels['Open Export Location'],
            'Basic export section not reachable'
        )
        local bottom = menu.window_bounds.y + 110 * menu.window_bounds.scale
        local status, restore = export_labels.Ready, export_labels['Restore Arrowhead LUT (Original)']
        assert(
            status and restore and status.y + status.size <= restore.y - 8 * menu.window_bounds.scale,
            'Basic status overlaps restore control after font resizing'
        )
        for _, label in ipairs({ 'Export...', 'DDS', 'Open Export Location' }) do
            assert(export_labels[label].y > bottom, 'Basic export overlapped window footer: ' .. label)
        end
    end
end
menu.font_size = 12
local export_button
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text == 'Export...' then
        export_button = c
    end
end
assert(export_button)
for _, pressed in ipairs({ true, false }) do
    menu.tick({
        down = function(key)
            return pressed and key == 1
        end,
        mouse = function()
            return export_button.x + 2, export_button.y + 2
        end,
        wheel = function()
            return 0
        end,
    })
end
assert(export_hits == 1, 'Scrolled Basic export button could not be clicked')

view.wheel(view.region_bounds.armor.x + 10, view.region_bounds.armor.y + 10, -1200)
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text == 'Region 8' and c.x < menu.window_bounds.x + menu.window_bounds.w * 0.54 then
        row8 = c
    end
end
local row8_point = region_point(menu.compose(1920, 1080), row8)
local x, y = row8_point.x + 2, row8_point.y + 2
menu.tick({
    down = function(k)
        return k == 1
    end,
    mouse = function()
        return x, y
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
        return x, y
    end,
    wheel = function()
        return 0
    end,
})
assert(
    selected == 8 and menu.color_picker and menu.color_picker.control.id == 'cell_color',
    'Basic click did not open primary-color picker for the selected row'
)
menu.close_color(false)
state.palette_ready = false
for _, command in ipairs(menu.compose(1920, 1080)) do
    assert(
        command.full_text ~= 'Region 1' and command.text ~= 'Region 1',
        'Basic exposes editable regions before current/imported LUTs are loaded'
    )
end
state.palette_ready = true
local handle = api.mods.basic_test.handle
local saved_editor = state.editor
state.editor = nil
local function bulk_label(value)
    for _, c in ipairs(menu.compose(1920, 1080)) do
        if c.full_text == value then
            return c
        end
    end
end
local function tap_label(value)
    local c = assert(bulk_label(value), 'Missing Basic bulk export control: ' .. value)
    for _, down in ipairs({ true, false }) do
        menu.tick({
            down = function(key)
                return down and key == 1
            end,
            mouse = function()
                return c.x + 3, c.y + 3
            end,
            wheel = function()
                return 0
            end,
        })
    end
end
for _, format in ipairs({ 1, 2, 3, 4 }) do
    assert(handle.set('export_format', format))
    menu.compose(1920, 1080)
    view.action_scroll = view.action_maximum
    local prior = export_hits
    tap_label('Export...')
    assert(
        export_hits == prior + ((format == 3 or format == 4) and 1 or 0),
        'Basic full-collection export eligibility changed for format ' .. format
    )
    assert((bulk_label('LUT# + HEX') ~= nil) == (format == 4), 'Basic DDS naming appears in the wrong format')
end
tap_label('LUT# + HEX')
assert(menu.dropdown and menu.dropdown.control.id == 'dds_naming', 'Basic bulk naming dropdown did not open')
menu.key(40)
menu.key(13)
assert(
    handle.get('dds_naming') == 2 and bulk_label('LUT# + Decimal'),
    'Basic naming selection was not shared with Toolbox settings'
)
for _, font in ipairs({ 12, 20 }) do
    menu.font_size = font
    menu.compose(1920, 1080)
    view.action_scroll = view.action_maximum
    local naming = assert(bulk_label('LUT# + Decimal'))
    local folder = assert(bulk_label('Open Export Location'))
    local export = assert(bulk_label('Export...'))
    assert(
        export.y > naming.y + naming.size and naming.y > folder.y + folder.size,
        'Basic bulk controls collide after font resizing'
    )
end
state.busy = true
local prior = export_hits
tap_label('Export...')
assert(export_hits == prior, 'Basic bulk export remained active during an import')
state.busy = false
state.editor = saved_editor
-- Camo stays in a fixed, compact footer. Region wheels belong to their gear
-- column and expose every row even when an imported-LUT action is present.
local camo_data = ffi.new('float[?]', 23 * 64 * 4)
local camo_document = { data = camo_data, width = 23, height = 64 }
state.raw.basic.armor.document, state.raw.basic.helmet.document = camo_document, camo_document
menu.text_metrics = function(size)
    return { min_y = -0.2 * size, max_y = 0.85 * size }
end
local function column_label(commands, kind, label)
    local b, window = view.region_bounds[kind], menu.window_bounds
    local left, right = window.x + b.x * window.scale, window.x + (b.x + b.w) * window.scale
    local found
    for _, c in ipairs(commands) do
        if (c.full_text or c.text) == label and c.x >= left and c.x < right then
            if not found or c.y < found.y then
                found = c
            end
        end
    end
    return found
end
local function tap(command)
    for _, pressed in ipairs({ true, false }) do
        menu.tick({
            down = function(key)
                return pressed and key == 1
            end,
            mouse = function()
                return command.x + 2, command.y + 2
            end,
            wheel = function()
                return 0
            end,
        })
    end
end
for _, loaded in ipairs({ false, true }) do
    state.loaded = loaded and saved_editor or nil
    for _, font in ipairs({ 12, 20 }) do
        for _, scale in ipairs({ 0.7, 1, 1.15 }) do
            menu.font_size, menu.ui_scale = font, scale
            view.region_scroll.armor, view.region_scroll.helmet = 0, 0
            local before = menu.compose(1920, 1080)
            local camo_armor = assert(column_label(before, 'armor', 'Off'))
            local camo_helmet = assert(column_label(before, 'helmet', 'Off'))
            for _, kind in ipairs({ 'armor', 'helmet' }) do
                local b = view.region_bounds[kind]
                local heading = assert(column_label(before, kind, 'Camo'))
                assert(column_label(before, kind, '64 checked regions'))
                local field = assert(column_label(before, kind, 'Off'))
                local footer_label = kind == 'armor' and 'Copy Helmet' or 'Copy Armor'
                local footer = assert(column_label(before, kind, footer_label))
                assert(
                    heading.y - 0.2 * heading.size > field.y + 0.85 * field.size,
                    'Camo heading overlaps its selector'
                )
                assert(
                    field.y - 0.2 * field.size > footer.y + 0.85 * footer.size,
                    'Camo overlaps the lower import/copy action'
                )
                assert(view.wheel(b.x + 5, b.y + 5, -12000))
                assert(view.region_scroll[kind] == view.region_maximum[kind] and view.region_scroll[kind] > 0)
                if kind == 'armor' then
                    assert(view.region_scroll.helmet == 0, 'Armor region wheel moved Helmet regions')
                end
                local after = menu.compose(1920, 1080)
                local last =
                    assert(column_label(after, kind, 'Region 64'), 'Last row disappeared behind the Camo footer')
                local window = menu.window_bounds
                assert(last.y - 0.2 * last.size >= window.y + b.y * window.scale)
                assert(last.y + 0.85 * last.size <= window.y + (b.y + b.h) * window.scale)
                local current = assert(column_label(after, kind, 'Off'))
                assert(current.y == field.y, 'Region scrolling moved the Camo selector')
                assert(
                    column_label(after, kind, footer_label).y == footer.y,
                    'Region scrolling moved the lower actions'
                )
                -- Click the last color swatch through its current scroll position.
                tap(region_point(after, last))
                assert(
                    selected == 64 and selected_kind == kind and menu.color_picker,
                    'Scrolled final region hit the wrong gear'
                )
                menu.close_color(false)
            end
            local after = menu.compose(1920, 1080)
            assert(
                column_label(after, 'armor', 'Off').y == camo_armor.y
                    and column_label(after, 'helmet', 'Off').y == camo_helmet.y
            )
            local before_armor, before_helmet = view.region_scroll.armor, view.region_scroll.helmet
            view.wheel(view.action_bounds.x + 5, view.action_bounds.y + 5, -1200)
            assert(
                view.region_scroll.armor == before_armor and view.region_scroll.helmet == before_helmet,
                'Action scrolling moved gear regions'
            )
        end
    end
end
menu.font_size, menu.ui_scale = 12, 1
tap(assert(column_label(menu.compose(1920, 1080), 'armor', 'Off')))
assert(menu.dropdown and menu.dropdown.control.id == 'basic_armor_camo')
menu.key(40)
menu.key(13)
assert(
    handle.get('basic_armor_camo') == 2 and handle.get('basic_helmet_camo') == 1,
    'Camo chooser changed the other gear column'
)
api.mods.basic_test.controls.basic_helmet_camo.disabled = true
tap(assert(column_label(menu.compose(1920, 1080), 'helmet', 'Off')))
assert(not menu.dropdown, 'Registry-disabled Camo opened an editable dropdown')

-- Camo colorways and four independent RGB pickers share the per-gear footer.
-- Their swatches read the camo tint columns, never the primary color or alpha.
for color = 1, 4 do
    local at = (15 + color) * 4
    camo_data[at], camo_data[at + 1], camo_data[at + 2], camo_data[at + 3] = color / 5, 0.3, 0.4, 0.91
end
local tint_commands = menu.compose(1920, 1080)
for _, kind in ipairs({ 'armor', 'helmet' }) do
    tap(assert(column_label(tint_commands, kind, 'Current / custom')))
    assert(menu.dropdown and menu.dropdown.control.id == 'basic_' .. kind .. '_camo_colorway')
    menu.key(27)
    for color = 1, 4 do
        local label = assert(column_label(menu.compose(1920, 1080), kind, tostring(color)))
        local scale = menu.window_bounds.scale
        local swatch
        for _, c in ipairs(menu.compose(1920, 1080)) do
            if
                c.type == 'rect'
                and math.abs(c.x - label.x) < 0.01
                and c.y < label.y
                and c.c[1] == math.floor(color / 5 * 255 + 0.5)
                and c.c[2] == 77
                and c.c[3] == 102
            then
                swatch = c
            end
        end
        assert(swatch, 'Camo RGB swatch read the wrong column')
        tap({ x = swatch.x + 2 * scale, y = swatch.y + 2 * scale })
        assert(
            menu.color_picker and menu.color_picker.control.id == 'basic_' .. kind .. '_camo_color_' .. color,
            'Camo swatch opened the wrong RGB picker'
        )
        menu.close_color(false)
    end
end
state.raw.basic.helmet.document = { data = ffi.new('float[?]', 16 * 5 * 4), width = 16, height = 5 }
local narrow = menu.compose(1920, 1080)
local narrow_label = assert(column_label(narrow, 'helmet', '1'))
tap({ x = narrow_label.x + 2, y = narrow_label.y - 16 * menu.window_bounds.scale })
assert(not menu.color_picker, 'Unsupported 16-column Cape exposed a Camo tint picker')
state.raw.basic.helmet.document = camo_document

-- Dirty guidance is content below the folder button, with its own measured
-- rows. Long native-font status text expands the scroll range rather than
-- overlapping controls or the fixed Basic footer.
state.dirty = true
state.status =
    'Applied Jungle colorway to all 64 regions in this Armor LUT. Exact colors are preserved when exported; save this appearance before switching to another preset.'
local dirty_notice = 'Modified - save or export to keep your colors.'
local dirty_scroll_exercised = false
for _, loaded in ipairs({ false, true }) do
    state.loaded = loaded and saved_editor or nil
    for _, font in ipairs({ 12, 20 }) do
        for _, resolution in ipairs({ { 1280, 720 }, { 1920, 1080 } }) do
            menu.font_size = font
            menu.compose(unpack(resolution))
            local maximum = view.action_maximum
            state.dirty = false
            menu.compose(unpack(resolution))
            assert(maximum >= view.action_maximum, 'Dirty notice reduced the action content extent')
            state.dirty = true
            menu.compose(unpack(resolution))
            view.action_scroll = view.action_maximum
            local commands = menu.compose(unpack(resolution))
            local folder, dirty_lines, scrollbar = nil, {}, nil
            for _, c in ipairs(commands) do
                local value = c.full_text or c.text
                if value == 'Open Export Location' then
                    folder = c
                elseif c.text_role == 'hint' and value and dirty_notice:find(value, 1, true) then
                    dirty_lines[#dirty_lines + 1] = c
                end
                if c.scrollbar == 'basic_actions' then
                    scrollbar = c
                end
            end
            assert(folder and #dirty_lines > 0, 'Basic dirty/footer content unreachable')
            local window, bounds = menu.window_bounds, view.action_bounds
            local lower = window.y + bounds.y * window.scale
            for _, c in ipairs(dirty_lines) do
                assert(c.y + 0.85 * c.size < folder.y - 0.2 * folder.size, 'Dirty notice overlaps Open Export Location')
                assert(c.y - 0.2 * c.size >= lower, 'Dirty notice escaped the action viewport into footer')
                assert(c.viewport, 'Dirty guidance lacks action viewport clipping')
            end
            if scrollbar then
                dirty_scroll_exercised = true
                local before_scroll = view.action_scroll
                local sx, sy = scrollbar.x + 2, scrollbar.y + scrollbar.h / 2
                menu.tick({
                    down = function(key)
                        return key == 1
                    end,
                    mouse = function()
                        return sx, sy
                    end,
                    wheel = function()
                        return 0
                    end,
                })
                menu.tick({
                    down = function(key)
                        return key == 1
                    end,
                    mouse = function()
                        return sx, sy + 16
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
                        return sx, sy + 16
                    end,
                    wheel = function()
                        return 0
                    end,
                })
                assert(view.action_scroll < before_scroll, 'Basic action scrollbar did not drag')
            else
                assert(
                    view.action_maximum == 0 and view.action_scroll == 0,
                    'Fully visible Basic action content retained a hidden scroll offset'
                )
            end
        end
    end
end
assert(dirty_scroll_exercised, 'Oversized Basic action content did not exercise scroll dragging')
state.dirty, state.status = false, 'Ready'
-- Render the actual viewport masks and footer chrome through the retained
-- native GUI mock. Checking only text baselines missed the previous bug: the
-- lower mask covered the upper four pixels of both fixed button borders.
local NativeView = dofile('vendor/menu/view.lua')
local native_items, native_id, native_order = {}, 0, 0
local function native_allocate(item)
    native_id, native_order = native_id + 1, native_order + 1
    item.order = native_order
    assert(item.z == math.floor(item.z), 'Basic footer emitted a fractional native layer')
    native_items[native_id] = item
    return native_id
end
local function ink(size)
    return { min_y = -0.2 * size, max_y = 0.85 * size, height = 1.05 * size }
end
local world = {}
local native = NativeView.new({
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
            return native_allocate({ x = p.x, y = p.y, w = size.x, h = size.y, z = p.z, color = color })
        end,
        text = function(_, value, _, size, _, p, color)
            local metric = ink(size)
            return native_allocate({
                x = p.x,
                y = p.y + metric.min_y,
                w = #value * size * 0.5,
                h = metric.height,
                z = p.z,
                color = color,
                text = value,
            })
        end,
        destroy_rect = function(_, id)
            native_items[id] = nil
        end,
        destroy_text = function(_, id)
            native_items[id] = nil
        end,
    },
}, true)
local function native_pixel(x, y)
    local winner
    for _, item in pairs(native_items) do
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
    return assert(winner, 'Missing Basic footer native pixel')
end
-- All ordinary gear regions fit at once, and their swatches use the available
-- viewport height. No saved offset or wheel input can hide one of eight rows.
local eight_previous = {
    armor = state.raw.basic.armor.document,
    helmet = state.raw.basic.helmet.document,
    loaded = state.loaded,
}
state.raw.basic.armor.document, state.raw.basic.helmet.document = saved_editor, saved_editor
for _, loaded in ipairs({ false, true }) do
    state.loaded = loaded and saved_editor or nil
    for _, font in ipairs({ 12, 20 }) do
        for _, resolution in ipairs({ { 1280, 720 }, { 1920, 1080 } }) do
            for _, scale in ipairs({ 0.7, 1, 1.15 }) do
                menu.font_size, menu.ui_scale = font, scale
                view.region_scroll.armor, view.region_scroll.helmet = 500, 900
                local commands = menu.compose(unpack(resolution))
                native.draw(commands)
                local region_count = 0
                for _, c in ipairs(commands) do
                    if c.full_text and c.full_text:match('^Region %d+$') then
                        region_count = region_count + 1
                    end
                    assert(
                        c.scrollbar ~= 'basic_armor_regions' and c.scrollbar ~= 'basic_helmet_regions',
                        'An ordinary eight-row Basic table renders a region scrollbar'
                    )
                end
                assert(region_count == 16, 'Basic eight-region matrix hides a gear row')
                for _, kind in ipairs({ 'armor', 'helmet' }) do
                    local b, window = view.region_bounds[kind], menu.window_bounds
                    assert(
                        view.region_maximum[kind] == 0 and view.region_scroll[kind] == 0,
                        'Eight-row Basic layout retained stale scroll or rounding overflow'
                    )
                    assert(
                        b.row_height >= 29 and math.abs(b.row_height * 8 - b.h) < 0.01,
                        'Eight-row Basic swatches do not fill their available viewport'
                    )
                    local previous, square_count = nil, 0
                    local center = window.x + (b.camo_x + b.camo_width / 2) * window.scale
                    for _, c in ipairs(commands) do
                        if
                            c.type == 'rect'
                            and c.ui_role == 'control_fill'
                            and math.abs(c.x + c.w / 2 - center) < 0.01
                            and math.abs(c.w - c.h) < 0.01
                            and c.y >= window.y + b.y * window.scale
                            and c.y + c.h <= window.y + (b.y + b.h) * window.scale
                        then
                            square_count = square_count + 1
                        end
                    end
                    assert(square_count == 8, 'Basic eight-row checkbox squares are not visible together')
                    for row = 1, 8 do
                        local label = assert(column_label(commands, kind, 'Region ' .. row))
                        assert(label.text == label.full_text, 'Basic region label was clipped at a large font')
                        assert(
                            label.y - 0.2 * label.size >= window.y + b.y * window.scale
                                and label.y + 0.85 * label.size <= window.y + (b.y + b.h) * window.scale,
                            'Eight-row Basic native glyph ink leaves its color viewport'
                        )
                        if previous then
                            assert(
                                previous.y - 0.2 * previous.size > label.y + 0.85 * label.size,
                                'Eight-row Basic labels overlap after stretching'
                            )
                        end
                        assert(
                            native_pixel(label.x + label.size * 0.1, label.y + label.size * 0.3).text == label.text,
                            'Native Basic row is obscured despite being in the eight-row command list'
                        )
                        local point = region_point(commands, label)
                        local pixel = native_pixel(point.x + 2, point.y + 2)
                        assert(
                            not pixel.text and pixel.color.r == 128 and pixel.color.g == 128 and pixel.color.b == 128,
                            'Eight-row Basic color swatch was masked by neighboring controls'
                        )
                        previous = label
                    end
                    local first = assert(column_label(commands, kind, 'Region 1'))
                    local last = assert(column_label(commands, kind, 'Region 8'))
                    if loaded then
                        local imported = assert(column_label(commands, kind, 'Apply DDS'))
                        assert(
                            imported.y - 0.2 * imported.size > first.y + 0.85 * first.size,
                            'Basic imported source overlaps the first of eight regions'
                        )
                    end
                    local camo = assert(column_label(commands, kind, 'Camo'))
                    assert(
                        last.y - 0.2 * last.size > camo.y + 0.85 * camo.size,
                        'Basic Camo footer overlaps the eighth region'
                    )
                    tap(region_point(commands, last))
                    assert(
                        selected == 8 and selected_kind == kind and menu.color_picker,
                        'Eighth Basic region is not clickable without scrolling'
                    )
                    menu.close_color(false)
                    assert(
                        view.wheel(b.x + 5, b.y + b.h / 2, -1200) and view.region_scroll[kind] == 0,
                        'Wheel input hid a fully visible ordinary Basic row'
                    )
                end
            end
        end
    end
end
state.raw.basic.armor.document, state.raw.basic.helmet.document = eight_previous.armor, eight_previous.helmet
state.loaded = eight_previous.loaded
local original_portrait = package.loaded['epic.player_preview.v1']
local preview_clicks, stop_clicks = 0, 0
package.loaded['epic.player_preview.v1'] = {
    toggle = function()
        preview_clicks = preview_clicks + 1
    end,
    is_enabled = function()
        return true
    end,
}
api.mods.basic_test.controls.stop_identify.on_activate = function()
    stop_clicks = stop_clicks + 1
end
for _, font in ipairs({ 12, 20 }) do
    for _, resolution in ipairs({ { 1280, 720 }, { 1920, 1080 } }) do
        for _, scale in ipairs({ 0.7, 1, 1.15 }) do
            menu.font_size, menu.ui_scale, menu.font_bold = font, scale, true
            state.loaded, state.dirty = saved_editor, true
            menu.compose(unpack(resolution))
            for _, position in ipairs({ 0, 0.5, 1 }) do
                view.action_scroll = view.action_maximum * position
                local commands = menu.compose(unpack(resolution))
                native.draw(commands)
                local window, logical = menu.window_bounds, view.footer_bounds
                local footer = {
                    x = window.x + logical.x * window.scale,
                    y = window.y + logical.y * window.scale,
                    w = logical.w * window.scale,
                    h = logical.h * window.scale,
                    button_width = logical.button_width * window.scale,
                }
                local labels = {}
                for _, c in ipairs(commands) do
                    if c.full_text == 'Player Preview' or c.full_text == 'Stop Highlight' then
                        labels[c.full_text] = c
                        assert(
                            not c.viewport and c.paint_plane >= 130,
                            'Fixed Basic footer retained scrolling-plane clipping'
                        )
                    end
                    if c.ui_role == 'viewport_mask' then
                        assert(
                            c.y >= footer.y + footer.h
                                or c.y + c.h <= footer.y
                                or c.x >= footer.x + footer.w
                                or c.x + c.w <= footer.x,
                            'Basic content mask intersects fixed footer chrome'
                        )
                    end
                end
                for _, label in ipairs({ 'Player Preview', 'Stop Highlight' }) do
                    local c = assert(labels[label], 'Fixed Basic footer label disappeared')
                    local metric = ink(c.size)
                    assert(
                        c.y + metric.min_y > footer.y and c.y + metric.max_y < footer.y + footer.h,
                        'Native footer ink does not fit the measured button row'
                    )
                    assert(
                        native_pixel(c.x + c.size * 0.1, c.y + metric.max_y - 0.25).text == label,
                        'Native viewport mask erased the upper footer glyph ink'
                    )
                    local bx = label == 'Player Preview' and footer.x or footer.x + footer.w - footer.button_width
                    local upper = native_pixel(bx + footer.button_width / 2, footer.y + footer.h - 0.5)
                    assert(
                        not upper.text and upper.z >= 130,
                        'Native content mask erased the upper footer button border'
                    )
                end
                for _, kind in ipairs({ 'armor', 'helmet' }) do
                    local registry = api.mods.basic_test.controls
                    local pattern_value =
                        registry['basic_' .. kind .. '_camo'].choices[handle.get('basic_' .. kind .. '_camo')]
                    local pattern = assert(column_label(commands, kind, pattern_value))
                    local colorway = assert(column_label(commands, kind, 'Current / custom'))
                    assert(
                        pattern.y - 0.2 * pattern.size > colorway.y + 0.85 * colorway.size,
                        'Basic Camo pattern/colorway selectors overlap after reordering'
                    )
                    for color = 1, 4 do
                        local number = assert(column_label(commands, kind, tostring(color)))
                        local swatch
                        for _, c in ipairs(commands) do
                            if
                                c.type == 'rect'
                                and math.abs(c.x - number.x) < 0.01
                                and c.y < number.y
                                and c.c[1] == math.floor(color / 5 * 255 + 0.5)
                                and c.c[2] == 77
                                and c.c[3] == 102
                            then
                                swatch = c
                            end
                        end
                        assert(
                            swatch and swatch.y > pattern.y + 0.85 * pattern.size,
                            'Basic Camo RGB swatches are not above the pattern/colorway selectors'
                        )
                        assert(
                            number.y - 0.2 * number.size > swatch.y + swatch.h,
                            'Basic Camo number labels overlap their reordered RGB swatches'
                        )
                    end
                end
                if position == 1 then
                    local preview_before, stop_before = preview_clicks, stop_clicks
                    tap({ x = footer.x + 3 * window.scale - 2, y = footer.y + footer.h - 2 * window.scale - 2 })
                    tap({
                        x = footer.x + footer.w - footer.button_width + 3 * window.scale - 2,
                        y = footer.y + footer.h - 2 * window.scale - 2,
                    })
                    assert(
                        preview_clicks == preview_before + 1 and stop_clicks == stop_before + 1,
                        'Fixed footer upper edges lost their hit targets to the scroll pane'
                    )
                end
            end
        end
    end
end
-- A Single LUT Import split chooses one shared source at the arrow; only its
-- main segment applies that source, to the gear column that was clicked.
local sources = {
    { data = data, width = 23, height = 8, source = 'C:/imported/Alpha.dds' },
    { data = camo_data, width = 23, height = 64, source = 'C:/imported/Beta.dds' },
}
local palette_control = api.mods.basic_test.controls.palette
palette_control.choices = { 'Alpha.dds', 'Beta.dds' }
palette_control.disabled = false
palette_control.on_change = function(value)
    state.loaded, state.palette_index = sources[value], value
end
local import_actions = {}
for _, kind in ipairs({ 'armor', 'helmet' }) do
    state.raw.basic[kind].kind = kind
    state.raw.basic[kind].group = {}
    state.raw.basic[kind].resource = kind == 'armor' and '[armor-target]' or '[helmet-target]'
    api.mods.basic_test.controls['apply_import_' .. kind].on_activate = function()
        import_actions[#import_actions + 1] = { kind = kind, source = state.loaded.source }
    end
end
local function split_label(commands, kind, filename)
    local b, window = view.region_bounds[kind], menu.window_bounds
    local lower, upper = window.x + b.x * window.scale, window.x + (b.x + b.w) * window.scale
    for _, c in ipairs(commands) do
        if
            c.full_text
            and c.full_text:sub(1, 6) == 'Apply '
            and c.full_text:find(filename, 1, true)
            and c.x >= lower
            and c.x < upper
        then
            return c
        end
    end
end
local function split_arrow(commands, kind, filename)
    local c = assert(split_label(commands, kind, filename), 'Single LUT Import filename not shown for ' .. kind)
    local b, window = view.region_bounds[kind], menu.window_bounds
    return { x = window.x + (b.x + b.w - 8) * window.scale - 2, y = c.y + c.size * 0.3 - 2 }
end
-- Destination -> imported source -> region colors. The imported source row
-- stays with its destination selector while each color column scrolls below;
-- loading an import must not reserve an empty area beside the Camo footer.
for _, font in ipairs({ 12, 20 }) do
    for _, resolution in ipairs({ { 1280, 720 }, { 1920, 1080 } }) do
        for _, scale in ipairs({ 0.7, 1, 1.15 }) do
            menu.font_size, menu.ui_scale = font, scale
            state.busy, state.loaded = false, nil
            view.region_scroll.armor, view.region_scroll.helmet = 0, 0
            local before = menu.compose(unpack(resolution))
            local fixed = {}
            for _, kind in ipairs({ 'armor', 'helmet' }) do
                assert(
                    not column_label(before, kind, 'Apply Imported Texture'),
                    'Basic source apply row is visible without an imported texture'
                )
                local copy = kind == 'armor' and 'Copy Helmet' or 'Copy Armor'
                fixed[kind] = {
                    camo = assert(column_label(before, kind, 'Camo')).y,
                    colorway = assert(column_label(before, kind, 'Current / custom')).y,
                    copy = assert(column_label(before, kind, copy)).y,
                }
                local first = assert(
                    column_label(before, kind, 'Region 1'),
                    'Basic first region is missing without an imported texture'
                )
                local window, b = menu.window_bounds, view.region_bounds[kind]
                assert(
                    first.y - 0.2 * first.size >= window.y + b.y * window.scale
                        and first.y + 0.85 * first.size <= window.y + (b.y + b.h) * window.scale,
                    'Basic first region ink escaped its no-import viewport'
                )
            end
            state.loaded = sources[1]
            local commands = menu.compose(unpack(resolution))
            for _, kind in ipairs({ 'armor', 'helmet' }) do
                local target = assert(column_label(commands, kind, 'LUT 1'))
                local heading = assert(column_label(commands, kind, 'Apply Imported Texture'))
                local main = assert(split_label(commands, kind, 'Alpha.dds'))
                local first = assert(column_label(commands, kind, 'Region 1'))
                assert(
                    main.full_text == 'Apply Alpha.dds',
                    'Basic apply source label repeats destination hashes or LUT ordinals'
                )
                assert(
                    target.y - 0.2 * target.size > heading.y + 0.85 * heading.size,
                    'Basic imported-texture heading overlaps its destination selector'
                )
                assert(
                    heading.y - 0.2 * heading.size > main.y + 0.85 * main.size,
                    'Basic imported-texture heading overlaps its split apply button'
                )
                local window, b = menu.window_bounds, view.region_bounds[kind]
                local top = window.y + (b.y + b.h) * window.scale
                assert(
                    main.y - 0.2 * main.size > top,
                    'Basic imported-texture apply button intrudes into scrolling region colors'
                )
                assert(
                    first.y + 0.85 * first.size < main.y - 0.2 * main.size,
                    'Basic first region overlaps the imported-texture apply button'
                )
                local copy = kind == 'armor' and 'Copy Helmet' or 'Copy Armor'
                assert(
                    column_label(commands, kind, 'Camo').y == fixed[kind].camo
                        and column_label(commands, kind, 'Current / custom').y == fixed[kind].colorway
                        and column_label(commands, kind, copy).y == fixed[kind].copy,
                    'Import loading left an unused reserve beside Basic Camo/copy controls'
                )
                local other = kind == 'armor' and 'helmet' or 'armor'
                local other_scroll = view.region_scroll[other]
                assert(view.wheel(b.x + 5, b.y + b.h / 2, -12000))
                commands = menu.compose(unpack(resolution))
                assert(
                    view.region_scroll[kind] == view.region_maximum[kind] and view.region_scroll[other] == other_scroll,
                    'Moved import row coupled Armor and Helmet region scrolling'
                )
                local last = assert(
                    column_label(commands, kind, 'Region 64'),
                    'Moved import row made the final Basic region unreachable'
                )
                assert(
                    last.y - 0.2 * last.size >= window.y + b.y * window.scale and last.y + 0.85 * last.size <= top,
                    'Final Basic region glyphs escaped the viewport below the imported source row'
                )
                assert(
                    column_label(commands, kind, 'Apply Imported Texture').y == heading.y
                        and split_label(commands, kind, 'Alpha.dds').y == main.y
                        and column_label(commands, kind, copy).y == fixed[kind].copy,
                    'Region scrolling moved Basic imported-source or copy controls'
                )
                native.draw(commands)
                for _, label in ipairs({ main, last }) do
                    assert(
                        native_pixel(label.x + label.size * 0.1, label.y + label.size * 0.3).text == label.text,
                        'Basic native source/region text was hidden after moving the import row'
                    )
                end
                tap(region_point(commands, last))
                assert(
                    selected == 64 and selected_kind == kind and menu.color_picker,
                    'Moved source row intercepted the final Basic region color click'
                )
                menu.close_color(false)
                view.region_scroll[kind] = 0
                commands = menu.compose(unpack(resolution))
                local reset = assert(column_label(commands, kind, 'Region 1'))
                tap(region_point(commands, reset))
                assert(
                    selected == 1 and selected_kind == kind and menu.color_picker,
                    'Moved source row intercepted the first Basic region color click'
                )
                menu.close_color(false)
            end
        end
    end
end
for _, font in ipairs({ 12, 20 }) do
    for _, scale in ipairs({ 0.7, 1, 1.15 }) do
        menu.font_size, menu.ui_scale = font, scale
        for _, kind in ipairs({ 'armor', 'helmet' }) do
            state.busy, state.loaded, state.palette_index = false, sources[1], 1
            assert(handle.set('palette', 1))
            local commands = menu.compose(1280, 720)
            local prior = #import_actions
            tap(split_arrow(commands, kind, 'Alpha.dds'))
            assert(
                menu.dropdown and menu.dropdown.control.id == 'palette' and #import_actions == prior,
                'Single LUT Import arrow applied instead of choosing its source'
            )
            local anchor_x, anchor_top, anchor_width = menu.dropdown.x, menu.dropdown.top, menu.dropdown.width
            commands = menu.compose(1280, 720)
            assert(
                menu.dropdown.x == anchor_x and menu.dropdown.top == anchor_top and menu.dropdown.width == anchor_width,
                'Shared palette widgets stole the split popup anchor after composition'
            )
            assert(
                math.abs(anchor_x - view.region_bounds[kind].x) < 0.01,
                'Split popup opened at the other gear column or action pane'
            )
            local option
            for _, c in ipairs(commands) do
                if c.popup and (c.full_text or c.text) == 'Beta.dds' then
                    option = c
                    assert(c.paint_plane >= 300, 'Imported-source popup fell behind Basic content clipping')
                end
            end
            assert(option, 'Single LUT Import source options did not render')
            native.draw(commands)
            assert(
                native_pixel(option.x + option.size * 0.1, option.y + option.size * 0.3).text == 'Beta.dds',
                'Imported-source popup was covered by Basic native primitives'
            )
            menu.key(40)
            menu.key(13)
            assert(
                not menu.dropdown
                    and state.loaded == sources[2]
                    and handle.get('palette') == 2
                    and #import_actions == prior,
                'Choosing an imported source applied it immediately'
            )
            commands = menu.compose(1280, 720)
            for _, target in ipairs({ 'armor', 'helmet' }) do
                local label = assert(
                    split_label(commands, target, 'Beta.dds'),
                    'Shared imported-source filename did not synchronize'
                )
                local window, bounds = menu.window_bounds, view.region_bounds[target]
                assert(
                    label.x + #label.text * label.size * 0.5 <= window.x + (bounds.x + bounds.w) * window.scale,
                    'Single LUT Import main text escaped its gear column'
                )
            end
            tap(assert(split_label(commands, kind, 'Beta.dds')))
            assert(
                #import_actions == prior + 1
                    and import_actions[#import_actions].kind == kind
                    and import_actions[#import_actions].source == sources[2].source
                    and not menu.dropdown,
                'Single LUT Import main segment applied the wrong gear/source or opened the chooser'
            )
            tap(split_arrow(menu.compose(1280, 720), kind, 'Beta.dds'))
            assert(
                menu.dropdown and menu.choice_focus.control.id == 'palette',
                'Split source arrow did not establish its keyboard focus'
            )
            menu.key(27)
            state.busy = true
            commands = menu.compose(1280, 720)
            local busy_before = #import_actions
            menu.key(13)
            assert(
                not menu.dropdown and #import_actions == busy_before,
                'Focused Single LUT Import keyboard chooser ignored busy state'
            )
            tap(assert(split_label(commands, kind, 'Beta.dds')))
            tap(split_arrow(menu.compose(1280, 720), kind, 'Beta.dds'))
            assert(not menu.dropdown and #import_actions == busy_before, 'Busy Single LUT Import remained editable')
            state.busy = false
            commands = menu.compose(1280, 720)
            tap(split_arrow(commands, kind, 'Beta.dds'))
            assert(menu.dropdown, 'Split source chooser did not recover after busy state')
            state.busy = true
            menu.compose(1280, 720)
            assert(
                not menu.dropdown and #import_actions == busy_before,
                'Open Single LUT Import popup survived becoming busy'
            )
            state.busy = false
            local group = state.raw.basic[kind].group
            state.raw.basic[kind].group = nil
            commands = menu.compose(1280, 720)
            tap(assert(split_label(commands, kind, 'Beta.dds')))
            assert(#import_actions == busy_before, 'Unavailable gear destination allowed Single LUT Import')
            tap(split_arrow(menu.compose(1280, 720), kind, 'Beta.dds'))
            assert(
                menu.dropdown and menu.dropdown.control.id == 'palette',
                'Unavailable target prevented choosing a reusable imported source'
            )
            menu.key(27)
            state.raw.basic[kind].group = group
        end
    end
end
-- Camo scope is opt-in for every Armor and Helmet row. The checkbox controls
-- selection only; primary editing, highlighting and imported-source applying
-- must not run as a side effect of changing that scope.
local function empty_scope(kind, missing)
    if missing then
        state.raw.basic[kind].camo_rows = nil
    else
        state.raw.basic[kind].camo_rows = {}
    end
    local registry = api.mods.basic_test.controls
    for _, suffix in ipairs({
        '_camo',
        '_camo_colorway',
        '_camo_color_1',
        '_camo_color_2',
        '_camo_color_3',
        '_camo_color_4',
    }) do
        registry['basic_' .. kind .. suffix].disabled = true
    end
end
local function checkbox_point(commands, kind, row)
    assert(column_label(commands, kind, 'Region ' .. row), 'Camo checkbox row is not visible')
    local b, window = view.region_bounds[kind], menu.window_bounds
    return {
        x = window.x + (b.camo_x + b.camo_width / 2) * window.scale - 2,
        y = window.y + (b.y + b.h + view.region_scroll[kind] - (row - 0.5) * b.row_height) * window.scale - 2,
    }
end
local checkbox_theme = dofile('vendor/menu/menu.lua').epic_palette
local function checkbox_visual(commands, kind, row, checked, enabled)
    local label = assert(column_label(commands, kind, 'Region ' .. row))
    local b, window = view.region_bounds[kind], menu.window_bounds
    local center = window.x + (b.camo_x + b.camo_width / 2) * window.scale
    local frame
    for _, c in ipairs(commands) do
        assert(c.full_text ~= '[x]' and c.full_text ~= '[ ]', 'Basic Camo still uses bracket text as its checkbox')
        if
            c.type == 'rect'
            and c.ui_role == 'control_fill'
            and math.abs(c.x + c.w / 2 - center) < 0.01
            and math.abs(c.w - c.h) < 0.01
            and c.y <= label.y
            and c.y + c.h > label.y
        then
            frame = c
        end
    end
    assert(frame and math.abs(frame.w / window.scale - 22) < 0.01, 'Basic Camo checkbox is not a centered square')
    local borders, ticks = {}, {}
    for _, c in ipairs(commands) do
        if
            c.type == 'rect'
            and c.x >= frame.x - 0.01
            and c.y >= frame.y - 0.01
            and c.x + c.w <= frame.x + frame.w + 0.01
            and c.y + c.h <= frame.y + frame.h + 0.01
        then
            if c.ui_role == 'control_border' then
                borders[#borders + 1] = c
            elseif c.ui_role == 'control_icon' then
                assert(
                    c.x > frame.x and c.y > frame.y and c.x + c.w < frame.x + frame.w and c.y + c.h < frame.y + frame.h,
                    'Basic Camo check mark escaped its square frame'
                )
                ticks[#ticks + 1] = c
            end
        end
    end
    assert(#borders == 4, 'Basic Camo square frame lost a border')
    assert((#ticks > 0) == checked, 'Basic Camo tick does not match the row selection')
    native.draw(commands)
    if checked then
        local color = enabled and checkbox_theme.focus or checkbox_theme.disabled
        local turn, left_arm, right_arm
        for _, tick in ipairs(ticks) do
            assert(
                tick.c[1] == color[1] and tick.c[2] == color[2] and tick.c[3] == color[3],
                'Basic Camo check mark has the wrong enabled/disabled contrast'
            )
            local pixel = native_pixel(tick.x + tick.w / 2, tick.y + tick.h / 2)
            assert(
                not pixel.text and pixel.color.r == color[1] and pixel.color.g == color[2] and pixel.color.b == color[3],
                'Native Basic Camo check mark is obscured by its frame or another primitive'
            )
            if not turn or tick.y < turn.y then
                turn = tick
            end
        end
        for _, tick in ipairs(ticks) do
            left_arm = left_arm or tick.x < turn.x - frame.w * 0.1 and tick.y > turn.y + frame.h * 0.1
            right_arm = right_arm or tick.x > turn.x + frame.w * 0.2 and tick.y > turn.y + frame.h * 0.2
        end
        assert(left_arm and right_arm, 'Basic Camo tick does not form descending and ascending check-mark arms')
    else
        local pixel = native_pixel(frame.x + frame.w / 2, frame.y + frame.h / 2)
        assert(
            not pixel.text
                and pixel.color.r == frame.c[1]
                and pixel.color.g == frame.c[2]
                and pixel.color.b == frame.c[3],
            'Native unchecked Basic Camo square is not empty'
        )
    end
    return frame
end
local unchanged_pixels = ffi.string(camo_data, 23 * 64 * 16)
for _, font in ipairs({ 12, 20 }) do
    for _, scale in ipairs({ 0.7, 1, 1.15 }) do
        menu.font_size, menu.ui_scale = font, scale
        state.loaded, state.busy = sources[1], false
        for _, kind in ipairs({ 'armor', 'helmet' }) do
            empty_scope(kind)
            view.region_scroll[kind] = 0
        end
        local commands = menu.compose(1280, 720)
        for _, kind in ipairs({ 'armor', 'helmet' }) do
            assert(column_label(commands, kind, 'Check regions above'), 'Unchecked Basic Camo scope is not explained')
            checkbox_visual(commands, kind, 1, false, true)
            local prior_toggles, prior_selection, prior_identify, prior_import =
                #camo_toggles, selected_calls, identify_calls, #import_actions
            tap(checkbox_point(commands, kind, 1))
            assert(
                #camo_toggles == prior_toggles + 1
                    and camo_toggles[#camo_toggles].row == 1
                    and camo_toggles[#camo_toggles].kind == kind
                    and camo_toggles[#camo_toggles].checked == true
                    and state.raw.basic[kind].camo_rows[1] == true,
                'Basic Camo checkbox did not toggle only its own gear row'
            )
            assert(
                selected_calls == prior_selection
                    and identify_calls == prior_identify
                    and #import_actions == prior_import
                    and not menu.color_picker
                    and not menu.dropdown,
                'Basic Camo checkbox also selected, flashed, applied or edited colors'
            )
            local other = kind == 'armor' and 'helmet' or 'armor'
            assert(not state.raw.basic[other].camo_rows[1], 'Basic Camo checkbox toggled the other gear column')
            commands = menu.compose(1280, 720)
            assert(column_label(commands, kind, '1 checked regions'), 'Checked Basic Camo row count is stale')
            checkbox_visual(commands, kind, 1, true, true)
            local busy_toggles = #camo_toggles
            state.busy = true
            commands = menu.compose(1280, 720)
            checkbox_visual(commands, kind, 1, true, false)
            tap(checkbox_point(commands, kind, 1))
            assert(
                #camo_toggles == busy_toggles and state.raw.basic[kind].camo_rows[1] == true,
                'Disabled Basic Camo square still toggles during an import'
            )
            state.busy = false
            commands = menu.compose(1280, 720)
            tap(checkbox_point(commands, kind, 1))
            assert(
                state.raw.basic[kind].camo_rows[1] == false and camo_toggles[#camo_toggles].checked == false,
                'Basic Camo checkbox could not be unchecked'
            )
            checkbox_visual(menu.compose(1280, 720), kind, 1, false, true)
            view.region_scroll[kind] = math.min(view.region_maximum[kind], 7 * 29)
            commands = menu.compose(1280, 720)
            tap(checkbox_point(commands, kind, 8))
            assert(
                state.raw.basic[kind].camo_rows[8] == true and camo_toggles[#camo_toggles].row == 8,
                'Basic Camo row8 could not be explicitly opted in'
            )
            checkbox_visual(menu.compose(1280, 720), kind, 8, true, true)
            tap(checkbox_point(menu.compose(1280, 720), kind, 8))
            assert(state.raw.basic[kind].camo_rows[8] == false, 'Basic Camo row8 could not be explicitly opted out')
            view.region_scroll[kind] = view.region_maximum[kind]
            commands = menu.compose(1280, 720)
            tap(checkbox_point(commands, kind, 64))
            assert(
                state.raw.basic[kind].camo_rows[64] == true and camo_toggles[#camo_toggles].row == 64,
                'Scrolled final Basic Camo checkbox toggled the wrong region'
            )
            checkbox_visual(menu.compose(1280, 720), kind, 64, true, true)
            assert(
                selected_calls == prior_selection
                    and identify_calls == prior_identify
                    and #import_actions == prior_import,
                'Scrolled Basic Camo checkbox leaked into color/flash/import controls'
            )
            empty_scope(kind)
            view.region_scroll[kind] = 0
            commands = menu.compose(1280, 720)
        end
        empty_scope('armor', true)
        empty_scope('helmet', true)
        commands = menu.compose(1280, 720)
        for _, kind in ipairs({ 'armor', 'helmet' }) do
            assert(state.raw.basic[kind].camo_rows == nil, 'Missing-map fixture did not remove its row selection')
            checkbox_visual(commands, kind, 1, false, true)
        end
        for _, kind in ipairs({ 'armor', 'helmet' }) do
            empty_scope(kind)
        end
    end
end
assert(ffi.string(camo_data, 23 * 64 * 16) == unchanged_pixels, 'Basic Camo checkbox selection changed LUT pixel data')
package.loaded['epic.player_preview.v1'] = original_portrait
native.release()
print(
    'PASS Basic eight-region layout: all16labels/squares/swatches visible together, stretched fill, no stale or rounded scroll, native ink and eighth-row hits across imports/fonts/screens/scales;64-row scrolling retained'
)
print(
    'PASS Basic import placement: destination/source/region ink separation, stationary source and camo/copy chrome, first/final independent region clicks and native containment across windows/fonts/scales'
)
print(
    'PASS Basic Camo check marks: empty native squares, contained two-arm ticks, enabled/disabled contrast and hit guards, opt-in row8/final-row scope and no color/flash/import/pixel side effects'
)
print(
    'PASS Basic split import: independent apply/arrow hits, shared source and filename synchronization, stable/native popup anchors, busy mouse/keyboard/cancellation and unavailable targets'
)
print(
    'PASS Basic Camo: per-gear pattern/colorway choices and RGB pickers, unsupported Cape guard, independent 64-row scrolling, native font clearance and disabled behavior'
)
print(
    'PASS Basic: primary color pickers, measured/wrapped actions, dirty-notice separation, draggable scrolling and native footer border/ink/hit containment'
)
