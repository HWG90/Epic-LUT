-- Basic Camo colors supply picker_commit without an alpha/preview session.
-- Exercise actual RGB/HEX text, blur and USE COLOR rather than direct callbacks.
local ffi = require('ffi')
local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local Text = dofile('src/platform/text_editor.lua')
local api = Core.new()
local pixels = ffi.new('float[12]', { 18 / 255, 52 / 255, 86 / 255, 3.75, -2.5, 4.125, 7, 2.75, 9, 10, 11, -0.25 })
local committed, last_alpha, fail = 0, nil, false
local rgba_alpha, rgba_commit = 0, nil
local definitions = {
    {
        id = 'camo',
        type = 'color',
        label = 'Camo RGB',
        default = '#123456',
        picker_channel_enabled = function(channel)
            return channel <= 3
        end,
        picker_commit = function(rgb, alpha)
            if fail then
                return false, 'Camo target changed'
            end
            last_alpha, committed = alpha, committed + 1
            for channel = 1, 3 do
                pixels[channel - 1] = rgb[channel] / 255
            end
            return true
        end,
    },
    {
        id = 'rgba',
        type = 'color',
        label = 'Full RGBA',
        default = '#123456',
        picker_alpha = function()
            return rgba_alpha
        end,
        picker_commit = function(rgb, alpha)
            rgba_commit = { rgb[1], rgb[2], rgb[3], alpha }
            return true
        end,
    },
    { id = 'plain', type = 'color', label = 'Plain color', default = '#123456' },
}
local handle = api.register({
    id = 'rgb_only',
    name = 'Epic LUT',
    pages = {
        { id = 'basic', name = 'Basic', require_confirmation = false, controls = definitions },
    },
})
local mod = api.mods[handle.id]
mod.tabs_top = true
mod.pages[1].render_layout = function(ui)
    for index, name in ipairs({ 'camo', 'rgba', 'plain' }) do
        local id = name
        ui.button(ui.x + 20, ui.y + 180 - index * 40, 240, 30, definitions[index].label, function()
            ui.activate(id, nil, id == 'camo' and 1 or nil)
        end)
    end
end
local menu = Menu.new(api, function(value, size)
    return #value * size * 0.5
end, Text)
menu.visible, menu.epic_typography, menu.window_width, menu.window_height = true, true, 1500, 1000
local function compose()
    local commands = menu.compose(1920, 1080)
    for _, command in ipairs(commands) do
        assert(not (command.text and command.text:find('attempt to ', 1, true)), command.text)
    end
    return commands
end
local function label(value)
    for _, command in ipairs(compose()) do
        if (command.full_text or command.text) == value then
            return command
        end
    end
    error('Missing RGB picker label ' .. value)
end
local function click(x, y)
    for _, down in ipairs({ true, false }) do
        menu.tick({
            down = function(key)
                return down and key == 1
            end,
            mouse = function()
                return x, y
            end,
        }, 0)
    end
end
local function button(value)
    local command = label(value)
    click(command.x + 2, command.y + 2)
end
local function field(value)
    local command, scale = label(value), menu.window_bounds.scale
    click(command.x + 70 * scale, command.y + 3 * scale)
    assert(menu.text_edit and menu.color_picker and menu.visible, 'RGB field did not retain menu/picker ownership')
end
local function type_text(value)
    menu.key(65, true)
    for character in value:gmatch('.') do
        local key = character:match('[%dA-F]') and string.byte(character)
            or character == '-' and 189
            or character == '.' and 190
        assert(key)
        menu.key(key)
    end
end
local original = ffi.string(pixels, 48)
local function retained()
    assert(ffi.string(pixels, 48):sub(13) == original:sub(13), 'RGB-only picker wrote alpha/material/unknown channels')
    assert(
        menu.visible and not menu.color_picker and not menu.text_edit,
        'RGB-only commit closed the main menu or leaked picker focus'
    )
end

button('Camo RGB')
assert(
    mod.controls.camo.picker_commit
        and mod.controls.camo.picker_alpha == nil
        and mod.controls.camo.picker_begin == nil
        and mod.controls.camo.picker_preview == nil
        and mod.controls.camo.picker_end == nil
)
for _, command in ipairs(compose()) do
    assert(not (command.popup and command.text == 'A'), 'RGB-only picker offered an unsupported alpha field')
