-- Optional editor tools. Only the active tab composes controls; document actions
-- remain in the editor registry so Basic and Advanced share the same behavior.
local T = {}
local tabs = { 'import', 'rows', 'export', 'options' }
local labels = { import = 'Import', rows = 'Rows', export = 'Export', options = 'Options' }
local accent, ink = { 244, 202, 53 }, { 25, 28, 31 }

function T.new(deps)
    local editor, document = deps.editor, deps.document
    local self = { tab = 'import' }
    local opened = false

    function self.open(tab)
        assert(tab == nil or labels[tab], 'Unknown editor tools tab')
        self.tab, opened = tab or self.tab, true
    end
    function self.close()
        opened = false
    end
    function self.is_open()
        return opened
    end
    function self.popup(ui)
        if not opened or not ui.floating then
            return
        end
        local h = editor.handle
        local controls = editor.api.mods[h.id].controls
        local d = document()
        local function draw(x, y, w, ht)
            local theme = ui.theme
            local white, muted = theme.white, theme.muted
            local bx, width = x + 14, w - 28
            local half, top = (width - 8) / 2, y + ht - 118
            local bh = math.max(28, (ui.text_size and ui.text_size(14) or 14) + 12)
            local step = bh + 10
            local function label(py, text, color)
                ui.bounded(bx, py, text, 14, color or white, width)
            end
            local function button(px, py, bw, text, id, enabled, callback, help)
                if id and not controls[id] then
                    return
                end
                enabled = enabled ~= false and (not id or not controls[id].disabled)
                local loading = id == 'populate_worn'
                local featured = enabled
                    and (
                        loading
                        or id == 'load_debug_lut'
                        or id == 'export_selected'
                        or id == 'save_row'
                        or id == 'save_setup'
                    )
                local color = loading and ui.load_color and ui.load_color(editor.load_seen and editor.load_seen())
                    or accent
                ui.button(px, py, bw, bh, text, function()
                    if callback then
                        callback()
                    else
                        ui.activate(id)
                    end
                end, {
                    enabled = enabled,
                    accent = featured and color,
                    ink = featured and ink,
                    help = help,
                })
            end
            local function action(py, text, id, enabled, help)
                button(bx, py, width, text, id, enabled, nil, help)
            end
            local function choice(id, py, bw, px)
                if ui.choice and controls[id] then
                    ui.choice(id, px or bx, py, bw or width)
                end
            end
            local function divider(py)
                ui.rect(bx, py, width, 1, theme.line)
            end
            local function preview(live)
                if ui.preview then
                    ui.preview(function(bounds)
                        return editor.preview(bounds, live)
                    end)
                end
            end
            ui.rect(x, y, w, ht, theme.panel)
            ui.rect(x, y + ht - 40, w, 40, theme.header)
            label(y + ht - 26, 'LUT Editor Tools')
            local tabw = (width - 24) / #tabs
            for i, tab in ipairs(tabs) do
                local tx, ty = bx + (i - 1) * (tabw + 6), y + ht - 78
                ui.button(tx, ty, tabw, 28, labels[tab], function()
                    self.tab = tab
                end, { selected = self.tab == tab })
            end

            if self.tab == 'import' then
                label(top, 'Import a palette, then choose the table to edit or apply.', muted)
                if controls.populate_worn then
                    action(
                        top - step * 6.5,
                        'Load Current Armor & Helmet',
                        'populate_worn',
                        true,
                        'Read every worn LUT slot without changing its colors.'
                    )
                end
                action(top - step, 'Import DDS / ZIP / RAR...', 'browse', true)
                choice('palette', top - step * 2)
                button(bx, top - step * 3, half, 'Preview Palette', nil, editor.preview ~= nil, function()
                    preview(false)
                end)
                button(
                    bx + half + 8,
                    top - step * 3,
                    half,
                    'Send to LUT Editor',
                    'save_palette',
                    true,
                    nil,
                    'Replace the editor table with the selected imported LUT. Gear is unchanged until applied.'
                )
                divider(top - step * 3 - 10)
                if controls.editor_load_armor then
                    local gear = editor.gear or 'armor'
                    local selector = controls['basic_' .. gear .. '_lut']
                    local selected = selector and selector.choices[h.get('basic_' .. gear .. '_lut')]
                    local target = selected and selected:match('^Cape') and selected
                        or (gear == 'armor' and 'Armor' or 'Helmet') .. ' LUT ' .. h.get('basic_' .. gear .. '_lut')
                    action(top - step * 4.3, 'Apply to ' .. target, 'editor_apply_' .. gear, d ~= nil)
                    action(
                        top - step * 5.3,
                        'Apply to All ' .. (gear == 'armor' and 'Armor' or 'Helmet') .. ' LUTs',
                        'editor_all_' .. gear,
                        d ~= nil,
                        'Apply the current editor table to every LUT on this gear. Send an imported LUT to the editor first.'
                    )
                else
                    choice('lut', top - step * 4.3, half)
                    button(
                        bx + half + 8,
                        top - step * 4.3,
                        half,
                        'Preview Live LUT',
                        nil,
                        editor.preview ~= nil,
                        function()
                            preview(true)
                        end
                    )
                    action(top - step * 5.3, 'Apply to checked targets', 'apply_editor', d ~= nil)
                end
            elseif self.tab == 'rows' then
                label(top, 'Selected row: ' .. h.get('edit_row') .. (d and ' / ' .. d.height or ' / Load a LUT first'))
                if ui.preset then
                    ui.preset('row_preset', 'row_preset_select', bx, top - step, width)
                else
                    action(top - step, 'Preset: ' .. h.get('row_preset'), 'row_preset', true)
                end
                action(top - step * 2, 'Save selected row', 'save_row', d ~= nil)
                action(top - step * 3, 'Apply preset to row', 'load_row', d ~= nil)
                divider(top - step * 3 - 10)
                button(bx, top - step * 4.3, half, 'Copy row', 'copy_row', d ~= nil)
                button(
                    bx + half + 8,
                    top - step * 4.3,
                    half,
                    'Paste row',
                    'paste_row',
                    d ~= nil and editor.row_clip ~= nil
                )
                button(bx, top - step * 5.3, half, 'Reset row', 'reset_row', d ~= nil)
                button(bx + half + 8, top - step * 5.3, half, 'Reset cell', 'reset_cell', d ~= nil)
            elseif self.tab == 'export' then
                label(top, 'Choose what to export. A timestamp is added to each filename.', muted)
                action(
                    top - step,
                    'Name: ' .. (ui.input_value and ui.input_value('save_name') or h.get('save_name')),
                    'save_name',
                    true
                )
                choice('export_format', top - step * 2)
                local bulk = h.get('export_format') == 4
                if bulk then
                    choice('dds_naming', top - step * 3)
                end
                local export_row = bulk and 4 or 3
                action(top - step * export_row, 'Export...', 'export_selected', d ~= nil or h.get('export_format') >= 3)
                divider(top - step * export_row - 10)
                action(top - step * (export_row + 1.3), 'Open Export Location', 'open_export', true)
                if controls.include_capes_in_armor_exports then
                    action(
                        top - step * (export_row + 2.3),
                        '[ '
                            .. (h.get('include_capes_in_armor_exports') and 'x' or ' ')
                            .. ' ] Include Capes in Armor Exports',
                        'include_capes_in_armor_exports',
                        true,
                        controls.include_capes_in_armor_exports.description
                    )
                end
            else
                label(top, 'Apply and restoration options for the current gear.', muted)
                action(top - step, 'Load Debug LUT', 'load_debug_lut', true)
                action(
                    top - step * 2,
                    '[ '
                        .. (controls.preserve_emissives and h.get('preserve_emissives') and 'x' or ' ')
                        .. ' ] Preserve Original Emissives',
                    'preserve_emissives',
                    true
                )
                if controls.editor_load_armor then
                    button(bx, top - step * 3, half, 'All Armor LUTs', 'editor_all_armor', d ~= nil)
                    button(bx + half + 8, top - step * 3, half, 'All Helmet LUTs', 'editor_all_helmet', d ~= nil)
                else
                    button(
                        bx,
                        top - step * 3,
                        half,
                        '[ ' .. (h.get('target_helmet') and 'x' or ' ') .. ' ] Helmet',
                        'target_helmet',
                        true
                    )
                    button(
                        bx + half + 8,
                        top - step * 3,
                        half,
                        '[ ' .. (h.get('target_armor') and 'x' or ' ') .. ' ] Armor',
                        'target_armor',
                        true
                    )
                end
                divider(top - step * 3 - 10)
                action(top - step * 4.3, 'Restore Arrowhead LUT (Original)', 'restore', true)
                action(top - step * 5.3, 'Reset imported table', 'reset_custom', d ~= nil)
                action(top - step * 6.3, 'Save applied setup', 'save_setup', true)
            end
        end
        ui.floating('editor_tools', draw, 620, 540, self.close, 40)
    end
    return self
end
return T
