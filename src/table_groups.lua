-- Equality uses every finite float, including alpha, masks and emissive fields.
local T={}
local cache=setmetatable({},{__mode='k'})
function T.key(table)
    local revision=table.revision or 0
    local cached=cache[table.data]
    if cached and cached.revision==revision and cached.width==table.width and cached.height==table.height then return cached.key end
    local ffi=require('ffi');local n=table.width*table.height*4;local values=ffi.new('float[?]',n);ffi.copy(values,table.data,n*4)
    for i=0,n-1 do if values[i]==0 then values[i]=0 end end -- +0 and -0 are equal values.
    local key=table.width..':'..table.height..':'..ffi.string(values,n*4)
    cache[table.data]={key=key,revision=revision,width=table.width,height=table.height};return key
end
function T.collapse(entries)
    local groups,by_key={},{}
    for _,entry in ipairs(entries)do
        local key=T.key(entry);local group=by_key[key]
        if not group then
            group={name=entry.name,width=entry.width,height=entry.height,data=entry.data,ids={},edited=entry.edited};by_key[key]=group;groups[#groups+1]=group
        end
        group.ids[#group.ids+1]=entry.index or #groups
    end
    for _,group in ipairs(groups)do if #group.ids>1 then
        table.sort(group.ids);local labels={};local first,last=group.ids[1],group.ids[1]
        for i=2,#group.ids+1 do
            local value=group.ids[i]
            if value==last+1 then last=value else labels[#labels+1]=first==last and tostring(first)or(first..'-'..last);first,last=value,value end
        end
        group.name='Tables '..table.concat(labels,', ')..' have identical values'
    end end
    return groups
end
return T
