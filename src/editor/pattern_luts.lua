-- Pattern LUTs are 3x1 accent tables, bound through PATTERN_SLOT, never the material LUT slot.
local P = {}
function P.new(deps)
    local ffi = require('ffi')
    local self = { groups = {}, undo = {}, redo = {}, busy = false, documents = {}, selections = {} }
    local handle, controls
    local function note(text)
        self.status = text
        return deps.note(text)
    end
    local function selected()
        return assert(self.groups[handle.get('pattern_lut')], 'Load current Pattern LUTs first')
    end
    local function pixels(d)
        return ffi.string(d.data, 48)
    end
    local function remember()
        local group = selected()
        self.documents[(self.gear or 'armor') .. ':' .. group.object] = {
            document = self.document,
            undo = self.undo,
            redo = self.redo,
            object = deps.binding(group.bindings[1]),
        }
    end
    local function push_history(before)
        self.undo[#self.undo + 1] = before
        if #self.undo > 64 then
            table.remove(self.undo, 1)
        end
        self.redo = {}
        remember()
    end
    local function validate(source)
        assert(source and source.width == 3 and source.height == 1, 'Pattern DDS must be 3x1')
        for i = 0, 11 do
            local value = tonumber(source.data[i])
            assert(value == value and math.abs(value) <= 1e10, 'Pattern contains an unsupported float value')
        end
        return source
    end
    local function sync()
        if not handle then
            return
        end
        for _, id in ipairs({
            'pattern_picker',
            'pattern_color',
            'pattern_metal_r',
            'pattern_metal_g',
            'pattern_metal_b',
            'pattern_opacity',
            'pattern_color_alpha',
            'pattern_unknown_r',
            'pattern_unknown_g',
            'pattern_unknown_b',
            'pattern_unknown_a',
            'pattern_undo',
            'pattern_redo',
            'pattern_export',
            'pattern_export_patch',
        }) do
            controls[id].disabled = self.document == nil
        end
        controls.pattern_lut.disabled = not self.ready or #self.groups == 0
        controls.pattern_import_apply.disabled = self.imported == nil or self.document == nil
        controls.pattern_undo.disabled = self.document == nil or #self.undo == 0
        controls.pattern_redo.disabled = self.document == nil or #self.redo == 0
        controls.pattern_export_patch.disabled = self.document == nil or not deps.export_patch
        if not self.document then
            return
        end
        local d = self.document
        self.busy = true
        local values = {
            pattern_color = string.format(
                '#%02X%02X%02X',
                math.floor(math.max(0, math.min(1, d.data[0])) * 255 + 0.5),
                math.floor(math.max(0, math.min(1, d.data[1])) * 255 + 0.5),
                math.floor(math.max(0, math.min(1, d.data[2])) * 255 + 0.5)
            ),
        }
        for i, id in ipairs({ 'pattern_metal_r', 'pattern_metal_g', 'pattern_metal_b', 'pattern_opacity' }) do
            values[id] = tonumber(d.data[i + 3])
        end
        for i, id in ipairs({ 'pattern_unknown_r', 'pattern_unknown_g', 'pattern_unknown_b', 'pattern_unknown_a' }) do
            values[id] = tonumber(d.data[i + 7])
        end
        values.pattern_color_alpha = tonumber(d.data[3])
        local ok, why = handle.set_many(values)
        self.busy = false
        assert(ok, why)
    end
    function self.scan(background)
        if deps.indicator then
            assert(deps.indicator.stop(), 'Pattern highlight restoration pending')
        end
        local existing = {}
        local kept = {}
        for _, b in ipairs(deps.session.owned) do
            if (not deps.present or deps.present(b)) and deps.binding(b) == b.current then
                existing[deps.key(b)] = b
                kept[#kept + 1] = b
            end
        end
        deps.session.owned = kept
        local editable = {}
        for _, group in ipairs(self.groups) do
            for _, b in ipairs(group.bindings) do
                editable[deps.key(b)] = b
            end
        end
        local groups, ordered, seen = {}, {}, {}
        for _, b in ipairs(deps.discover()) do
            local key = deps.key(b)
            local prior = existing[key]
            if prior and deps.binding(b) == prior.current then
                b = prior
            elseif editable[key] and deps.binding(b) == editable[key].original then
                -- Keep the active editor and session on the same record when
                -- the game resets this material to its verified original.
                b = editable[key]
                b.current, b.previous, b.texture, b.document = b.original, nil, nil, nil
            end
            local object = b.original or deps.binding(b)
            if object and object ~= 0 and not seen[key] then
                seen[key] = true
                b.original, b.current = object, deps.binding(b)
                local group = groups[object]
                if not group then
                    group = { object = object, bindings = {}, helmet = b.helmet, armor = b.armor }
                    groups[object] = group
                    ordered[#ordered + 1] = group
                end
                group.helmet, group.armor = group.helmet or b.helmet, group.armor or b.armor
                group.bindings[#group.bindings + 1] = b
            end
        end
        table.sort(ordered, function(a, b)
            return a.object < b.object
        end)
        if background then
            return ordered
        end
        self.all_groups = ordered
        return self.filter(self.gear or 'armor')
    end
    function self.filter(kind)
        self.gear = kind
        local ordered = {}
        for _, group in ipairs(self.all_groups or {}) do
            local filtered =
                { object = group.object, bindings = {}, armor = kind == 'armor', helmet = kind == 'helmet' }
            for _, b in ipairs(group.bindings) do
                if b[kind] then
                    filtered.bindings[#filtered.bindings + 1] = b
                end
            end
            if #filtered.bindings > 0 then
                ordered[#ordered + 1] = filtered
            end
        end
        self.groups = ordered
        self.document, self.waiting, self.undo, self.redo = nil, nil, {}, {}
        sync()
        if controls then
            local choices, details = {}, {}
            for i, group in ipairs(ordered) do
                choices[i] = (group.armor and (group.helmet and 'Armor + Helmet' or 'Armor') or 'Helmet')
                    .. ' Pattern LUT '
                    .. i
                details[i] = deps.resource_id(group.object)
            end
            controls.pattern_lut.choices = #choices > 0 and choices or { 'No bound Pattern LUTs' }
            controls.pattern_lut.choice_details = details
            local selected_index = 1
            for i, group in ipairs(ordered) do
                if group.object == self.selections[kind] then
                    selected_index = i
                end
            end
            self.busy = true
            local disabled = controls.pattern_lut.disabled
            controls.pattern_lut.disabled = false
            local ok, why = handle.set('pattern_lut', selected_index)
            controls.pattern_lut.disabled = disabled
            self.busy = false
            assert(ok, why)
        end
        return #ordered
    end
    function self.load(force)
        if deps.indicator then
            assert(deps.indicator.stop(), 'Pattern highlight restoration pending')
        end
        local group = selected()
        self.selections[self.gear or 'armor'] = group.object
        local key = (self.gear or 'armor') .. ':' .. group.object
        local bound = deps.binding(group.bindings[1])
        local cached = not force and self.documents[key]
        if cached and cached.object ~= bound then
            cached = nil
        end
        if cached then
            self.document, self.undo, self.redo = cached.document, cached.undo, cached.redo
            self.ready, self.requested, self.waiting = true, true, nil
            sync()
            return note('Loaded cached current Pattern LUT values.')
        end
        local first = group.bindings[1]
        local original = deps.original(group.object)
        local source = bound ~= first.original
                and bound == first.current
                and ((first.texture and first.texture.object == bound and first.texture) or first.document)
            or original
        if not source then
            self.document = nil
            sync()
            self.waiting = self.waiting and self.waiting.key == key and self.waiting
                or { age = 0, elapsed = 0, key = key }
            return note('Loading current Pattern LUT values automatically...')
        end
        validate(source)
        self.ready, self.requested, self.waiting = true, true, nil
        local data = ffi.new('float[12]')
        ffi.copy(data, source.data, 48)
        self.document = { data = data, width = 3, height = 1, original = original and pixels(original) or nil }
        self.undo, self.redo = {}, {}
        remember()
        sync()
        return note('Loaded selected 3x1 Pattern LUT. Unknown channels are retained.')
    end
    function self.import(source)
        validate(source)
        local data = ffi.new('float[12]')
        ffi.copy(data, source.data, 48)
        self.imported = { data = data, width = 3, height = 1 }
        self.ready = true
        sync()
        return note('3x1 Pattern DDS ready. Load a destination Pattern LUT, then apply the imported table.')
    end
    local function apply()
        local group = selected()
        for _, b in ipairs(group.bindings) do
            local current = deps.binding(b)
            if current == b.original then
                b.current = current -- The game reset an owned table; reclaim only its known original.
            elseif current ~= b.current then
                if deps.log then
                    deps.log(
                        'PATTERN_STALE target='
                            .. deps.key(b)
                            .. ' expected='
                            .. tostring(b.current)
                            .. ' actual='
                            .. tostring(current)
                            .. ' original='
                            .. tostring(b.original)
                    )
                end
                error('Pattern changed; click Load Current Patterns to reload it.', 0)
            end
        end
        deps.session.apply(self.document, group.bindings)
        if deps.applied then
            deps.applied(group.bindings)
        end
        remember()
        sync()
    end
    local function edit(fn)
        if deps.indicator then
            assert(deps.indicator.stop(), 'Pattern highlight restoration pending')
        end
        if self.busy then
            return
        end
        local d = assert(self.document, 'Load a Pattern LUT first')
        local before = pixels(d)
        fn(d.data)
        if pixels(d) == before then
            return true
        end
        local ok, why = pcall(function()
            validate(d)
            apply()
        end)

        if not ok then
            ffi.copy(d.data, before, 48)
            sync()
            error(why, 0)
        end
        push_history(before)
        sync()
        return note('Selected Pattern LUT updated live.')
    end
    local function history(from, to)
        if deps.indicator then
            assert(deps.indicator.stop(), 'Pattern highlight restoration pending')
        end
        local d = assert(self.document, 'Load a Pattern LUT first')
        local value = from[#from]
        if not value then
            return note('No more Pattern LUT history')
        end
        local before = pixels(d)
        ffi.copy(d.data, value, 48)
        local ok, why = pcall(apply)
        if not ok then
            ffi.copy(d.data, before, 48)
            sync()
            error(why, 0)
        end
        table.remove(from)
        to[#to + 1] = before
        sync()
        return note('Pattern LUT history updated.')
    end
    function self.controls()
        local out = {
            { id = 'pattern_flash', type = 'button', label = 'Flash Pattern', on_activate = self.flash },
            { id = 'pattern_stop_flash', type = 'button', label = 'Stop Pattern Flash', on_activate = self.stop_flash },
            {
                id = 'pattern_picker',
                type = 'color',
                label = 'Pattern RGBA',
                default = '#FFFFFF',
                on_change = function(hex)
                    return edit(function(data)
                        local at = ((self.column or 1) - 1) * 4
                        local r, g, b = deps.rgb(hex)
                        data[at], data[at + 1], data[at + 2] = r, g, b
                    end)
                end,
            },
            {
                id = 'pattern_open',
                type = 'button',
                label = 'Pattern LUT Editor',
                on_activate = function()
                    return self.show(deps.current_gear and deps.current_gear() or 'armor')
                end,
            },
            {
                type = 'section',
                id = 'pattern_section',
                label = 'Pattern LUTs - accent colors',
                collapsible = true,
                collapsed = false,
                children = {
                    {
                        type = 'text',
                        label = '3 columns x 1 row. Column 1: color. Column 2: metallic RGB and opacity A (provisional mapping). Column 3: unknown.',
                    },
                    {
                        id = 'pattern_load',
                        type = 'button',
                        label = 'Load Current Pattern LUTs',
                        on_activate = function()
                            self.load_seen, self.requested = true, true
                            if deps.mark_load_seen then
                                deps.mark_load_seen()
                            end
                            assert(self.scan() > 0, 'No bound Pattern LUTs')
                            return self.load(true)
                        end,
                    },
                    {
                        id = 'pattern_lut',
                        type = 'choice',
                        choices = { 'Load current patterns first' },
                        default = 1,
                        label = 'Pattern LUT',
                        on_change = function()
                            if not self.busy then
                                self.load()
                            end
                        end,
                    },
                    {
                        id = 'pattern_color',
                        type = 'color',
                        label = 'Column 1 - Pattern color',
                        default = '#FFFFFF',
                        on_change = function(hex)
                            return edit(function(data)
                                local r, g, b = deps.rgb(hex)
                                data[0], data[1], data[2] = r, g, b
                            end)
                        end,
                    },
                },
            },
        }
        local children = out[5].children
        for i, spec in ipairs({
            { 'pattern_metal_r', 'Column 2 - Metallic R', 4 },
            { 'pattern_metal_g', 'Column 2 - Metallic G', 5 },
            { 'pattern_metal_b', 'Column 2 - Metallic B', 6 },
            { 'pattern_opacity', 'Column 2 - Pattern opacity A', 7 },
        }) do
            local index = spec[3]
            children[#children + 1] = {
                id = spec[1],
                type = 'slider',
                label = spec[2],
                min = -1e10,
                max = 1e10,
                drag_min = 0,
                drag_max = 1,
                step = 0.001,
                default = 0,
                on_change = function(value)
                    return edit(function(data)
                        data[index] = value
                    end)
                end,
            }
        end
        children[#children + 1] = {
            id = 'pattern_import_apply',
            type = 'button',
            label = 'Apply Imported Pattern DDS to Selected Pattern LUT',
            on_activate = function()
                local source = assert(self.imported, 'Import a 3x1 Pattern DDS first')
                if #self.groups == 0 then
                    assert(self.scan() > 0, 'No bound Pattern LUTs')
                end
                if not self.document then
                    self.load()
                end
                assert(self.document, 'Destination Pattern LUT is still loading; wait before applying the import')
                return edit(function(target)
                    ffi.copy(target, source.data, 48)
                end)
            end,
        }
        children[#children + 1] = {
            id = 'pattern_undo',
            type = 'button',
            label = 'Undo Pattern Edit',
            on_activate = function()
                return history(self.undo, self.redo)
            end,
        }
        children[#children + 1] = {
            id = 'pattern_redo',
            type = 'button',
            label = 'Redo Pattern Edit',
            on_activate = function()
                return history(self.redo, self.undo)
            end,
        }
        children[#children + 1] = {
            id = 'pattern_restore',
            type = 'button',
            label = 'Restore Original Pattern LUTs',
            on_activate = function()
                if deps.indicator then
                    assert(deps.indicator.stop(), 'Pattern highlight restoration pending')
                end
                assert(deps.session.restore(), 'Pattern restoration pending')
                if deps.restored then
                    deps.restored()
                end
                self.document = nil
                self.documents, self.undo, self.redo, self.waiting = {}, {}, {}, nil
                sync()
                return note('Original Pattern LUT bindings restored.')
            end,
        }
        children[#children + 1] =
            { id = 'pattern_export_name', type = 'input', label = 'Pattern DDS name', default = 'Epic-LUT-pattern' }
        children[#children + 1] = {
            id = 'pattern_export',
            type = 'button',
            label = 'Export Pattern DDS',
            on_activate = function()
                return deps.export(handle.get('pattern_export_name'), assert(self.document, 'Load a Pattern LUT first'))
            end,
        }
        children[#children + 1] = {
            id = 'pattern_export_patch',
            type = 'button',
            label = 'Export Pattern Patch ZIP',
            on_activate = function()
                assert(deps.export_patch, 'Pattern patch export unavailable')
                local group = selected()
                return deps.export_patch(
                    handle.get('pattern_export_name'),
                    assert(self.document, 'Load a Pattern LUT first'),
                    deps.original(group.object)
                )
            end,
        }
        local raw = {
            type = 'section',
            id = 'pattern_unknown',
            label = 'Unknown channels - raw values',
            collapsible = true,
            collapsed = true,
            children = {},
        }
        for _, spec in ipairs({
            { 'pattern_color_alpha', 'Column 1 - Unknown A', 3 },
            { 'pattern_unknown_r', 'Column 3 - Unknown R', 8 },
            { 'pattern_unknown_g', 'Column 3 - Unknown G', 9 },
            { 'pattern_unknown_b', 'Column 3 - Unknown B', 10 },
            { 'pattern_unknown_a', 'Column 3 - Unknown A', 11 },
        }) do
            local index = spec[3]
            raw.children[#raw.children + 1] = {
                id = spec[1],
                type = 'slider',
                label = spec[2],
                min = -1e10,
                max = 1e10,
                step = 0.001,
                default = 0,
                on_change = function(value)
                    return edit(function(data)
                        data[index] = value
                    end)
                end,
            }
        end
        children[#children + 1] = raw
        return out
    end
    function self.switch(kind)
        assert(kind == 'armor' or kind == 'helmet')
        if not self.ready then
            return false
        end
        local ok, why = pcall(function()
            local signature = deps.gear_signature and deps.gear_signature() or nil
            if self.gear == kind and self.document and signature == self.gear_signature then
                return
            end
            self.gear_signature = signature
            self.waiting = nil
            self.gear = kind
            assert(self.scan() > 0, 'No bound Pattern LUTs for ' .. kind)
            self.load()
        end)
        if not ok then
            self.document = nil
            sync()
            note(tostring(why))
        end
        return ok
    end
    function self.flash()
        assert(deps.indicator, 'Pattern highlighting unavailable')
        assert(deps.indicator.stop(), 'Previous pattern flash restoration pending')
        local d = assert(self.document, 'Load a Pattern LUT first')
        local items = {}
        for _, b in ipairs(selected().bindings) do
            local object = deps.binding(b)
            assert(object == b.current or object == b.original, 'Pattern changed; load current patterns again')
            if object == b.original then
                b.current = object
            end
            local source = b.texture and b.texture.object == object and b.texture or d
            items[#items + 1] =
                { binding = b, source = source, object = object, texture = b.texture, document = b.document }
        end
        deps.indicator.start(items, 1)
        return note('Flashing the selected pattern accent for four seconds. An unused pattern may not show.')
    end
    function self.stop_flash()
        return not deps.indicator or deps.indicator.stop()
    end
    function self.flashing()
        return deps.indicator and deps.indicator.job ~= nil or false
    end
    function self.tick(dt)
        dt = math.max(0, tonumber(dt) or 0)
        if self.open then
            self.cue_time = (self.cue_time or 0) + dt
        end
        if deps.indicator then
            deps.indicator.tick(dt, self.open == true)
        end
        if self.open and self.requested and deps.gear_signature then
            self.gear_elapsed = (self.gear_elapsed or 0) + math.max(0, dt or 0)
            if self.gear_elapsed >= 0.5 then
                self.gear_elapsed = 0
                local ok, why = pcall(function()
                    local signature = deps.gear_signature()
                    local group = self.groups[handle.get('pattern_lut')]
                    local missing = group and deps.present and not deps.present(group.bindings[1])
                    if signature ~= self.gear_signature or missing then
                        self.gear_signature = signature
                        self.document, self.waiting = nil, nil
                        assert(self.scan() > 0, 'No bound Pattern LUTs for current gear')
                        self.load()
                    end
                end)
                if not ok then
                    self.document = nil
                    sync()
                    if self.refresh_error ~= tostring(why) then
                        note(tostring(why))
                    end
                    self.refresh_error = tostring(why)
                else
                    self.refresh_error = nil
                end
            end
        end
        local pending = self.waiting
        if not pending then
            return
        end
        pending.age, pending.elapsed = pending.age + (dt or 0), pending.elapsed + (dt or 0)
        if pending.age > 120 then
            self.waiting = nil
            note('Pattern snapshot unavailable; Load Current Patterns to retry')
            return
        end
        if pending.elapsed >= 0.25 then
            pending.elapsed = 0
            local ok, why = pcall(self.load)
            if not ok then
                self.waiting = nil
                note(tostring(why))
            end
        end
    end
    function self.show(kind)
        self.open = true
        self.gear = kind or self.gear or 'armor'
        self.gear_elapsed = 0
        local auto = deps.auto_populate and deps.auto_populate()
        if not (auto or self.ready or self.imported or next(self.documents)) then
            self.document, self.waiting, self.groups, self.all_groups = nil, nil, {}, nil
            if controls then
                controls.pattern_lut.choices = { 'Load current patterns first' }
                controls.pattern_lut.choice_details = {}
            end
            sync()
            return note('Load Current Patterns to edit the worn Armor and Helmet pattern tables.')
        end
        self.requested = true
        local ok, why = pcall(function()
            self.gear_signature = deps.gear_signature and deps.gear_signature() or nil
            assert(self.scan() > 0, 'No bound Pattern LUTs for this gear')
            self.load()
        end)
        if not ok then
            self.document, self.waiting = nil, nil
            sync()
            note(tostring(why))
        end
        return self.status or 'Pattern LUT Editor opened'
    end
    function self.popup(ui)
        if not self.open or not ui.floating then
            return
        end
        local function draw(x, y, w, h)
            local theme = ui.theme
            local white, muted = theme.white, theme.muted
            local function label(px, py, text, width)
                ui.bounded(px, py, text, 13, white, width or w - 24)
            end
            local function button(px, py, width, text, id, enabled, callback, active)
                local featured = enabled ~= false
                    and (id == 'pattern_export' or id == 'pattern_export_patch' or id == 'pattern_load')
                local featured_color = { 244, 202, 53 }
                local seen = self.load_seen
                if deps.load_seen then
                    seen = deps.load_seen()
                end
                if id == 'pattern_load' and not seen then
                    local pulse = math.floor(32 + 26 * math.sin((self.cue_time or 0) * 4))
                    featured_color = { 244, math.min(255, 202 + pulse), 53 + pulse }
                end
                ui.button(px, py, width, 26, text, function()
                    if callback then
                        callback()
                    else
                        ui.activate(id)
                    end
                end, {
                    enabled = enabled,
                    selected = active,
                    accent = featured and featured_color,
                    ink = featured and { 25, 28, 31 },
                    size = 13,
                    padding = 6,
                })
            end
            ui.rect(x, y, w, h, theme.panel)
            ui.rect(x, y + h - 40, w, 40, theme.header)
            label(x + 10, y + h - 27, 'Pattern LUT Editor', w - 40)
            for i, kind in ipairs({ 'armor', 'helmet' }) do
                local gear = kind
                button(
                    x + 12 + (i - 1) * 132,
                    y + h - 66,
                    124,
                    (self.gear == kind and '> ' or '') .. (kind == 'armor' and 'Armor' or 'Helmet'),
                    nil,
                    self.ready == true,
                    function()
                        self.switch(gear)
                    end,
                    self.gear == gear
                )
            end
            button(x + 284, y + h - 66, w - 296, 'Load Current Patterns', 'pattern_load')
            ui.choice('pattern_lut', x + 12, y + h - 104, w - 170)
            button(
                x + w - 150,
                y + h - 104,
                138,
                '[ ' .. (handle.get('show_alpha') and 'x' or ' ') .. ' ] Show Alpha',
                'show_alpha'
            )
            local group = self.groups[handle.get('pattern_lut')]
            ui.bounded(
                x + 12,
                y + h - 124,
                group and deps.resource_id(group.object) or 'No pattern resource selected',
                12,
                { 244, 202, 53 },
                w - 24
            )
            local d = self.document
            local sw = (w - 36) / 3
            for col = 1, 3 do
                local index = (col - 1) * 4
                local color = { 0, 0, 0 }
                if d then
                    for ch = 1, 3 do
                        color[ch] = math.floor(math.max(0, math.min(1, d.data[index + ch - 1])) * 255 + 0.5)
                    end
                end
                local px = x + 12 + (col - 1) * (sw + 6)
                label(px, y + h - 150, ({ '1: Accent color', '2: Material / opacity', '3: Unknown' })[col], sw)
                ui.rect(px - 1, y + h - 211, sw + 2, 50, self.column == col and { 244, 202, 53 } or muted)
                deps.swatch(ui, px, y + h - 210, sw, 48, color, d and d.data[index + 3] or 1, handle.get('show_alpha'))
                local selected_column = col
                ui.hit(
                    px,
                    y + h - 210,
                    sw,
                    48,
                    function()
                        self.column = selected_column
                    end,
                    nil,
                    nil,
                    'Double-click to edit this Pattern LUT swatch.',
                    function()
                        if not self.document then
                            note('Load a Pattern LUT first')
                            return
                        end
                        self.column = selected_column
                        local at = (selected_column - 1) * 4
                        self.busy = true
                        local color = {}
                        for ch = 1, 3 do
                            color[ch] =
                                math.floor(math.max(0, math.min(1, self.document.data[at + ch - 1])) * 255 + 0.5)
                        end
                        assert(
                            handle.set('pattern_picker', string.format('#%02X%02X%02X', color[1], color[2], color[3]))
                        )
                        self.busy = false
                        ui.activate('pattern_picker')
                    end
                )
            end
            self.column = self.column or 1
            local cursor = y + h - 249
            local function number(id, name)
                label(x + 12, cursor + 5, name, 142)
                ui.number(
                    id,
                    x + 157,
                    cursor,
                    w - 169,
                    handle.get(id),
                    function() end,
                    d ~= nil,
                    controls[id].drag_min or 0,
                    controls[id].drag_max or 1
                )
                cursor = cursor - 32
            end
            if d then
                if self.column == 1 then
                    button(x + 12, cursor, w - 24, 'Edit accent color', 'pattern_color')
                    cursor = cursor - 34
                    button(
                        x + 12,
                        cursor,
                        w - 24,
                        (self.raw and 'v ' or '> ') .. 'Advanced: unknown alpha',
                        nil,
                        true,
                        function()
                            self.raw = not self.raw
                        end
                    )
                    cursor = cursor - 34
                    if self.raw then
                        number('pattern_color_alpha', 'Unknown A')
                    end
                elseif self.column == 2 then
                    number('pattern_metal_r', 'Metallic R')
                    number('pattern_metal_g', 'Metallic G')
                    number('pattern_metal_b', 'Metallic B')
                    number('pattern_opacity', 'Opacity A')
                else
                    button(
                        x + 12,
                        cursor,
                        w - 24,
                        (self.raw and 'v ' or '> ') .. 'Advanced: raw unknown values',
                        nil,
                        true,
                        function()
                            self.raw = not self.raw
                        end
                    )
                    cursor = cursor - 34
                    if self.raw then
                        number('pattern_unknown_r', 'Unknown R')
                        number('pattern_unknown_g', 'Unknown G')
                        number('pattern_unknown_b', 'Unknown B')
                        number('pattern_unknown_a', 'Unknown A')
                    end
                end
            else
                label(x + 12, cursor, 'Load current patterns to edit. Snapshots may still be loading.')
            end
            button(x + 12, y + 294, (w - 30) / 2, 'Flash Pattern', 'pattern_flash', d ~= nil)
            button(x + 18 + (w - 30) / 2, y + 294, (w - 30) / 2, 'Stop Flash', 'pattern_stop_flash')
            local bw = (w - 36) / 3
            button(x + 12, y + 256, bw, 'Undo', 'pattern_undo', d ~= nil and #self.undo > 0)
            button(x + 18 + bw, y + 256, bw, 'Redo', 'pattern_redo', d ~= nil and #self.redo > 0)
            button(x + 24 + bw * 2, y + 256, bw, 'Restore All Patterns', 'pattern_restore')
            ui.rect(x + 12, y + 244, w - 24, 1, theme.line)
            label(x + 12, y + 222, 'Pattern Import', w - 24)
            if self.imported then
                label(x + 12, y + 199, 'Imported:', 80)
                for col = 1, 3 do
                    local at = (col - 1) * 4
                    local color = {}
                    for ch = 1, 3 do
                        color[ch] = math.floor(math.max(0, math.min(1, self.imported.data[at + ch - 1])) * 255 + 0.5)
                    end
                    deps.swatch(
                        ui,
                        x + 96 + (col - 1) * 62,
                        y + 190,
                        56,
                        20,
                        color,
                        self.imported.data[at + 3],
                        handle.get('show_alpha')
                    )
                end
            end
            button(x + 12, y + 80, bw, 'Import', 'browse')
            button(
                x + 18 + bw,
                y + 80,
                bw * 2 + 6,
                'Apply Imported DDS to Selected Pattern LUT',
                'pattern_import_apply',
                self.imported ~= nil and d ~= nil
            )
            ui.bounded(x + 12, y + 12, self.status or 'Pattern LUT values apply live.', 11, muted, w - 24)
        end
        ui.floating('pattern_lut_editor', draw, 580, 700, function()
            self.open = false
            self.waiting = nil
            self.stop_flash()
        end, 40)
    end
    function self.attach(h, c)
        handle, controls = h, c
        controls.pattern_picker.can_open_picker = function()
            return self.document ~= nil
                and not self.document.read_only
                and not self.document.stale
                and ((self.column or 1) <= 2 or self.raw == true),
                'Enable Advanced raw values to edit this Pattern channel.'
        end
        controls.pattern_picker.picker_channel_enabled = function(channel)
            return channel <= 3 or (self.column == 2 or self.raw == true)
        end
        controls.pattern_picker.picker_begin = function()
            assert(controls.pattern_picker.can_open_picker())
            assert(self.stop_flash(), 'Pattern highlight restoration pending')
            self.color_session = {
                before = pixels(assert(self.document)),
                column = self.column or 1,
                document = self.document,
                object = selected().object,
            }
        end
        controls.pattern_picker.picker_preview = function(color, alpha)
            local session = assert(self.color_session, 'Pattern color session ended')
            assert(controls.pattern_picker.can_open_picker())
            assert(
                self.document == session.document and selected().object == session.object,
                'Pattern changed while picking a color; close the picker and load current patterns'
            )
            local d = session.document
            local current_pixels = pixels(d)
            local at = (session.column - 1) * 4
            local original = ffi.new('float[12]')
            ffi.copy(original, session.before, 48)
            for ch = 1, 3 do
                local displayed = math.floor(math.max(0, math.min(1, original[at + ch - 1])) * 255 + 0.5)
                d.data[at + ch - 1] = color[ch] == displayed and original[at + ch - 1] or color[ch] / 255
            end
            if session.column == 2 or self.raw then
                d.data[at + 3] = alpha
            end
            if pixels(d) ~= current_pixels then
                local ok, why = pcall(function()
                    validate(d)
                    apply()
                end)
                if not ok then
                    ffi.copy(d.data, current_pixels, 48)
                    sync()
                    error(why, 0)
                end
                session.changed = true
            end
        end
        controls.pattern_picker.picker_end = function(commit)
            local session = self.color_session
            self.color_session = nil
            if not session then
                return
            end
            local d = session.document
            if self.document ~= d then
                return
            end
            if commit and pixels(d) ~= session.before then
                push_history(session.before)
            elseif not commit and session.changed then
                local before = pixels(d)
                ffi.copy(d.data, session.before, 48)
                local ok, why = pcall(apply)
                if not ok then
                    ffi.copy(d.data, before, 48)
                    sync()
                    error(why, 0)
                end
            end
            sync()
        end
        controls.pattern_picker.picker_alpha = function()
            return self.document and tonumber(self.document.data[((self.column or 1) - 1) * 4 + 3]) or 1
        end
        controls.pattern_picker.picker_commit = function(color, alpha)
            assert(controls.pattern_picker.can_open_picker())
            if self.color_session then
                controls.pattern_picker.picker_preview(color, alpha)
                return true
            end
            return edit(function(data)
                local at = ((self.column or 1) - 1) * 4
                for ch = 1, 3 do
                    local before = math.floor(math.max(0, math.min(1, data[at + ch - 1])) * 255 + 0.5)
                    if color[ch] ~= before then
                        data[at + ch - 1] = color[ch] / 255
                    end
                end
                if self.column == 2 or self.raw then
                    data[at + 3] = alpha
                end
            end)
        end
        for _, name in ipairs({
            'can_open_picker',
            'picker_channel_enabled',
            'picker_begin',
            'picker_preview',
            'picker_end',
            'picker_alpha',
            'picker_commit',
        }) do
            controls.pattern_color[name] = controls.pattern_picker[name]
        end
        sync()
    end
    function self.close()
        if not self.stop_flash() then
            return false
        end
        self.open, self.waiting = false, nil
        local restored = deps.session.restore()
        if restored then
            self.document, self.documents, self.undo, self.redo = nil, {}, {}, {}
            self.color_session = nil
            self.ready, self.requested = self.imported ~= nil, false
            sync()
        end
        return restored
    end
    return self
end
return P
