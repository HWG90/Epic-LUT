-- Controller integration: simulated actor/material lifetimes, actual discovery/ownership/intent logic.
local ffi = require('ffi')
local core = dofile('vendor/menu/core.lua')
local D = dofile('src/core/dds.lua')
local History = dofile('src/core/action_history.lua')
local Pattern = dofile('src/editor/pattern_luts.lua')
local store = {
    load = function()
        return {}
    end,
    save = function()
        return true
    end,
}
local api = core.new(store)
local scene = true
local kits = { body = 7, armor = 21, helmet = 22 }
local units, materials, live, bound, metadata = {}, {}, {}, {}, {}
local created, binds, history, pattern, frontend = 0, 0, nil, nil, nil
local saved_defaults
api.focus_page = function(id, page_id)
    for index, page in ipairs(api.mods[id].pages) do
        if page.id == page_id then
            frontend.menu.page = index
            return true
        end
    end
    return false
end
local hashes = { '0000000000000100', '0000000000000200', '0000000000000300', '0000000000000400' }
local originals = {}
for i = 1, 4 do
    local width = i <= 2 and 23 or 3
    local d = {
        width = width,
        height = i <= 2 and 8 or 1,
        data = ffi.new('float[?]', width * (i <= 2 and 8 or 1) * 4),
        resource = hashes[i],
    }
    d.data[0] = i / 8
    originals[i] = d
end
local function actor(generation)
    units, materials, live = {}, {}, {}
    for i = 1, 2 do
        local unit = generation * 100 + i
        local material = generation * 1000 + i
        units[i] = { unit = unit, type = 0, slot = i == 1 and 1 or 0 }
        live[unit] = true
        materials[unit] = { { mesh = material + 20, material = material, mesh_index = 0, material_index = 0 } }
        bound[material] = { [1] = generation * 10000 + i, [2] = generation * 10000 + i + 2 }
        metadata[bound[material][1]] = originals[i]
        metadata[bound[material][2]] = originals[i + 2]
    end
end
actor(1)
local native = {
    alive = function(unit)
        return live[unit] and 1 or 0
    end,
    commit = function() end,
}
local memory = {
    verify_build = function()
        return true
    end,
    address = function()
        return 1
    end,
    module = function()
        return 1
    end,
    read_into = function()
        return true
    end,
}
local material_doc = { width = 23, height = 8, data = ffi.new('float[736]') }
material_doc.data[0], material_doc.data[3], material_doc.data[43] = 0.625, 2, 13.25
local pattern_doc = { width = 3, height = 1, data = ffi.new('float[12]') }
pattern_doc.data[0], pattern_doc.data[3], pattern_doc.data[7], pattern_doc.data[11] = 0.875, -0.125, 0.75, 17.5
local files = { material = D.encode(material_doc.data, 23, 8), pattern = D.encode(pattern_doc.data, 3, 1) }
local m = {
    appearance_state = dofile('src/gear/appearance_state.lua'),
    direct_setup = {
        new = function()
            return {
                read = function()
                    return {}
                end,
                clear = function() end,
                save = function(_, defaults)
                    saved_defaults = defaults
                    return 1
                end,
            }
        end,
    },
    binding_session = dofile('src/gear/binding_session.lua'),
    gear_catalog = dofile('src/gear/gear_catalog.lua'),
    basic_state = dofile('src/core/basic_state.lua'),
    region_indicator = dofile('src/gear/region_indicator.lua'),
    editor_registry = dofile('src/editor/editor_registry.lua'),
    lut_editor = dofile('src/editor/lut_editor.lua'),
    lut_editor_controls = dofile('src/editor/lut_editor_controls.lua'),
    lut_editor_view = dofile('src/editor/lut_editor_view.lua'),
    configuration = dofile('src/editor/configuration.lua'),
    semantics = dofile('src/core/semantics.lua'),
    palette = dofile('src/core/palette.lua'),
    resource_ids = dofile('src/core/resource_ids.lua'),
    lut_files = dofile('src/presets/lut_files.lua'),
    dds = D,
    ui_core = core,
    table_index = dofile('src/imports/table_index.lua'),
    import_job = dofile('src/imports/import_job.lua'),
    import_protocol = dofile('src/imports/import_protocol.lua'),
    file_io = {
        read = function(path)
            local key = path:match('/([^/]+)%.dds$')
            return assert(files[key], 'Unexpected test read: ' .. path)
        end,
    },
    windows = {
        row_presets = function()
            return {}
        end,
    },
    native_import = {},
    paths = {
        new = function()
            return {
                files = 'fixture/files',
                presets = 'fixture/presets',
                cache = 'fixture/cache',
                exports = 'fixture/exports',
                settings = 'fixture/settings',
                storage = store,
            }
        end,
    },
    bingus_memory = {
        new = function()
            return memory
        end,
    },
    avatar = {
        resolve_live = function()
            return scene and { unit = units[1].unit, units_at = 1 } or nil
        end,
        resolve = function()
            return scene and { body = kits.body, armor = kits.armor, helmet = kits.helmet } or nil
        end,
        units = function()
            return scene and units or {}
        end,
    },
    engine = {
        LUT_SLOT = 1,
        PATTERN_SLOT = 2,
        open = function()
            return native
        end,
        unit_materials = function(_, unit)
            return materials[unit] or {}
        end,
        binding = function(_, material, slot)
            return bound[material] and bound[material][slot or 1]
        end,
        create_texture = function(_, width, height, data)
            created = created + 1
            return { object = 90000 + created, data = data, width = width, height = height }
        end,
        bind = function(_, material, slot, object)
            binds = binds + 1
            bound[material][slot] = object
        end,
    },
    original_luts = {
        new = function()
            return {
                loaded = true,
                status = 'Ready',
                start = function() end,
                tick = function() end,
                scan = function() end,
                close = function() end,
                get = function(object)
                    return metadata[object]
                end,
            }
        end,
    },
    preferences = {
        new = function()
            return { close = function() end }
        end,
    },
    provider_menu = {
        disable_matching = function()
            return true, false
        end,
    },
    action_history = {
        new = function(capture, restore)
            history = History.new(capture, restore)
            return history
        end,
    },
    pattern_luts = {
        new = function(deps)
            pattern = Pattern.new(deps)
            return pattern
        end,
    },
    frontend = {
        new = function()
            frontend = {
                menu = {
                    visible = false,
                    page = 1,
                    is_interacting = function()
                        return false
                    end,
                },
                tick = function() end,
                resolve = function()
                    return api
                end,
                close = function()
                    return true
                end,
            }
            return frontend
        end,
    },
}
local source = assert(io.open('src/editor/direct_editor.lua', 'rb'))
local runtime = assert(loadstring('local m=...\n' .. source:read('*a')))(m)
source:close()
local ctx = { log = function() end, on_cleanup = function() end }
runtime.on_enable(ctx)
runtime.on_update(ctx, 0)
local h = api.mods.epic_direct_lut.handle
local function activate(id)
    local called, ok, value = pcall(h.activate, id)
    assert(called and ok, id .. ': ' .. tostring(called and value or ok))
    assert(type(value) ~= 'string' or not value:find('fixture', 1, true), value)
    return value
