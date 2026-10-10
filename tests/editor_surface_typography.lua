-- Use the native menu composer to keep every Tools action reachable at the
-- supported font and scale extremes, including the last import/options rows.
local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local api, activated = Core.new(), {}
local controls = {
    { id = 'palette', type = 'choice', choices = { 'Imported LUT 1' }, default = 1 },
    { id = 'basic_armor_lut', type = 'choice', choices = { 'Armor LUT 1' }, default = 1 },
    { id = 'basic_helmet_lut', type = 'choice', choices = { 'Helmet LUT 1' }, default = 1 },
    {
        id = 'export_format',
        type = 'choice',
        choices = { 'DDS', 'Selected Patch', 'Entire Patch', 'All DDS' },
        default = 4,
    },
    { id = 'dds_naming', type = 'choice', choices = { 'LUT# + HEX' }, default = 1 },
    { id = 'row_preset', type = 'input', default = 'Sample row' },
    { id = 'row_preset_select', type = 'choice', choices = { 'Sample row' }, default = 1 },
    { id = 'edit_row', type = 'slider', min = 1, max = 64, step = 1, default = 1 },
    { id = 'save_name', type = 'input', default = 'Test' },
    { id = 'preserve_emissives', type = 'toggle', default = true },
    { id = 'include_capes_in_armor_exports', type = 'toggle', default = true },
}
for _, id in ipairs({
    'populate_worn',
    'browse',
    'save_palette',
    'editor_load_armor',
    'editor_apply_armor',
    'editor_all_armor',
    'editor_all_helmet',
    'save_row',
    'load_row',
    'copy_row',
    'paste_row',
    'reset_row',
    'reset_cell',
    'export_selected',
    'open_export',
    'load_debug_lut',
    'restore',
    'reset_custom',
    'save_setup',
}) do
    local action = id
    controls[#controls + 1] = {
        id = action,
        type = 'button',
        on_activate = function()
            activated[#activated + 1] = action
            return true
        end,
    }
end
for _, control in ipairs(controls) do
    control.label = control.label or control.id
end
local handle = api.register({
    id = 'tools_surface_typography',
    name = 'Epic LUT',
    pages = { { id = 'editor', name = 'LUT Editor', require_confirmation = false, controls = controls } },
})
local editor = {
    api = api,
    handle = handle,
    gear = 'armor',
    row_clip = {},
    load_seen = function()
        return true
    end,
}
local tools = dofile('src/editor/editor_tools.lua').new({
    editor = editor,
    document = function()
        return { height = 8 }
    end,
})
api.mods[handle.id].tabs_top = true
api.mods[handle.id].pages[1].render_layout = tools.popup
local menu = Menu.new(api, function(value, size)
    return #value * size * 0.5
end)
menu.visible, menu.epic_typography, menu.compact_fonts = true, true, true
menu.window_width, menu.window_height = 1800, 1000
local actions = {
    import = {
        { 'Load Current Armor & Helmet', 'populate_worn' },
        { 'Import DDS / ZIP / RAR...', 'browse' },
        { 'Send to LUT Editor', 'save_palette' },
        { 'Apply to Armor LUT 1', 'editor_apply_armor' },
        { 'Apply to All Armor LUTs', 'editor_all_armor' },
    },
    rows = {
        { 'Save selected row', 'save_row' },
        { 'Apply preset to row', 'load_row' },
        { 'Copy row', 'copy_row' },
        { 'Paste row', 'paste_row' },
        { 'Reset row', 'reset_row' },
        { 'Reset cell', 'reset_cell' },
    },
    export = { { 'Export...', 'export_selected' }, { 'Open Export Location', 'open_export' } },
    options = {
        { 'Load Debug LUT', 'load_debug_lut' },
        { 'All Armor LUTs', 'editor_all_armor' },
        { 'All Helmet LUTs', 'editor_all_helmet' },
        { 'Restore Arrowhead LUT (Original)', 'restore' },
        { 'Reset imported table', 'reset_custom' },
        { 'Save applied setup', 'save_setup' },
    },
}
for _, font in ipairs({ 12, 20 }) do
    for _, scale in ipairs({ 0.85, 1.3 }) do
        menu.font_size, menu.ui_scale = font, scale
        for _, tab in ipairs({ 'import', 'rows', 'export', 'options' }) do
            tools.open(tab)
            local commands = menu.compose(1920, 1080)
            local bounds = assert(menu.floating_bounds)
            local labels = {}
            for _, command in ipairs(commands) do
                assert(not (command.text and command.text:find('Editor control missing:', 1, true)))
                if command.floating_id == 'editor_tools' then
                    if command.full_text then
                        labels[command.full_text] = command
                    end
                    if command.type == 'rect' and command.ui_role ~= 'window_frame' then
                        assert(
                            command.x >= bounds.x - 0.01
                                and command.y >= bounds.y - 0.01
                                and command.x + command.w <= bounds.x + bounds.w + 0.01
                                and command.y + command.h <= bounds.y + bounds.h + 0.01,
                            'Tools control escaped its window at font ' .. font .. ' / ' .. tab
                        )
                    end
                end
            end
            assert(labels['LUT Editor Tools'].text_role == 'heading', 'Tools title lost its heading style')
            if tab == 'export' then
                assert(labels['All DDS'] and labels['LUT# + HEX'] and labels['[ x ] Include Capes in Armor Exports'])
            end
            for _, action in ipairs(actions[tab]) do
                local label = assert(labels[action[1]], 'Missing Tools action: ' .. action[1])
                local before = #activated
                for _, pressed in ipairs({ true, false }) do
                    menu.tick({
                        down = function(key)
                            return pressed and key == 1
                        end,
                        mouse = function()
                            return label.x + 2, label.y + 2
                        end,
                        wheel = function()
                            return 0
                        end,
                    })
                end
                assert(
                    #activated == before + 1 and activated[#activated] == action[2],
                    'Tools hit target lost ' .. action[1]
                )
            end
        end
    end
end
print('PASS editor surface typography: Tools action containment and hit targets at fonts 12/20 and scales 85/130')
