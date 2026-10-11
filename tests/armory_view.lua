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
local document = { width = 23, height = 8, data = ffi.new('float[736]') }
local state =
    { editor = document, status = 'Ready', raw = { outfit = { armor = { document }, helmet = { document } } } }
state.armory_targets = { armor = true, helmet = true, cape = true }
local view = dofile('src/editor/armory_view.lua').new(function()
    return state
end)
local saved
local exports = {}
local actions = {}
local applied_targets = {}
local menu
local controls = {
    { id = 'armory_search', type = 'input', allow_empty = true, label = 'Search', default = '' },
    { id = 'armory_sort', type = 'choice', label = 'Sort', choices = { 'A-Z', 'Z-A' }, default = 1 },
    { id = 'basic_preset_name', type = 'input', label = 'Name', default = 'palette' },
    { id = 'basic_preset', type = 'choice', label = 'Palette', choices = { 'New preset' }, default = 1 },
    { id = 'outfit_preset', type = 'choice', label = 'Outfit', choices = { 'Choose outfit', 'Example' }, default = 1 },
    { id = 'armory_export_name', type = 'input', label = 'Export name', default = 'Saved Set' },
    {
        id = 'armory_export_format',
        type = 'choice',
        label = 'Export format',
        choices = {
            'Shareable Preset ZIP',
            'Selected LUT Patch ZIP',
            'Entire Preset Patch ZIP',
            'Raw DDS (selected LUT)',
            'Raw DDS (entire preset)',
        },
        default = 1,
        on_change = function(value)
            state.armory_export_format = value
        end,
    },
    {
        id = 'armory_dds_naming',
        type = 'choice',
        presentation = 'dropdown',
        label = 'DDS filenames',
        choices = { 'LUT# + HEX', 'LUT# + Decimal', 'LUT#', 'HEX', 'Decimal' },
        default = 1,
    },
    { id = 'armory_export_lut', type = 'choice', label = 'Saved LUT', choices = { 'Armor LUT 1' }, default = 1 },
    {
        id = 'outfit_name',
        type = 'input',
        label = 'Outfit name',
        default = 'my-outfit',
        on_change = function(name)
            saved = name
            menu.outfit_dialog = nil
        end,
    },
}
for _, kind in ipairs({ 'armor', 'helmet', 'cape' }) do
    controls[#controls + 1] = {
        id = 'outfit_target_' .. kind,
        type = 'toggle',
        label = kind,
        default = true,
        on_change = function(value)
            state.armory_targets[kind] = value
        end,
    }
