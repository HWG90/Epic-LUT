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
local descriptors_before = bridge.descriptors
local refreshed, cold = {}, true
f.runtime.refresh = function(slot)
    refreshed[slot], cold = (refreshed[slot] or 0) + 1, false
end
bridge.descriptors = function(...)
    assert(not cold, 'Armory planned against an uninitialized weapon catalog')
    return descriptors_before(...)
end
local preview = workflow.plan(saved, { preview = true })
assert(
    refreshed[1] == 1 and not refreshed[2] and not refreshed[3],
    'Armory must refresh only saved weapon slots once per explicit plan'
)
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

do
    local f = F.new()
    local group = f.group(1, 'material', 1, 'babd338977faa2ff', 0.25, 1)
    local attempts, complete, name = 0, false, 'Frozen'
    local pending = 'pending proof'
    local workflow = Workflow.new(
        { weapon_mapping = Mapping, weapon_presets = Presets, outfit_targets = dofile('src/presets/outfit_targets.lua') },
        {
            bridge = function()
                return {
                    runtime = function()
                        return f.runtime
                    end,
                    descriptors = function()
                        return { group }
                    end,
                }
            end,
            outfits = function()
                return storage
            end,
            message = function(text)
                return text
            end,
            export_options = function()
                return name, 3, 1
            end,
            export_pending = function(why)
                return why == pending
            end,
            exporter = function(snapshot)
                return {
                    save = function(export_name, preset)
                        attempts = attempts + 1
                        assert(
                            export_name == 'Frozen'
                                and preset == snapshot
                                and preset.entries[1].document.data[0] == 0.25
                        )
                        if attempts < 3 then
                            error(pending, 0)
                        end
                        complete = true
                        return 'output', 'one weapon', 'output.zip'
                    end,
                }
            end,
        }
    )
    assert(workflow.export({ group }):find('finish automatically', 1, true) and attempts == 1)
    name = 'Later'
    group.source_document.data[0] = 0.9
    assert(not pcall(workflow.export, { group }), 'A second click replaced the queued snapshot')
    workflow.tick(0.1)
    assert(attempts == 1)
    workflow.tick(0.2)
    assert(attempts == 2 and not complete)
    workflow.tick(0.3)
    assert(attempts == 3 and complete)
    workflow.tick(10)
    assert(attempts == 3, 'Finished export repeated')
end
print('PASS deferred weapon export: frozen name/pixels, one queued job, rate-limited retry and one publication')

