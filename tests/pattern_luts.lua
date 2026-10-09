local Menu = dofile('vendor/menu/menu.lua')
local ffi = require('ffi')
local core = dofile('vendor/menu/core.lua')
local api = core.new({
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
})
local source = { width = 3, height = 1, data = ffi.new('float[12]') }
for i = 0, 11 do
    source.data[i] = i / 10
end
source.data[3], source.data[11] = 2.75, -0.25
local current, created, writes = 100, 200, 0
local binding = { unit = 1, mesh = 2, material = 3, helmet = true, slot = 987, save_key = '0:0:0:0' }
local deps = {
    present = function()
        return true
    end,
    binding = function(b)
        assert(b.slot == 987)
        return current
    end,
    key = function()
        return 'pattern'
    end,
    retain = { records = {}, cache = {}, bytes = 0 },
    create_texture = function(w, h, data)
        assert(w == 3 and h == 1)
        created = created + 1
        return { object = created }
    end,
    bind = function(b, object)
        assert(b.slot == 987, 'Pattern wrote into the material LUT slot')
        current = object
        writes = writes + 1
    end,
}
local session = dofile('src/gear/binding_session.lua').new(deps)
local exported
local pattern = dofile('src/editor/pattern_luts.lua').new({
    session = session,
    key = deps.key,
    binding = deps.binding,
    discover = function()
        return { binding }
    end,
    original = function(object)
        assert(object == 100)
        return source
    end,
    rgb = dofile('src/core/palette.lua').rgb,
    swatch = dofile('src/core/palette.lua').swatch,
    note = function(text)
        return text
    end,
    resource_id = function()
        return '[0x123]'
    end,
    export = function(name, document)
        exported = { name = name, pixels = ffi.string(document.data, 48) }
    end,
})
local handle = api.register({
    id = 'patterns',
    name = 'Patterns',
    pages = {
        {
            id = 'advanced',
            name = 'Material',
            controls = (function()
                local list = pattern.controls()
                list[#list + 1] = { id = 'show_alpha', type = 'toggle', label = 'Show Alpha', default = false }
                return list
            end)(),
        },
    },
})
pattern.attach(handle, api.mods.patterns.controls)
pattern.gear = 'helmet'
assert(handle.activate('pattern_load'))
assert(writes == 0, 'Loading original pattern changed native binding')
assert(handle.set('pattern_color', '#FF0000'))
assert(pattern.document.data[0] == 1 and pattern.document.data[1] == 0 and pattern.document.data[2] == 0)
assert(pattern.document.data[3] == 2.75 and pattern.document.data[11] == -0.25, 'Color edit changed unknown channels')
assert(handle.set('pattern_opacity', 0.4))
assert(math.abs(pattern.document.data[7] - 0.4) < 0.00001)
assert(handle.activate('pattern_undo'))
assert(pattern.document.data[7] == source.data[7])
assert(handle.activate('pattern_redo'))
assert(math.abs(pattern.document.data[7] - 0.4) < 0.00001)
local active_document, active_undo, active_redo, active_groups =
    pattern.document, pattern.undo, pattern.redo, pattern.groups
local background_groups = pattern.scan(true)
assert(#background_groups == 1 and background_groups[1].object == 100)
assert(
    pattern.document == active_document
        and pattern.undo == active_undo
        and pattern.redo == active_redo
        and pattern.groups == active_groups,
    'Appearance recovery changed Pattern editor state'
)
-- Real discovery returns fresh binding tables. Background recovery of a
-- still-live material must preserve the popup's ownership reference.
local reset_current, reset_created = 100, 1000
local reset_deps = {
    present = function()
        return true
    end,
    binding = function()
        return reset_current
    end,
    key = function(b)
        return b.unit .. ':' .. b.mesh .. ':' .. b.material
    end,
    retain = { records = {}, cache = {}, bytes = 0 },
    create_texture = function()
        reset_created = reset_created + 1
        return { object = reset_created }
    end,
    bind = function(_, object)
        reset_current = object
    end,
}
local reset_session = dofile('src/gear/binding_session.lua').new(reset_deps)
local reset_pattern = dofile('src/editor/pattern_luts.lua').new({
    session = reset_session,
    present = reset_deps.present,
    binding = reset_deps.binding,
    key = reset_deps.key,
    discover = function()
        return { { unit = 10, mesh = 20, material = 30, slot = 987, helmet = true, save_key = '0:0:0:0' } }
    end,
    original = function(object)
        assert(object == 100)
        return source
    end,
    rgb = dofile('src/core/palette.lua').rgb,
    note = function(text)
        return text
    end,
    resource_id = tostring,
})
local reset_api = core.new({
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
})
local reset_controls = reset_pattern.controls()
reset_controls[#reset_controls + 1] = { id = 'show_alpha', type = 'toggle', label = 'Show Alpha', default = false }
local reset_handle = reset_api.register({
    id = 'reset_pattern',
    name = 'Pattern reset',
    pages = { { id = 'advanced', name = 'Pattern', controls = reset_controls } },
})
reset_pattern.attach(reset_handle, reset_api.mods[reset_handle.id].controls)
reset_pattern.gear = 'helmet'
assert(reset_handle.activate('pattern_load') and reset_handle.set('pattern_color', '#FF0000'))
local popup_binding = reset_pattern.groups[1].bindings[1]
local remembered_texture = popup_binding.texture
reset_current = 100
local reset_groups = reset_pattern.scan(true)
assert(reset_groups[1].bindings[1] == popup_binding, 'Background reset replaced the active popup binding')
assert(popup_binding.current == 100 and popup_binding.texture == nil and popup_binding.document == nil)
reset_session.apply(remembered_texture, reset_groups[1].bindings)
assert(reset_handle.set('pattern_color', '#00FF00'))
assert(
    reset_session.owned[1] == popup_binding and reset_session.owned[1].current == reset_current,
    'Editing after background replay lost native Pattern ownership'
)
assert(
    reset_pattern.close() and reset_current == 100,
    'Pattern close falsely reported restoration after recovered popup edits'
)
local imported = { width = 3, height = 1, data = ffi.new('float[12]') }
imported.data[0], imported.data[7] = 0.25, 0.8
local before_import = current
assert(pattern.import(imported))
assert(current == before_import, 'Import applied before explicit button')
assert(handle.activate('pattern_import_apply'))
assert(pattern.document.data[0] == imported.data[0] and pattern.document.data[7] == imported.data[7])
assert(handle.activate('pattern_export'))
assert(exported and #exported.pixels == 48)
assert(pattern.close() and current == 100)
pattern.gear = 'helmet'
assert(handle.activate('pattern_load'))
assert(handle.set('pattern_color', '#00FF00'))
current = 999 -- A competing mod now owns the binding.
assert(pattern.close() and current == 999, 'Pattern restore overwrote a foreign binding')
print(
    'PASS Pattern LUTs: separate native slot, 3x1 values, unknown-channel preservation, undo/redo, export and foreign ownership'
)

pattern.show('helmet')
local palette = dofile('src/core/palette.lua')
local rects, labels = {}, {}
local ui = Menu.custom_ui({
    rect = function(x, y, w, h, c, a, role)
        rects[#rects + 1] = { x = x, y = y, w = w, h = h, c = c, role = role }
    end,
    bounded = function(x, y, text)
        labels[text] = true
    end,
    hit = function() end,
    choice = function() end,
    number = function() end,
    activate = function() end,
    floating = function(id, draw, w, h, close)
        assert(id == 'pattern_lut_editor')
        draw(0, 0, w, h)
    end,
})
pattern.popup(ui)
local borders = 0
for _, rect in ipairs(rects) do
    if rect.role == 'swatch_border' then
        borders = borders + 1
        assert(rect.h == 50, 'Pattern border role attached to an unrelated background')
    end
end
assert(borders == 3, 'Pattern swatches do not distinguish borders from color fills')
assert(
    labels['Pattern LUT Editor']
        and labels['1: Accent color']
        and labels['2: Material / opacity']
        and labels['3: Unknown']
)
local unchanged = ffi.string(pattern.document.data, 48)
assert(handle.set('show_alpha', true))
pattern.popup(ui)
assert(ffi.string(pattern.document.data, 48) == unchanged, 'Show Alpha changed LUT values')
local samples = {}
local display = {
    rect = function(x, y, w, h, c, a, role)
        assert(role == 'swatch_fill', 'Solid/checker palette primitive lost its fill role')
        samples[#samples + 1] = c
    end,
}
palette.swatch(display, 0, 0, 10, 10, { 255, 0, 0 }, 0, true)
assert(#samples == 4 and samples[1][1] == 220 and samples[2][1] == 125, 'Transparent swatch does not show checkerboard')
samples = {}
palette.swatch(display, 0, 0, 10, 10, { 255, 0, 0 }, 1, true)
assert(#samples == 1 and samples[1][1] == 255, 'Opaque swatch was checkerboard')

pattern.column = 2
local picker = api.mods.patterns.controls.pattern_picker
local pattern_before = ffi.string(pattern.document.data, 48)
local pattern_history = #pattern.undo
pattern.column, pattern.raw = 3, false
assert(
    picker.can_open_picker() == false and not pcall(picker.picker_begin),
    'Unknown Pattern channels opened without the Advanced raw gate'
)
assert(
    ffi.string(pattern.document.data, 48) == pattern_before and #pattern.undo == pattern_history,
    'Protected Pattern picker mutated pixels/history'
)
pattern.raw = true
assert(picker.can_open_picker() == true, 'Advanced raw gate did not enable Pattern picker')
pattern.document.read_only = true
assert(picker.can_open_picker() == false, 'Read-only Pattern opened its picker')
pattern.document.read_only = nil
pattern.column, pattern.raw = 2, false
assert(picker.picker_commit({ 255, 0, 0 }, 0.6))
assert(pattern.document.data[4] == 1 and math.abs(pattern.document.data[7] - 0.6) < 0.00001)
assert(picker.picker_alpha() == tonumber(pattern.document.data[7]))
assert(handle.activate('pattern_undo'))

current = binding.original -- Simulate the game resetting an already-edited pattern to its original.
assert(api.mods.patterns.controls.pattern_picker.picker_commit({ 0, 0, 255 }, 1))
assert(current ~= binding.original, 'Known original reset prevented Use Color')
current = 123456 -- A different writer owns this slot now.
assert(
    not pcall(api.mods.patterns.controls.pattern_picker.picker_commit, { 255, 0, 255 }, 1),
    'Unexpected binding was overwritten'
)
assert(current == 123456)

-- Armor/Helmet switching must clear unavailable values and finish an async load.
local ready_helmet = false
local armor_pixels, helmet_pixels = ffi.new('float[12]'), ffi.new('float[12]')
armor_pixels[0], helmet_pixels[0] = 0.1, 0.8
local tab_pattern = dofile('src/editor/pattern_luts.lua').new({
    session = {
        owned = {},
        restore = function()
            return true
        end,
    },
    key = function(b)
        return b.material
    end,
    binding = function(b)
        return b.material
    end,
    discover = function()
        return { { material = 400, armor = true, helmet = false }, { material = 500, armor = false, helmet = true } }
    end,
    original = function(object)
        if object == 500 and not ready_helmet then
            return nil
        end
        return { width = 3, height = 1, data = object == 400 and armor_pixels or helmet_pixels }
    end,
    resource_id = function(object)
        return '[' .. object .. ']'
    end,
    rgb = dofile('src/core/palette.lua').rgb,
    note = function(t)
        return t
    end,
})

local tabs_handle = api.register({
    id = 'pattern_tabs_test',
    name = 'Tabs',
    pages = {
        { id = 'p', name = 'Patterns', controls = tab_pattern.controls() },
    },
})
tab_pattern.attach(tabs_handle, api.mods.pattern_tabs_test.controls)
assert(tabs_handle.activate('pattern_load'))
assert(math.abs(tab_pattern.document.data[0] - 0.1) < 0.00001)
assert(tab_pattern.switch('helmet'))
assert(
    tab_pattern.document == nil and tab_pattern.waiting,
    'Old Armor values remained visible while Helmet was loading'
)
ready_helmet = true
tab_pattern.tick(0.3)
assert(tab_pattern.gear == 'helmet' and math.abs(tab_pattern.document.data[0] - 0.8) < 0.00001)
assert(tab_pattern.switch('armor') and math.abs(tab_pattern.document.data[0] - 0.1) < 0.00001)

-- Clicking Flash again must snapshot the restored binding, never the previous magenta texture.
current = 100
local indicator = dofile('src/gear/region_indicator.lua').new({
    present = deps.present,
    binding = deps.binding,
    apply = session.apply,
    bind = deps.bind,
})
local flashing = dofile('src/editor/pattern_luts.lua').new({
    session = session,
    indicator = indicator,
    key = deps.key,
    binding = deps.binding,
    discover = function()
        return { binding }
    end,
    original = function()
        return source
    end,
    rgb = dofile('src/core/palette.lua').rgb,
    note = function(t)
        return t
    end,
    resource_id = function()
        return '[pattern]'
    end,
})
local fh = api.register({
    id = 'pattern_flash_test',
    name = 'Flash',
    pages = {
        { id = 'p', name = 'Pattern', controls = flashing.controls() },
    },
})
flashing.attach(fh, api.mods.pattern_flash_test.controls)
flashing.show('helmet')
assert(fh.activate('pattern_load'))
flashing.flash()
assert(current ~= 100)
flashing.flash()
assert(current ~= 100)
flashing.tick(4.1)
assert(current == 100 and not flashing.flashing(), 'Repeated Flash captured magenta as its restore target')

current = 100
pattern.show('helmet')
local pcontrol = api.mods.patterns.controls.pattern_picker
local old_pixels = ffi.string(pattern.document.data, 48)
pcontrol.picker_begin()
pcontrol.picker_preview({ 1, 99, 201 }, 0.5)
assert(ffi.string(pattern.document.data, 48) ~= old_pixels)
pcontrol.picker_end(false)
assert(ffi.string(pattern.document.data, 48) == old_pixels, 'Pattern picker cancel did not restore its values')

-- A pending destination cannot be replaced by importing blindly, and an import
-- keeps all previous edits in the same history instead of recreating the table.
current = 100
assert(pattern.show('helmet'))
local doc_before_import = pattern.document
assert(handle.set('pattern_opacity', 0.2))
local history_before_import = #pattern.undo
local before_import_pixels = ffi.string(pattern.document.data, 48)
assert(pattern.import(imported))
assert(handle.activate('pattern_import_apply'))
assert(pattern.document == doc_before_import and #pattern.undo == history_before_import + 1)
assert(handle.activate('pattern_undo'))
assert(ffi.string(pattern.document.data, 48) == before_import_pixels, 'Import lost the current table history')

local controls = api.mods.patterns.controls
local before_noop_writes, before_noop_history = writes, #pattern.undo
assert(controls.pattern_opacity.on_change(tonumber(pattern.document.data[7])))
assert(
    writes == before_noop_writes and #pattern.undo == before_noop_history,
    'An unchanged field allocated a texture or added history'
)
assert(not pcall(pattern.import, { width = 23, height = 1, data = source.data }))
local invalid = ffi.new('float[12]')
invalid[0] = 0 / 0
assert(not pcall(pattern.import, { width = 3, height = 1, data = invalid }), 'NaN imported into the pattern table')

-- Picker preview failures must roll CPU values back and never claim a foreign
-- texture. Opening a picker also stops a flash before capturing its baseline.
pattern.column = 1
controls.pattern_picker.picker_begin()
local picker_before = ffi.string(pattern.document.data, 48)
local owned_object = current
current = 54321
assert(not pcall(controls.pattern_picker.picker_preview, { 255, 1, 2 }, 0.25))
assert(ffi.string(pattern.document.data, 48) == picker_before and current == 54321)
controls.pattern_picker.picker_end(false)
current = owned_object
assert(handle.activate('pattern_redo'))
assert(#pattern.redo == 0)
assert(handle.activate('pattern_undo'))
assert(#pattern.redo > 0)
controls.pattern_picker.picker_begin()
controls.pattern_picker.picker_preview({ 123, 42, 17 }, 0.75)
controls.pattern_picker.picker_end(true)
assert(#pattern.redo == 0 and controls.pattern_redo.disabled)
assert(pattern.show('helmet'))
assert(#pattern.redo == 0, 'Picker commit resurrected old redo after reloading a cached table')

current = 100
flashing.show('helmet')
flashing.flash()
local flash_control = api.mods.pattern_flash_test.controls.pattern_picker
flash_control.picker_begin()
assert(current == 100 and not flashing.flashing(), 'Picker captured the flashing magenta table')
flash_control.picker_preview({ 20, 30, 40 }, 1)
flash_control.picker_end(false)
assert(
    ffi.string(flashing.document.data, 48) == ffi.string(source.data, 48),
    'Flash picker cancel changed pattern pixels'
)

ready_helmet = false
tab_pattern.documents['helmet:500'] = nil
assert(tab_pattern.switch('helmet'))
assert(tab_pattern.document == nil)
tab_pattern.import(imported)
assert(api.mods.pattern_tabs_test.controls.pattern_import_apply.disabled)
assert(
    not pcall(api.mods.pattern_tabs_test.controls.pattern_import_apply.on_activate),
    'Import applied without a loaded destination'
)

-- The open popup refreshes only twice per second when worn gear changes. It
-- clears unavailable data instead of leaving the previous garment's table.
local signature, selected_material, scans = 'kit-a', 400, 0
local refresh = dofile('src/editor/pattern_luts.lua').new({
    session = {
        owned = {},
        restore = function()
            return true
        end,
    },
    key = function(b)
        return b.material
    end,
    binding = function(b)
        return b.material
    end,
    gear_signature = function()
        return signature
    end,
    present = function()
        return true
    end,
    discover = function()
        scans = scans + 1
        return { { material = selected_material, armor = true } }
    end,
    original = function(object)
        return object == 400 and { width = 3, height = 1, data = armor_pixels } or nil
    end,
    resource_id = function(object)
        return tostring(object)
    end,
    rgb = dofile('src/core/palette.lua').rgb,
    note = function(t)
        return t
    end,
})
local rh = api.register({
    id = 'pattern_refresh_test',
    name = 'Refresh',
    pages = { { id = 'p', name = 'Pattern', controls = refresh.controls() } },
})
refresh.attach(rh, api.mods.pattern_refresh_test.controls)
refresh.show('armor')
assert(scans == 0 and refresh.document == nil and not refresh.ready)
assert(rh.activate('pattern_load'))
assert(scans == 1 and refresh.document)
for i = 1, 20 do
    refresh.tick(0.01)
end
assert(scans == 1, 'Pattern discovery ran for every frame')
signature, selected_material = 'kit-b', 500
refresh.tick(0.31)
assert(scans == 2 and refresh.document == nil and refresh.waiting)
refresh.close()
refresh.tick(1)
assert(scans == 2 and refresh.document == nil, 'Closed popup kept rediscovering worn gear')
print(
    'PASS Pattern robustness: import readiness/history, cached picker undo, flash/cancel, foreign ownership, exact unknown floats, throttled gear refresh'
)

-- Optional refresh failures stay within the Pattern popup instead of escaping the menu click.
local bad_signature = dofile('src/editor/pattern_luts.lua').new({
    auto_populate = function()
        return true
    end,
    gear_signature = function()
        error('identity not ready')
    end,
    note = function(t)
        return t
    end,
    session = {
        owned = {},
        restore = function()
            return true
        end,
    },
    discover = function()
        return {}
    end,
    key = function(b)
        return b.material
    end,
    binding = function()
        return 0
    end,
    rgb = dofile('src/core/palette.lua').rgb,
    original = function()
        return nil
    end,
    resource_id = tostring,
})
local bad_handle = api.register({
    id = 'pattern_bad_identity',
    name = 'Pattern',
    pages = { { id = 'p', name = 'Pattern', controls = bad_signature.controls() } },
})
bad_signature.attach(bad_handle, api.mods[bad_handle.id].controls)
assert(pcall(bad_signature.show), 'Identity failure escaped Pattern open')
assert(pcall(bad_signature.switch, 'armor'), 'Identity failure escaped Armor button')
assert(pcall(bad_signature.tick, 0.5), 'Identity failure escaped Pattern poll')
assert(bad_signature.open and bad_signature.document == nil, 'Failed identity left unsafe editable values')

-- Startup guidance is explicit: no discovery or enabled gear selectors before
-- a successful manual load/import. Only the Load button flashes, and its saved
-- cue can be reset without changing the automatic-populate preference.
local cue_seen, cue_auto, cue_scans, cue_marks = false, false, 0, 0
local cue_sources, cue_bindings = {}, {}
for i = 1, 8 do
    local data = ffi.new('float[12]')
    for j = 0, 11 do
        data[j] = i + j / 100
    end
    cue_sources[600 + i] = { width = 3, height = 1, data = data }
    cue_bindings[i] = { material = 600 + i, armor = i <= 4, helmet = i > 4 }
end
local cue = dofile('src/editor/pattern_luts.lua').new({
    session = {
        owned = {},
        restore = function()
            return true
        end,
    },
    auto_populate = function()
        return cue_auto
    end,
    load_seen = function()
        return cue_seen
    end,
    mark_load_seen = function()
        cue_seen = true
        cue_marks = cue_marks + 1
    end,
    key = function(b)
        return b.material
    end,
    binding = function(b)
        return b.material
    end,
    discover = function()
        cue_scans = cue_scans + 1
        return cue_bindings
    end,
    original = function(object)
        return cue_sources[object]
    end,
    resource_id = tostring,
    rgb = palette.rgb,
    swatch = palette.swatch,
    note = function(t)
        return t
    end,
})
local cue_list = cue.controls()
cue_list[#cue_list + 1] = { id = 'show_alpha', type = 'toggle', label = 'Alpha', default = false }
local ch = api.register({
    id = 'pattern_cue_test',
    name = 'Cue',
    pages = { { id = 'p', name = 'Pattern', controls = cue_list } },
})
local cc = api.mods[ch.id].controls
cue.attach(ch, cc)
cue.show('armor')
assert(cue.document == nil and cue_scans == 0 and cc.pattern_lut.disabled)
assert(not cue.switch('helmet') and cue_scans == 0 and cue.gear == 'armor')
local button_colors, hits = {}, {}
local cu = Menu.custom_ui({
    rect = function(x, y, w, h, color)
        if y == 634 then
            button_colors[x] = color
        end
    end,
    bounded = function() end,
    number = function() end,
    choice = function() end,
    activate = ch.activate,
    hit = function(x, y, w, h, callback)
        if y == 634 then
            hits[x] = callback
        end
    end,
    floating = function(_, draw, w, h)
        draw(0, 0, w, h)
    end,
})
cue.popup(cu)
assert(
    button_colors[12] == Menu.palette.panel and button_colors[144] == Menu.palette.panel,
    'Unloaded Pattern tabs were not gray'
)
hits[144]()
assert(cue_scans == 0 and cue.gear == 'armor', 'Gray Helmet button still discovered live data')
assert(button_colors[284][1] == 244 and button_colors[284][2] ~= 202, 'First-load cue was not flashing gold')
cue.tick(0.2)
assert(cue_scans == 0, 'Unloaded Pattern popup auto-discovered despite manual-load setting')
assert(ch.activate('pattern_load'))
assert(cue.ready and cue.document and cue_marks == 1 and cue_seen and not cc.pattern_lut.disabled)
cue.popup(cu)
assert(button_colors[12] ~= Menu.palette.panel and button_colors[144] ~= Menu.palette.panel)
assert(button_colors[284][1] == 244 and button_colors[284][2] == 202, 'Load button did not stay gold after first press')
for _, gear in ipairs({ 'armor', 'helmet' }) do
    assert(cue.switch(gear))
    for i = 1, 4 do
        assert(ch.set('pattern_lut', i))
        assert(cue.document.data[0] == (gear == 'armor' and i or i + 4))
    end
end
assert((function()
    local count = 0
    for _ in pairs(cue.documents) do
        count = count + 1
    end
    return count
end)() == 8, 'Pattern table caches mixed Armor and Helmet values')
cue_seen = false
cue.popup(cu)
assert(button_colors[284][2] ~= 202, 'Reset Load cue did not override the in-memory seen state')
assert(cue.close() and not cue.ready and cc.pattern_lut.disabled)
cue_auto = true
cue.show('armor')
assert(cue.document and cue.ready, 'Automatic populate did not bypass manual-load guidance')
cue.close()
cue_auto = false
cue.import(source)
assert(cue.ready and not cue.document, 'A valid imported Pattern did not enable gear selection')
cue.show('helmet')
assert(cue.document and cue.gear == 'helmet')
print(
    'PASS Pattern startup guidance: manual readiness, gray selectors, resettable gold cue, automatic populate, exact eight-table caches'
)
