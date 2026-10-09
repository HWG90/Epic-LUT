-- Theme source: DBF-MCM src/ui/theme.lua, inspected 2026-10-09.
-- Source SHA256: 7179FAEB1F3122E575BA3FD1F638589B87C14093384A6723BFB6E8F8644F3A82.
-- The owning MCM checkout may have uncommitted work, so compare current bytes
-- when it exists, with the recorded palette contract for standalone/CI runs.
local Menu = dofile('vendor/menu/menu.lua')
local expected = {
    background = { 17, 22, 27 },
    panel = { 23, 29, 35 },
    header = { 31, 38, 44 },
    border = { 65, 77, 85 },
    line = { 43, 53, 61 },
    white = { 231, 236, 239 },
    muted = { 153, 166, 175 },
    brass = { 221, 184, 105 },
    focus = { 119, 185, 205 },
    hover = { 35, 46, 55 },
    selected = { 38, 53, 63 },
    field = { 29, 39, 47 },
    field_hover = { 40, 55, 65 },
    enabled = { 118, 207, 177 },
    disabled = { 111, 124, 133 },
}
local function same(a, b)
    return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end
local reference = '../DBF-MCM/src/ui/theme.lua'
local file = io.open(reference, 'rb')
if file then
    file:close()
    expected = dofile(reference).palette
end
for key, color in pairs(expected) do
    assert(same(Menu.palette[key], color), 'MCM palette drift: ' .. key)
end

local Core = dofile('vendor/menu/core.lua')
local writes, clicks = 0, {}
local api = Core.new({
    load = function()
        return {}
    end,
    save = function()
        writes = writes + 1
        return true
    end,
})
local state = { armor = {}, helmet = {}, palette_count = 0, status = 'Ready', time = 0, load_seen = false }
local view = dofile('src/editor/import_view.lua').new(function()
    return state
end, nil, nil, Core)
local controls = {}
for _, id in ipairs({
    'populate_worn',
    'stop_identify',
    'browse',
    'save_palette',
    'apply_file_armor',
    'apply_file_helmet',
    'preserve_emissives',
    'restore',
    'restore_imported',
    'global_undo',
    'global_redo',
    'save_setup',
}) do
    local key = id
    controls[#controls + 1] = {
        id = id,
        type = 'button',
        label = id,
        on_activate = function()
            clicks[key] = (clicks[key] or 0) + 1
            return true
        end,
    }
end
local h = api.register({
    id = 'style',
    name = 'Epic LUT',
    pages = {
        { id = 'import', name = 'Import', controls = controls },
        {
            id = 'surfaces',
            name = 'Surfaces',
            controls = {
                { id = 'style_color', type = 'color', label = 'Color', default = '#FFFFFF' },
            },
        },
    },
})
local mod = api.mods[h.id]
mod.tabs_top = true
mod.pages[1].render_layout = view.draw
mod.pages[2].render_layout = function(ui)
    -- A color helper used as the final rect argument must not leak a second
    -- boolean return into renderer opacity when the pointer enters the surface.
    ui.rect(ui.x + 10, ui.y + 100, 220, 32, ui.surface_color(ui.x + 10, ui.y + 100, 220, 32))
    ui.button(ui.x + 10, ui.y + 100, 220, 32, 'Action', function()
        clicks.action = (clicks.action or 0) + 1
    end)
    ui.button(ui.x + 10, ui.y + 60, 220, 32, 'Unavailable', function()
        error('Disabled action ran')
    end, { enabled = false })
    ui.button(ui.x + 250, ui.y + 100, 220, 32, 'Selected', function() end, { selected = true })
    ui.button(ui.x + 250, ui.y + 60, 220, 32, 'Export', function()
        clicks.export = (clicks.export or 0) + 1
    end, { accent = { 244, 202, 53 }, ink = { 25, 28, 31 } })
end
local menu = Menu.new(api, function(text, size)
    return #text * size * 0.5
end)
menu.visible = true
local function compose()
    return menu.compose(1920, 1080)
end
local function button(commands, label)
    for i, c in ipairs(commands) do
        if c.full_text == label then
            assert(commands[i - 1].type == 'rect')
            return commands[i - 1], c
        end
    end
    error('Missing composed control: ' .. label)
end
local function input(rect, down)
    menu.tick({
        down = function(key)
            return down and key == 1
        end,
        mouse = function()
            return rect.x + rect.w / 2, rect.y + rect.h / 2
        end,
        wheel = function()
            return 0
        end,
    })
end
local function tap(rect)
    input(rect, true)
    input(rect, false)
end

local commands = compose()
local load = button(commands, 'Load Current Armor & Helmet')
local scratch = button(commands, 'Quick Scratch')
assert(load.x + load.w <= scratch.x or scratch.y + scratch.h < load.y, 'Import toolbar collision returned')
local before = writes
input(scratch, false)
local hovered = button(compose(), 'Quick Scratch')
assert(
    same(hovered.c, Menu.palette.field_hover) and writes == before,
    'Custom Import action has no passive hover feedback'
)
tap(load)
assert(clicks.populate_worn == 1 and not view.scratch_open, 'Load hit was intercepted by Quick Scratch')
local unavailable = button(compose(), 'Send to LUT Editor')
tap(unavailable)
assert(not clicks.save_palette, 'Empty Import workspace submitted a nonexistent table')

menu.page = 2
commands = compose()
local action = button(commands, 'Action')
assert(same(action.c, Menu.palette.field), 'Action does not use the MCM value surface')
input(action, false)
commands = compose()
assert(same(button(commands, 'Action').c, Menu.palette.field_hover) and writes == before, 'Hover publishes settings')
for _, command in ipairs(commands) do
    assert(type(command.a) == 'number', 'Surface hover leaked a boolean into renderer opacity')
end
tap(action)
assert(clicks.action == 1, 'Styled custom button changed its callback routing')
local disabled, text = button(compose(), 'Unavailable')
assert(
    same(disabled.c, Menu.palette.panel) and same(text.c, Menu.palette.disabled),
    'Disabled custom control is not gray'
)
tap(disabled)
assert(same(button(compose(), 'Selected').c, Menu.palette.selected), 'Selected custom tab lost its state feedback')
local export, export_text = button(compose(), 'Export')
assert(same(export.c, { 244, 202, 53 }) and same(export_text.c, { 25, 28, 31 }), 'Semantic Export accent changed')
input(export, false)
assert(same(button(compose(), 'Export').c, { 244, 202, 53 }), 'Hover removed the Export accent')
tap(export)
assert(clicks.export == 1, 'Export accent blocks pointer activation')
menu.color_picker = { mod = mod, control = mod.controls.style_color, rgb = { 255, 255, 255 } }
input(action, false)
assert(same(button(compose(), 'Action').c, Menu.palette.field), 'Covered action reacts through a modal picker')
menu.color_picker = nil
for _, font in ipairs({ 12, 20 }) do
    menu.compact_fonts, menu.font_size = true, font
    local rect, label = button(compose(), 'Action')
    assert(label.y >= rect.y and label.y + label.size <= rect.y + rect.h, 'Styled label clips after font resize')
end
print(
    'PASS custom UI styling: current MCM palette, Import toolbar clicks, hover/modal feedback, disabled controls, semantic accents and font containment'
)
