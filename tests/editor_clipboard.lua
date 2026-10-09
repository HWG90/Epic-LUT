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
local text, sets = '', 0
api.clipboard = {
    get = function()
        return text
    end,
    set = function(value)
        text = value
        sets = sets + 1
        return true
    end,
}
local document = { width = 23, height = 2, data = ffi.new('float[184]') }
for i = 0, 183 do
    document.data[i] = (i % 11) / 10
end
ffi.cast('uint32_t *', document.data)[4] = 0x80000000
local m = {
    ui_core = core,
    lut_editor_controls = dofile('src/editor/lut_editor_controls.lua'),
    lut_editor_view = dofile('src/editor/lut_editor_view.lua'),
    editor_tools = dofile('src/editor/editor_tools.lua'),
    scratch_tool = dofile('src/editor/scratch_tool.lua'),
    lut_files = dofile('src/presets/lut_files.lua'),
    file_io = dofile('src/core/file_io.lua'),
    dds = dofile('src/core/dds.lua'),
    semantics = dofile('src/core/semantics.lua'),
    palette = dofile('src/core/palette.lua'),
    windows = {
        row_presets = function()
            return {}
        end,
    },
}
local editor = dofile('src/editor/lut_editor.lua').new(m, function()
    return document
end, function(value)
    return value
end, function()
    return true
end, 'tests/tmp/presets')
local registry = editor.pages()
local canonical_bumps = {
    'flat (dry grime)',
    'flat (wet grime)',
    'damascus',
    'suede (dry grime)',
    'suede (wet grime)',
    'wall (bullet holes)',
    'denim',
    'corduroy',
    'waffle',
    'wall (plaster)',
    'wall (concrete)',
    'raincoat',
    'wool (knitted)',
    'wool (woven)',
    'scrapmetal',
    'leather (worn)',
    'linen',
    'linen (worn)',
    'nylon',
    'leather (wet grime)',
    'leather (dry grime)',
    'boulder',
    'circuitboard',
    'dimpled (square)',
    'vinyl',
    'circuitboard (light)',
}
for _, control in ipairs(registry[2].controls) do
    if control.id == 'detail_texture' then
        for index, name in ipairs(canonical_bumps) do
            assert(
                control.choices[index] == 'R' .. (index - 1) .. ' - ' .. name,
                'Initial bump-map label/index mismatch'
            )
        end
    end
end
local handle = api.register({ id = 'clipboard', name = 'Epic LUT', pages = registry })
editor.attach(api, handle)
local function bytes()
    return ffi.string(document.data, document.width * document.height * 16)
end
local function context(control, floating)
    return { control = control, floating = floating, clipboard = api.clipboard }
end
assert(editor.key(67, false, false, context()) == false, 'Unmodified C was consumed')
-- Named bump choices set the exact R index, leaving fractional/unknown raw values alone.
assert(handle.set('unlock', true))
editor.focus_cell(1, 2)
for index, name in ipairs(canonical_bumps) do
    local choices = api.mods[handle.id].controls.detail_texture.choices
    assert(choices[index] == 'R' .. (index - 1) .. ' - ' .. name, 'Synced bump-map order changed')
    assert(
        handle.set('detail_texture', index) and document.data[4] == index - 1,
        'Named choice wrote another raw bump index'
    )
end
for _, value in ipairs({ 0.625, -1, 26, 90.5 }) do
    document.data[4] = value
    editor.sync()
    local choices = api.mods[handle.id].controls.detail_texture.choices
    assert(choices[27]:find('Custom:', 1, true) == 1 and document.data[4] == value, 'Unknown bump value was remapped')
