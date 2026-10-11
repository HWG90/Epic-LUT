local ffi = require('ffi')
local Menu = dofile('vendor/menu/menu.lua')
local core = dofile('vendor/menu/core.lua')
local palette = dofile('src/core/palette.lua')
local api = core.new({
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
})
local scans, uploads, restored, marks = 0, 0, 0, 0
local quick_loaded, quick_kind = false, 'helmet'
local objects, sources = {}, {}
for index, kind in ipairs({ 'armor', 'helmet' }) do
    local object = 100 + index
    objects[index] = { original = object, current = object, material = object, [kind] = true }
    local source = { width = 3, height = 1, data = ffi.new('float[12]') }
    for channel = 0, 11 do
        source.data[channel] = index / 10 + channel / 100
    end
    source.data[3], source.data[11] = 2.75, -0.25
    sources[object] = source
end
local exported, patched, browsed, activations
local pattern = dofile('src/editor/pattern_luts.lua').new({
    session = {
        owned = {},
        apply = function(document, bindings)
            uploads = uploads + 1
            for _, binding in ipairs(bindings) do
                binding.current = 1000 + uploads
                binding.texture = { object = binding.current, width = 3, height = 1, data = document.data }
                binding.document = document
            end
        end,
        restore = function()
            restored = restored + 1
            for _, binding in ipairs(objects) do
                binding.current = binding.original
            end
            return true
        end,
    },
    auto_populate = function()
        return false
    end,
    mark_load_seen = function()
        marks = marks + 1
    end,
    discover = function()
        scans = scans + 1
        return objects
    end,
    binding = function(binding)
        return binding.current
    end,
    key = function(binding)
        return binding.material
    end,
    present = function()
        return true
    end,
    original = function(object)
        return sources[object]
    end,
    cached_original = function(object)
        return sources[object]
    end,
    quick_bindings = function()
        if quick_loaded then
            return quick_kind, objects, quick_kind == 'helmet' and objects[2].material or objects[1].material
        end
    end,
    resource_id = function(object)
        return '[0x' .. object .. ']'
    end,
    rgb = palette.rgb,
    swatch = palette.swatch,
    note = function(value)
        return value
    end,
    export = function(name, document)
        exported = { name, ffi.string(document.data, 48) }
    end,
    export_patch = function(name, document, original)
        patched = { name, ffi.string(document.data, 48), original }
    end,
})
local definitions = pattern.controls()
definitions[#definitions + 1] = { id = 'show_alpha', type = 'toggle', label = 'Show Alpha', default = false }
definitions[#definitions + 1] = {
    id = 'browse',
    type = 'button',
    label = 'Import',
    on_activate = function()
        browsed = (browsed or 0) + 1
    end,
}
local handle = api.register({
    id = 'workspace',
    name = 'Workspace',
    pages = {
        { id = 'pattern', name = 'Pattern', controls = definitions },
    },
})
local controls = api.mods[handle.id].controls
pattern.attach(handle, controls)

-- This renderer exercises real custom button drawing while modeling the
-- native viewport's intersections. Every returned hit is actually reachable.
local function renderer(font)
    local output = { labels = {}, rects = {}, hits = {}, numbers = {}, choices = {}, bars = {}, floats = 0 }
    local clip
    local function intersects(x, y, w, h)
        return not clip or x + w > clip.x and x < clip.x + clip.w and y + h > clip.y and y < clip.y + clip.h
    end
    local ui = Menu.custom_ui({
        epic_style = true,
        pixel_width = 1,
        spacing = function(value)
            return value * font / 12
        end,
        text_size = function(value)
            return value * font / 12
        end,
        text_metrics = function(value)
            return { height = value * font / 12, min_y = -2 }
        end,
        text_width = function(value, size)
            return #value * size * font / 12 * 0.6
        end,
        text_y = function(y, h, size)
            return y + (h - size * font / 12) / 2 + 2
        end,
        control_height = function(size, padding, minimum)
            return math.max(minimum or 0, (size + padding * 2) * font / 12)
        end,
        rect = function(x, y, w, h, color, alpha, role)
            if intersects(x, y, w, h) then
                output.rects[#output.rects + 1] = { x = x, y = y, w = w, h = h, color = color, role = role }
            end
        end,
        bounded = function(x, y, text, size)
            if intersects(x, y - 2, 1, size * font / 12) then
                output.labels[text] = true
                output.current_label = text
            end
        end,
        hit = function(x, y, w, h, callback, _, _, help, double)
            if intersects(x, y, w, h) then
                output.hits[#output.hits + 1] = {
                    x = x,
                    y = y,
                    w = w,
                    h = h,
                    callback = callback,
                    label = output.current_label,
                    help = help,
                    double = double,
                }
            end
        end,
        choice = function(id, x, y, width)
            output.choices[id] = { x = x, y = y, w = width }
        end,
        number = function(id, x, y, width, value, prepare, enabled)
            output.numbers[id] = { x = x, y = y, w = width, value = value, enabled = enabled }
        end,
        activate = function(id)
            activations = activations or {}
            activations[#activations + 1] = id
            if controls[id].type ~= 'color' then
                assert(handle.activate(id))
            end
        end,
        input_value = handle.get,
        floating = function()
            output.floats = output.floats + 1
        end,
        viewport = function(bounds, draw, covers)
            assert(not clip and covers.top >= bounds.y + bounds.h and covers.bottom <= bounds.y)
            clip = bounds
            draw()
            clip = nil
        end,
        scrollbar = function(id, x, y, height, total, visible, offset, callback)
            output.bars[id] =
                { x = x, y = y, h = height, total = total, visible = visible, offset = offset, callback = callback }
        end,
    })
    return ui, output
end
local function hit(output, label)
    for _, item in ipairs(output.hits) do
        if item.label == label then
            return item
        end
    end
    error('Missing reachable Pattern action: ' .. label)
end

pattern.set_workspace_host(true)
local ui, output = renderer(12)
local quick = { x = 40, y = 50, w = 660, h = pattern.quick_height(ui) }
assert(quick.h <= 60, 'Quick Pattern strip consumes too many material row heights')
pattern.quick(ui, quick, 'helmet')
assert(scans == 0 and uploads == 0 and pattern.document == nil and pattern.gear == nil)
local swatches = {}
for _, rectangle in ipairs(output.rects) do
    if rectangle.role == 'swatch_border' then
        swatches[#swatches + 1] = rectangle
        assert(rectangle.y >= quick.y and rectangle.y + rectangle.h <= quick.y + quick.h)
    end
end
assert(
    #swatches == 2 and output.labels['Quick Editor: Pattern LUT'],
    'Quick strip must show only Accent and Material swatches'
)
for _, rectangle in ipairs(swatches) do
    assert(rectangle.w == 28 and rectangle.h == 28, 'Quick swatches stretched to fill the pane')
end
local sized_ui, sized_output = renderer(20)
local sized_bounds =
    { x = quick.x, y = quick.y, w = 1000, h = pattern.quick_height(sized_ui, 38), cell_width = 38, row_height = 38 }
pattern.quick(sized_ui, sized_bounds, 'helmet')
assert(
    pattern.quick_height(sized_ui, 0) + 38 == sized_bounds.h,
    'Quick height overhead cannot reserve actual row height'
)
local sized_count = 0
for _, rectangle in ipairs(sized_output.rects) do
    if rectangle.role == 'swatch_border' then
        sized_count = sized_count + 1
        assert(
            rectangle.w == 38 and rectangle.h == 38,
            'Quick Pattern swatches do not match the material table cell width/height'
        )
    end
end
assert(sized_count == 2 and scans == 0 and uploads == 0)
local capped_ui, capped_output = renderer(20)
pattern.quick(capped_ui, {
    x = quick.x,
    y = quick.y,
    w = 2400,
    h = pattern.quick_height(capped_ui, 100),
    cell_width = 100,
    row_height = 100,
}, 'helmet')
local capped_count = 0
for _, rectangle in ipairs(capped_output.rects) do
    if rectangle.role == 'swatch_border' then
        capped_count = capped_count + 1
        assert(rectangle.w == 40 and rectangle.h == 40, 'Quick painted borders bypassed the40px clamp')
    end
end
assert(capped_count == 2 and scans == 0 and uploads == 0)
hit(output, 'Quick Editor: Pattern LUT').callback()
assert(pattern.is_open() and scans == 0, 'Opening workspace bypassed the manual load gate')
pattern.popup(ui)
assert(output.floats == 0, 'Hosted Pattern opened a floating window')
pattern.workspace(ui, { x = 40, y = 50, w = 660, h = 900 })
assert(hit(output, 'Load Current Patterns'))
assert(pattern.dismiss() and not pattern.is_open())
assert(pattern.prime('helmet') and scans == 1 and pattern.document and pattern.gear == 'helmet')
assert(
    not pattern.is_open() and marks == 1 and pattern.load_seen and pattern.requested,
    'Explicit material load priming opened Pattern UI or failed to acknowledge manual readiness'
)

local before, undo = ffi.string(pattern.document.data, 48), #pattern.undo
ui, output = renderer(12)
pattern.quick(ui, quick, 'helmet')
local quick_hits = {}
for _, item in ipairs(output.hits) do
    if item.help == 'Edit this Pattern LUT swatch.' then
        quick_hits[#quick_hits + 1] = item
    end
end
assert(#quick_hits == 2, 'Quick strip exposes the hidden Unknown channel')
quick_hits[2].callback()
assert(pattern.column == 2 and activations[#activations] == 'pattern_picker')
assert(
    ffi.string(pattern.document.data, 48) == before and #pattern.undo == undo and uploads == 0,
    'Opening Quick Pattern picker wrote a texture or changed history'
)
assert(controls.pattern_picker.picker_commit({ 0, 255, 0 }, 0.8))
assert(pattern.document.data[4] == 0 and pattern.document.data[5] == 1 and pattern.document.data[6] == 0)
assert(math.abs(pattern.document.data[7] - 0.8) < 0.00001 and #pattern.undo == undo + 1)
assert(
    pattern.document.data[3] == 2.75 and pattern.document.data[11] == -0.25,
    'Quick Material color edit touched other Pattern channels'
)
local edited_document, edited_bytes, edited_undo = pattern.document, ffi.string(pattern.document.data, 48), pattern.undo
local cached_scans = scans
assert(pattern.prime('helmet') and scans == cached_scans + 1 and marks == 2 and not pattern.is_open())
assert(
    pattern.document == edited_document
        and pattern.undo == edited_undo
        and #pattern.undo == undo + 1
        and ffi.string(pattern.document.data, 48) == edited_bytes
        and uploads == 1,
    'Re-priming the Quick strip lost owned edits or their Undo history'
)
cached_scans = scans
pattern.scan()
assert(pattern.document == nil and scans == cached_scans + 1)
ui, output = renderer(12)
pattern.quick(ui, quick, 'helmet')
assert(pattern.document == nil and scans == cached_scans + 1, 'Quick drawing loaded or discovered gear')
quick_loaded = true
pattern.tick(0.5)
pattern.quick(ui, quick, 'helmet')
assert(
    pattern.document == edited_document
        and pattern.undo == edited_undo
        and not pattern.is_open()
        and ffi.string(pattern.document.data, 48) == edited_bytes
        and scans == cached_scans + 1
        and uploads == 1,
    'Quick strip did not recover cached values after scan without discovery/popout/write'
)
assert(
    not pattern.prime('cape') and pattern.gear == 'helmet' and scans == cached_scans + 1,
    'Cape priming silently loaded an unrelated Armor Pattern'
)
local owned = objects[2].current
assert(
    pattern.dismiss() and not pattern.is_open() and objects[2].current == owned and restored == 0,
    'Returning to LUT Table restored owned Pattern edits'
)
pattern.raw = false
assert(pattern.show('helmet'))
ui, output = renderer(12)
pattern.workspace(ui, { x = 40, y = 50, w = 900, h = 1000 })
local workspace_swatches = {}
for _, item in ipairs(output.hits) do
    if item.help == 'Double-click to edit this Pattern LUT swatch.' then
        workspace_swatches[#workspace_swatches + 1] = item
    end
end
assert(#workspace_swatches == 3, 'Full workspace lost the stored Unknown channel')
workspace_swatches[3].callback()
assert(
    pattern.is_open() and pattern.column == 3 and not controls.pattern_picker.can_open_picker(),
    'Full workspace Unknown swatch bypassed Advanced raw protection'
)
pattern.quick(ui, quick, 'armor')
assert(
    pattern.gear == 'helmet' and scans == cached_scans + 2,
    'Quick drawing changed the full workspace gear selection'
)
assert(pattern.dismiss())
quick_kind = 'armor'
pattern.tick(0.5)
pattern.quick(ui, quick, 'armor')
assert(
    pattern.gear == 'armor' and scans == cached_scans + 2 and pattern.document.data[0] == sources[101].data[0],
    'Quick Pattern retained Helmet values after material gear changed'
)
local expected_scans = scans
pattern.quick(ui, quick, 'armor')
assert(scans == expected_scans, 'Quick Pattern repeatedly scanned unchanged equipped gear')
local cape_document, cape_bytes, cape_gear = pattern.document, ffi.string(pattern.document.data, 48), pattern.gear
ui, output = renderer(12)
pattern.quick(ui, quick, 'cape')
assert(
    output.labels['Quick Editor: Pattern LUT - Armor / Helmet only'] and #output.hits == 0,
    'Cape Quick strip exposes an unrelated Armor picker'
)
assert(
    scans == expected_scans
        and pattern.gear == cape_gear
        and pattern.document == cape_document
        and ffi.string(pattern.document.data, 48) == cape_bytes,
    'Cape Quick strip changed Armor/Helmet selection or data'
)

pattern.column, pattern.raw, pattern.scroll = 1, false, 0
assert(pattern.show('armor'))
assert(handle.set('pattern_export_name', 'embedded-pattern'))
pattern.import(sources[101])
ui, output = renderer(12)
pattern.workspace(ui, { x = 40, y = 50, w = 900, h = 1000 })
for _, label in ipairs({
    'Pattern LUT Editor',
    'Armor',
    'Helmet',
    'Load Current Patterns',
    '[0x101]',
    '1: Accent color',
    '2: Material / opacity',
    '3: Unknown',
    'Edit accent color',
    '> Advanced: unknown alpha',
    'Flash Pattern',
    'Stop Flash',
    'Undo',
    'Redo',
    'Restore All Patterns',
    'Pattern Import',
    'Import',
    'Apply Imported DDS to Selected Pattern LUT',
    'Name: embedded-pattern',
    'Export Pattern DDS',
    'Export Pattern Patch ZIP',
}) do
    assert(output.labels[label], 'Embedded Pattern omitted ' .. label)
end
assert(output.choices.pattern_lut, 'Embedded Pattern omitted destination selector')
hit(output, 'Import').callback()
hit(output, 'Export Pattern DDS').callback()
hit(output, 'Export Pattern Patch ZIP').callback()
assert(browsed == 1 and exported[1] == 'embedded-pattern' and exported[2] == ffi.string(pattern.document.data, 48))
assert(
    patched[1] == exported[1] and patched[2] == exported[2] and patched[3] == sources[101],
    'Embedded Pattern exports used a material LUT or wrong original resource'
)

pattern.column, pattern.raw = 2, false
ui, output = renderer(12)
pattern.workspace(ui, { x = 40, y = 50, w = 900, h = 1000 })
for _, id in ipairs({ 'pattern_metal_r', 'pattern_metal_g', 'pattern_metal_b', 'pattern_opacity' }) do
    assert(output.numbers[id] and output.numbers[id].enabled, 'Embedded Pattern omitted ' .. id)
end
pattern.column, pattern.raw = 3, false
ui, output = renderer(12)
pattern.workspace(ui, { x = 40, y = 50, w = 900, h = 1000 })
assert(next(output.numbers) == nil, 'Unknown Pattern controls ignore Advanced gate')
hit(output, '> Advanced: raw unknown values').callback()
ui, output = renderer(12)
pattern.workspace(ui, { x = 40, y = 50, w = 900, h = 1000 })
for _, id in ipairs({ 'pattern_unknown_r', 'pattern_unknown_g', 'pattern_unknown_b', 'pattern_unknown_a' }) do
    assert(output.numbers[id], 'Embedded Pattern omitted Advanced ' .. id)
end

-- Short viewports keep every action reachable through their own wheel and
-- draggable scrollbar, independently of material/Tools scroll offsets.
for _, font in ipairs({ 12, 20 }) do
    for _, width in ipairs({ 400, 900 }) do
        ui, output = renderer(font)
        local bounds = { x = 40, y = 50, w = width, h = 210 }
        pattern.scroll = 0
        pattern.workspace(ui, bounds)
        assert(pattern.maximum > 0 and output.bars.pattern_workspace, 'Short Pattern viewport has no scroll control')
        local first = pattern.scroll
        assert(
            pattern.wheel(60, 70, -120) and pattern.scroll > first and pattern.scroll <= 30,
            'Pattern wheel does not provide fine control'
        )
        assert(not pattern.wheel(5, 5, -120), 'Pattern wheel consumes a pointer outside its workspace')
        output.bars.pattern_workspace.callback(math.huge)
        assert(pattern.scroll == pattern.maximum)
        ui, output = renderer(font)
        pattern.workspace(ui, bounds)
        assert(
            output.labels['Name: embedded-pattern']
                and output.labels['Export Pattern DDS']
                and output.labels['Export Pattern Patch ZIP'],
            'Scrolling to end cannot reach Pattern exports'
        )
        assert(output.bars.pattern_workspace.offset == pattern.maximum)
    end
end
assert(
    pattern.close() and restored == 1 and objects[1].current == objects[1].original,
    'Embedded Pattern lifecycle close lost native restoration'
)
print(
    'PASS Pattern workspace: compact quick swatches, manual load gate, hosted controls, picker/raw/history ownership, exact exports and independent fine scrolling'
)