end
assert(h.set('preserve_emissives', false))
assert(h.set('format', 1) and h.set('file', 'material'))
activate('load')
activate('apply_file_armor')
activate('apply_file_helmet')
local armor_material, helmet_material = materials[units[1].unit][1].material, materials[units[2].unit][1].material
local owned_material = bound[armor_material][1]
assert(
    bound[helmet_material][1] == owned_material and created == 1,
    'Identical user material edits did not reuse a texture'
)
assert(h.set('file', 'pattern'))
activate('load')
assert(pattern.document, 'Pattern load failed: ' .. tostring(pattern.status))
activate('pattern_import_apply')
pattern.switch('helmet')
activate('pattern_import_apply')
local owned_pattern = bound[armor_material][2]
assert(
    bound[helmet_material][2] == owned_pattern and created == 2,
    'Pattern edits did not share their immutable cached texture'
)
pattern.open = false
frontend.menu.visible = false
local allocations, history_count, pattern_undo = created, #history.undo, #pattern.undo
local function current()
    return materials[units[1].unit][1].material, materials[units[2].unit][1].material
end
local function expect_custom()
    local armor, helmet = current()
    assert(
        bound[armor][1] == owned_material and bound[helmet][1] == owned_material,
        'Material appearance reverted after actor replacement'
    )
    assert(
        bound[armor][2] == owned_pattern and bound[helmet][2] == owned_pattern,
        'Pattern appearance reverted after actor replacement'
    )
end
local function unchanged_counts()
    assert(
        created == allocations and #history.undo == history_count and #pattern.undo == pattern_undo,
        'Recovery allocated textures or recorded user history'
    )
end
-- No actor during a scene boundary; keeping the menu closed must not suspend recovery.
scene = false
live = {}
local before_binds = binds
for _ = 1, 5 do
    runtime.on_update(ctx, 0.5)
