-- Saved, named full-LUT palettes. Selecting previews; applying is explicit.
local A = {}
function A.new(info, preview)
    local self = { scroll = 0 }
    function self.wheel(x, y, delta)
        local b = self.bounds
        if b and x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
            self.scroll = math.max(0, math.min(self.maximum or 0, self.scroll - delta / 120 * 48))
            return true
        end
    end
    function self.draw(ui)
        local state = info()
        local d = state.editor
        local top = ui.y + ui.h
        local white, muted, blue = { 225, 230, 235 }, { 155, 166, 175 }, { 35, 62, 90 }
        local left = ui.w * 0.37
        local x = ui.x + left + 20
        local width = ui.w - left - 20
        local function button(y, label, id, enabled)
            ui.rect(ui.x + 12, y, left - 24, 28, enabled == false and { 35, 39, 43 } or blue)
            ui.bounded(ui.x + 20, y + 7, label, 14, white, left - 40)
            ui.hit(ui.x + 12, y, left - 24, 28, function()
                if enabled ~= false then
                    ui.activate(id)
                end
            end)
        end
        ui.bounded(ui.x + 12, top - 22, 'The Armory - saved palettes', 18, white, left - 24)
        ui.choice('outfit_preset', ui.x + 12, top - 65, left - 24)
        ui.bounded(ui.x + 12, top - 91, 'Saved outfit swatches: Armor | Helmet', 12, muted, left - 24)
        button(top - 132, 'Save Current Gear Preset', 'save_setup')
        local outfit = state.raw and state.raw.outfit
        button(top - 178, 'Apply Preset Armor LUTs', 'outfit_apply_armor', outfit ~= nil and #outfit.armor > 0)
        button(top - 218, 'Apply Preset Helmet LUTs', 'outfit_apply_helmet', outfit ~= nil and #outfit.helmet > 0)
        ui.rect(ui.x + 12, top - 241, left - 24, 1, { 65, 76, 85 })
        button(top - 278, 'Rename Preset', 'outfit_rename', outfit ~= nil)
        button(top - 318, 'Delete Preset', 'outfit_delete', outfit ~= nil)
        if outfit then
            ui.bounded(
                ui.x + 12,
                top - 348,
                (#outfit.armor > 0 and (#outfit.helmet > 0 and 'Armor + Helmet' or 'Armor Only') or 'Helmet Only')
                    .. ' / '
                    .. (#outfit.armor + #outfit.helmet)
                    .. ' LUTs',
                12,
                muted,
                left - 24
            )
        end
        ui.bounded(ui.x + 12, ui.y + 20, state.status or '', 12, muted, left - 24)
        ui.rect(x - 10, ui.y, 1, ui.h, { 65, 76, 85 })
        ui.bounded(x, top - 22, 'Palette Preview', 18, white, width)
        if outfit then
            local columns = { 1, 3, 6, 7, 13, 15, 17, 18, 19, 20 }
            local labels = { 'Base', 'D1', 'In', 'Out', 'Curv', 'Tint', 'C1', 'C2', 'C3', 'C4' }
            local half = (width - 14) / 2
            local total = 0
            self.bounds = { x = x, y = ui.y, w = width, h = ui.h - 40 }
            for n, kind in ipairs({ 'armor', 'helmet' }) do
                local px = x + (n - 1) * (half + 14)
                local cursor = top - 80 + self.scroll
                ui.bounded(px, top - 58, kind == 'armor' and 'Armor' or 'Helmet', 14, white, half)
                local docs = outfit[kind] or {}
                local height = 0
                for index, doc in ipairs(docs) do
                    local cell = math.min(32, (half - 58) / 10)
                    local block = 48 + doc.height * cell
                    if cursor <= top - 80 and cursor >= ui.y + 16 then
                        ui.bounded(px, cursor, 'LUT ' .. index, 14, white, half)
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
                                ui.rect(px + 58 + (c - 1) * cell, y, cell - 2, cell - 2, rgb)
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
