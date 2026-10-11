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
local selected, selected_kind
local export_hits = 0
local view = dofile('src/editor/basic_view.lua').new(function()
    return state
end, function(row, kind)
    selected, selected_kind = row, kind
end)
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
            min_height = 780,
            require_confirmation = false,
            controls = controls,
            render_layout = view.draw,
        },
    },
})
api.mods.basic_test.tabs_top = true
api.mods.basic_test.pages[1].render_layout = view.draw
api.mods.basic_test.pages[1].minimum_width = 1100
api.mods.basic_test.pages[1].minimum_height = 780
local menu = dofile('vendor/menu/menu.lua').new(api, function(t, size)
    return #t * size * 0.5
end)
menu.epic_typography = true
menu.visible = true
menu.window_width = 1100
menu.window_height = 780
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
        and not apply_labels['Single LUT Import'],
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
        and imported_labels['Single LUT Import'],
    'Loaded import controls missing'
)
assert(regions >= 2, 'Basic did not show both region palettes: ' .. regions)
-- Whole-LUT camo controls stay readable instead of shrinking the region rows.
-- Compact Basic can scroll either gear column to expose the final region.
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
    assert(last, 'Compact Basic final region is not scrollable')
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
assert(view.action_maximum > 0, 'Loaded Basic actions need a scroll range at 780px window height')
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
local x, y = row8.x + 85, row8.y + 2
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
    for _, c in ipairs(commands) do
        if (c.full_text or c.text) == label and c.x >= left and c.x < right then
            return c
        end
    end
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
                assert(column_label(before, kind, 'All regions in this LUT'))
                local field = assert(column_label(before, kind, 'Off'))
                local footer_label = loaded and 'Single LUT Import'
                    or (kind == 'armor' and 'Copy Helmet' or 'Copy Armor')
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
                tap({ x = window.x + (b.x + 82) * window.scale, y = last.y })
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
for _, loaded in ipairs({ false, true }) do
    state.loaded = loaded and saved_editor or nil
    for _, font in ipairs({ 12, 20 }) do
        for _, resolution in ipairs({ { 1280, 720 }, { 1920, 1080 } }) do
            menu.font_size = font
            menu.compose(unpack(resolution))
            local maximum = view.action_maximum
            state.dirty = false
            menu.compose(unpack(resolution))
            assert(maximum > view.action_maximum, 'Dirty notice did not reserve its own scroll space')
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
            assert(folder and #dirty_lines > 0 and scrollbar, 'Scrolled Basic dirty/footer content unreachable')
            local window, bounds = menu.window_bounds, view.action_bounds
            local lower = window.y + bounds.y * window.scale
            for _, c in ipairs(dirty_lines) do
                assert(c.y + 0.85 * c.size < folder.y - 0.2 * folder.size, 'Dirty notice overlaps Open Export Location')
                assert(c.y - 0.2 * c.size >= lower, 'Dirty notice escaped the action viewport into footer')
                assert(c.viewport, 'Dirty guidance lacks action viewport clipping')
            end
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
        end
    end
end
state.dirty, state.status = false, 'Ready'
print(
    'PASS Basic Camo: per-gear pattern/colorway choices and RGB pickers, unsupported Cape guard, independent 64-row scrolling, native font clearance and disabled behavior'
)
print(
    'PASS Basic: primary color pickers, measured wrapped action content, dirty-notice separation, draggable scrolling and compact/scaled footer containment'
)
