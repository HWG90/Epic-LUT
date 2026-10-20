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
local exported, patched
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
        exported = { name = name, document = document, pixels = ffi.string(document.data, 48) }
    end,
    export_patch = function(name, document, original)
        patched = { name = name, document = document, original = original, pixels = ffi.string(document.data, 48) }
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

local scalar = api.mods.patterns.controls.pattern_opacity
local start = ffi.string(pattern.document.data, 48)
local count = #pattern.undo
local starting_setting = handle.get('pattern_opacity')
local gesture = scalar.slider_begin()
scalar.slider_preview(gesture, 0.25)
scalar.slider_preview(gesture, 0.75)
assert(pattern.document.data[7] == 0.75 and #pattern.undo == count and writes > 0
    and handle.get('pattern_opacity') == starting_setting,
    'Pattern slider failed to preview natively without intermediate history')
scalar.slider_end(gesture, true)
assert(#pattern.undo == count + 1)
assert(handle.activate('pattern_undo'))
assert(ffi.string(pattern.document.data, 48) == start, 'Pattern slider Undo missed its starting pixels')
assert(handle.activate('pattern_redo') and pattern.document.data[7] == 0.75)
assert(handle.activate('pattern_undo'))
gesture = scalar.slider_begin()
scalar.slider_preview(gesture, 0.125)
scalar.slider_end(gesture, false)
assert(ffi.string(pattern.document.data, 48) == start and #pattern.undo == count)
print('PASS Pattern scalar drag: native preview, endpoint Undo/Redo and cancellation')
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
        and labels['3: Roughness (A)']
)
local unchanged = ffi.string(pattern.document.data, 48)
assert(handle.set('show_alpha', true))
pattern.popup(ui)
assert(ffi.string(pattern.document.data, 48) == unchanged, 'Show Alpha changed LUT values')
-- Export must be reachable through the floating Pattern window. Activating a
-- registry button directly does not catch controls omitted from the renderer.
local export_hits, export_labels, activated = {}, {}, {}
local export_ui = Menu.custom_ui({
    rect = function() end,
    bounded = function(_, _, text)
        export_labels[text] = true
    end,
    hit = function(x, y, w, h, callback)
        export_hits[y .. ':' .. x] = { callback = callback, x = x, y = y, w = w, h = h }
    end,
    choice = function() end,
    number = function() end,
    input_value = handle.get,
    activate = function(id)
        activated[#activated + 1] = id
        if id == 'pattern_export_name' then
            assert(handle.set(id, 'Pattern-popup-export'))
        else
            assert(handle.activate(id))
        end
    end,
    floating = function(id, draw, w, h)
        assert(id == 'pattern_lut_editor' and w == 580 and h == 700, 'Pattern export enlarged the floating window')
        draw(0, 0, w, h)
    end,
})
pattern.popup(export_ui)
local name_hit, dds_hit, patch_hit = export_hits['112:12'], export_hits['76:12'], export_hits['76:293']
assert(name_hit and dds_hit and patch_hit, 'Pattern export name/DDS/Patch controls are missing from the popup')
assert(
    export_labels['Name: Epic-LUT-pattern']
        and export_labels['Export Pattern DDS']
        and export_labels['Export Pattern Patch ZIP']
)
local import_hit = assert(export_hits['162:12'], 'Pattern import was lost while adding exports')
assert(
    dds_hit.y + dds_hit.h < name_hit.y
        and name_hit.y + name_hit.h < 150
        and 150 < import_hit.y
        and import_hit.y + import_hit.h < 190
        and dds_hit.y > 12 + 11,
    'Pattern import/export controls overlap each other, the imported swatches, or status text'
)
name_hit.callback()
pattern.popup(export_ui)
assert(export_labels['Name: Pattern-popup-export'], 'Pattern export name edit is not displayed')
local popup_document = pattern.document
dds_hit.callback()
patch_hit.callback()
assert(
    table.concat(activated, ',') == 'pattern_export_name,pattern_export,pattern_export_patch',
    'Pattern popup routed an export to the main material editor'
)
assert(
    exported.name == 'Pattern-popup-export'
        and exported.document == popup_document
        and exported.document.width == 3
        and exported.document.height == 1
        and exported.pixels == ffi.string(popup_document.data, 48),
    'Pattern DDS popup export used the wrong document or name'
)
assert(
    patched.name == exported.name
        and patched.document == popup_document
        and patched.original == source
        and patched.pixels == exported.pixels,
    'Pattern patch popup export used the wrong selected 3x1 document or original resource'
)
pattern.document = nil
pattern.popup(export_ui)
export_hits['76:12'].callback()
export_hits['76:293'].callback()
assert(#activated == 3, 'Unloaded Pattern export buttons remained clickable')
pattern.document = popup_document
print(
    'PASS Pattern popup exports: editable name, reachable DDS/Patch actions, exact resource, disabled state and compact layout'
)
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
    picker.can_open_picker() == true and picker.picker_channel_enabled(4),
    'Roughness alpha is unavailable without the Advanced raw gate'
)
for channel = 1, 3 do
    assert(not picker.picker_channel_enabled(channel), 'Roughness picker exposed unknown RGB without Advanced')
end
assert(
    ffi.string(pattern.document.data, 48) == pattern_before and #pattern.undo == pattern_history,
    'Checking Roughness picker permissions mutated pixels/history'
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
local button_colors, hits, cue_export_attempts = {}, {}, 0
local cu = Menu.custom_ui({
    rect = function(x, y, w, h, color)
        if y == 634 then
            button_colors[x] = color
        end
    end,
    bounded = function() end,
    number = function() end,
    choice = function() end,
    activate = function(id)
        if id == 'pattern_export_patch' then
            cue_export_attempts = cue_export_attempts + 1
        end
        return ch.activate(id)
    end,
    hit = function(x, y, w, h, callback)
        if y == 634 then
            hits[x] = callback
        elseif y == 76 and x == 293 then
            hits.patch = callback
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
assert(hits.patch and cc.pattern_export_patch.disabled, 'Unavailable Pattern patch exporter was not rendered disabled')
hits.patch()
assert(cue_export_attempts == 0, 'Pattern popup activated a missing patch exporter')
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

-- The Quick strip initializes from already loaded material targets during
-- update, including delayed snapshots. Drawing never starts native discovery.
do
    local ready, kind, focus = false, 'armor', '20'
    local objects, cached, created, writes, discovery, reads = { [10] = 10, [20] = 20, [30] = 30 }, {}, 40, 0, 0, 0
    local targets = {
        { material = 10, armor = true },
        { material = 20, armor = true },
        { material = 30, helmet = true },
    }
    local function original(r, g, b)
        local data = ffi.new('float[12]')
        data[0], data[1], data[2], data[3] = r, g, b, 1
        data[4], data[5], data[6], data[7] = 0.25, 0.5, 0.75, 1
        data[8], data[9], data[10], data[11] = 0.123, -7, 8, 9
        return { width = 3, height = 1, data = data }
    end
    local red, blue, green = original(1, 0, 0), original(0, 0, 1), original(0, 1, 0)
    cached[10], cached[30] = red, green
    local session = { owned = {} }
    session.apply = function(document, bindings)
        for _, b in ipairs(bindings) do
            created, writes = created + 1, writes + 1
            objects[b.material], b.current, b.document = created, created, document
            session.owned = { b }
        end
    end
    local colors = {}
    local quick = dofile('src/editor/pattern_luts.lua').new({
        session = session,
        key = function(b)
            return tostring(b.material)
        end,
        binding = function(b)
            return objects[b.material]
        end,
        discover = function()
            discovery = discovery + 1
            error('Quick strip attempted full discovery')
        end,
        original = function()
            reads = reads + 1
            error('Quick strip requested an uncached original')
        end,
        cached_original = function(object)
            return cached[object]
        end,
        quick_bindings = function()
            if ready then
                return kind, kind == 'armor' and { targets[1], targets[2] } or { targets[3] }, focus
            end
        end,
        gear_signature = function()
            error('Quick drawing rediscovered gear identity')
        end,
        resource_id = tostring,
        note = function(text)
            return text
        end,
        rgb = palette.rgb,
        swatch = function(_, _, _, _, _, color)
            colors[#colors + 1] = color
        end,
    })
    local list = quick.controls()
    list[#list + 1] = { id = 'show_alpha', type = 'toggle', label = 'Alpha', default = false }
    local h = api.register({
        id = 'pattern_quick_init',
        name = 'Quick',
        pages = { { id = 'p', name = 'Pattern', controls = list } },
    })
    quick.attach(h, api.mods[h.id].controls)
    local ui = {
        theme = { muted = { 80, 80, 80 }, white = { 255, 255, 255 } },
        bounded = function() end,
        rect = function() end,
        hit = function() end,
    }
    local bounds = { x = 0, y = 0, w = 300, h = 60, cell_width = 28, row_height = 28 }
    quick.quick(ui, bounds, 'armor')
    quick.tick(0)
    assert(discovery == 0 and reads == 0 and not quick.requested and quick.document == nil)
    assert(colors[1][1] == 80, 'Unloaded Quick strip showed a fake black palette')
    ready = true
    quick.tick(1, true)
    assert(not quick.requested and quick.document == nil, 'Deferred Quick hydration competed with recovery work')
    quick.tick(0)
    assert(quick.waiting and not quick.document and not quick.is_open())
    cached[20] = blue
    quick.tick(0.25)
    assert(quick.document and quick.document.data[2] == 1 and h.get('pattern_lut') == 2)
    assert(writes == 0 and reads == 0 and discovery == 0, 'Quick initialization wrote gear or started discovery')
    colors = {}
    quick.quick(ui, bounds, 'armor')
    assert(#colors == 3 and colors[1][3] == 255 and colors[2][2] == 128)
    assert(h.set('pattern_color', '#FFFF00'))
    local edited, undo = quick.document, quick.undo
    quick.tick(0.5)
    assert(quick.document == edited and quick.undo == undo and #undo == 1, 'Quick hydration discarded cached edits')
    assert(ffi.string(quick.document.data + 8, 16) == ffi.string(blue.data + 8, 16))
    kind, focus = 'helmet', '30'
    quick.color_session = {}
    quick.tick(0.5)
    assert(quick.document == edited, 'Quick hydration replaced a live color-picker document')
    quick.color_session = nil
    quick.tick(0.5)
    assert(quick.gear == 'helmet' and quick.document.data[1] == 1)
    colors = {}
    quick.quick(ui, bounds, 'armor')
    assert(colors[1][1] == 80, 'Quick drawing showed another gear family before update')
    kind, focus = 'armor', '10'
    quick.tick(0.5)
    assert(quick.document.data[0] == 1 and quick.document.data[1] == 0 and h.get('pattern_lut') == 1)
    focus = '20'
    quick.tick(0.5)
    assert(quick.document == edited and quick.undo == undo and h.get('pattern_lut') == 2)
    assert(writes == 1 and reads == 0 and discovery == 0 and not quick.is_open())
end
print(
    'PASS Pattern Quick initialization: cached snapshots, async readiness, selected slot/gear, edits/history and no draw discovery'
)

-- Roughness is column 3 Alpha. Its normal picker must preserve every other
-- float bit, including HDR/out-of-range RGB and signed zero in unknown RGB.
do
    local stock = { width = 3, height = 1, data = ffi.new('float[12]') }
    for index = 0, 11 do
        stock.data[index] = (index - 5) * 0.37
    end
    stock.data[3], stock.data[7] = 2.75, -0.25
    stock.data[8], stock.data[9], stock.data[11] = 3.125, -2.5, 0.6
    ffi.cast('uint32_t *', stock.data)[10] = 0x80000000
    local target = { original = 900, current = 900, material = 901, armor = true }
    local current, writes = 900, 0
    local roughness = dofile('src/editor/pattern_luts.lua').new({
        session = {
            owned = {},
            apply = function(document, bindings)
                assert(current == target.current, 'Foreign Roughness binding')
                writes = writes + 1
                current, target.current = 1000 + writes, 1000 + writes
                target.texture = { object = current, width = 3, height = 1, data = document.data }
                target.document = document
            end,
            restore = function()
                return true
            end,
        },
        discover = function()
            return { target }
        end,
        key = function(binding)
            return binding.material
        end,
        binding = function()
            return current
        end,
        present = function()
            return true
        end,
        original = function()
            return stock
        end,
        resource_id = function(object)
            return tostring(object)
        end,
        rgb = dofile('src/core/palette.lua').rgb,
        note = function(value)
            return value
        end,
    })
    local definitions = roughness.controls()
    definitions[#definitions + 1] = { id = 'show_alpha', type = 'toggle', label = 'Show Alpha', default = false }
    local h = api.register({
        id = 'roughness_regression',
        name = 'Roughness',
        pages = { { id = 'p', name = 'Pattern', controls = definitions } },
    })
    local controls = api.mods[h.id].controls
    roughness.attach(h, controls)
    assert(roughness.prime('armor'))
    roughness.column, roughness.raw = 3, false
    local picker = controls.pattern_picker
    assert(picker.can_open_picker() and picker.picker_channel_enabled(4), 'Roughness Alpha requires Advanced')
    for channel = 1, 3 do
        assert(not picker.picker_channel_enabled(channel), 'Roughness exposes unknown RGB channels')
    end
    local before = ffi.string(roughness.document.data, 48)
    local before_history = #roughness.undo
    picker.picker_begin()
    assert(writes == 0 and #roughness.undo == before_history, 'Opening Roughness changed the document/history')
    picker.picker_preview({ 255, 0, 127 }, 0.2)
    assert(
        ffi.string(roughness.document.data, 48):sub(1, 44) == before:sub(1, 44),
        'Roughness preview changed RGB or other Alpha'
    )
    assert(math.abs(roughness.document.data[11] - 0.2) < 0.00001)
    picker.picker_end(false)
    assert(
        ffi.string(roughness.document.data, 48) == before and #roughness.undo == before_history,
        'Roughness cancel did not restore exact pixels/history'
    )

    picker.picker_begin()
    picker.picker_preview({ 0, 255, 0 }, 0.3)
    picker.picker_preview({ 1, 2, 3 }, 0.4)
    picker.picker_end(true)
    local committed = ffi.string(roughness.document.data, 48)
    assert(
        committed:sub(1, 44) == before:sub(1, 44) and committed ~= before,
        'Roughness commit changed channels besides Alpha'
    )
    assert(#roughness.undo == before_history + 1, 'Continuous Roughness preview did not produce exactly one Undo')
    assert(ffi.cast('uint32_t *', roughness.document.data)[10] == 0x80000000, 'Roughness erased signed-zero RGB')
    assert(h.activate('pattern_undo') and ffi.string(roughness.document.data, 48) == before)
    assert(h.activate('pattern_redo') and ffi.string(roughness.document.data, 48) == committed)

    local unchanged_writes, unchanged_history = writes, #roughness.undo
    assert(picker.picker_commit({ 254, 253, 252 }, picker.picker_alpha()))
    assert(
        writes == unchanged_writes and #roughness.undo == unchanged_history,
        'Unchanged Roughness allocated/uploaded a texture or added history'
    )
    picker.picker_begin()
    picker.picker_preview({ 0, 0, 0 }, picker.picker_alpha())
    picker.picker_end(true)
    assert(
        writes == unchanged_writes and #roughness.undo == unchanged_history,
        'Unchanged Roughness preview added writes/history'
    )

    assert(picker.picker_commit({ 0, 255, 255 }, 0))
    assert(roughness.document.data[11] == 0 and ffi.string(roughness.document.data, 48):sub(1, 44) == before:sub(1, 44))
    assert(h.set('pattern_unknown_a', 2.75), 'Roughness scalar lost finite raw-value support')
    assert(
        roughness.document.data[11] == 2.75 and ffi.string(roughness.document.data, 48):sub(1, 44) == before:sub(1, 44)
    )

    roughness.document.read_only = true
    assert(not picker.can_open_picker() and not pcall(picker.picker_begin))
    roughness.document.read_only = nil
    roughness.document.stale = true
    assert(not picker.can_open_picker() and not pcall(picker.picker_begin))
    roughness.document.stale = nil
    picker.picker_begin()
    local foreign_before = ffi.string(roughness.document.data, 48)
    current = 7777
    assert(not pcall(picker.picker_preview, { 20, 30, 40 }, 0.1), 'Roughness overwrote a foreign native binding')
    assert(
        current == 7777 and ffi.string(roughness.document.data, 48) == foreign_before,
        'Failed Roughness preview changed CPU pixels or claimed a foreign texture'
    )
    picker.picker_end(false)
end
print(
    'PASS Roughness Alpha: exact other-channel bits, live preview/cancel, one Undo, zero/raw numeric values, no-op and ownership guards'
)
