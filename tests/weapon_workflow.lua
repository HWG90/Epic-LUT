local F = dofile('tests/weapon_services_fixture.lua')
local Mapping = dofile('src/editor/weapon_mapping.lua')
local Presets = dofile('src/presets/weapon_presets.lua')
local Workflow = dofile('src/editor/weapon_workflow.lua')
local f = F.new()
local body = f.group(1, 'material', 1, 'babd338977faa2ff', 2.5, 3)
local pattern = f.group(1, 'pattern', 1, 'cf0cc31b981786c9', -0.25, 3)
local secondary = f.group(2, 'material', 1, '3333333333333333', 0.5, 1)
local saved, invalidated, exported, mutations, selected_preset
local stored_presets = {}
local bridge = {
    runtime = function()
        return f.runtime
    end,
    descriptors = function(targets)
        return targets or f.groups
    end,
}
local storage = {
    names = function()
        local names = {}
        for name in pairs(stored_presets) do
            names[#names + 1] = name
        end
        return names
    end,
    save = function(name, entries)
        saved = { name = name, entries = entries }
        stored_presets[name] = saved
        return true
    end,
    load = function(name)
        return assert(stored_presets[name])
    end,
}
local workflow = Workflow.new(
    { weapon_mapping = Mapping, weapon_presets = Presets, outfit_targets = dofile('src/presets/outfit_targets.lua') },
    {
        bridge = function()
            return bridge
        end,
        menu = f.host.menu,
        mod = function()
            return { controls = { outfit_name = {} } }
        end,
        outfits = function()
            return storage
        end,
        selected_preset = function()
            return selected_preset
        end,
        invalidate = function(name)
            invalidated = name
        end,
        imports = f.host.imports,
        message = function(text)
            return text
        end,
        mutate = function(fn)
            mutations = (mutations or 0) + 1
            return fn()
        end,
        export_options = function()
            return 'Adjudicator', 1, 1
        end,
        exporter = function(preset)
            return {
                save = function(name, value, format, index, naming)
                    assert(value == preset and name == 'Adjudicator' and format == 1 and index == 1 and naming == 1)
                    exported = value
                    return 'output', 'exact weapon bindings', 'output.zip'
                end,
            }
        end,
    }
)
assert(workflow.save({ body, pattern }))
assert(f.menu.outfit_dialog.save_kind.weapon_slots[1] and not f.menu.outfit_dialog.save_kind.weapon_slots[2])
local save_status = f.menu.outfit_dialog.on_save('Adjudicator')
assert(save_status:find('Patch assignment proof is pending or unavailable', 1, true))
assert(saved and #saved.entries == 6 and invalidated == 'Adjudicator' and not f.menu.outfit_dialog)
assert(saved.entries[1].document.data[0] == 2.5)
stored_presets.Mixed = {
    name = 'Mixed',
    entries = {
        { kind = 'armor', key = '0:1:0:0', document = F.document(23, 8, 7) },
        {
            kind = 'weapon',
            key = '3:1:0:0',
            weapon_slot = 1,
            weapon_resource = 'ffffffffffffffff',
            document = F.document(23, 8, 8),
        },
    },
}
local original_saved = saved
selected_preset = stored_presets.Mixed
assert(workflow.save({ body, pattern }) and not f.menu.outfit_dialog)
assert(
    #saved.entries == 8 and saved.entries[1].kind == 'armor' and saved.entries[2].weapon_resource == 'ffffffffffffffff'
)
local before_confirm = saved
assert(workflow.save({ body, pattern }) == false)
assert(saved == before_confirm and f.menu.outfit_dialog.phase == 'confirm')
assert(f.menu.outfit_dialog.on_confirm() and #saved.entries == 8)
selected_preset, saved, invalidated = nil, original_saved, 'Adjudicator'
local preview = workflow.plan(saved, { preview = true })
assert(#preview.choices == 2 and preview.choices[1].has_pattern and preview.validate())
local selected = { [preview.choices[1].id] = true }
local plan = workflow.plan(saved, { selected = selected })
assert(plan.count == 6 and plan.apply() == 6 and #f.plan == 2)
assert(workflow.export({ body, pattern }) and #exported.entries == 6)
f.import('lut000.dds', F.document(23, 8, 4))
local mapped = workflow.map_prepared({ body, pattern })
local map_ok, map_status = mapped.on_map('source:1', 'weapon:1:material:1')
assert(
    map_ok == true and map_status == 'Mapped 1 weapon LUT tables.' and mutations == 1,
    'Workflow did not forward mapping history or preserve its result tuple'
)
assert(workflow.save({ secondary }))
local existing = {
    name = 'Existing Armor Look',
    entries = {
        { kind = 'armor', key = '0:1:0:0', document = F.document(23, 8, 5.25) },
        { kind = 'helmet', key = 'p:1:0:0:0', document = F.document(3, 1, 0.625) },
    },
}
existing.entries[2].document.data[11] = 0.875
local existing_pixels = Mapping.bytes(existing.entries[1].document)
assert(workflow.map_preset({ body, pattern }, existing))
assert(
    #f.plan == 2 and body.bindings[1].document.data[0] == 5.25 and pattern.bindings[1].document.data[11] == 0.875,
    'Existing garment preset did not map material and Pattern palettes to selected weapons'
)
assert(
    Mapping.bytes(existing.entries[1].document) == existing_pixels,
    'Testing a preset on weapons modified the saved garment palette'
)
do
    local scoped = F.new()
    local main = scoped.group(1, 'material', 1, 'babd338977faa2ff', 0.5, 2)
    local companion = scoped.group(1, 'pattern', 1, 'cf0cc31b981786c9', 0.75, 2)
    companion.bindings[2].document = { width = 3, height = 1, data = 'unavailable unselected pixels' }
    local captured
    local scoped_bridge = {
        runtime = function()
            return scoped.runtime
        end,
        descriptors = function()
            return scoped.groups
        end,
        check = function()
            return scoped.runtime.target(1, 1, 'material')
        end,
    }
    local scoped_workflow = Workflow.new({
        weapon_mapping = Mapping,
        weapon_presets = Presets,
        outfit_targets = dofile('src/presets/outfit_targets.lua'),
    }, {
        bridge = function()
            return scoped_bridge
        end,
        outfits = function()
            return storage
        end,
        message = function(value)
            return value
        end,
        exporter = function(preset)
            return {
                save = function(_, _, format)
                    captured = preset.entries
                    assert(format == 2, 'Selected weapon export changed its format')
                    return 'output', 'subset', 'subset.zip'
                end,
            }
        end,
    })
    local target =
        { kind = 'weapon', weapon_slot = 1, group_index = 1, family = 'material', bindings = { main.bindings[1] } }
    local draft = F.document(23, 8, 0.25)
    assert(scoped_workflow.export_editor(target, draft, 'Subset', false))
    assert(
        #captured == 2 and captured[1].key == '3:1:0:0' and captured[2].key == 'p:3:1:0:0',
        'Selected export captured unselected material or Pattern destinations'
    )
    assert(captured[1].document.data[0] == 0.25 and captured[2].document.data[0] == 0.75)
    assert(
        not pcall(scoped_workflow.export_editor, target, draft, 'Entire', true),
        'Entire export silently omitted unavailable required Pattern pixels'
    )
    local descriptor = {}
    for key, value in pairs(companion) do
        descriptor[key] = value
    end
    descriptor.bindings = { companion.bindings[1] }
    local _, validate = Mapping.freeze(scoped.runtime, { descriptor })
    local old_mesh = companion.bindings[2].mesh
    companion.bindings[2].mesh = old_mesh + 1
    assert(not pcall(validate), 'Subset capture stopped checking the full group identity')
    companion.bindings[2].mesh = old_mesh
    assert(validate())
    scoped.foreign(companion.bindings[2])
    assert(
        not pcall(scoped_workflow.export_editor, target, draft, 'Subset', false),
        'Subset export bypassed whole-group native ownership validation'
    )
end
f.foreign(secondary.bindings[1])
assert(not pcall(f.menu.outfit_dialog.on_save, 'Changed'))
assert(invalidated == 'Adjudicator')
print(
    'PASS weapon workflow: frozen naming, exact slots/LOD capture, material-Pattern apply, export delegation and stale refusal'
)
