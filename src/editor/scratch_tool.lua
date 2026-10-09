-- Independent brush palette. Closed Scratch does not query or compose controls.
local S = {}
function S.new(deps)
    local editor, document, core = deps.editor, deps.document, deps.ui_core
    local self, opened = {}, false
    local scratch_hue, scratch_colors
    function self.open()
        opened = true
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
        local h, d = editor.handle, document()
        local function draw(x, y, w, ht)
            local theme = ui.theme
            local white, muted = theme.white, theme.muted
            local bx, width, top = x + 14, w - 28, y + ht - 72
            local bh = math.max(28, (ui.text_size and ui.text_size(14) or 14) + 12)
            local function label(py, value, color)
                ui.bounded(bx, py, value, 14, color or white, width)
            end
            local function action(py, value, id, enabled)
                ui.button(bx, py, width, bh, value, function()
                    ui.activate(id)
                end, { enabled = enabled })
            end
            ui.rect(x, y, w, ht, theme.panel)
            ui.rect(x, y + ht - 40, w, 40, theme.header)
            label(y + ht - 26, 'Scratch Pixel')
            local hex_width, hex_y = (width - 12) / 2, top - 8
            ui.button(bx, hex_y, hex_width, bh, 'HEX: ' .. h.get('scratch_color'), function()
                ui.activate('scratch_color')
            end, { help = 'Edit HEX in the color picker. Ctrl+V pastes in its HEX field.' })
            local clip_width = (width - hex_width - 12) / 2
            ui.button(bx + hex_width + 6, hex_y, clip_width, bh, 'Copy HEX', function()
                ui.activate('scratch_copy')
            end)
            ui.button(bx + hex_width + clip_width + 12, hex_y, clip_width, bh, 'Paste HEX', function()
                ui.activate('scratch_paste')
            end)
            local color = editor.scratch or { 255, 255, 255 }
            local alpha = h.get('scratch_alpha')
            ui.rect(bx, top - 48, width, 30, color, nil, 'swatch_fill')
            ui.hit(bx, top - 48, width, 30, function()
                ui.activate('scratch_color')
            end)
            local gx, gy, gw = bx, y + 95, width - 47
            local gh = math.max(40, top - 60 - gy)
            local hue = core.rgb_hsv(color)
            if hue ~= scratch_hue then
                scratch_hue, scratch_colors = hue, {}
                for vy = 0, 19 do
                    for sx = 0, 19 do
                        scratch_colors[vy * 20 + sx + 1] = core.hsv_rgb(hue, sx / 19, vy / 19)
                    end
                end
            end
            for vy = 0, 19 do
                for sx = 0, 19 do
                    local rgb = scratch_colors[vy * 20 + sx + 1]
                    local px, py = gx + sx * gw / 20, gy + vy * gh / 20
                    ui.rect(px, py, gw / 20 + 1, gh / 20 + 1, rgb, nil, 'swatch_fill')
                    ui.hit(px, py, gw / 20, gh / 20, function()
                        assert(h.set('scratch_color', string.format('#%02X%02X%02X', rgb[1], rgb[2], rgb[3])))
                    end)
                end
            end
            for i = 0, 19 do
                local chosen, py = i / 20, gy + i * gh / 20
                ui.rect(gx + gw + 5, py, 12, gh / 20 + 1, core.hsv_rgb(chosen, 1, 1), nil, 'swatch_fill')
                ui.hit(gx + gw + 5, py, 12, gh / 20, function()
                    local rgb = core.hsv_rgb(chosen, 1, 1)
                    assert(h.set('scratch_color', string.format('#%02X%02X%02X', rgb[1], rgb[2], rgb[3])))
                end)
            end
            local ax = gx + gw + 25
            if ui.vertical then
                alpha = ui.vertical('scratch_alpha', ax, gy, 16, gh)
            end
            for row = 0, 19 do
                local opacity = row / 19
                for col = 0, 1 do
                    local background = (row + col) % 2 == 0 and 220 or 125
                    local rgba = {}
                    for channel = 1, 3 do
                        rgba[channel] = math.floor(background * (1 - opacity) + color[channel] * opacity + 0.5)
                    end
                    ui.rect(ax + col * 8, gy + row * gh / 20, 8, gh / 20 + 1, rgba, nil, 'swatch_fill')
                end
                if not ui.vertical then
                    local chosen = opacity
                    ui.hit(ax, gy + row * gh / 20, 16, gh / 20, function()
                        assert(h.set('scratch_alpha', chosen))
                    end)
                end
            end
            ui.rect(ax - 2, gy + alpha * gh - 2, 20, 4, { 15, 15, 15 }, nil, 'marker_border')
            ui.rect(ax - 2, gy + alpha * gh - 1, 20, 2, white, nil, 'marker_fill')
            label(y + 73, string.format('A: %.2f', alpha))
            action(y + 28, 'Paint selected RGB', 'paint_scratch', d ~= nil)
        end
        ui.floating('editor_scratch', draw, 420, 480, self.close, 40)
    end
    return self
end
return S
