-- Production composer: reclaim the lower custom workspace while preserving
-- native notice ink clearance, authored top edges and real footer hit targets.
local Core, Menu = dofile('vendor/menu/core.lua'), dofile('vendor/menu/menu.lua')
local api = Core.new({
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
})
local handle = api.register({
    id = 'custom_space',
    name = 'Custom workspace',
    pages = {
        { id = 'colors', name = 'LUT Editor', controls = {} },
    },
})
local mod = api.mods[handle.id]
mod.tabs_top = true
local workspace, clicks, metric_calls = nil, 0, {}
local function metrics(size, label)
    local low = -0.22 * size
    local high = (label == 'Workspace status saved' and 0.85 or 0.72) * size
    return { min_y = low, max_y = high, height = high - low }
end
mod.pages[1].render_layout = function(ui)
    workspace = { x = ui.x, y = ui.y, w = ui.w, h = ui.h, top = ui.y + ui.h }
    ui.rect(ui.x, ui.y, ui.w, ui.h, { 12, 210, 34 })
    ui.button(ui.x + 10, ui.y + 6, 220, 32, 'Footer action', function()
        clicks = clicks + 1
        return true
    end)
end
local menu = Menu.new(api, function(glyph, size)
    return #glyph * size * 0.5
end)
menu.visible, menu.compact_fonts = true, true
menu.window_width, menu.window_height = 1400, 960
menu.notice = 'Workspace status saved'
menu.text_metrics = function(size, label)
    metric_calls[#metric_calls + 1] = { size = size, label = label }
    return metrics(size, label)
end
local function compose()
    return menu.compose(3840, 2160)
end
local function text(commands, label)
    for i, c in ipairs(commands) do
        if (c.full_text or c.text) == label then
            return c, i
        end
    end
    error('Missing composed label ' .. label)
end
local function footer(commands)
    local label, index = text(commands, 'Footer action')
    for i = index - 1, 1, -1 do
        local c = commands[i]
        if
            c.type == 'rect'
            and c.ui_role == 'control_fill'
            and c.x <= label.x
            and c.x + c.w >= label.x
            and c.y <= label.y
            and c.y + c.h >= label.y
        then
            return c, label
        end
    end
    error('Missing footer control body')
end
local function tap(x, y)
    local function input(pressed)
        menu.tick({
            down = function(code)
                return pressed and code == 1
            end,
            mouse = function()
                return x, y
            end,
            wheel = function()
                return 0
            end,
        }, 0)
    end
    input(true)
    input(false)
end
local function close(a, b)
    return math.abs(a - b) < 0.001
end
for _, font in ipairs({ 12, 20 }) do
    for _, scale in ipairs({ 0.7, 1, 1.15 }) do
        menu.font_size, menu.ui_scale = font, scale
        menu.epic_typography = false
        local legacy_commands = compose()
        local legacy = { y = workspace.y, h = workspace.h, top = workspace.top }
        local legacy_footer = footer(legacy_commands)
        local bounds = menu.window_bounds
        local logical_height = bounds.h / bounds.scale
        assert(close(bounds.scale, 2 * scale), 'Fixture screen unexpectedly clamped its requested UI scale')
        assert(
            legacy.y == 110 and close(legacy.h, logical_height - 280) and close(legacy.top, logical_height - 170),
            'Legacy custom workspace changed'
        )
        menu.epic_typography = true
        local commands = compose()
        local body, label = footer(commands)
        local notice = text(commands, menu.notice)
        bounds = menu.window_bounds
        assert(
            workspace.y < legacy.y and workspace.h > legacy.h and close(workspace.top, legacy.top),
            'Epic workspace did not gain height while preserving its top'
        )
        local divider
        for _, c in ipairs(commands) do
            if c.type == 'rect' and c.c[1] == 110 and c.c[2] == 88 and c.c[3] == 35 then
                divider = c
            end
        end
        assert(divider and close((divider.y - bounds.y) / bounds.scale, 55), 'Fixed colored footer divider moved')
        local new_gap = body.y - divider.y
        local old_gap = legacy_footer.y - divider.y
        assert(new_gap > 0 and new_gap < old_gap, 'Authored footer did not move closer to the colored divider')
        local ink = metrics(notice.size, notice.text)
        assert(notice.y + ink.max_y < body.y, 'Native notice ink overlapped the reclaimed footer control')
        local footer_ink = metrics(label.size, label.text)
        assert(
            label.y + footer_ink.min_y >= body.y and label.y + footer_ink.max_y <= body.y + body.h,
            'Footer text escaped its measured control padding'
        )
        local before = clicks
        tap(body.x + body.w / 2, body.y + body.h / 2)
        assert(clicks == before + 1, 'Footer hit target remained at its old position after workspace expansion')
    end
end
local measured_notice = false
for _, call in ipairs(metric_calls) do
    measured_notice = measured_notice or call.label == menu.notice
end
assert(measured_notice, 'Composer ignored native notice bearings')
print(
    'PASS custom layout space: larger Epic workspace, lower clickable footer, measured notice clearance, unchanged top and legacy layout at 12/20 fonts and 70/100/115 scales'
)
