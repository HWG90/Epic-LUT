local fixture = dofile('tests/weapon_controller.lua')
local View = dofile('src/editor/weapon_view.lua')
local function canvas(width, height, font, scale)
    local commands, clips = {}, {}
    local ui = {
        x = 10,
        y = 20,
        w = width,
        h = height,
        theme = {
            white = { 255, 255, 255 },
            muted = { 170, 170, 170 },
            line = { 60, 60, 60 },
            panel = { 35, 35, 35 },
            accent = { 255, 220, 20 },
        },
    }
    local function measure(label)
        return #label * font * scale * 0.55
    end
    local function record(kind, x, y, w, h, label, callback, enabled)
        assert(w >= 0 and h >= 0, kind .. ' has negative geometry')
        assert(x >= ui.x - 0.01 and x + w <= ui.x + ui.w + 0.01, kind .. ' escaped horizontally: ' .. tostring(label))
        assert(y >= ui.y - 0.01 and y + h <= ui.y + ui.h + 0.01, kind .. ' escaped vertically: ' .. tostring(label))
        commands[#commands + 1] = {
            kind = kind,
            x = x,
            y = y,
            w = w,
            h = h,
            label = label,
            callback = callback,
            enabled = enabled,
            clip = clips[#clips],
        }
        return commands[#commands]
    end
    ui.spacing = function(value)
        return value * scale
    end
    ui.text_size = function()
        return font * scale
    end
    ui.text_width = measure
    ui.control_height = function(_, padding, minimum)
        return math.max(minimum * scale, (font + padding * 2) * scale)
    end
    ui.text_y = function(y, h)
        return y + math.max(0, (h - font * scale) / 2)
    end
    ui.rect = function(x, y, w, h, color)
        local item = record('rect', x, y, w, h)
        item.color = color
    end
    ui.bounded = function(x, y, label, _, _, w, role)
        local item = record('text', x, y, w, math.min(font * scale, ui.y + ui.h - y), label)
        item.role = role
    end
    ui.button = function(x, y, w, h, label, callback, options)
        assert(
            measure(label) <= w + 0.01,
            'Button text clipped: ' .. label .. ' at font ' .. font .. ' scale ' .. scale .. ' width ' .. width
        )
        local item = record('button', x, y, w, h, label, callback, options.enabled)
        item.action = options.action
    end
    ui.choice = function(id, x, y, w, _, options)
        record('choice', x, y, w, options.height, id, nil, options.enabled)
    end
    ui.hit = function(x, y, w, h, callback, _, _, help)
        record('hit', x, y, w, h, help, callback, true)
    end
    ui.checkbox = function(x, y, w, h, checked, enabled, callback)
        local item = record('checkbox', x, y, w, h, nil, callback, enabled)
        item.checked = checked
    end
    ui.viewport = function(bounds, draw)
        clips[#clips + 1] = bounds
        draw()
        clips[#clips] = nil
    end
    ui.scrollbar = function(id, x, y, h, content, visible, value, callback)
        local item = record('scrollbar', x, y, 4, h, id, callback, true)
        item.content, item.visible, item.value = content, visible, value
    end
    return ui, commands
end
for _, font in ipairs({ 12, 16, 20, 28 }) do
    for _, scale in ipairs({ 0.7, 1, 1.15 }) do
        for _, size in ipairs({ { 700, 620 }, { 1800, 1100 } }) do
            local f = fixture()
            f.host.apply_camo = function()
                return true
            end
            local view = View.new(f.controller)
            local ui, commands = canvas(size[1], size[2], font, scale)
            local snapshots, snapshot = 0, f.host.snapshot
            f.host.snapshot = function(...)
                snapshots = snapshots + 1
                return snapshot(...)
            end
            view.draw(ui)
            assert(snapshots == 1, 'Weapon draw rebuilt its state more than once')
            assert(view.grid.cell_width <= 40 and view.grid.row_height <= 40, 'Window width inflated LUT cells')
            local labels, rows, scrollbars = {}, {}, {}
            for _, item in ipairs(commands) do
                if item.label then
                    labels[item.label] = item
                end
                if item.kind == 'text' and item.label:match('^Row %d+$') then
                    rows[item.label] = true
                end
                if item.kind == 'scrollbar' then
                    scrollbars[item.label] = item
                end
                if item.kind == 'rect' and item.color and item.w == item.h then
                    assert(item.w <= 40, 'Pattern swatch grew beyond its cap')
                end
            end
            assert(labels['Primary'] and labels['Secondary'] and labels['Support'], 'Weapon selectors missing')
            assert(labels.absent and labels.loading, 'Absent/loading weapons presented as available')
            assert(labels['Quick Editor: Pattern LUT'] and labels['Color'], 'Pattern quick editor missing')
            assert(labels['Mat/Opac'] or labels['Mat/Op'] or labels.Mat or labels.M, 'Material/opacity caption missing')
            assert(labels.Roughness or labels['Rough.'] or labels.Rgh or labels.R, 'Roughness caption missing')
            if size[2] == 1100 then
                assert(rows['Row 8'] and view.table_maximum == 0, 'Full window needlessly hid weapon LUT rows')
            end
            view.section = 'presets'
            ui, commands = canvas(size[1], size[2], font, scale)
            view.draw(ui)
            if view.action_maximum > 0 then
                assert(
                    scrollbars.weapon_actions and view.wheel(view.action_bounds.x + 2, view.action_bounds.y + 2, -12000)
                )
                ui, commands = canvas(size[1], size[2], font, scale)
                view.draw(ui)
                local shared
                for _, item in ipairs(commands) do
                    if item.action == 'weapon_share' then
                        shared = item
                    end
                end
                assert(
                    shared and shared.enabled,
                    'Bottom Shared LUT action inaccessible through scrolling font='
                        .. font
                        .. ' scale='
                        .. scale
                        .. ' width='
                        .. size[1]
                )
            end
        end
    end
end
local f = fixture()
for _, font in ipairs({ 12, 16, 20, 28 }) do
    for _, scale in ipairs({ 0.7, 1, 1.15 }) do
        for _, size in ipairs({ { 700, 620 }, { 1800, 1100 } }) do
            local basic_fixture = fixture()
            basic_fixture.host.apply_camo = function()
                return true
            end
            local basic_view = View.new(basic_fixture.controller)
            local basic_ui, basic_commands = canvas(size[1], size[2], font, scale)
            basic_ui.basic_only = true
            basic_view.draw(basic_ui)
            local regions = 0
            for _, item in ipairs(basic_commands) do
                if item.kind == 'text' and item.label:match('^Region %d+$') then
                    regions = regions + 1
                end
                assert(
                    not (item.kind == 'hit' and item.label == 'Edit Row 1, column 2 in the LUT table.'),
                    'Basic weapon view retained the dense material grid'
                )
            end
            assert(regions > 0, 'Basic weapon region colors missing')
        end
    end
end
local view = View.new(f.controller)
local ui, commands = canvas(1800, 1100, 16, 1)
view.draw(ui)
view.section = 'presets'
local preset_ui, preset_commands = canvas(1800, 1100, 16, 1)
view.draw(preset_ui)
view.section = 'edit'
local preset_choice = false
for _, item in ipairs(preset_commands) do
    if item.kind == 'choice' and item.label == 'outfit_preset' then
        preset_choice = true
    end
end
assert(preset_choice, 'Weapon page omitted the existing Armory preset selector')
local actions = {}
local hits = {}
for _, item in ipairs(commands) do
    if item.action then
        actions[item.action] = item
    end
    if item.kind == 'hit' then
        hits[item.label] = item
    end
end
assert(hits['Edit Row 1, column 1 in the LUT table.'].callback())
assert(f.hits.edit_rgb[1] == 1)
assert(hits['Edit Row 8, column 20 in the LUT table.'].callback())
assert(f.hits.edit_camo[1] == 8 and f.hits.edit_camo[2] == 4)
assert(hits['Edit Row 2, column 2 in the LUT table.'].callback())
assert(f.hits.load_editor[1] == f.body and f.hits.open_editor[1].row == 2)
assert(hits.Roughness.callback() and f.hits.edit_pattern[4].alpha_only == true)
for id, action in pairs({
    weapon_load = 'load_current',
    weapon_editor = 'open_editor',
    weapon_pattern_editor = 'open_pattern',
    weapon_apply = 'apply',
    weapon_restore = 'restore',
    weapon_import = 'import',
    weapon_map = 'map_imports',
    weapon_auto_map = 'map_imports',
    weapon_preset = 'save_preset',
    weapon_export = 'export',
    weapon_share = 'share',
}) do
    local section = (id == 'weapon_import' or id == 'weapon_map' or id == 'weapon_auto_map') and 'import'
        or (id == 'weapon_preset' or id == 'weapon_export' or id == 'weapon_share') and 'presets'
        or 'edit'
    view.section = section
    if not actions[id] then
        view.action_scroll = view.action_maximum
        ui, commands = canvas(1800, 1100, 16, 1)
        view.draw(ui)
        for _, item in ipairs(commands) do
            if item.action then
                actions[item.action] = item
            end
        end
    end
    assert(actions[id] and actions[id].enabled and actions[id].callback(), 'UI action did not activate: ' .. id)
    assert(f.hits[action], 'UI action did not reach its editable host: ' .. action)
end
local old_hit = hits['Edit Row 1, column 1 in the LUT table.']
assert(f.controller.choose_group(2))
local before = #f.order
assert(old_hit.callback() == false and #f.order == before, 'A stale rendered target edited another weapon table')
ui, commands = canvas(1800, 1100, 16, 1)
view.draw(ui)
local no_pattern
for _, item in ipairs(commands) do
    if item.label == 'No Pattern LUT for this table.' then
        no_pattern = true
    end
end
assert(no_pattern, "Rail table displayed another section's Pattern LUT")
print(
    'PASS: weapon view real editing/mapping/export actions; 24 font/scale/window layouts; clamps, scrolling and exact Pattern association'
)
