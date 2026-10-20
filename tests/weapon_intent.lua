local F=dofile('tests/weapon_fixture.lua')
local M=dofile('src/editor/weapon_mapping.lua')
local W=dofile('src/editor/weapon_workflow.lua')
local I=dofile('src/weapons/weapon_intent.lua')
local DDS=dofile('src/core/dds.lua')
local function fixture()
    local f=F()
    local bridge={runtime=function()return f.runtime end,discovery=function()return f.discovery end,
        recovery_pending=function()return false end}
    bridge.descriptors=function(_,slots)
        local out={}
        for slot=1,3 do
            if not slots or slots[slot] then
                for _,kind in ipairs({'material','pattern'}) do
                    for index,group in ipairs(f.runtime.groups(slot,kind)) do
                        out[#out+1]={index=index,family=kind,weapon_slot=slot,
                            weapon_resource=group.weapon_resource or group.weapon_resource64,
                            source_resource=group.source_resource,bindings=group.bindings}
                    end
                end
            end
        end
        return out
    end
    local workflow=W.new({weapon_mapping=M,outfit_targets=dofile('src/presets/outfit_targets.lua')},
        {bridge=function()return bridge end})
    local attempts=0
    local service=I.new({weapon_mapping=M},{bridge=function()return bridge end,
        original=function()error('Restart requested export pixels')end,
        sources=function()error('Restart requested export proof')end,
        message=function()end,
        restore_slot=function(preset,slot)
            attempts=attempts+1
            if f.not_ready then error('No weapon yet') end
            return workflow.plan(preset,{slots={[slot]=true}}).apply()
        end})
    return f,service,function()return attempts end
end
local f,service=fixture()
for slot=1,2 do
    f.runtime.refresh(slot)
    local document=f.runtime.load(slot,1)
    document.data[0]=slot/4
    f.runtime.apply(document,slot,1)
end
local entries=service.capture()
assert(#entries>0 and entries[1].original==nil and entries[1].binding_provenance==nil,
    'Restart persistence still requires export proof')
local storage=dofile('src/gear/direct_setup.lua').new({dds=DDS,
    native_import=dofile('src/platform/windows.lua'),
    file_io=dofile('src/core/file_io.lua'),windows=dofile('src/platform/windows.lua'),
    outfit_presets=dofile('src/presets/outfit_presets.lua'),
    binding_provenance=dofile('src/presets/binding_provenance.lua')},
    {settings='tests/tmp/direct-state',presets='tests/tmp/presets'})
storage.clear()
assert(storage.save({}, {}, entries,true)>0)
local _,_,saved=storage.read()
assert(saved.slot_intent and #saved.entries==#entries,'Slot intent did not survive disk round trip')
local fresh,resume,attempts=fixture()
fresh.respawn(1,91,'9999999999999999')
resume.start(saved)
fresh.not_ready=true
resume.tick();resume.tick()
local before=attempts()
for i=1,1000 do resume.tick() end
assert(attempts()==before and resume.recovering(),'Unavailable weapon triggered continuous polling')
fresh.not_ready=false
resume.wake(3)
resume.tick();resume.tick()
assert(not resume.pending() and not resume.recovering(),'Current slot mapper failed startup')
for slot=1,2 do
    local document=fresh.runtime.load(slot,1)
    assert(document.data[0]==slot/4,'Saved colors not restored to equipped slot')
end
local reads,writes=fresh.reads,#fresh.writes
for i=1,1000 do resume.tick() end
assert(fresh.reads==reads and #fresh.writes==writes,'Completed startup performed idle work')
resume.start(saved);resume.cancel(true);resume.wake();resume.tick()
assert(not resume.recovering(),'Cancelled startup rearmed itself')
-- Unavailable current weapons cannot silently delete a previous assignment.
f.units[f.snapshots[1].weapon_unit_ref].alive=false
assert(not pcall(service.capture),'Dead weapon permitted saved intent deletion')
storage.clear()
print('PASS weapon restart intent: cold export-independent save, disk round trip, changed weapon slot mapping, event-only readiness, cancellation and zero idle reads/writes')
