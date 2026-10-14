local F = dofile('tests/weapon_services_fixture.lua')
local Mapping = dofile('src/editor/weapon_mapping.lua')
local Presets = dofile('src/presets/weapon_presets.lua')
local Workflow = dofile('src/editor/weapon_workflow.lua')
local f = F.new()
local body = f.group(1, 'material', 1, 'babd338977faa2ff', 2.5, 3)
local pattern = f.group(1, 'pattern', 1, 'cf0cc31b981786c9', -0.25, 3)
local secondary = f.group(2, 'material', 1, '3333333333333333', 0.5, 1)
local saved, invalidated, exported, mutations
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
        return { 'Existing' }
    end,
    save = function(name, entries)
        saved = { name = name, entries = entries }
        return true
    end,
    load = function(name)
        assert(saved.name == name)
        return saved
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
f.foreign(secondary.bindings[1])
assert(not pcall(f.menu.outfit_dialog.on_save, 'Changed'))
assert(invalidated == 'Adjudicator')
print(
    'PASS weapon workflow: frozen naming, exact slots/LOD capture, material-Pattern apply, export delegation and stale refusal'
)
