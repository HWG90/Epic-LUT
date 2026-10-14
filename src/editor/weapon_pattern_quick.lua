-- Pattern controls beneath the shared weapon table. Drawing uses cached pixels;
-- clicks retain the exact companion material subset through the controller.
local Q = {}
function Q.new(controller)
    local self = {}
    local labels = { 'Color', 'Mat/Opac', 'Roughness' }
    local alternatives = { { 'Color', 'Clr' }, { 'Mat/Opac', 'Mat/Op', 'M/O' }, { 'Roughness', 'Rough', 'Rgh' } }
    local function metric(ui, size, text, role)
        return ui.text_metrics and ui.text_metrics(size, text, role)
            or { min_y = 0, height = ui.text_size and ui.text_size(size, role) or size }
    end
    local function width(ui, text)
        return ui.text_width and ui.text_width(text, 11, 'hint') or #text * 6.6
    end
    function self.is_open()
        return false
    end
    function self.workspace()
        return false
    end
    function self.show()
        local state = controller.state()
        return controller.open_pattern(state.pattern_target)
    end
    function self.quick_height(ui, cell)
        local gap = ui.spacing and ui.spacing(6) or 6
        return metric(ui, 13, 'Quick Editor: Pattern LUT', 'heading').height
            + metric(ui, 11, 'Roughness', 'hint').height
            + gap * 3
            + math.max(0, math.min(40, cell or 0))
    end
    function self.quick(ui, bounds)
        local state = controller.state()
        local document = state.pattern_document
        local enabled = state.pattern_ready and not state.busy
        local gap = ui.spacing and ui.spacing(6) or 6
        local heading = metric(ui, 13, 'Quick Editor: Pattern LUT', 'heading')
        local caption = metric(ui, 11, 'Roughness', 'hint')
        local available = math.max(1, (bounds.w - gap * 2) / 3)
        local cell = math.min(40, bounds.cell_width or bounds.row_height or 28, available)
        local height =
            math.max(1, math.min(40, bounds.row_height or cell, bounds.h - heading.height - caption.height - gap * 3))
        local lane = cell
        for _, label in ipairs(labels) do
            lane = math.max(lane, width(ui, label))
        end
        lane = math.min(lane, available)
        ui.bounded(
            bounds.x,
            bounds.y + bounds.h - heading.height - heading.min_y,
            'Quick Editor: Pattern LUT',
            13,
            ui.theme.text,
            bounds.w,
            'heading'
        )
        for column = 1, 3 do
            local label = labels[column]
            for _, candidate in ipairs(alternatives[column]) do
                label = candidate
                if width(ui, label) <= lane then
                    break
                end
            end
            local x, y = bounds.x + (column - 1) * (lane + gap), bounds.y + gap
            local ink = metric(ui, 11, label, 'hint')
            ui.bounded(x, y + height + gap - ink.min_y, label, 11, ui.theme.text, lane, 'hint')
            local color = { 64, 64, 64 }
            if enabled then
                for channel = 1, 3 do
                    local index = column == 3 and 11 or (column - 1) * 4 + channel - 1
                    color[channel] = math.floor(math.max(0, math.min(1, document.data[index])) * 255 + 0.5)
                end
            end
            ui.rect(x, y, cell, height, color, nil, 'swatch_fill')
            if enabled then
                local channel, target = column, state.pattern_target
                ui.hit(x, y, cell, height, function()
                    return controller.edit_pattern(channel, target)
                end, nil, nil, labels[column])
            end
        end
    end
    return self
end
return Q