end
for _, id in ipairs({
    'outfit_rename',
    'outfit_delete',
    'save_setup',
    'outfit_apply_selected',
    'basic_save',
    'basic_export',
    'open_editor',
    'armory_export',
    'armory_import',
    'open_export',
}) do
    controls[#controls + 1] = {
        id = id,
        type = 'button',
        label = id,
        on_activate = function()
            actions[#actions + 1] = id
            if id == 'outfit_apply_selected' then
                applied_targets[#applied_targets + 1] = {
                    armor = state.armory_targets.armor,
                    helmet = state.armory_targets.helmet,
                    cape = state.armory_targets.cape,
                }
            end
            if id == 'armory_export' then
                exports[#exports + 1] = {
                    format = api.mods.armory_test.handle.get('armory_export_format'),
                    naming = api.mods.armory_test.handle.get('armory_dds_naming'),
                }
            end
            return true
        end,
    }
end
local h = api.register({
    id = 'armory_test',
    name = 'Epic LUT',
    pages = { { id = 'armory', name = 'The Armory', controls = controls, require_confirmation = false } },
})
api.mods[h.id].pages[1].render_layout = view.draw
api.mods[h.id].tabs_top = true
menu = dofile('vendor/menu/menu.lua').new(api, function(t, size)
    return #t * size * 0.5
end)
menu.epic_typography = true
menu.visible = true
local labels = {}
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text or c.text then
        labels[c.full_text or c.text] = c
    end
end
assert(
    labels['Palette Preview'].text_role == 'heading'
        and labels['Palette Preview'].size > labels['Save Current Gear Preset'].size
        and labels['Saved outfit swatches: Armor / Cape | Helmet'].text_role == 'hint',
    'Armory hierarchy did not distinguish headings, controls and help'
)
assert(
    labels.Armor and labels.Helmet and labels['Save Current Gear Preset'],
    'Armory lacks paired preview or save action'
)
assert(
    not labels['Save Current LUT as Preset'] and not labels['Export DDS to Share'] and not labels['Open LUT Editor'],
    'Removed single-LUT section still visible'
)
state.raw.outfit.armor = { document, document, document }
menu.compose(1920, 1080)
assert(view.maximum > 0, 'Multiple saved LUTs did not create a scrollable preview')
view.wheel(view.bounds.x + 2, view.bounds.y + 2, -1200)
local later = {}
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text then
        later[c.full_text] = true
    end
end
assert(later['LUT 3'], 'Later saved LUT missing from Armory preview')
-- A small viewport must retain access to export/import without controls escaping.
menu.compose(960, 720)
assert(view.sidebar_maximum > 0, 'Small Armory window did not scroll its controls')
view.wheel(view.sidebar_bounds.x + 2, view.sidebar_bounds.y + 2, -1200)
local bottom = {}
for _, c in ipairs(menu.compose(960, 720)) do
    if c.full_text then
        bottom[c.full_text] = true
    end
end
assert(
    bottom['Export Selected Preset...'] and bottom['Import Shared Preset...'],
    'Armory export/import controls unreachable'
)
state.raw.outfit.helmet = { { width = 3, height = 1, data = ffi.new('float[12]') } }
view.scroll = 0
local pattern_labels = {}
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text then
        pattern_labels[c.full_text] = true
    end
end
assert(pattern_labels['Pattern LUT 1'], '3x1 Pattern preset missing safe preview')
state.raw.outfit.armor = {}
state.raw.outfit.cape = { document }
view.scroll, view.sidebar_scroll = 0, 0
local cape_labels = {}
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text then
        cape_labels[c.full_text] = true
    end
end
assert(cape_labels['Cape LUT 1'] and cape_labels['Armor / Cape'], 'Cape LUT missing from paired Armory preview')
assert(view.preview_columns[1][1].kind == 'cape' and view.preview_columns[1][1].document == document)
state.raw.outfit.armor, state.raw.outfit.cape = { document }, nil

local saved_kind
local scope_saves = 0
local function click(c, offset_x)
    for _, down in ipairs({ true, false }) do
        menu.tick({
            down = function(key)
                return down and key == 1
            end,
            mouse = function()
                return c.x + (offset_x or 2), c.y + 2
            end,
            wheel = function()
                return 0
            end,
        })
    end
end
local function popup_label(value)
    for _, c in ipairs(menu.compose(1920, 1080)) do
        if c.popup and (c.full_text or c.text) == value then
            return c
        end
    end
end
local function click_scope_box(label)
    local c = assert(popup_label(label))
    click({ x = c.x - 20 * menu.window_bounds.scale - 2, y = c.y })
end
local function save_scope()
    menu.outfit_dialog = {
        phase = 'scope',
        mod = api.mods[h.id],
        control = api.mods[h.id].controls.outfit_name,
        on_save = function(name, kind)
            scope_saves = scope_saves + 1
            saved, saved_kind = name, kind
        end,
    }
    menu.compose(1920, 1080)
    return menu.outfit_dialog
end
for mask = 1, 7 do
    local dialog = save_scope()
    assert(
        dialog.save_kind.armor and dialog.save_kind.helmet and dialog.save_kind.cape,
        'Armory save checkboxes do not default to all three gear kinds'
    )
    local expected =
        { armor = mask % 2 == 1, helmet = math.floor(mask / 2) % 2 == 1, cape = math.floor(mask / 4) % 2 == 1 }
    for _, entry in ipairs({ { 'armor', 'Armor' }, { 'helmet', 'Helmet' }, { 'cape', 'Cape' } }) do
        if not expected[entry[1]] then
            if mask % 2 == 1 then
                click(assert(popup_label(entry[2])))
            else
                click_scope_box(entry[2])
            end
        end
        assert(dialog.save_kind[entry[1]] == expected[entry[1]], 'Armory save label click toggled the wrong scope')
    end
    local before = scope_saves
    menu.key(13)
    assert(
        menu.outfit_dialog.phase == 'scope' and not menu.text_edit and scope_saves == before,
        'Armory save scope Enter typed or saved before the explicit Save action'
    )
    click(assert(popup_label('Save')))
    assert(
        menu.outfit_dialog.phase == 'name' and menu.text_edit and scope_saves == before,
        'Armory Save scope action wrote a preset before naming'
    )
    local parts = {}
    for _, entry in ipairs({ { 'armor', 'Armor' }, { 'helmet', 'Helmet' }, { 'cape', 'Cape' } }) do
        if expected[entry[1]] then
            parts[#parts + 1] = entry[2]
        end
    end
    assert(popup_label('Saving: ' .. table.concat(parts, ' + ')), 'Armory name caption lost its selected scopes')
    menu.text_edit.text = 'Scoped Set ' .. mask
    if mask % 2 == 1 then
        menu.key(13)
    else
        click(assert(popup_label('Save Preset')))
    end
    assert(
        scope_saves == before + 1 and saved == 'Scoped Set ' .. mask and not menu.outfit_dialog,
        'Armory named Save/Enter did not commit exactly once'
    )
    for kind, wanted in pairs(expected) do
        assert(saved_kind[kind] == wanted, 'Armory Save lost one of the seven scope combinations')
    end
end
local empty_dialog = save_scope()
for _, label in ipairs({ 'Armor', 'Helmet', 'Cape' }) do
    click(assert(popup_label(label)))
end
local empty_count = scope_saves
click(assert(popup_label('Save')))
menu.key(13)
assert(
    menu.outfit_dialog == empty_dialog and not menu.text_edit and scope_saves == empty_count,
    'Empty Armory scope can advance or write a preset'
)
click(assert(popup_label('Cancel')))
assert(
    not menu.outfit_dialog and not menu.text_edit and scope_saves == empty_count,
    'Armory scope cancel saved a preset'
)
save_scope()
click(assert(popup_label('Save')))
menu.text_edit.text = 'Cancelled Name'
click(assert(popup_label('Saving: Armor + Helmet + Cape')))
assert(
    menu.text_edit and menu.text_edit.text == 'Cancelled Name' and scope_saves == empty_count,
    'Armory outside-field click committed or discarded a pending name'
)
click(assert(popup_label('Cancelled Name|')))
assert(
    menu.text_edit and menu.text_edit.text == 'Cancelled Name' and scope_saves == empty_count,
    'Armory naming-field click reset or committed its text'
)
click(assert(popup_label('Cancel')))
assert(
    not menu.outfit_dialog and not menu.text_edit and scope_saves == empty_count,
    'Armory naming cancel saved a preset'
)
local blank_attempts = 0
menu.outfit_dialog = {
    phase = 'name',
    mod = api.mods[h.id],
    control = api.mods[h.id].controls.outfit_name,
    save_kind = { armor = true, helmet = true, cape = true },
    on_save = function(name)
        blank_attempts = blank_attempts + 1
        assert(name:find('%S'), 'Blank name must not be stored')
        error('The blank-name Cancel fixture must never store a preset')
    end,
}
menu.text_edit = { mod = api.mods[h.id], control = api.mods[h.id].controls.outfit_name, text = '', replace = true }
menu.compose(1920, 1080)
menu.key(13)
assert(
    menu.outfit_dialog and menu.outfit_dialog.phase == 'name' and menu.text_edit,
    'Blank Armory name validation did not retain its editing dialog'
)
local attempts_before_cancel = blank_attempts
click(assert(popup_label('Cancel')))
assert(
    not menu.outfit_dialog
        and not menu.text_edit
        and blank_attempts == attempts_before_cancel
        and scope_saves == empty_count,
    'Blank Armory name validation intercepted Cancel or retried its save callback'
)
menu.outfit_dialog = { phase = 'confirm', mod = api.mods[h.id], control = api.mods[h.id].controls.outfit_name }
local yes
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text == 'Yes' then
        yes = c
    end
end
assert(yes, 'Keep preset confirmation missing')
local x, y = yes.x + 2, yes.y + 2
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
assert(menu.text_edit and menu.outfit_dialog.phase == 'name', 'Yes did not open naming box')
menu.text_edit.text = 'Mixed Set'
menu.key(13)
assert(saved == 'Mixed Set' and not menu.outfit_dialog, 'Named preset did not save/close')
local function composed(value)
    for _, c in ipairs(menu.compose(1920, 1080)) do
        if c.full_text == value then
            return c
        end
    end
end
local function tap_label(value)
    local c = assert(composed(value), 'Missing Armory export control: ' .. value)
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
local function sidebar_label(value)
    local window, b = menu.window_bounds, view.sidebar_bounds
    for _, c in ipairs(menu.compose(1920, 1080)) do
        if
            c.full_text == value
            and c.x >= window.x + b.x * window.scale
            and c.x < window.x + (b.x + b.w) * window.scale
        then
            return c
        end
    end
end
local function set_targets(mask)
    for _, kind in ipairs({ 'armor', 'helmet', 'cape' }) do
        assert(h.set('outfit_target_' .. kind, mask[kind]))
    end
end
do
    local previous = state.raw.outfit
    state.raw.outfit = { armor = { document }, cape = { document }, helmet = { document } }
    state.armory_cape_available = true
    view.sidebar_scroll = 0
    assert(sidebar_label('Apply Preset'), 'Armory single Apply Preset action is missing')
    for _, old in ipairs({
        'Apply Preset Armor LUTs',
        'Apply Preset Armor + Cape LUTs',
        'Apply Preset Helmet LUTs',
        'Apply Preset Cape LUTs',
    }) do
        assert(not composed(old), 'Armory still renders a duplicate separate apply action')
    end
    for mask = 1, 7 do
        local expected =
            { armor = mask % 2 == 1, helmet = math.floor(mask / 2) % 2 == 1, cape = math.floor(mask / 4) % 2 == 1 }
        set_targets({ armor = true, helmet = true, cape = true })
        for _, entry in ipairs({ { 'armor', 'Armor' }, { 'helmet', 'Helmet' }, { 'cape', 'Cape' } }) do
            if not expected[entry[1]] then
                click(assert(sidebar_label(entry[2])))
            end
            assert(
                state.armory_targets[entry[1]] == expected[entry[1]],
                'Armory target label changed the wrong preference'
            )
        end
        local before = #applied_targets
        click(assert(sidebar_label('Apply Preset')))
        assert(
            #applied_targets == before + 1 and actions[#actions] == 'outfit_apply_selected',
            'Armory selected Apply did not dispatch once'
        )
        for kind, value in pairs(expected) do
            assert(applied_targets[#applied_targets][kind] == value, 'Armory Apply lost a target mask bit')
        end
    end
    set_targets({ armor = false, helmet = false, cape = false })
    local empty = #applied_targets
    click(assert(sidebar_label('Apply Preset')))
    assert(#applied_targets == empty, 'Armory Apply activated with no checked families')
    set_targets({ armor = false, helmet = false, cape = true })
    state.armory_cape_available = false
    click(assert(sidebar_label('Cape')))
    click(assert(sidebar_label('Apply Preset')))
    assert(
        state.armory_targets.cape == true and h.get('outfit_target_cape') == true and #applied_targets == empty,
        'Unavailable Cape target changed stored preference or applied'
    )
    state.raw.outfit = nil
    state.armory_cape_available = true
    click(assert(sidebar_label('Cape')))
    click(assert(sidebar_label('Apply Preset')))
    assert(
        state.armory_targets.cape == true and #applied_targets == empty,
        'Missing preset retained a Cape apply route'
    )
    state.raw.outfit = { armor = {}, helmet = {}, cape = { document } }
    click(assert(sidebar_label('Apply Preset')))
    assert(#applied_targets == empty + 1, 'Cape-only preset lost its explicit checked target')
    menu.compose(1920, 1080)
    view.sidebar_scroll = view.sidebar_maximum
    assert(composed('Cape Only / 1 LUTs'), 'Cape-only preset was counted as Armor')
    state.raw.outfit = { armor = { document }, cape = { document }, helmet = { document } }
    menu.compose(1920, 1080)
    view.sidebar_scroll = view.sidebar_maximum
    assert(composed('Armor + Cape + Helmet / 3 LUTs'), 'Saved Cape count was hidden in Armor count')
    state.raw.outfit, state.armory_cape_available = previous, nil
    set_targets({ armor = true, helmet = true, cape = true })
end
for format = 1, 4 do
    assert(h.set('armory_export_format', format))
    menu.compose(1920, 1080)
    view.sidebar_scroll = view.sidebar_maximum
    assert(not composed('LUT# + HEX'), 'Armory naming chooser leaked into an existing format')
    assert(
        (composed('Armor LUT 1') ~= nil) == (format == 2 or format == 4),
        'Armory selected-LUT chooser changed its original format eligibility'
    )
    tap_label('Export Selected Preset...')
    assert(exports[#exports].format == format, 'Armory old export format callback changed')
end
assert(h.set('armory_export_format', 5))
menu.compose(1920, 1080)
view.sidebar_scroll = view.sidebar_maximum
assert(not composed('Armor LUT 1'), 'Entire preset bulk DDS still asks for a single LUT')
tap_label('LUT# + HEX')
assert(menu.dropdown and menu.dropdown.control.id == 'armory_dds_naming', 'Armory bulk naming dropdown did not open')
for i = 1, 3 do
    menu.key(40)
end
menu.key(13)
tap_label('Export Selected Preset...')
assert(
    exports[#exports].format == 5 and exports[#exports].naming == 4,
    'Armory bulk export lost its HEX naming selection'
)
-- The shared checkbox primitive must be visible and contained on both the
-- ordinary sidebar and the higher modal plane, independent of font/scale.
local NativeView = dofile('vendor/menu/view.lua')
local native_items, native_id = {}, 0
local function allocate(item)
    native_id = native_id + 1
    item.order = native_id
    assert(item.z == math.floor(item.z), 'Armory checkbox used a fractional native layer')
    native_items[native_id] = item
    return native_id
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
            native_items[id] = nil
        end,
        destroy_text = function(_, id)
            native_items[id] = nil
        end,
    },
}, true)
local function pixel(x, y)
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
    return assert(winner, 'Missing Armory checkbox native pixel')
end
local function checkbox(commands, label, checked)
    local s = menu.window_bounds.scale
    local cx, cy = label.x - 20 * s, label.y + 0.325 * label.size
    local frame
    for _, c in ipairs(commands) do
        if
            c.type == 'rect'
            and c.ui_role == 'control_fill'
            and (c.popup == true) == (label.popup == true)
            and math.abs(c.x + c.w / 2 - cx) < 0.01
            and math.abs(c.y + c.h / 2 - cy) < 0.01
            and math.abs(c.w - c.h) < 0.01
        then
            frame = c
        end
    end
    assert(frame and math.abs(frame.w / s - 22) < 0.01, 'Armory checkbox did not render its square beside the label')
    local ticks = {}
    for _, c in ipairs(commands) do
        if
            c.type == 'rect'
            and c.ui_role == 'control_icon'
            and c.x > frame.x
            and c.y > frame.y
            and c.x + c.w < frame.x + frame.w
            and c.y + c.h < frame.y + frame.h
        then
            ticks[#ticks + 1] = c
        end
    end
    assert((#ticks > 0) == checked, 'Armory checkbox visual disagrees with its effective selection')
    assert(label.text == label.full_text, 'Armory checkbox label is clipped at a large font')
    local m = metrics(label.size)
    assert(
        label.x > frame.x + frame.w
            and label.y + m.min_y > frame.y - 8 * s
            and label.y + m.max_y < frame.y + frame.h + 8 * s,
        'Armory checkbox label overlaps its square or leaves the target row'
    )
    renderer.draw(commands)
    assert(
        pixel(label.x + label.size * 0.1, label.y + label.size * 0.3).text == label.text,
        'Native Armory checkbox label is obscured'
    )
    if checked then
        for _, t in ipairs(ticks) do
            local p = pixel(t.x + t.w / 2, t.y + t.h / 2)
            assert(
                not p.text and p.color.r == t.c[1] and p.color.g == t.c[2] and p.color.b == t.c[3],
                'Native Armory check mark is obscured by its frame'
            )
        end
    end
    return { x = cx - 2, y = cy - 2 }, frame
end
menu.text_metrics = metrics
local original_outfit = state.raw.outfit
state.raw.outfit = { armor = { document }, helmet = { document }, cape = { document } }
state.armory_cape_available = true
for _, font in ipairs({ 12, 20 }) do
    for _, scale in ipairs({ 0.7, 1, 1.15 }) do
        menu.font_size, menu.ui_scale, menu.window_width, menu.window_height = font, scale, 1500, 1000
        view.sidebar_scroll = 0
        set_targets({ armor = true, helmet = true, cape = true })
        local commands = menu.compose(1920, 1080)
        local targets = {}
        for _, label in ipairs({ 'Armor', 'Helmet', 'Cape' }) do
            targets[#targets + 1] = assert(sidebar_label(label))
            checkbox(commands, targets[#targets], true)
        end
        local armor_box = checkbox(commands, targets[1], true)
        click(armor_box)
        assert(
            state.armory_targets.armor == false,
            'Armory checkbox square is not clickable independently of its label'
        )
        local apply = assert(sidebar_label('Apply Preset'))
        if font == 12 then
            assert(math.abs(apply.y - targets[1].y) < 0.01, 'Roomy Armory applies did not share one row')
            assert(
                targets[3].x + #targets[3].text * targets[3].size * 0.5 < apply.x,
                'Inline Armory Apply overlaps Cape label'
            )
        end
        menu.window_width = 1100
        menu.font_size = 20
        commands = menu.compose(1920, 1080)
        local narrow_armor = assert(sidebar_label('Armor'))
        local narrow_apply = assert(sidebar_label('Apply Preset'))
        assert(
            narrow_apply.y + 0.85 * narrow_apply.size < narrow_armor.y - 0.2 * narrow_armor.size,
            'Narrow/high-font Armory did not give Apply its own row'
        )
        for _, entry in ipairs({ { 'Armor', false }, { 'Helmet', true }, { 'Cape', true } }) do
            checkbox(commands, assert(sidebar_label(entry[1])), entry[2])
        end
        state.armory_cape_available = false
        commands = menu.compose(1920, 1080)
        local unavailable_box = checkbox(commands, assert(sidebar_label('Cape')), false)
        click(unavailable_box)
        assert(state.armory_targets.cape == true, 'Unavailable Cape square mutated the remembered target')
        state.armory_cape_available = true
        menu.font_size = font
        save_scope()
        commands = menu.compose(1920, 1080)
        local count = scope_saves
        for _, label in ipairs({ 'Armor', 'Helmet', 'Cape' }) do
            local point = checkbox(commands, assert(popup_label(label)), true)
            click(point)
            commands = menu.compose(1920, 1080)
            checkbox(commands, assert(popup_label(label)), false)
        end
        click(assert(popup_label('Save')))
        assert(
            menu.outfit_dialog.phase == 'scope' and scope_saves == count,
            'Native empty scope advanced despite disabled Save'
        )
        click(assert(popup_label('Cancel')))
        assert(not menu.outfit_dialog and scope_saves == count, 'Native scope cancellation saved a preset')
    end
end
renderer.release()
state.raw.outfit, state.armory_cape_available = original_outfit, nil
print(
    'PASS Armory masks: seven save/apply combinations, checkbox and label hits, explicit name commits, empty/cancel guards, unavailable targets, inline/fallback layout and native checkbox/label containment'
)
print('PASS Armory: split Armor/Helmet preview, keep-preset confirmation, editable naming popup')
