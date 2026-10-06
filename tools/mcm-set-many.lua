        -- Validate and persist a complete import before publishing any values or callbacks.
        function handle.set_many(values)
            assert(api.mods[mod.id]==mod,'Retired registration')
            assert(type(values)=='table','Settings table required')
            local next_values=copy(mod.values);local changes={};local keys={}
            for key in pairs(values)do keys[#keys+1]=key end;table.sort(keys)
            for _,key in ipairs(keys)do
                local c=assert(mod.controls[key],'Unknown control');assert(stored(c) and not c.disabled,'Setting unavailable')
                local value=normalize(c,values[key]);if c.validate then assert(c.validate(value)~=false,'Value rejected by mod')end
                if value~=mod.values[key]then next_values[key]=value;changes[#changes+1]={c=c,key=key,v=value,old=mod.values[key]}end
            end
            if #changes==0 then return true end
            if store then local ok,err=store.save(mod.id,next_values);if not ok then return false,err end end
            mod.values=next_values
            for _,change in ipairs(changes)do
                for _,callback in ipairs({change.c.on_change or false,mod.on_change or false})do
                    if callback then local ok,err=pcall(callback,change.v,change.key,change.old);if not ok then log('Callback failed: '..tostring(err))end end
                end
            end
            api.revision=api.revision+1;log('Settings batch committed: '..mod.id..' ('..#changes..' settings)');return true
        end
