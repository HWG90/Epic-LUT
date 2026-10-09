local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local api = Core.new()
local handle = api.register({
    id = 'windows',
    name = 'Windows',
    pages = {
        {
            id = 'main',
            name = 'Main',
            controls = {
                {
                    id = 'tools_choice',
                    type = 'choice',
                    presentation = 'dropdown',
                    label = 'Tools choice',
                    choices = { 'Tool One', 'Tool Two' },
                    default = 1,
                },
                {
                    id = 'scratch_choice',
                    type = 'choice',
                    presentation = 'dropdown',
                    label = 'Scratch choice',
                    choices = { 'Scratch One', 'Scratch Two' },
                    default = 1,
                },
                { id = 'tools_name', type = 'input', label = 'Name', default = 'Example' },
            },
        },
    },
})
local mod = api.mods[handle.id]
mod.tabs_top = true
local open = { editor_tools = true, editor_scratch = true }
local clicks = {}
mod.pages[1].render_layout = function(ui)
    for _, spec in ipairs({
        { 'editor_tools', 620, 540, 'Tools choice', 'tools_choice' },
        { 'editor_scratch', 420, 480, 'Scratch choice', 'scratch_choice' },
    }) do
        local id = spec[1]
        if open[id] then
            ui.floating(
                id,
                function(x, y, w, h)
                    ui.rect(x, y, w, h, ui.theme.panel)
                    ui.rect(x, y + h - 40, w, 40, ui.theme.header)
                    ui.bounded(x + 10, y + h - 27, spec[4], 14, ui.theme.white, w - 50)
                    ui.choice(spec[5], x + 12, y + h - 100, w - 24)
                    ui.button(x + 12, y + 20, w - 24, 28, 'Activate ' .. id, function()
                        clicks[id] = (clicks[id] or 0) + 1
                    end)
                    if id == 'editor_tools' then
                        ui.button(x + 12, y + 60, w - 24, 28, 'Type name', function()
                            ui.activate('tools_name')
                        end)
                    end
                end,
                spec[2],
                spec[3],
                function()
                    open[id] = false
                end,
                40
            )
        end
    end
end
local underlying = 0
mod.pages[1].on_wheel = function()
    underlying = underlying + 1
    return true
end
local menu = Menu.new(api, function(value, size)
    return #value * size * 0.5
end)
menu.visible = true
menu.window_width, menu.window_height = 1400, 960
local function compose()
    return menu.compose(1920, 1080)
end
local function input(x, y, pressed)
    menu.tick({
        down = function(key)
            return pressed and key == 1
        end,
        mouse = function()
            return x, y
        end,
        wheel = function()
            return 0
        end,
    })
end
local function tap(x, y)
    input(x, y, true)
    input(x, y, false)
end
local function text(commands, value, id)
    for _, c in ipairs(commands) do
        if c.full_text == value and (not id or c.floating_id == id) then
            return c
        end
    end
    error('Missing floating control: ' .. value)
end
local function window(id)
    for _, b in ipairs(menu.floating_windows) do
        if b.id == id then
            return b
        end
    end
    error('Missing floating bounds: ' .. id)
