-- Independent Cape material document and editor, using the existing pixel/value contracts.
local C = {}
local prefix = 'cape_'
function C.new(m, deps)
    local self = { open = false, active = false }
    local document, target, revision
    local editor = m.lut_editor.new(
        m,
        function()
            return document
        end,
        deps.note,
        function()
            return false
        end,
        deps.presets
    )
    editor.embedded, editor.tools, editor.scratch_tool = true, nil, nil
    self.editor = editor
    local pages, controls, registered = editor.pages(), {}, {}
    for _, page in ipairs(pages) do
        for _, control in ipairs(page.controls) do
            if control.id then
                local id = control.id
                control.id = prefix .. id
                control.tab_stop = false
                controls[id] = control
                registered[#registered + 1] = control
            end
        end
    end
    function self.controls()
        return registered
    end
    function self.attach(api, handle)
        local aliases = {}
        for id in pairs(controls) do
            aliases[id] = assert(api.mods[handle.id].controls[prefix .. id])
        end
        local scoped = { id = handle.id }
        for _, method in ipairs({ 'get', 'preview', 'set', 'activate' }) do
            local name = method
            scoped[name] = function(id, ...)
                return handle[name](prefix .. id, ...)
            end
        end
        scoped.set_many = function(values)
            local mapped = {}
            for id, value in pairs(values) do
                mapped[prefix .. id] = value
            end
            return handle.set_many(mapped)
        end
        local proxy = { mods = { [handle.id] = { controls = aliases, pages = pages } }, clipboard = api.clipboard }
        editor.attach(proxy, scoped)
        assert(scoped.set('value_editor_visible', false))
        self.handle = handle
        self.mod = api.mods[handle.id]
        for _, page in ipairs(self.mod.pages) do
            if page.id == 'colors' then
                self.page = page
            end
        end
    end
    function self.invalidate()
        document, target, revision = nil, nil, nil
        self.active = false
        editor.color_session = nil
        editor.sync()
    end
    function self.is_loaded()
        return document ~= nil
    end
    function self.load()
        local source, destination = deps.load()
        assert(
            source and source.width == 23,
            'Current Cape material colors are unavailable; retry after snapshots load'
        )
        document, target = m.basic_state.clone(source, 'Cape material'), destination
        revision = document.revision or 0
        self.open, self.active = true, true
        editor.sync()
        return deps.note('Cape material loaded into its own editor. Armor and Helmet edits stay in place.')
    end
    function self.apply()
        assert(document and target, 'Load current Cape material first')
        deps.apply(document, target)
        revision = document.revision or 0
        return deps.note('Applied Cape material colors.')
    end
    function self.restore()
        deps.restore()
        self.invalidate()
        return self.load()
    end
    function self.tick()
        if document and (document.revision or 0) ~= revision then
            revision = document.revision or 0
            local ok, why = pcall(deps.apply, document, target)
            if not ok then
                document.stale = true
                editor.sync()
                deps.note(tostring(why))
            end
        end
    end
    function self.key(code, ctrl, shift, context)
        if self.open and self.active and document then
            local scoped = {}
            for key, value in pairs(context or {}) do
                scoped[key] = value
            end
            scoped.control = self.scalar_focus and scoped.control and scoped.control:gsub('^cape_', '') or nil
            return editor.key(code, ctrl, shift, scoped)
        end
    end
    function self.wheel(x, y, delta)
        local b = self.viewport
        if self.open and b and x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
            if (self.scroll_max or 0) > 0 then
                self.scroll = math.max(0, math.min(self.scroll_max, (self.scroll or 0) - delta / 120 * 36))
                return true
            end
            return document and editor.wheel(x, y, delta) or true
        end
    end
    local function plan(ui)
        local scale = (ui.text_size and ui.text_size(14) or 12) / 12
        local bh = math.max(26, ui.control_height and ui.control_height(14, 5) or 0)
        local gap, rows, x = 6 * scale, 1, 12
        local items = {}
        local function item(id, label, width)
            width =
                math.min(ui.w - 24, width or (ui.text_width and ui.text_width(label, 14) or #label * 8) + 18 * scale)
            if x > 12 and x + width > ui.w - 12 then
                rows, x = rows + 1, 12
            end
            items[#items + 1] = { id = id, label = label, width = width, x = x, row = rows }
            x = x + width + gap
        end
        if self.open then
            item('basic_cape_lut', nil, math.min(240, ui.w * 0.30))
            item('editor_load_cape', 'Load Current Cape')
            item('editor_apply_cape', 'Apply Cape')
            item('editor_restore_cape', 'Restore Cape')
            item('cape_unlock', 'Advanced')
        end
        local height = bh + 8 * scale
        if self.open then
            height = math.min(ui.h * 0.50, math.max(300, 300 * scale))
        end
        if self.max_height then
            local minimum = bh + 8 * scale + (self.open and (26 + gap * 2) or 0)
            height = math.max(minimum, math.min(height, self.max_height))
        end
        return { height = height, bh = bh, gap = gap, rows = rows, items = items }
    end
    function self.height(ui, maximum)
        if maximum then
            self.max_height = maximum
        end
        return plan(ui).height
    end
    function self.draw(ui, y)
        if self.mod then
            for id in pairs(controls) do
                self.mod.controls[prefix .. id].tab_stop = false
            end
            if self.page then
                local keep = {}
                for _, c in ipairs(self.page.controls) do
                    if not c.id or c.id:sub(1, #prefix) ~= prefix then
                        keep[#keep + 1] = c
                    end
                end
                self.page.controls = keep
            end
        end
        local function visible_control(id)
            local c = self.mod and self.mod.controls[id]
            if c and not c.disabled and id:sub(1, #prefix) == prefix then
                c.tab_stop = true
                if self.page then
                    self.page.controls[#self.page.controls + 1] = c
                end
            end
        end
        local layout = plan(ui)
        local top, bh, gap = y + layout.height, layout.bh, layout.gap
        self.bounds = { x = ui.x, y = y, w = ui.w, h = layout.height }
        ui.rect(ui.x, y, ui.w, layout.height, ui.theme.panel)
        for _, edge in ipairs({
            { ui.x, y, ui.w, 1 },
            { ui.x, top - 1, ui.w, 1 },
            { ui.x, y, 1, layout.height },
            { ui.x + ui.w - 1, y, 1, layout.height },
        }) do
            ui.rect(edge[1], edge[2], edge[3], edge[4], ui.theme.line)
        end
        ui.button(ui.x + 8, top - bh - 4, ui.w - 16, bh, (self.open and 'v ' or '> ') .. 'Cape Material', function()
            self.open = not self.open
            if not self.open then
                self.active = false
            end
        end, {
            selected = self.open,
            help = 'Separate Cape material document, selection and history. Scroll here for more controls/rows.',
        })
        self.viewport = nil
        if not self.open then
            return
        end
        local floor, ceiling = y + 4, top - bh - gap
        local height = math.max(1, ceiling - floor)
        self.viewport = { x = ui.x + 4, y = floor, w = ui.w - 8, h = height }
        local grid_height = math.max(180, height - layout.rows * (bh + gap) - bh - gap)
        local total = layout.rows * (bh + gap) + grid_height + bh + gap
        self.scroll_max = math.max(0, total - height)
        self.scroll = math.min(self.scroll or 0, self.scroll_max)
        local content_top = ceiling + self.scroll
        local function inside(x, py, w, h)
            return x >= ui.x + 4 and x + w <= ui.x + ui.w - 4 and py >= floor and py + h <= ceiling
        end
        local clipped = setmetatable({}, { __index = ui })
        clipped.rect = function(x, py, w, h, ...)
            local l, b, r, t =
                math.max(x, ui.x + 4), math.max(py, floor), math.min(x + w, ui.x + ui.w - 4), math.min(py + h, ceiling)
            if r > l and t > b then
                return ui.rect(l, b, r - l, t - b, ...)
            end
        end
        for _, method in ipairs({ 'text', 'bounded' }) do
            local name = method
            clipped[name] = function(x, py, text, size, ...)
                local metrics = ui.text_metrics and ui.text_metrics(size, text)
                    or { min_y = 0, max_y = ui.text_size and ui.text_size(size) or size }
                if py + metrics.min_y >= floor and py + metrics.max_y <= ceiling then
                    return ui[name](x, py, text, size, ...)
                end
            end
        end
        clipped.button = function(x, py, w, h, label, action, ...)
            if inside(x, py, w, h) then
                return ui.button(x, py, w, h, label, function()
                    self.active = true
                    return action()
                end, ...)
            end
        end
        clipped.hit = function(x, py, w, h, action, ...)
            if inside(x, py, w, h) then
                return ui.hit(x, py, w, h, function()
                    self.active = true
                    self.scalar_focus = false
                    return action()
                end, ...)
            end
        end
        clipped.choice = function(id, x, py, w, prepare)
            if inside(x, py, w, 26) then
                visible_control(id)
                return ui.choice(id, x, py, w, prepare)
            end
        end
        clipped.number = function(id, x, py, w, value, prepare, ...)
            local number_height = math.max(21, (ui.text_size and ui.text_size(14) or 14) + 8)
            if inside(x, py, w, number_height) then
                visible_control(id)
                return ui.number(id, x, py, w, value, prepare, ...)
            end
        end
        for _, item in ipairs(layout.items) do
            local py = content_top - item.row * (bh + gap)
            if item.id == 'basic_cape_lut' then
                clipped.choice(item.id, ui.x + item.x, py, item.width)
            else
                clipped.button(ui.x + item.x, py, item.width, bh, item.label, function()
                    ui.activate(item.id)
                end, {
                    enabled = item.id == 'editor_load_cape' or document ~= nil,
                    accent = item.id == 'editor_load_cape' and { 244, 202, 53 },
                    ink = item.id == 'editor_load_cape' and { 25, 28, 31 },
                })
            end
        end
        local grid_top = content_top - layout.rows * (bh + gap)
        if not document then
            clipped.bounded(
                ui.x + 12,
                grid_top - 30,
                'Load Current Cape to edit its material colors here.',
                14,
                ui.theme.muted,
                ui.w - 24
            )
            return
        end
        local inner = setmetatable(
            { x = ui.x + 8, y = grid_top - grid_height, w = ui.w - 16, h = grid_height },
            { __index = clipped }
        )
        for _, name in ipairs({ 'activate', 'set' }) do
            local method = name
            inner[method] = function(id, ...)
                self.active = true
                return ui[method](prefix .. id, ...)
            end
        end
        inner.choice = function(id, x, py, w, prepare)
            return clipped.choice(prefix .. id, x, py, w, function()
                self.active = true
                if prepare then
                    prepare()
                end
            end)
        end
        inner.number = function(id, x, py, w, value, prepare, ...)
            return clipped.number(prefix .. id, x, py, w, value, function()
                self.active = true
                if prepare then
                    prepare()
                end
            end, ...)
        end
        editor.layout(inner)
        local py, width = grid_top - grid_height - bh - gap, (ui.w - 24) / 4
        for ch, name in ipairs({ 'r', 'g', 'b', 'a' }) do
            local x = ui.x + 12 + (ch - 1) * width
            local control = editor.api.mods[editor.handle.id].controls['cell_' .. name]
            if inside(x, py, width - 4, bh) then
                ui.bounded(x, py + 5, name:upper(), 13, ui.theme.white, 20)
                clipped.number(
                    prefix .. 'cell_' .. name,
                    x + 24,
                    py,
                    width - 28,
                    editor.handle.get('cell_' .. name),
                    function()
                        self.active = true
                        self.scalar_focus = true
                        editor.focus_value(editor.handle.get('edit_row'), editor.handle.get('edit_column'), ch)
                    end,
                    not control.disabled,
                    control.drag_min,
                    control.drag_max
                )
            end
        end
    end
    return self
end
return C