end
assert(binds == before_binds and not frontend.menu.visible, 'Actor gap wrote stale bindings or opened the menu')
actor(2)
scene = true
runtime.on_update(ctx, 0.5)
expect_custom()
unchanged_counts()
-- Pattern slots recover independently if material LUT discovery is temporarily empty.
actor(7)
local pattern_armor, pattern_helmet = current()
bound[pattern_armor][1], bound[pattern_helmet][1] = 0, 0
runtime.on_update(ctx, 0.5)
assert(
    bound[pattern_armor][2] == owned_pattern and bound[pattern_helmet][2] == owned_pattern,
    'Pattern recovery was blocked by unavailable material LUTs'
)
unchanged_counts()
actor(2)
runtime.on_update(ctx, 0.5)
expect_custom()
unchanged_counts()
-- The same material objects can have their bindings reset by game code.
local armor, helmet = current()
bound[armor][1], bound[armor][2] = 20001, 20003
bound[helmet][1], bound[helmet][2] = 20002, 20004
runtime.on_update(ctx, 0.5)
expect_custom()
unchanged_counts()
local stable_binds = binds
for _ = 1, 6 do
    runtime.on_update(ctx, 0.5)
end
assert(binds == stable_binds, 'Stable owned appearance was rebound on every recovery poll')
-- Foreign writers are preserved, even with identical gear and slot numbers.
bound[armor][1], bound[armor][2] = 777777, 888888
runtime.on_update(ctx, 0.5)
assert(bound[armor][1] == 777777 and bound[armor][2] == 888888, 'Recovery replaced a foreign writer')
unchanged_counts()
-- New material instances with a shared original ID still require the original kit proof.
actor(3)
kits.armor = 99
runtime.on_update(ctx, 0.5)
armor, helmet = current()
assert(bound[armor][1] == 30001 and bound[armor][2] == 30003, 'Previous armor colors were applied to a changed kit')
assert(
    bound[helmet][1] == owned_material and bound[helmet][2] == owned_pattern,
    'Unchanged Helmet profile was lost when armor changed'
)
unchanged_counts()
activate('save_setup')
assert(
    saved_defaults and not saved_defaults.armor and saved_defaults.helmet,
    'Saving after a gear change retained the previous Armor blanket default'
)
kits.armor = 21
runtime.on_update(ctx, 0.5)
expect_custom()
unchanged_counts()
-- Explicit Restore Original clears intent so future actor recreations stay original.
activate('restore')
actor(4)
runtime.on_update(ctx, 0.5)
armor, helmet = current()
assert(
    bound[armor][1] == 40001 and bound[helmet][1] == 40002 and bound[armor][2] == 40003 and bound[helmet][2] == 40004,
    'Restore Original left a transition replay intent'
)
assert(created == allocations, 'Restore/scene transition allocated extra textures')
-- Applying while original ID metadata is delayed must still capture durable Armor intent later.
local delayed = metadata[40001]
metadata[40001] = nil
assert(h.set('file', 'material'))
activate('load')
activate('apply_file_armor')
assert(bound[armor][1] == owned_material, 'User apply failed while source metadata was pending')
metadata[40001] = delayed
runtime.on_update(ctx, 0.5)
-- Undo clears the desired application too; background polls must not resurrect it.
activate('global_undo')
assert(bound[armor][1] == 40001, 'Undo did not restore the original live binding')
local undo_binds = binds
for _ = 1, 4 do
    runtime.on_update(ctx, 0.5)
end
assert(bound[armor][1] == 40001 and binds == undo_binds, 'Recovery reapplied an undone appearance')
activate('global_redo')
runtime.on_update(ctx, 0.5)
assert(bound[armor][1] == owned_material, 'Redo failed to restore desired application')
history_count, pattern_undo = #history.undo, #pattern.undo
scene = false
live = {}
runtime.on_update(ctx, 0.5)
actor(5)
scene = true
runtime.on_update(ctx, 0.5)
armor, helmet = current()
assert(bound[armor][1] == owned_material, 'Delayed Armor metadata failed to survive actor replacement after Redo')
assert(
    bound[helmet][1] == 50002 and bound[armor][2] == 50003 and bound[helmet][2] == 50004,
    'A single Armor intent recolored unmatched Helmet/Pattern slots'
)
unchanged_counts()
activate('restore')
actor(6)
runtime.on_update(ctx, 0.5)
armor, helmet = current()
assert(bound[armor][1] == 60001 and bound[helmet][1] == 60002, 'Explicit Restore failed to clear redo/recovery intent')
assert(runtime.on_disable(ctx))
print(
    'PASS direct appearance runtime: user material/Pattern application, closed-menu actor gap/replacement, game reset recovery, exact cached texture reuse, no automatic history, foreign/changed-kit protection, delayed metadata and Undo/Redo/Restore intent'
)
