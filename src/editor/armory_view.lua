-- Saved, named full-LUT palettes. Selecting previews; applying is explicit.
local A = {}
function A.new(info, preview)
    local self = { scroll = 0, sidebar_scroll = 0 }
    function self.wheel(x, y, delta)
        local side = self.sidebar_bounds
        if side and x >= side.x and x <= side.x + side.w and y >= side.y and y <= side.y + side.h then
            self.sidebar_scroll =
                math.max(0, math.min(self.sidebar_maximum or 0, self.sidebar_scroll - delta / 120 * 48))
            return true
        end
        local b = self.bounds
        if b and x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
            self.scroll = math.max(0, math.min(self.maximum or 0, self.scroll - delta / 120 * 48))
            return true
        end
    end
    function self.draw(ui)
        local state = info()
        local top = ui.y + ui.h
        local theme = ui.theme
        local white, muted = theme.white, theme.muted
        local left = ui.w * 0.37
        local x = ui.x + left + 20
        local width = ui.w - left - 20
        local bh = math.max(28, (ui.text_size and ui.text_size(14) or 14) + 12)
        local line = (ui.text_size and ui.text_size(12) or 12) + 6
        local heading = (ui.text_size and ui.text_size(18) or 18) + 16
        local step, depth = bh + 8, 0
        local lower, upper = ui.y + line * 2 + 10, top - heading
        self.sidebar_bounds = { x = ui.x, y = lower, w = left, h = upper - lower }
        local function position(height)
            depth = depth + (height or step)
            local py = upper - depth + self.sidebar_scroll
            return py, py >= lower and py + (height or bh) <= upper
        end
        local function button(label, id, enabled)
            local y, visible = position()
            if not visible then
                return
            end
            local featured = enabled ~= false and (id == 'save_setup' or id == 'armory_export')
            ui.button(ui.x + 12, y, left - 24, bh, label, function()
                ui.activate(id)
            end, {
                enabled = enabled,
                accent = featured and { 244, 202, 53 },
                ink = featured and { 25, 28, 31 },
                field = id == 'armory_search' or id == 'armory_export_name',
            })
        end
        local function choice(id)
            local y, visible = position()
            if visible then
                ui.choice(id, ui.x + 12, y, left - 24)
            end
        end
        local function label(text)
            local y, visible = position(line + 8)
            if visible then
                ui.bounded(ui.x + 12, y + 5, text, 12, muted, left - 24)
            end
        end
        local function separator()
            local y, visible = position(12)
            if visible then
                ui.rect(ui.x + 12, y + 4, left - 24, 1, theme.line, nil, 'control_accent')
            end
        end
        ui.bounded(ui.x + 12, top - heading + 8, 'The Armory - saved palettes', 18, white, left - 24)
        button('Search: ' .. (state.armory_query or 'all presets'), 'armory_search')
        choice('armory_sort')
        choice('outfit_preset')
        label('Saved outfit swatches: Armor / Cape | Helmet')
        button('Save Current Gear Preset', 'save_setup')
        local outfit = state.raw and state.raw.outfit
        local armor_count = outfit and (#outfit.armor + #(outfit.cape or {})) or 0
        button('Apply Preset Armor LUTs', 'outfit_apply_armor', armor_count > 0)
        button('Apply Preset Helmet LUTs', 'outfit_apply_helmet', outfit ~= nil and #outfit.helmet > 0)
        separator()
        button('Rename Preset', 'outfit_rename', outfit ~= nil)
        button('Delete Preset', 'outfit_delete', outfit ~= nil)
        if outfit then
            label(
                (armor_count > 0 and (#outfit.helmet > 0 and 'Armor + Helmet' or 'Armor Only') or 'Helmet Only')
                    .. ' / '
                    .. (armor_count + #outfit.helmet)
                    .. ' LUTs'
            )
        end
        separator()
        label('Export selected saved preset')
        button(
            'Name: '
                .. (
                    (ui.input_value and ui.input_value('armory_export_name'))
                    or state.armory_export_name
                    or 'my-preset'
                ),
            'armory_export_name'
        )
        choice('armory_export_format')
        if state.armory_export_format == 2 or state.armory_export_format == 4 then
            choice('armory_export_lut')
        elseif state.armory_export_format == 5 then
            choice('armory_dds_naming')
        end
        button('Export Selected Preset...', 'armory_export', outfit ~= nil)
        button('Import Shared Preset...', 'armory_import')
        button('Open Export Location', 'open_export')
        self.sidebar_maximum = math.max(0, depth - (upper - lower))
        self.sidebar_scroll = math.min(self.sidebar_scroll, self.sidebar_maximum)
        if self.sidebar_maximum > 0 then
            ui.bounded(ui.x + 12, ui.y + line + 8, 'Scroll for more Armory controls', 12, muted, left - 24)
        end
        ui.bounded(ui.x + 12, ui.y + 8, state.status or '', 12, muted, left - 24)
        ui.rect(x - 10, ui.y, 1, ui.h, theme.line, nil, 'control_accent')
        ui.bounded(x, top - 22, 'Palette Preview', 18, white, width)
        if outfit then
            if
                self.outfit ~= outfit
                or self.armor ~= outfit.armor
                or self.cape ~= outfit.cape
                or self.helmet ~= outfit.helmet
            then
                self.outfit, self.armor, self.cape, self.helmet = outfit, outfit.armor, outfit.cape, outfit.helmet
                self.preview_columns = { {}, {} }
                for _, kind in ipairs({ 'armor', 'cape', 'helmet' }) do
                    local column = self.preview_columns[kind == 'helmet' and 2 or 1]
                    for index, doc in ipairs(outfit[kind] or {}) do
                        column[#column + 1] = { document = doc, index = index, kind = kind }
                    end
                end
            end
            local half = (width - 14) / 2
            local total = 0
            self.bounds = { x = x, y = ui.y, w = width, h = ui.h - 40 }
            for n, docs in ipairs(self.preview_columns) do
                local px = x + (n - 1) * (half + 14)
                local cursor = top - 80 + self.scroll
                ui.bounded(
                    px,
                    top - 58,
                    n == 1 and (#(outfit.cape or {}) > 0 and 'Armor / Cape' or 'Armor') or 'Helmet',
                    14,
                    white,
                    half
                )
                local height = 0
                for _, item in ipairs(docs) do
                    local doc = item.document
                    local pattern = doc.width == 3
                    local columns = pattern and { 1, 2, 3 } or { 1, 3, 6, 7, 13, 15, 17, 18, 19, 20 }
                    local labels = pattern and { 'Accent', 'Material', 'Unknown' }
                        or { 'Base', 'D1', 'In', 'Out', 'Curv', 'Tint', 'C1', 'C2', 'C3', 'C4' }
                    local cell = math.min(32, (half - 58) / #columns)
                    local block = 48 + doc.height * cell
                    if cursor <= top - 80 and cursor >= ui.y + 16 then
                        ui.bounded(
                            px,
                            cursor,
                            (item.kind == 'cape' and 'Cape ' or '')
                                .. (pattern and 'Pattern LUT ' or 'LUT ')
                                .. item.index,
                            14,
                            white,
                            half
                        )
                    end
                    for c, label in ipairs(labels) do
                        if cursor - 22 <= top - 80 and cursor - 22 >= ui.y + 16 then
                            ui.bounded(px + 58 + (c - 1) * cell, cursor - 22, label, 12, muted, cell - 2)
                        end
                    end
                    for row = 1, doc.height do
                        local y = cursor - 30 - row * cell
                        if y >= ui.y + 16 and y + cell <= top - 80 then
                            ui.bounded(px, y + cell * 0.3, 'Row ' .. row, 12, white, 54)
                            for c, column in ipairs(columns) do
                                local at = ((row - 1) * doc.width + column - 1) * 4
                                local rgb = {}
                                for ch = 0, 2 do
                                    rgb[#rgb + 1] = math.floor(math.max(0, math.min(1, doc.data[at + ch])) * 255 + 0.5)
                                end
                                ui.rect(px + 58 + (c - 1) * cell, y, cell - 2, cell - 2, rgb, nil, 'swatch_fill')
                            end
                        end
                    end
                    cursor = cursor - block
                    height = height + block
                end
                if #docs == 0 then
                    ui.bounded(px, top - 100, 'No LUT saved', 12, muted, half)
                end
                total = math.max(total, height)
            end
            self.maximum = math.max(0, total - (ui.h - 96))
            self.scroll = math.min(self.scroll, self.maximum)
            if self.maximum > 0 then
                ui.bounded(x, ui.y + 2, 'Scroll to preview more saved LUTs', 12, muted, width)
            end
            return
        end
        ui.bounded(x, top - 70, 'Choose a saved Armory preset to preview its LUTs.', 14, muted, width)
    end
    return self
end
return A
