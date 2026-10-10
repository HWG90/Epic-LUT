local Core = dofile('vendor/menu/core.lua')
local Menu = dofile('vendor/menu/menu.lua')
local api = Core.new({
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
})
local handle =
    api.register({ id = 'tooltip_wrap', name = 'Epic LUT', pages = { { id = 'test', name = 'Test', controls = {} } } })
local guidance = 'Edit the current brush color. Scratch tools also include alpha.'
local help = guidance
api.mods[handle.id].pages[1].render_layout = function(ui)
    ui.button(ui.x + 20, ui.y + 30, 150, 30, 'Brush', function() end, { help = help })
end
-- The real view's fallback is a per-glyph metric, not a string-width API.
local menu = Menu.new(api, function(_, size)
    return size * 0.62
end)
menu.visible, menu.selected, menu.page, menu.compact_fonts = true, 1, 1, true
local function tooltip_text(commands)
    local plane, lines = nil, {}
    for _, command in ipairs(commands) do
        if command.window_frame == 'tooltip' then
            plane = command.paint_plane
        end
    end
    if plane then
        assert(plane == math.floor(plane), 'Tooltip plane is not an integer')
        for _, command in ipairs(commands) do
            if command.paint_plane == plane and command.text then
                lines[#lines + 1] = command
            end
        end
    end
    return lines, plane
end
for _, font in ipairs({ 12, 20 }) do
    menu.font_size = font
    local label
    for _, command in ipairs(menu.compose(1920, 1080)) do
        if command.full_text == 'Brush' then
            label = command
        end
    end
    assert(label)
    menu.tick({
        down = function()
            return false
        end,
        mouse = function()
            return label.x + 2, label.y + 2
        end,
        wheel = function()
            return 0
        end,
    })
    menu.compose(1920, 1080)
    menu.advance(0.6)
    local lines = tooltip_text(menu.compose(1920, 1080))
    local full = {}
    for i, line in ipairs(lines) do
        assert(line.text == line.full_text, 'Tooltip renderer truncated a wrapped word')
        full[#full + 1] = line.text
        if i > 1 then
            assert(line.y + line.size < lines[i - 1].y, 'Tooltip lines overlap')
        end
    end
    assert(table.concat(full, ' ') == guidance, 'Tooltip dropped a letter or word')
end
for _, empty in ipairs({
    '',
    '   \t\r\n',
    function()
        return ''
    end,
    function()
        return nil
    end,
    function()
        error('Unavailable optional tooltip')
    end,
}) do
    help = empty
    menu.compose(1920, 1080)
    menu.advance(0.6)
    local lines, plane = tooltip_text(menu.compose(1920, 1080))
    assert(not plane and #lines == 0, 'Empty tooltip rendered a blank panel')
end
help = function()
    return guidance
end
menu.compose(1920, 1080)
menu.advance(0.6)
assert(#tooltip_text(menu.compose(1920, 1080)) > 0, 'Nonempty callback tooltip was suppressed')
print('PASS tooltip wrapping: per-glyph fallback, complete words and resized line spacing')