-- Saved configuration IDs identify sources; equipped slot identities own writes.
do
    local cross = F.new()
    local entries = {}
    for slot = 1, 3 do
        for index = 1, 3 do
            cross.group(slot, 'material', index, string.format('%016x', slot * 100 + index), 0, 2)
            cross.group(slot, 'pattern', index, string.format('%016x', slot * 200 + index), 0, 2)
        end
        for index = 1, 2 do
            entries[#entries + 1] = {
                kind = 'weapon',
                key = '3:' .. slot .. ':0:' .. (index - 1),
                weapon_slot = slot,
                weapon_resource = 'ffffffffffffffff',
                document = F.document(23, 5, slot * 10 + index),
                original = { resource = string.format('%016x', index) },
            }
        end
        entries[#entries + 1] = {
            kind = 'weapon',
            key = 'p:3:' .. slot .. ':0:0',
            weapon_slot = slot,
            weapon_resource = 'ffffffffffffffff',
            document = F.document(3, 1, slot * 100),
            original = { resource = 'aaaaaaaaaaaaaaaa' },
        }
    end
    local service = Workflow.new({ weapon_mapping = Mapping }, {
        bridge = function()
            return {
                runtime = function()
                    return cross.runtime
                end,
                descriptors = function()
                    return cross.groups
                end,
            }
        end,
    })
    local preset = { entries = entries }
    local preview = service.plan(preset, { preview = true })
    assert(#preview.choices == 18 and preview.choices[1].weapon_resource ~= 'ffffffffffffffff')
    local bytes_before = Mapping.bytes(entries[1].document)
    local plan = service.plan(preset)
    assert(plan.apply() == 36 and #cross.plan == 18, 'Cross-weapon mapping missed a slot, table or LOD')
    for _, applied in ipairs(cross.plan) do
        local expected = applied.family == 'pattern' and applied.weapon_slot * 100
            or applied.weapon_slot * 10 + ((applied.index - 1) % 2 + 1)
        assert(applied.document.data[0] == expected, 'Slot source order or rollover crossed weapon families')
        assert(applied.document.data[3] == -0.375, 'Cross-weapon mapping lost alpha')
        assert(applied.weapon_resource == cross.config[applied.weapon_slot], 'Write used saved weapon identity')
    end
    assert(Mapping.bytes(entries[1].document) == bytes_before, 'Preset mapping mutated saved colors')
    local pending = service.plan(preset)
    cross.groups[1].bindings[1].weapon_resource = 'eeeeeeeeeeeeeeee'
    assert(not pcall(pending.apply), 'Equipment change after planning escaped ownership checks')
end
print(
    'PASS slot-based preset auto-map: three different equipped weapons, rollover, row adaptation, Patterns, alpha and stale refusal'
)

do
    local attempts, finished = 0, 0
    local preset = { name = 'Queued Mixed', entries = {
        { kind = 'armor', key = '0:2:0:0', document = F.document(23, 8, 0.375) },
        { kind = 'weapon', key = '3:2:0:0', weapon_slot = 2, weapon_resource = 'ffffffffffffffff',
          document = F.document(23, 8, 0.625), binding_provenance = { version = 4 } },
    } }
    local workflow = Workflow.new({ weapon_mapping = Mapping }, {
        export_pending = function(why) return why == 'scope pending' end,
        message = function(value) return value end,
    })
    local function factory(snapshot)
        return { save = function(name, received, format, lut, naming)
            attempts = attempts + 1
            assert(name == 'Frozen Name' and format == 3 and lut == 2 and naming == 4)
            assert(received == snapshot and received.name == 'Queued Mixed')
            assert(received.entries[1].document.data[0] == 0.375 and received.entries[2].document.data[0] == 0.625)
            assert(received.entries[2].binding_provenance.version == 4)
            if attempts < 3 then error('scope pending', 0) end
            finished = finished + 1
            return 'out', 'entire preset', 'out.zip'
        end }
    end
    assert(workflow.export_saved(preset, 'Frozen Name', 3, 2, 4, factory):find('finish automatically', 1, true))
    preset.name = 'Other'
    preset.entries[1].document.data[0] = 9
    preset.entries[2].binding_provenance.version = 99
    assert(not pcall(workflow.export_saved, preset, 'Other', 1, 1, 1, factory))
    workflow.tick(0.1); assert(attempts == 1)
    workflow.tick(0.2); assert(attempts == 2)
    workflow.tick(0.3); assert(finished == 1)
    workflow.tick(20); assert(attempts == 3 and finished == 1)
end
print('PASS queued mixed Armory export: immutable preset/settings, source verification retry, duplicate refusal and one completion')

-- Editor capture can be pending before an exporter exists. Completion, not
-- repeated frame retries, must resume that immutable request exactly once.
do
    local binding = {save_key='3:1:0:0',current=10,original=9,unit=1,material=2}
    local descriptor = {weapon_slot=1,index=1,family='material',bindings={binding}}
    local target = {weapon_slot=1,group_index=1,family='material',bindings={binding}}
    local callback, cold, captures, publications, result = nil, true, 0, 0
    local pending = 'source pending'
    local workflow = Workflow.new({weapon_mapping=Mapping,weapon_presets={new=function()
        return {capture=function()
            captures=captures+1
            if cold then error(pending,0) end
            return {{kind='weapon',key=binding.save_key,document=F.document(23,8,0)}}
        end}
    end}}, {
        bridge=function() return {check=function() return true end,runtime=function() return {} end,
            descriptors=function() return {descriptor} end} end,
        outfits=function() return {} end,
        message=function(v) result=v;return v end,
        export_pending=function(v) return v==pending end,
        when_sources_ready=function(fn) callback=fn end,
        exporter=function() return {save=function(name,preset)
            publications=publications+1
            assert(name=='Frozen editor' and preset.entries[1].document.data[0]==0.25)
            return 'out','selected','out.zip'
        end} end,
    })
    local draft=F.document(23,8,0.25)
    workflow.export_editor(target,draft,'Frozen editor',false)
    draft.data[0]=0.75
    assert(callback and captures==1 and publications==0)
    assert(not pcall(workflow.export_editor,target,draft,'Duplicate',false))
    for i=1,100 do workflow.tick(0.016) end
    assert(captures==1,'Pending editor export retried every frame')
    cold=false;callback(true)
    assert(captures==2 and publications==1)
    cold=true;workflow.export_editor(target,F.document(23,8,0.25),'Frozen editor',false)
    binding.current=11;cold=false;callback(true)
    assert(publications==1 and result:find('Weapon changed',1,true),'Changed target was exported')
end
print('PASS editor cold-source export: one-shot completion, frozen pixels/name, idle frames, duplicate and stale guards')
