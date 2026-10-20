local api = dofile('vendor/menu/core.lua').new({
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
})
local changes = 0
local h = api.register({
    id = 'slider_test',
    name = 'Slider',
    pages = {
        {
            id = 'p',
            name = 'Page',
            require_confirmation = false,
            controls = {
                {
                    id = 'value',
                    type = 'slider',
                    label = 'Value',
                    min = 0,
                    max = 1,
                    step = 0.01,
                    default = 0.2,
                    on_change = function()
                        changes = changes + 1
                    end,
                },
            },
        },
    },
})
api.mods[h.id].pages[1].render_layout = function(ui)
    ui.number('value', ui.x + 10, ui.y + 100, 400, h.get('value'), function() end, true, 0, 1)
    ui.number('value', ui.x + 10, ui.y + 50, 400, 0.2, function() end, true, 0, 1)
end
local Menu = dofile('vendor/menu/menu.lua')
local menu = Menu.new(api, function(text, size)
    return #text * size * 0.5
end)
menu.visible = true
local function input(x, y, down)
    menu.tick({
        down = function(k)
            return down and k == 1
        end,
        mouse = function()
            return x, y
        end,
        wheel = function()
            return 0
        end,
    })
end
local bar
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.type == 'rect' and c.c == Menu.palette.focus and c.h == 5 then
        if not bar then
            bar = c
        end
    end
end
assert(bar)
local x, y = bar.x + (bar.w / 0.2) * 0.8, bar.y + 5
input(bar.x + (bar.w / 0.2) * 0.4, y, true)
input(bar.x + (bar.w / 0.2) * 0.6, y, true)
input(x, y, true)
assert(menu.is_interacting(), 'Active value drag is invisible to automatic gear refresh')
local displayed = false
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text == '0.8' or c.text == '0.8' then
        displayed = true
    end
end
local other = false
for _, c in ipairs(menu.compose(1920, 1080)) do
    if c.full_text == '0.2' or c.text == '0.2' then
        other = true
    end
end
assert(other, 'Dragging one channel previewed its value in another column')
assert(displayed and h.get('value') == 0.2 and changes == 0, 'Held slider committed intermediate edits')
input(x, y, false)
assert(not menu.is_interacting(), 'Released value drag keeps automatic gear refresh blocked')
assert(math.abs(h.get('value') - 0.8) < 1e-9 and changes == 1, 'Release duplicated the live update')
-- Returning to the starting value must not create a redundant edit.
input(bar.x + (bar.w / 0.2) * 0.3, y, true)
input(x, y, true)
input(x, y, false)
assert(math.abs(h.get('value') - 0.8) < 1e-9 and changes == 1, 'No-op drag created another edit')
-- Closing the menu cancels the draft rather than committing it.
input(bar.x + (bar.w / 0.2) * 0.1, y, true)
menu.visible = false
input(bar.x + (bar.w / 0.2) * 0.1, y, false)
assert(math.abs(h.get('value') - 0.8) < 1e-9 and changes == 1, 'Closing the menu committed an unfinished drag')
print('PASS slider transaction: responsive draft display, zero intermediate callbacks, one release commit and no-op rejection')

-- Owners with transient pixels can preview live without committing settings.
local runtime, previews, finishes = h.get('value'), 0, 0
local control = api.mods[h.id].controls.value
control.slider_begin = function() return { before = runtime } end
control.slider_preview = function(session, value)
    previews = previews + 1
    runtime = value
end
control.slider_end = function(session, commit)
    finishes = finishes + 1
    if commit then assert(h.set('value', runtime)) else runtime = session.before end
end
menu.visible = true
input(x, y, false)
menu.compose(1920, 1080)
local function at(value, down) input(bar.x + (bar.w / 0.2) * value, y, down) end
at(0.1, true)
at(0.2, true)
assert(runtime ~= 0.8 and changes == 1, 'Held slider did not preview independently of its settings')
for i = 1, 5 do at(0.2, true) end -- Flush the pending changed value.
local count = previews
for i = 1, 120 do at(0.2, true) end
assert(previews == count, 'Stationary slider repeated preview work')
for i = 1, 60 do at(0.2 + i / 100, true) end
assert(previews - count <= 15, 'Numeric preview exceeded its 15 Hz work budget')
at(0.8, false)
assert(runtime == 0.8 and h.get('value') == 0.8 and finishes == 1 and changes == 1,
    'Returning to the starting value committed history')
at(0.1, true)
at(0.3, true)
at(0.3, false)
assert(math.abs(runtime - 0.3) < 1e-9 and changes == 2 and finishes == 2,
    'Release failed to flush the final value as one commit')
at(0.7, true)
at(0.6, true)
menu.visible = false
at(0.6, false)
assert(math.abs(runtime - 0.3) < 1e-9 and changes == 2 and finishes == 3,
    'Closing the menu failed to restore the drag starting value')
print('PASS live numeric preview: bounded changed-value work, exact endpoint commit and close rollback')