end
field('R')
type_text('222')
menu.key(13)
assert(menu.color_picker and menu.color_picker.rgb[1] == 222 and not menu.text_edit and committed == 0)
field('G')
type_text('91')
field('B') -- Blur commits G into the picker before focusing B.
assert(menu.color_picker.rgb[2] == 91 and committed == 0)
type_text('33')
field('HEX') -- Its initial text must include B finalized by this same click.
assert(menu.text_edit.text == '#DE5B21', 'RGB blur opened HEX with stale pre-blur values')
menu.key(13)
button('USE COLOR') -- Blur B and commit RGB with missing optional alpha hook.
assert(
    committed == 1
        and last_alpha == 1
        and pixels[0] == ffi.new('float[1]', 222 / 255)[0]
        and pixels[1] == ffi.new('float[1]', 91 / 255)[0]
        and pixels[2] == ffi.new('float[1]', 33 / 255)[0]
)
retained()

button('Camo RGB')
field('HEX')
type_text('ABCDEF')
menu.key(13)
assert(menu.color_picker and not menu.text_edit and committed == 1)
menu.key(13) -- Enter outside a field commits the RGB-only picker.
assert(
    committed == 2
        and last_alpha == 1
        and pixels[0] == ffi.new('float[1]', 171 / 255)[0]
        and pixels[1] == ffi.new('float[1]', 205 / 255)[0]
        and pixels[2] == ffi.new('float[1]', 239 / 255)[0]
)
retained()

button('Camo RGB')
field('HEX')
type_text('102030')
button('USE COLOR') -- Pending HEX is finalized by blur on USE COLOR.
assert(
    committed == 3
        and pixels[0] == ffi.new('float[1]', 16 / 255)[0]
        and pixels[1] == ffi.new('float[1]', 32 / 255)[0]
        and pixels[2] == ffi.new('float[1]', 48 / 255)[0]
)
retained()

local snapshot = ffi.string(pixels, 48)
button('Camo RGB')
field('R')
type_text('-')
button('USE COLOR')
assert(
    menu.visible and menu.color_picker and menu.text_edit and committed == 3 and ffi.string(pixels, 48) == snapshot,
    'Invalid RGB draft closed the menu/picker or wrote pixels'
)
menu.key(27)
menu.key(27)
assert(menu.visible and not menu.color_picker and ffi.string(pixels, 48) == snapshot)
button('Camo RGB')
field('HEX')
type_text('ABC')
button('USE COLOR')
assert(menu.visible and menu.color_picker and menu.text_edit and committed == 3, 'Invalid HEX escaped picker ownership')
menu.key(27)
button('CANCEL')
assert(menu.visible and not menu.color_picker and ffi.string(pixels, 48) == snapshot)
button('Camo RGB')
field('R')
type_text('244')
menu.key(13)
fail = true
button('USE COLOR')
fail = false
assert(
    menu.visible
        and menu.color_picker
        and menu.color_picker.error == 'Camo target changed'
        and committed == 3
        and ffi.string(pixels, 48) == snapshot,
    'Rejected RGB commit closed the main menu'
)
button('CANCEL')
assert(menu.visible and not menu.color_picker)

-- Alpha-capable LUT controls retain zero and HDR alpha. They do not inherit
-- the RGB-only fallback, and errors resolving their hook stay inside pcall.
for _, alpha in ipairs({ 0, 2.75 }) do
    rgba_alpha = alpha
    button('Full RGBA')
    compose()
    button('USE COLOR')
    assert(
        menu.visible and not menu.color_picker and rgba_commit[4] == alpha,
        'Optional fallback changed full LUT alpha'
    )
end
button('Full RGBA')
local getter = mod.controls.rgba.picker_alpha
mod.controls.rgba.picker_alpha = function()
    error('Alpha target changed', 0)
end
menu.color_picker.alpha = nil
menu.commit_color()
mod.controls.rgba.picker_alpha = getter
assert(
    menu.visible and menu.color_picker and menu.color_picker.error:find('Alpha target changed', 1, true),
    'Alpha getter failure escaped the protected commit callback'
)
button('CANCEL')
button('Plain color')
field('HEX')
type_text('FEDCBA')
button('USE COLOR')
assert(
    menu.visible and not menu.color_picker and handle.get('plain') == '#FEDCBA',
    'Callback-free RGB color commit regressed'
)
print(
    'PASS RGB-only picker: real RGB/HEX Enter/blur/USE COLOR, optional callback absence, alpha/material byte preservation, rejected/cancel guards and zero/HDR RGBA hooks'
)
