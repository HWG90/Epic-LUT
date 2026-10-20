-- Production all-channel grouping and weak/revision caches with real float buffers.
local Buffer = require('src.core.float_buffer')
local Groups = dofile('src/core/table_groups.lua')
local function document(index)
    local values = Buffer.new(184)
    for i=0,183 do values[i]=(i-92)/17 end
    values[0],values[3],values[52],values[183]=2^-149,-1/math.huge,1000000,-0.25
    return {index=index,name='Table '..index,width=23,height=2,data=values,
        source='owned.dds',resource='0123456789abcdef',revision=0,edited=true}
end
local first, second, third = document(1),document(2),document(5)
second.data[3]=0
local original=Buffer.bytes(first.data,184)
assert(Groups.key(first)==Groups.key(second),'Signed zero produced separate value groups')
assert(Buffer.bytes(first.data,184)==original and 1/first.data[3]==-math.huge,'Grouping mutated immutable source bytes')
local grouped=Groups.collapse({third,first,second})
assert(#grouped==1 and grouped[1].name=='Tables 1-2, 5 have identical values')
assert(grouped[1].data==third.data and grouped[1].source==third.source and grouped[1].resource==third.resource
    and grouped[1].revision==third.revision and grouped[1].edited==third.edited,'Collapsed group lost source identity')
for _,index in ipairs({3,52,53,54,55,183}) do
    local prior=second.data[index]
    second.data[index]=prior+0.125
    second.revision=second.revision+1
    assert(#Groups.collapse({first,second})==2,'Alpha/mask/emissive difference was hidden: '..index)
    second.data[index]=first.data[index]
    second.revision=second.revision+1
    assert(#Groups.collapse({first,second})==1,'Restored values failed to merge: '..index)
end
local new,bytes=Buffer.new,Buffer.bytes
local allocations,serializations=0,0
Buffer.new=function(...) allocations=allocations+1; return new(...) end
Buffer.bytes=function(...) serializations=serializations+1; return bytes(...) end
local cached=document(8)
allocations=0
local key=Groups.key(cached)
assert(allocations==1 and serializations==1)
for _=1,1000 do assert(Groups.key(cached)==key) end
assert(allocations==1 and serializations==1,'Unchanged grouping reallocated/serialized its cached table')
cached.data[7]=0.625;cached.revision=1
assert(Groups.key(cached)~=key and allocations==2 and serializations==2,'Revision did not invalidate equality bytes')
cached.width,cached.height=46,1
local shape=Groups.key(cached)
assert(shape:sub(1,5)=='46:1:' and allocations==3 and serializations==3,'Shape did not invalidate equality key')
Buffer.new,Buffer.bytes=new,bytes
local weak=setmetatable({}, {__mode='v'})
do local transient=document(99);weak[1]=transient.data;Groups.key(transient) end
collectgarbage('collect');collectgarbage('collect')
assert(weak[1]==nil,'Grouping cache retained a released document allocation')
print('PASS portable grouping: exact all-channel values, signed-zero equality, source retention, revision/shape caches and weak lifetime')
