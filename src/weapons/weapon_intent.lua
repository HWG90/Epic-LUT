-- Restart intent is palette + equipment slot; patch provenance belongs to export.
local I = {}
function I.new(m, host)
    local M = assert(m.weapon_mapping)
    local function has_flag(mask, flag) return math.floor(mask / flag) % 2 == 1 end
    local self, saved, remaining, queued = {}, nil, {}, {}
    local function freeze(entries)
        assert(type(entries)=='table' and #entries>0 and #entries<=4096, 'Invalid saved weapon intent')
        local copy, seen, payloads, total = {}, {}, {}, 0
        for _,entry in ipairs(entries) do
            local slot=entry.weapon_slot
            assert(entry.kind=='weapon' and type(slot)=='number' and slot%1==0 and slot>=1 and slot<=3,
                'Invalid saved weapon slot')
            assert(type(entry.key)=='string' and not seen[entry.key], 'Duplicate saved weapon intent')
            seen[entry.key]=true
            local bytes=M.bytes(entry.document)
            if not payloads[bytes] then
                total=total+#bytes
                assert(total<=8*1024*1024, 'Weapon intent payload budget exceeded')
                payloads[bytes]=M.copy(entry.document)
            end
            copy[#copy+1]={kind='weapon', key=entry.key, weapon_slot=slot,
                weapon_resource=entry.weapon_resource, document=payloads[bytes]}
        end
        return copy
    end
    self.slot_intent=true
    function self.capture()
        assert(not next(remaining), 'Saved weapon setup is awaiting recovery; previous setup retained')
        local editor,entries,checks,captured=host.bridge(),{},{},{}
        local runtime,discovery=editor.runtime(),editor.discovery()
        for slot=1,3 do
            local catalog=runtime.catalog(slot)
            if catalog and catalog.available then
                assert(not editor.recovery_pending or not editor.recovery_pending(slot),
                    'Applied weapon setup is awaiting recovery; previous setup retained')
                assert(discovery.validate(catalog.receipt), 'Weapon changed during save')
                for _,kind in ipairs({'material','pattern'}) do
                    for _,group in ipairs(runtime.groups(slot,kind)) do
                        for _,b in ipairs(group.bindings) do
                            if b.texture and b.current==b.texture.object then
                                assert(discovery.present(b) and discovery.binding(b)==b.current, 'Weapon changed during save')
                                captured[slot]=true
                                entries[#entries+1]={kind='weapon', key=(kind=='pattern' and 'p:' or '')..b.save_key,
                                    weapon_slot=slot,weapon_resource=b.weapon_resource or b.weapon_resource64,
                                    document=b.texture}
                                checks[#checks+1]={binding=b,current=b.current,bytes=M.bytes(b.texture)}
                            end
                        end
                    end
                end
            end
        end
        for _,b in ipairs(runtime.all_owned()) do
            if b.texture and b.current==b.texture.object and not captured[b.weapon_slot] then
                error('Applied weapon setup is awaiting recovery; previous setup retained',0)
            end
        end
        local result=#entries>0 and freeze(entries) or {}
        for _,check in ipairs(checks) do
            local b=check.binding
            assert(discovery.present(b) and discovery.binding(b)==check.current
                and b.current==check.current and b.texture and M.bytes(b.texture)==check.bytes,
                'Weapon changed during save')
        end
        return result
    end
    local capture=self.capture
    function self.capture()
        local discovery=host.bridge().discovery()
        if discovery.with_validation_batch then return discovery.with_validation_batch(capture) end
        return capture()
    end
    function self.start(preset)
        saved={entries=freeze(assert(preset.entries))}
        remaining,queued={},{}
        for _,entry in ipairs(saved.entries) do remaining[entry.weapon_slot]=true end
        self.wake()
    end
    function self.wake(mask)
        for slot in pairs(remaining) do
            if not mask or has_flag(mask,2^(slot-1)) or has_flag(mask,8) then queued[slot]=true end
        end
    end
    function self.cancel(discard)
        queued={}
        if discard then remaining,saved={},nil end
    end
    function self.pending() return next(queued)~=nil end
    function self.recovering() return next(remaining)~=nil end
    function self.tick()
        if not saved or not next(queued) or host.busy and host.busy() then return end
        -- Consume one slot per update. Failure waits for another lifecycle event,
        -- never a clock-based retry or an idle native inventory read.
        local slot=next(queued)
        queued[slot]=nil
        local ok,count=pcall(host.restore_slot,saved,slot)
        if ok and type(count)=='number' and count>0 then
            remaining[slot]=nil
            host.message('Saved weapon colors restored to slot '..slot..'.')
        else
            host.message('Saved weapon colors retained; waiting for slot '..slot..' readiness.')
        end
    end
    return self
end
return I