end
ffi.cast('uint32_t *', document.data)[4] = 0x80000000
editor.sync()
assert(handle.set('unlock', false))
-- Scalar copy preserves one exact float and does not change the current document.
editor.focus_value(1, 2, 1)
local before = bytes()
assert(
    handle.activate('copy_value') and text == '-0' and bytes() == before,
    'Scalar copy changed pixels or lost negative zero'
)
assert(handle.set('unlock', true))
editor.focus_value(2, 3, 2)
assert(handle.activate('paste_value'))
local target = m.semantics.index(2, 3, 2, 23, 2)
assert(ffi.cast('uint32_t *', document.data)[target] == 0x80000000, 'Scalar paste lost signed-zero bits')
assert(handle.activate('undo') and bytes() == before, 'Scalar paste failed undo')
text = ' 1.23456789e+5 '
editor.focus_value(1, 1, 2)
assert(handle.activate('paste_value'))
local encoded = ffi.new('float[1]', tonumber(text))
assert(ffi.string(document.data + 1, 4) == ffi.string(encoded, 4), 'Scientific scalar paste changed precision')
local changed = bytes()
assert(editor.key(90, true, false, context()) and bytes() == before, 'Ctrl+Z failed scalar undo')
assert(editor.key(90, true, true, context()) and bytes() == changed, 'Ctrl+Shift+Z failed redo')
assert(
    editor.key(90, true, false, context()) and editor.key(89, true, false, context()) and bytes() == changed,
    'Ctrl+Y failed redo'
)
assert(handle.activate('undo'))
-- Raw numeric schema keeps finite HDR values outside visual slider bounds.
text = '1e20'
editor.focus_value(1, 1, 2)
assert(handle.activate('paste_value'))
local hdr = ffi.new('float[1]', 1e20)
assert(ffi.string(document.data + 1, 4) == ffi.string(hdr, 4), 'Raw numeric paste imposed the visual slider range')
assert(handle.activate('undo') and bytes() == before)
-- Malformed/overflow/protected/read-only/stale paste must not mutate or add history.
local history_count = #editor.undo
for _, invalid in ipairs({ 'nan', 'inf', '1e309', '1e40', 'abc', '0.5 trailing', '' }) do
    text = invalid
    assert(not pcall(editor.paste_value), 'Invalid scalar pasted: ' .. invalid)
    assert(bytes() == before and #editor.undo == history_count, 'Invalid scalar was not atomic')
end
assert(handle.set('unlock', false))
editor.focus_value(1, 2, 1)
text = '0.25'
assert(not pcall(editor.paste_value) and bytes() == before, 'Protected material value was pasted')
editor.focus_value(1, 1, 4)
assert(not pcall(editor.paste_value) and bytes() == before, 'Protected alpha was pasted')
editor.focus_value(1, 1, 1)
document.read_only = true
assert(not pcall(editor.paste_value) and bytes() == before, 'Read-only document was pasted')
assert(not pcall(editor.key, 86, true, false, context()), 'Keyboard paste bypassed read-only protection')
document.read_only = nil
document.stale = true
assert(not pcall(editor.paste_value) and bytes() == before, 'Stale document was pasted')
document.stale = nil
-- Focused Value Editor shortcuts choose its scalar channel; grid shortcuts remain full RGBA.
editor.focus_cell(1, 1)
assert(
    editor.key(67, true, false, context('cell_b')) and text == string.format('%.9g', tonumber(document.data[2])),
    'Value shortcut copied the grid selection'
)
text = '0.625'
assert(
    editor.key(86, true, false, context('cell_b')) and document.data[2] == 0.625,
    'Value shortcut pasted another channel'
)
assert(handle.activate('undo') and bytes() == before)
assert(handle.set('unlock', true))
editor.focus_cell(1, 1)
assert(
    editor.key(67, true, false, context()) and editor.clip.width == 1 and editor.clip.height == 1,
    'Ctrl+C did not copy pixels'
)
local pixel = ffi.string(document.data, 16)
editor.focus_cell(2, 3)
assert(
    editor.key(86, true, false, context()) and ffi.string(document.data + 100, 16) == pixel,
    'Ctrl+V lost pixel RGBA'
)
assert(handle.activate('undo') and bytes() == before)
assert(handle.set('unlock', false))
editor.focus_cell(1, 1)
assert(editor.key(67, true, false, context()))
editor.focus_cell(2, 3)
assert(
    not pcall(editor.key, 86, true, false, context()) and bytes() == before,
    'Pixel shortcut silently discarded protected RGBA channels'
)
-- Scratch system HEX copy/paste changes only the shared brush, retaining alpha on RGB paste.
assert(handle.set_many({ scratch_color = '#123456', scratch_alpha = 0.75 }))
assert(editor.key(67, true, false, context(nil, 'editor_scratch')) and text == '#123456')
text = ' 0xAaBBcC '
assert(editor.key(86, true, false, context(nil, 'editor_scratch')))
assert(handle.get('scratch_color') == '#AABBCC' and handle.get('scratch_alpha') == 0.75 and bytes() == before)
text = '#11223344'
assert(handle.activate('scratch_paste'))
assert(handle.get('scratch_color') == '#112233' and math.abs(handle.get('scratch_alpha') - 68 / 255) < 0.001)
local scratch_before = handle.get('scratch_color')
text = '#bad-color'
assert(not pcall(editor.scratch_paste) and handle.get('scratch_color') == scratch_before, 'Invalid HEX changed Scratch')
assert(
    editor.key(90, true, false, context(nil, 'editor_scratch')) == false,
    'Scratch Ctrl+Z unexpectedly changed the LUT'
)
assert(
    editor.key(86, true, false, context(nil, 'pattern_lut')) == false,
    'Other popup shortcut pasted into the main LUT'
)
-- A changed document invalidates scalar focus until its editor sync completes.
editor.focus_value(1, 1, 1)
document = { width = 23, height = 2, data = ffi.new('float[184]') }
text = '0.375'
assert(not pcall(editor.paste_value), 'Old scalar focus pasted into a replaced document')
editor.sync()
editor.focus_cell(1, 1)
assert(not editor.value_target and editor.paste_value() and document.data[0] == 0.375)
assert(api.mods[handle.id].pages[1].on_key == editor.key, 'Editor page did not register its keyboard hook')
-- Actual menu dispatch routes Scratch ownership and lets native text edits consume Ctrl+V first.
api.mods[handle.id].tabs_top = true
local menu = dofile('vendor/menu/menu.lua').new(api, function(value, size)
    return #value * size * 0.5
end)
menu.visible, menu.selected, menu.page, menu.clipboard = true, 1, 1, api.clipboard
menu.compact_fonts, menu.window_width, menu.window_height = true, 1800, 1000
local function compose()
    return menu.compose(1920, 1080)
end
local function tap_label(value)
    local target
    for _, command in ipairs(compose()) do
        if command.full_text == value or command.text == value then
            target = command
            break
        end
    end
    assert(target, 'Missing real clipboard control: ' .. value)
    for _, down in ipairs({ true, false }) do
        menu.tick({
            down = function(key)
                return down and key == 1
            end,
            mouse = function()
                return target.x + 3, target.y + 3
            end,
            wheel = function()
                return 0
            end,
        })
    end
end
assert(handle.set('unlock', true))
editor.focus_cell(1, 1)
compose()
menu.key(67, true, false)
assert(editor.clip and editor.clip.width == 1, 'Menu did not route Ctrl+C to pixel clipboard')
local main_before = bytes()
tap_label('Scratch')
tap_label('Copy HEX')
assert(menu.shortcut_context.floating == 'editor_scratch', 'Scratch click lost its owner for keyboard shortcuts')
text = '#778899'
menu.key(86, true, false)
assert(handle.get('scratch_color') == '#778899' and bytes() == main_before, 'Menu Scratch paste changed the LUT')
menu.text_edit =
    { mod = api.mods[handle.id], control = api.mods[handle.id].controls.cell_g, text = '0', replace = true }
text = '0.125'
menu.key(86, true, false)
local text_value = ffi.new('float[1]', 0.125)
local expected_text_edit = main_before:sub(1, 4) .. ffi.string(text_value, 4) .. main_before:sub(9)
assert(menu.text_edit.text == '0.125' and bytes() == expected_text_edit, 'Native text paste also ran a LUT shortcut')
menu.text_edit = nil
for id, expected in pairs({ shader_mode = { 1, 4 }, detail_texture = { 2, 1 }, camo_pattern = { 22, 4 } }) do
    editor.focus_cell(1, 7)
    assert(editor.key(67, true, false, { control = id, clipboard = api.clipboard }))
    assert(
        editor.value_target.column == expected[1] and editor.value_target.channel == expected[2],
        'Keyboard enum focus copied the previously selected column'
    )
end
print(
    'PASS editor clipboard: exact scalar/signed-zero values, finite atomic paste, locks/readonly/stale guards, Ctrl pixel RGBA and undo/redo, shared Scratch HEX/alpha'
)