end
local commands = compose()
assert(
    #menu.floating_windows == 2
        and text(commands, 'Tools choice', 'editor_tools')
        and text(commands, 'Scratch choice', 'editor_scratch'),
    'Second floating request replaced the first window'
)
local a, b = window('editor_tools'), window('editor_scratch')
assert(a.x ~= b.x and a.y ~= b.y, 'New floating windows did not get staggered placements')
menu.floating_positions.editor_tools = { x = 350, y = 150 }
menu.floating_positions.editor_scratch = { x = 700, y = 220 }
commands = compose()
a, b = window('editor_tools'), window('editor_scratch')
assert(menu.floating_bounds.id == 'editor_scratch', 'Newest window did not start in front')
-- Exposed background and controls focus their own window, irrespective of the
-- caller's stable Tools-then-Scratch queue order.
tap(a.x + 20, a.y + 150)
commands = compose()
assert(menu.floating_bounds.id == 'editor_tools', 'Exposed background did not raise its window')
local activate = text(commands, 'Activate editor_tools', 'editor_tools')
tap(activate.x + 3, activate.y + 3)
assert(clicks.editor_tools == 1 and not clicks.editor_scratch, 'Raised window routed a child click to its neighbor')
commands = compose()
local active = text(commands, 'Tool One', 'editor_tools')
tap(active.x + 3, active.y + 3)
assert(menu.dropdown and menu.dropdown.owner.id == 'editor_tools', 'Dropdown belongs to the wrong floating owner')
local before_x, before_top = menu.dropdown.x, menu.dropdown.top
local scratch_x = menu.floating_positions.editor_scratch.x
local title = text(compose(), 'Tools choice', 'editor_tools')
input(title.x + 30, title.y + 5, true)
input(title.x - 30, title.y + 20, true)
input(title.x - 30, title.y + 20, false)
commands = compose()
assert(
    menu.dropdown and menu.dropdown.x < before_x and menu.dropdown.top > before_top,
    'Dragging a floating owner did not carry its dropdown'
)
assert(menu.floating_positions.editor_scratch.x == scratch_x, 'Dragging Tools moved Scratch too')
-- Removing an unrelated window preserves the owner and its dropdown.
open.editor_scratch = false
commands = compose()
assert(
    #menu.floating_windows == 1 and menu.dropdown and menu.dropdown.owner.id == 'editor_tools',
    'Closing Scratch discarded the Tools dropdown'
)
open.editor_tools = false
compose()
assert(
    #menu.floating_windows == 0 and not menu.dropdown and not menu.floating_bounds,
    'Closing a dropdown owner left modal input behind'
)
open.editor_tools = true
commands = compose()
local name = text(commands, 'Type name', 'editor_tools')
tap(name.x + 3, name.y + 3)
assert(
    menu.text_edit and menu.text_edit.floating_owner == 'editor_tools',
    'Floating typed field did not record its owner'
)
open.editor_scratch = true
compose()
assert(menu.text_edit, 'Opening another window discarded the typed field')
open.editor_scratch = false
compose()
assert(menu.text_edit, 'Closing unrelated window discarded typed field')
open.editor_tools = false
compose()
assert(not menu.text_edit, 'Closing text owner retained a stale editor')
-- Player Preview uses owns_pointer: rear/exposed windows must own it too, and
-- neither front nor rear popup may scroll a page under the stack.
open.editor_tools, open.editor_scratch = true, true
commands = compose()
a, b = window('editor_tools'), window('editor_scratch')
assert(
    menu.owns_pointer(a.x + 20, a.y + 100) and menu.owns_pointer(b.x + b.w - 10, b.y + 100),
    'Rear popup did not protect the pointer from Player Preview'
)
menu.wheel(-120, a.x + 20, a.y + 100)
menu.wheel(-120, b.x + b.w - 10, b.y + 100)
assert(underlying == 0, 'Floating windows scrolled the underlying page')
local maximum_tools, minimum_scratch = 0, math.huge
for _, c in ipairs(commands) do
    if c.floating_id == 'editor_tools' then
        maximum_tools = math.max(maximum_tools, c.layer)
    end
    if c.floating_id == 'editor_scratch' then
        minimum_scratch = math.min(minimum_scratch, c.layer)
    end
end
assert(minimum_scratch > maximum_tools, 'Independent windows share or cross render layers')
-- Closing a moving owner cancels its drag lease instead of capturing the mouse
-- after its window disappears.
a = window('editor_tools')
input(a.x + 25, a.y + a.h - 18, true)
open.editor_tools = false
compose()
assert(not menu.owns_pointer(0, 0), 'Closed window retained its drag capture')
input(0, 0, false)
menu.visible = false
compose()
assert(not menu.floating_bounds and #menu.floating_windows == 0, 'Hidden menu retained floating hit bounds')
print(
    'PASS floating window stack: independent queue/focus/drag, owner dropdown/input cleanup, staggering, layers and rear-window pointer/wheel capture'
)
