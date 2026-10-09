-- Primary RGB only. No shader, alpha or raw-column controls.
local B = {}
function B.new(info, select_row, help)
    help = help or {}
    local self = { scroll = 0, action_scroll = 0 }
    function self.wheel(x, y, delta)
        local actions = self.action_bounds
        if
            actions
            and x >= actions.x
            and x <= actions.x + actions.w
            and y >= actions.y
            and y <= actions.y + actions.h
        then
            self.action_scroll = math.max(0, math.min(self.action_maximum or 0, self.action_scroll - delta / 120 * 36))
            return true
        end
        local b = self.bounds
        if b and x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
            self.scroll = math.max(0, math.min(self.maximum or 0, self.scroll - delta / 120 * 36))
            return true
        end
    end
    function self.draw(ui)
        local state = info()
        local d = state.editor
        local top = ui.y + ui.h
        local left = ui.w * 0.54
        local right = ui.x + left + 18
        local width = ui.w - left - 18
        local white, muted, blue = { 225, 230, 235 }, { 155, 166, 175 }, { 35, 62, 90 }
        local divider = { 65, 76, 85 }
        ui.rect(ui.x + left / 2, ui.y + 48, 1, math.max(0, ui.h - 148), divider)
        ui.rect(right - 9, ui.y, 1, ui.h, divider)
        local function text(x, y, t)
            ui.bounded(x, y, t, 14, white, ui.w - (x - ui.x) - 10)
        end
        local guidance = help.basic or {}
        local function button(x, y, w, label, id, enabled, drawing)
            local ui = drawing or ui
            local featured = enabled ~= false and (id == 'export_selected' or id == 'save_dds' or id == 'save_setup')
            ui.rect(x, y, w, 28, enabled == false and { 35, 39, 43 } or (featured and { 244, 202, 53 } or blue))
            ui.bounded(x + 8, y + 8, label, 14, featured and { 25, 28, 31 } or white, w - 16)
            ui.hit(x, y, w, 28, function()
                if enabled ~= false then
                    ui.activate(id)
                end
            end, nil, nil, guidance[id])
        end
        text(ui.x + 10, top - 20, 'Basic - primary colors only')
        text(ui.x + 10, top - 44, 'Click a color region to edit. Importing a file is optional.')
        local panels = state.raw and state.raw.basic
        if panels and ((panels.armor and panels.armor.document) or (panels.helmet and panels.helmet.document)) then
            button(ui.x + 10, top - 85, left - 20, 'Load Current Armor & Helmet', 'populate_worn')
        else
            ui.bounded(ui.x + 10, top - 75, 'Loading current colors...', 12, muted, left - 20)
        end
        local cliptop, clipbottom = top - 142, ui.y + (state.loaded and 102 or 56)
        local y = cliptop + self.scroll
        self.bounds = { x = ui.x, y = clipbottom, w = left, h = cliptop - clipbottom }
        local rows = 0
        local half = (left - 26) / 2
        for n, kind in ipairs({ 'armor', 'helmet' }) do
            local x = ui.x + 10 + (n - 1) * (half + 6)
            local panel = state.raw and state.raw.basic and state.raw.basic[kind]
            local document = panel and panel.document
            ui.bounded(x, top - 110, kind == 'armor' and 'Armor' or 'Helmet', 14, white, half)
            if panel and panel.resource then
                ui.bounded(x + 65, top - 110, 'ID: ' .. panel.resource, 12, muted, half - 65)
            end
            ui.choice('basic_' .. kind .. '_lut', x, top - 142, half)
            local cursor = top - 153 + self.scroll
            if document then
                rows = math.max(rows, document.height)
                for row = 1, document.height do
                    cursor = cursor - 29
                    if cursor >= clipbottom and cursor + 28 <= cliptop then
                        local at = (row - 1) * document.width * 4
                        local rgb = {}
                        for ch = 0, 2 do
                            rgb[#rgb + 1] = math.floor(math.max(0, math.min(1, document.data[at + ch])) * 255 + 0.5)
                        end
                        local pulse = 0.5 + 0.5 * math.sin((state.time or 0) * 3)
                        ui.bounded(
                            x + 3,
                            cursor + 9,
                            'Region ' .. row,
                            12,
                            { math.floor(175 + 69 * pulse), math.floor(180 + 22 * pulse), math.floor(140 - 87 * pulse) },
                            75
                        )
                        ui.rect(x + 80, cursor + 2, half - 83, 26, rgb)
                        local selected = row
                        local target = kind
                        ui.hit(x, cursor, 78, 28, function()
                            if select_row(selected, target) ~= false then
                                ui.activate('identify_region')
                            end
                        end, nil, nil, 'Flash this region on your character to find which part it colors.')
                        ui.hit(x + 80, cursor, half - 80, 28, function()
                            if select_row(selected, target) ~= false then
                                ui.activate('cell_color')
                            end
                        end, nil, nil, 'Edit this region color. Your changes apply to this gear table automatically.')
                    end
                end
            else
                ui.bounded(
                    x,
                    top - 181,
                    panel and panel.unavailable and 'Original LUT unavailable.' or 'Reading colors...',
                    12,
                    muted,
                    half
                )
                ui.bounded(x, top - 201, 'Try another LUT # or Load Current Colors.', 12, muted, half)
            end
            if state.loaded then
                ui.bounded(x, ui.y + 80, 'Single LUT Import', 12, white, half)
                local filename = state.loaded and (state.loaded.source or ''):gsub('\\', '/'):match('[^/]+$') or 'DDS'
                local number = panel and panel.label and panel.label:match('LUT (%d+)')
                -- The per-target selection is exposed separately from the imported source.
                number = number or (kind == 'armor' and state.armor_lut or state.helmet_lut) or 1
                button(
                    x,
                    ui.y + 48,
                    half,
                    'Import '
                        .. filename
                        .. ' into LUT '
                        .. number
                        .. ' '
                        .. (panel and panel.resource or '[unavailable]'),
                    'apply_import_' .. kind,
                    state.loaded ~= nil and panel ~= nil and panel.group ~= nil and not state.busy
                )
            end
            if kind == 'armor' then
                button(x, ui.y + 10, (half - 6) * 0.43, 'Copy Helmet', 'basic_copy_helmet')
                button(
                    x + (half - 6) * 0.43 + 6,
                    ui.y + 10,
                    (half - 6) * 0.57,
                    'Copy Helmet to All',
                    'basic_copy_helmet_all'
                )
            else
                button(x, ui.y + 10, half, 'Copy Armor', 'basic_copy_armor')
            end
        end
        y = cliptop + self.scroll - rows * 29 - 11
        self.maximum = math.max(0, cliptop + self.scroll - y - (cliptop - clipbottom))
        self.scroll = math.min(self.scroll, self.maximum)
        button(right + width - 150, ui.y - 24, 150, 'Stop Highlight', 'stop_identify')
        local portrait = package.loaded['epic.player_preview.v1']
        if portrait and portrait.toggle then
            ui.rect(right, ui.y - 24, 150, 28, blue)
            ui.bounded(right + 8, ui.y - 16, 'Player Preview', 14, white, 134)
            ui.hit(right, ui.y - 24, 150, 28, portrait.toggle)
        end
        -- Keep the action pane reachable at Basic's compact window height.
        local clip_top, clip_bottom = top - 30, ui.y + 12
        local viewport = clip_top - clip_bottom
        self.action_bounds = { x = right, y = clip_bottom, w = width + 8, h = viewport }
        self.action_maximum = math.max(0, (state.loaded and 601 or 491) - ui.h + 12)
        self.action_scroll = math.min(self.action_scroll, self.action_maximum)
        local base_ui, offset = ui, self.action_scroll
        local function visible(y, height)
            return y >= clip_bottom and y + height <= clip_top
        end
        local actions = setmetatable({}, { __index = ui })
        actions.rect = function(x, y, w, height, color, alpha)
            y = y + offset
            local bottom, upper = math.max(clip_bottom, y), math.min(clip_top, y + height)
            if upper > bottom then
                base_ui.rect(x, bottom, w, upper - bottom, color, alpha)
            end
        end
        for _, name in ipairs({ 'text', 'bounded' }) do
            actions[name] = function(x, y, value, size, color, w)
                y = y + offset
                local height = base_ui.text_size and base_ui.text_size(size) or size
                if visible(y, height) then
                    base_ui[name](x, y, value, size, color, w)
                end
            end
        end
        actions.hit = function(x, y, w, height, ...)
            y = y + offset
            if visible(y, height) then
                base_ui.hit(x, y, w, height, ...)
            end
        end
        actions.choice = function(id, x, y, w)
            y = y + offset
            if visible(y, 26) then
                base_ui.choice(id, x, y, w)
            end
        end
        local draw_button = button
        do
            local ui = actions
            local function text(x, y, value)
                ui.bounded(x, y, value, 14, white, width)
            end
            local function button(x, y, w, label, id, enabled)
                draw_button(x, y, w, label, id, enabled, actions)
            end
            for _, position in ipairs(state.loaded and { 260, 393, 430 } or { 150, 283, 320 }) do
                ui.rect(right, top - position, width, 1, divider)
            end
            text(right, top - 48, 'Import a palette (optional)')
            button(right, top - 85, width, 'Import DDS / ZIP / RAR...', 'browse')
            if state.busy then
                ui.bounded(
                    right,
                    top - 115,
                    (state.import_detail or state.phase or 'Importing...')
                        .. (state.waiting and '' or ' / ' .. (state.progress or 0) .. '% completed'),
                    12,
                    muted,
                    width
                )
            else
                local plan = state.raw and state.raw.matching
                text(
                    right,
                    top - 115,
                    state.loaded
                            and plan
                            and ((plan.total or state.palette_count or 0) .. ' imported / ' .. plan.matched .. ' matched / ' .. math.max(
                                0,
                                (plan.total or state.palette_count or 0) - plan.matched
                            ) .. ' for manual assignment')
                        or 'Color changes apply live. Region label: identify.'
                )
            end
            if (state.palette_count or 0) > 1 then
                local plan = state.raw and state.raw.matching
                button(
                    right,
                    top - 150,
                    width,
                    'Apply Matching LUTs',
                    'apply_matching',
                    plan and plan.matched > 0 and not state.busy
                )
            end
            if state.loaded then
                local document = state.loaded
                local size = math.min(28, width / document.height)
                for row = 1, document.height do
                    local at = (row - 1) * document.width * 4
                    local color = {}
                    for ch = 0, 2 do
                        color[#color + 1] = math.floor(math.max(0, math.min(1, document.data[at + ch])) * 255 + 0.5)
                    end
                    ui.rect(right + (row - 1) * size, top - 177, size - 2, 14, color)
                end
            end
            if state.loaded then
                ui.choice('palette', right, top - 207, width)
                local source = state.loaded ~= nil and not state.busy
                local index = state.palette_index or 1
                button(
                    right,
                    top - 241,
                    (width - 6) / 2,
                    'Apply LUT ' .. index .. ' to All Armor',
                    'apply_file_armor',
                    source
                )
                button(
                    right + (width + 6) / 2,
                    top - 241,
                    (width - 6) / 2,
                    'Apply LUT ' .. index .. ' to All Helmet',
                    'apply_file_helmet',
                    source
                )
            end
            local saved_top = top + (state.loaded and 0 or 110)
            text(right, saved_top - 274, 'Armory Presets')
            ui.choice('outfit_preset', right, saved_top - 307, width)
            button(
                right,
                saved_top - 341,
                (width - 6) / 2,
                'Apply Preset Armor',
                'outfit_apply_armor',
                state.raw and state.raw.outfit and #state.raw.outfit.armor > 0
            )
            button(
                right + (width + 6) / 2,
                saved_top - 341,
                (width - 6) / 2,
                'Apply Preset Helmet',
                'outfit_apply_helmet',
                state.raw and state.raw.outfit and #state.raw.outfit.helmet > 0
            )
            button(right, saved_top - 375, width, 'Save to Armory', 'save_setup')
            button(right, saved_top - 409, (width - 6) / 2, 'Undo', 'undo')
            button(right + (width + 6) / 2, saved_top - 409, (width - 6) / 2, 'Redo', 'redo')
            if state.loaded then
                button(right, saved_top - 443, (width - 6) / 2, 'Restore Imported', 'restore_imported')
                button(
                    right + (width + 6) / 2,
                    saved_top - 443,
                    (width - 6) / 2,
                    'Restore Arrowhead LUT (Original)',
                    'restore'
                )
            else
                button(right, saved_top - 443, width, 'Restore Arrowhead LUT (Original)', 'restore')
            end
            ui.bounded(right, saved_top - 466, state.status or '', 13, muted, width)
            ui.rect(right, saved_top - 471, width, 1, { 65, 76, 85 })
            text(right, saved_top - 495, 'Export')
            button(
                right,
                saved_top - 533,
                width,
                'Name: ' .. (ui.input_value and ui.input_value('save_name') or state.export_name or 'Epic-LUT-edited'),
                'save_name'
            )
            button(
                right,
                saved_top - 567,
                width * 0.35 - 3,
                'Export...',
                'export_selected',
                state.editor ~= nil and not state.busy
            )
            ui.choice('export_format', right + width * 0.35 + 3, saved_top - 567, width * 0.65 - 3)
            button(right, saved_top - 601, width, 'Open Export Location', 'open_export')
        end
        if self.action_maximum > 0 then
            local thumb = math.max(24, viewport * viewport / (viewport + self.action_maximum))
            ui.rect(right + width + 3, clip_bottom, 4, viewport, divider)
            ui.rect(
                right + width + 2,
                clip_top - thumb - (viewport - thumb) * self.action_scroll / self.action_maximum,
                6,
                thumb,
                muted
            )
        end
        if state.dirty then
            text(right, ui.y + 20, 'Modified - save or export to keep your colors.')
        end
    end
    return self
end
return B
