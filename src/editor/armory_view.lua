-- Saved, named full-LUT palettes. Selecting previews; applying is explicit.
local ffi = require('ffi')
local A = {}
local categories = { 'armor', 'helmet', 'cape', 'pattern' }
local titles = { armor = 'Armor', helmet = 'Helmet', cape = 'Cape', pattern = 'Patterns', weapon = 'Weapons' }
local weapon_titles = { 'Primary', 'Secondary', 'Support' }
local function preview_entries(outfit, visit)
    if outfit.entries and #outfit.entries > 0 then
        for index, entry in ipairs(outfit.entries) do
            visit(
                entry.kind,
                entry.document,
                entry.original and entry.original.resource or entry.document.resource,
                index,
                entry
            )
        end
    else
        for _, kind in ipairs({ 'armor', 'helmet', 'cape' }) do
            for index, document in ipairs(outfit[kind] or {}) do
                visit(kind, document, document.resource, index)
            end
        end
    end
end
local function preview_categories(outfit)
    local present, weapon = {}, false
    for _, entry in ipairs(outfit and outfit.entries or {}) do
        if entry.kind == 'weapon' then
            present.weapon, weapon = true, true
        else
            present[entry.document.width == 3 and entry.document.height == 1 and 'pattern' or entry.kind] = true
        end
    end
    if not weapon then
        return categories
    end
    local result = {}
    for _, category in ipairs({ 'armor', 'helmet', 'cape', 'pattern', 'weapon' }) do
        if present[category] then
            result[#result + 1] = category
        end
    end
    return result
end
local function same_input(old, kind, document, resource, entry)
    return old
        and old.kind == kind
        and old.document == document
        and old.data == document.data
        and old.width == document.width
        and old.height == document.height
        and old.revision == document.revision
        and old.resource == resource
        and old.source == document.source
        and old.weapon_slot == (entry and entry.weapon_slot)
        and old.weapon_resource == (entry and entry.weapon_resource)
        and old.key == (entry and entry.key)
end
local function update_preview(self, outfit)
    local inputs = self.preview_inputs or {}
    local count, changed = 0, self.preview_outfit ~= outfit
    preview_entries(outfit, function(kind, document, resource, _, entry)
        count = count + 1
        changed = changed or not same_input(inputs[count], kind, document, resource, entry)
    end)
    if not changed and count == #inputs then
        return
    end
    local plan, fingerprints, snapshots = {}, {}, {}
    for _, category in ipairs(preview_categories(outfit)) do
        plan[category] = { items = {}, lookup = {}, bindings = 0 }
    end
    preview_entries(outfit, function(kind, document, resource, index, entry)
        snapshots[#snapshots + 1] = {
            kind = kind,
            document = document,
            data = document.data,
            width = document.width,
            height = document.height,
            revision = document.revision,
            resource = resource,
            source = document.source,
            weapon_slot = entry and entry.weapon_slot,
            weapon_resource = entry and entry.weapon_resource,
            key = entry and entry.key,
        }
        local pattern = document.width == 3 and document.height == 1
        local category = kind == 'weapon' and 'weapon' or pattern and 'pattern' or kind
        local lane = plan[category]
        if not lane then
            return
        end
        local bytes = fingerprints[document]
        if not bytes then
            local previous = self.preview_fingerprints and self.preview_fingerprints[document]
            if
                previous
                and previous.data == document.data
                and previous.width == document.width
                and previous.height == document.height
                and previous.revision == document.revision
            then
                bytes = previous
            else
                bytes = {
                    data = document.data,
                    width = document.width,
                    height = document.height,
                    revision = document.revision,
                    pixels = ffi.string(document.data, document.width * document.height * 16),
                }
                self.preview_fingerprint_reads = (self.preview_fingerprint_reads or 0) + 1
            end
            fingerprints[document] = bytes
        end
        local key = kind .. ':' .. document.width .. ':' .. document.height .. ':' .. bytes.pixels
        if kind == 'weapon' then
            key = key
                .. ':'
                .. tostring(entry and entry.weapon_slot or index)
                .. ':'
                .. tostring(entry and entry.weapon_resource or index)
        end
        local item = lane.lookup[key]
        if not item then
            item = {
                kind = kind,
                document = document,
                index = #lane.items + 1,
                count = 0,
                resources = {},
                resource_set = {},
                weapon_slot = entry and entry.weapon_slot,
                weapon_resource = entry and entry.weapon_resource,
            }
            lane.items[#lane.items + 1], lane.lookup[key] = item, item
        end
        item.count, lane.bindings = item.count + 1, lane.bindings + 1
        if resource and not item.resource_set[resource] then
            item.resource_set[resource] = true
            item.resources[#item.resources + 1] = resource
        end
    end)
    for _, lane in pairs(plan) do
        lane.lookup = nil
    end
    self.preview_outfit, self.preview_inputs, self.preview_fingerprints = outfit, snapshots, fingerprints
    self.preview_plan = plan
    self.preview_rebuilds = (self.preview_rebuilds or 0) + 1
end
function A.new(info, preview)
    local self = { scroll = 0, sidebar_scroll = 0, lane_scroll = {} }
    function self.wheel(x, y, delta)
        local side = self.sidebar_bounds
        if side and x >= side.x and x <= side.x + side.w and y >= side.y and y <= side.y + side.h then
            self.sidebar_scroll =
                math.max(0, math.min(self.sidebar_maximum or 0, self.sidebar_scroll - delta / 120 * 48))
            return true
        end
        for category, lane in pairs(self.preview_lanes or {}) do
            local b = lane.viewport
            if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
                self.lane_scroll[category] =
                    math.max(0, math.min(lane.maximum, (self.lane_scroll[category] or 0) - delta / 120 * 36))
                return true
            end
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
        local bh = ui.control_height and ui.control_height(14, 6, 28)
            or math.max(28, (ui.text_size and ui.text_size(14) or 14) + 12)
        local line = (ui.text_size and ui.text_size(12, 'hint') or 12) + 6
        local heading_font = ui.text_size and ui.text_size(18, 'heading') or 18
        local heading = heading_font + 16
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
                ui.bounded(ui.x + 12, y + 5, text, 12, muted, left - 24, 'hint')
            end
        end
        local function separator()
            local y, visible = position(12)
            if visible then
                ui.rect(ui.x + 12, y + 4, left - 24, 1, theme.line, nil, 'control_accent')
            end
        end
        ui.bounded(ui.x + 12, top - heading + 8, 'The Armory - saved palettes', 18, white, left - 24, 'heading')
        button('Search: ' .. (state.armory_query or 'all presets'), 'armory_search')
        choice('armory_sort')
        choice('outfit_preset')
        label('Saved outfit swatches: Armor / Cape | Helmet')
        button('Save Current Gear Preset', 'save_setup')
        local outfit = state.raw and state.raw.outfit
        local armor_count = outfit and #(outfit.armor or {}) or 0
        local cape_count = outfit and #(outfit.cape or {}) or 0
        local weapon_count = outfit and #(outfit.weapon or {}) or 0
        local targets = state.armory_targets or {}
        local available = {
            armor = armor_count > 0,
            helmet = outfit ~= nil and #(outfit.helmet or {}) > 0,
            cape = outfit ~= nil and state.armory_cape_available == true,
            weapon = weapon_count > 0,
        }
        local any = false
        local y, visible = position()
        local font = ui.text_size and ui.text_size(14) or 14
        local padding = ui.spacing and ui.spacing(8) or 8
        local apply_width = math.max(
            90,
            math.ceil(
                (ui.text_width and ui.text_width('Apply Preset', 14) or #'Apply Preset' * font * 0.62) + padding * 2
            )
        )
        local options = { { 'armor', 'Armor' }, { 'helmet', 'Helmet' }, { 'cape', 'Cape' } }
        if weapon_count > 0 then
            options[#options + 1] = { 'weapon', 'Weapons' }
        end
        local label_width = 0
        for _, option in ipairs(options) do
            label_width =
                math.max(label_width, ui.text_width and ui.text_width(option[2], 14) or #option[2] * font * 0.62)
        end
        local target_minimum = label_width + 38
        local target_columns = math.max(1, math.min(3, math.floor((left - 24) / target_minimum)))
        local inline_apply = #options == 3 and target_columns == 3 and left - 24 >= target_minimum * 3 + apply_width + 8
        local target_width = (left - 24 - (inline_apply and apply_width + 8 or 0)) / target_columns
        for i, option in ipairs(options) do
            if i > 1 and (i - 1) % target_columns == 0 then
                y, visible = position()
            end
            local kind, label = option[1], option[2]
            local enabled = available[kind]
            local checked = enabled
                and (kind == 'weapon' and targets[kind] == true or kind ~= 'weapon' and targets[kind] ~= false)
            any = any or checked
            if visible then
                local x = ui.x + 12 + ((i - 1) % target_columns) * target_width
                ui.checkbox(x, y, 28, bh, checked, enabled)
                ui.bounded(
                    x + 34,
                    ui.text_y and ui.text_y(y, bh, 14, label) or y + 8,
                    label,
                    14,
                    enabled and white or muted,
                    math.max(0, target_width - 38)
                )
                ui.hit(x, y, target_width, bh, function()
                    if enabled then
                        ui.activate('outfit_target_' .. kind)
                    end
                end, nil, nil, 'Include ' .. label .. ' when applying this preset.')
            end
        end
        if inline_apply then
            if visible then
                ui.button(ui.x + 12 + target_width * 3 + 8, y, apply_width, bh, 'Apply Preset', function()
                    ui.activate('outfit_apply_selected')
                end, { enabled = any })
            end
        else
            button('Apply Preset', 'outfit_apply_selected', any)
        end
        separator()
        button('Rename Preset', 'outfit_rename', outfit ~= nil)
        button('Delete Preset', 'outfit_delete', outfit ~= nil)
        if outfit then
            local scopes = {}
            for _, entry in ipairs({
                { 'Armor', armor_count },
                { 'Cape', cape_count },
                { 'Helmet', #(outfit.helmet or {}) },
                { 'Weapons', weapon_count },
            }) do
                if entry[2] > 0 then
                    scopes[#scopes + 1] = entry[1]
                end
            end
            label(
                (#scopes == 0 and 'Empty preset' or table.concat(scopes, ' + ') .. (#scopes == 1 and ' Only' or ''))
                    .. ' / '
                    .. (armor_count + cape_count + #(outfit.helmet or {}) + weapon_count)
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
            ui.bounded(ui.x + 12, ui.y + line + 8, 'Scroll for more Armory controls', 12, muted, left - 24, 'hint')
        end
        ui.bounded(ui.x + 12, ui.y + 8, state.status or '', 12, muted, left - 24, 'hint')
        ui.rect(x - 10, ui.y, 1, ui.h, theme.line, nil, 'control_accent')
        ui.bounded(x, top - heading + 8, 'Palette Preview', 18, white, width, 'heading')
        local area_top, area_bottom = top - heading - 14, ui.y + 8
        local lane_gap = 12
        local active_categories = preview_categories(outfit)
        local columns = math.min(#active_categories, width >= 744 and (#active_categories == 4 and 4 or 3) or 2)
        local lane_rows = math.ceil(#active_categories / columns)
        local lane_width = (width - lane_gap * (columns - 1)) / columns
        local lane_height = (area_top - area_bottom - lane_gap * (lane_rows - 1)) / lane_rows
        local heading_h = ui.control_height and ui.control_height(14, 2, 20, 'heading') or heading_font + 4
        local hint_h = ui.control_height and ui.control_height(12, 1, 16, 'hint') or line
        local lane_header = heading_h + hint_h + 8
        self.bounds = { x = x, y = area_bottom, w = width, h = area_top - area_bottom }
        self.preview_lanes = {}
        if outfit then
            update_preview(self, outfit)
        else
            self.preview_outfit, self.preview_inputs, self.preview_fingerprints, self.preview_plan = nil, nil, nil, nil
        end
        for position, category in ipairs(active_categories) do
            local col, row = (position - 1) % columns, math.floor((position - 1) / columns)
            local lx = x + col * (lane_width + lane_gap)
            local ly = area_top - (row + 1) * lane_height - row * lane_gap
            local lane = outfit and self.preview_plan[category] or { items = {}, bindings = 0 }
            local body =
                { x = lx + 5, y = ly + 5, w = lane_width - 10, h = math.max(1, lane_height - lane_header - 10) }
            local body_top = body.y + body.h
            ui.rect(lx, ly, lane_width, lane_height, theme.panel)
            local cards, content = {}, 0
            for _, item in ipairs(lane.items) do
                local doc = item.document
                local pattern = doc.width == 3 and doc.height == 1
                local selected_columns = pattern and { 1, 2, 3 } or { 1, 3, 6, 7, 13, 15, 17, 18, 19, 20 }
                local compact_labels = pattern and { 'C', 'M/O', 'R' }
                    or { 'B', 'D', 'In', 'Out', 'Cv', 'T', '1', '2', '3', '4' }
                local valid_columns, column_labels = {}, {}
                for index, column in ipairs(selected_columns) do
                    if column <= doc.width then
                        valid_columns[#valid_columns + 1] = column
                        column_labels[#column_labels + 1] = compact_labels[index]
                    end
                end
                local cell = math.min(18, math.max(4, (body.w - 26) / math.max(1, #valid_columns)))
                local sample_count = math.min(8, doc.height)
                local samples = {}
                for index = 1, sample_count do
                    samples[index] = doc.height <= 8 and index
                        or math.floor(1 + (index - 1) * (doc.height - 1) / 7 + 0.5)
                end
                local caption_h = heading_h
                    + hint_h
                    + (item.resources[1] and hint_h or 0)
                    + (item.weapon_resource and hint_h or 0)
                local row_pitch = math.max(cell, hint_h + 2)
                local card_h = caption_h + hint_h + sample_count * row_pitch + (doc.height > 8 and hint_h or 0) + 12
                cards[#cards + 1] = {
                    item = item,
                    depth = content,
                    h = card_h,
                    cell = cell,
                    samples = samples,
                    columns = valid_columns,
                    labels = column_labels,
                    caption = caption_h,
                    row_pitch = row_pitch,
                }
                content = content + card_h
            end
            local maximum = math.max(0, content - body.h)
            local scroll = math.max(0, math.min(self.lane_scroll[category] or 0, maximum))
            self.lane_scroll[category] = scroll
            self.preview_lanes[category] = {
                viewport = body,
                bounds = { x = lx, y = ly, w = lane_width, h = lane_height },
                maximum = maximum,
                scroll = scroll,
                items = lane.items,
                bindings = lane.bindings,
                cards = cards,
            }
            local function draw_cards()
                if #cards == 0 then
                    ui.bounded(
                        body.x + 4,
                        body_top - hint_h - 4,
                        outfit and 'No saved LUTs' or 'Choose a saved preset',
                        12,
                        muted,
                        body.w - 8,
                        'hint'
                    )
                end
                for _, card in ipairs(cards) do
                    local item, doc = card.item, card.item.document
                    local cy = body_top + scroll - card.depth
                    if cy > body.y and cy - card.h < body_top then
                        local name = (
                            item.kind == 'weapon' and (weapon_titles[item.weapon_slot] or 'Weapon') or titles[item.kind]
                        )
                            .. (doc.width == 3 and doc.height == 1 and ' Pattern LUT ' or ' LUT ')
                            .. item.index
                        ui.bounded(
                            body.x + 3,
                            ui.text_y and ui.text_y(cy - heading_h, heading_h, 14, name, 'heading') or cy - heading_h,
                            name,
                            14,
                            white,
                            body.w - 6,
                            'heading'
                        )
                        cy = cy - heading_h
                        ui.bounded(
                            body.x + 3,
                            cy - hint_h + 2,
                            'x' .. item.count .. ' bindings',
                            12,
                            muted,
                            body.w - 6,
                            'hint'
                        )
                        cy = cy - hint_h
                        if item.weapon_resource then
                            ui.bounded(
                                body.x + 3,
                                cy - hint_h + 2,
                                'Weapon [' .. item.weapon_resource .. ']',
                                12,
                                muted,
                                body.w - 6,
                                'hint'
                            )
                            cy = cy - hint_h
                        end
                        if item.resources[1] then
                            local source = '['
                                .. item.resources[1]
                                .. ']'
                                .. (#item.resources > 1 and (' +' .. (#item.resources - 1) .. ' sources') or '')
                            ui.bounded(body.x + 3, cy - hint_h + 2, source, 12, muted, body.w - 6, 'hint')
                            cy = cy - hint_h
                        end
                        for index, label in ipairs(card.labels) do
                            ui.bounded(
                                body.x + 26 + (index - 1) * card.cell,
                                cy - hint_h + 2,
                                label,
                                12,
                                muted,
                                card.cell - 1,
                                'hint'
                            )
                        end
                        cy = cy - hint_h
                        for displayed, actual in ipairs(card.samples) do
                            local row_y = cy - displayed * card.row_pitch
                            local py = row_y + (card.row_pitch - card.cell) / 2
                            ui.bounded(
                                body.x + 2,
                                ui.text_y and ui.text_y(row_y, card.row_pitch, 12, tostring(actual), 'hint')
                                    or row_y + 2,
                                tostring(actual),
                                12,
                                muted,
                                22,
                                'hint'
                            )
                            for index, column in ipairs(card.columns) do
                                local at = ((actual - 1) * doc.width + column - 1) * 4
                                local color = {}
                                for channel = 0, 2 do
                                    color[channel + 1] = math.floor(
                                        math.max(
                                            0,
                                            math.min(
                                                1,
                                                doc.data[at + (doc.width == 3 and doc.height == 1 and column == 3 and 3 or channel)]
                                            )
                                        )
                                                * 255
                                            + 0.5
                                    )
                                end
                                ui.rect(
                                    body.x + 26 + (index - 1) * card.cell,
                                    py,
                                    card.cell - 1,
                                    card.cell - 1,
                                    color,
                                    nil,
                                    'swatch_fill'
                                )
                            end
                        end
                        cy = cy - #card.samples * card.row_pitch
                        if doc.height > 8 then
                            ui.bounded(
                                body.x + 3,
                                cy - hint_h + 2,
                                'Rows 1-' .. doc.height .. ' / 8 sampled',
                                12,
                                muted,
                                body.w - 6,
                                'hint'
                            )
                        end
                    end
                end
            end
            if ui.viewport then
                ui.viewport(body, draw_cards, { top = ly + lane_height, bottom = ly, color = theme.panel })
            else
                draw_cards()
            end
            local finish = ui.surface and ui.surface(130)
            ui.bounded(
                lx + 6,
                ui.text_y and ui.text_y(ly + lane_height - heading_h - 4, heading_h, 14, titles[category], 'heading')
                    or ly + lane_height - heading_h,
                titles[category],
                14,
                white,
                lane_width - 12,
                'heading'
            )
            ui.bounded(
                lx + 6,
                ly + lane_height - lane_header + 4,
                #lane.items .. ' unique / ' .. lane.bindings .. ' bindings',
                12,
                muted,
                lane_width - 12,
                'hint'
            )
            if ui.scrollbar then
                ui.scrollbar(
                    'armory_' .. category,
                    lx + lane_width - 5,
                    body.y,
                    body.h,
                    content,
                    body.h,
                    scroll,
                    function(value)
                        self.lane_scroll[category] = value >= maximum - 1 and maximum or value
                    end
                )
            end
            if finish then
                finish()
            end
        end
    end
    return self
end
return A
