-- Ten distinct detailed baseline LUTs through real codec/publication scheduling.
-- Only the external lobby transport is a fixture; no FFI/native compressor.
local buffers = require('src.core.float_buffer')
local C = dofile('src/gear/shared_lut_codec.lua')
local S = dofile('src/gear/shared_appearance.lua')
local originals, entries = {}, {}
for n=1,10 do
    local base={width=23,height=8,data=buffers.new(736),resource=string.format('%016x',n)}
    local edited={width=23,height=8,data=buffers.new(736)}
    for i=0,735 do base.data[i]=math.sin(i*17+n*31)*4+i/1000 end
    buffers.copy(edited.data,base.data,736)
    edited.data[n*4],edited.data[n*4+1],edited.data[n*4+3]=2.75,-0.125,0.375
    originals[base.resource]=base
    entries[n]={key='0:1:'..n..':0',document=edited,original=base}
end
local backend=C.compression()
local compress,compression_calls=backend.compress,0
backend.compress=function(bytes,tag,checkpoint)
    assert(type(checkpoint)=='function','Actual compressor missed the scheduled checkpoint')
    compression_calls=compression_calls+1
    return compress(bytes,tag,checkpoint)
end
local codec=C.new(backend,function(resource)return originals[resource]end)
local encode,encodes=codec.encode,0
codec.encode=function(...)encodes=encodes+1;return encode(...)end
local published,clock,revision,entry_reads=nil,0,1,0
local identity={body=123,armor=456,helmet=789}
local sharing=S.new({codec=codec,defer_publication=true,
    identity=function()return identity end,identity_key=function()return identity.armor end,
    revision=function()return revision end,highlighting=function()return false end,
    entries=function()entry_reads=entry_reads+1;return entries end,
    publication_clock=function()clock=clock+0.003;return clock end,note=function()end,
    sync={session=function()return{
        poll=function(_,text)published=text;return{}end,clear=function()return true end,
    }end}})
sharing.tick(2,true)
assert(encodes==0 and published==nil,'Whole packet was built during scheduling')
local stages,worst=0,0
for i=1,20000 do
    local started=os.clock();sharing.tick(0,true)
    worst=math.max(worst,os.clock()-started);stages=i
    if encodes==1 and sharing.status:find('waiting for stable lobby',1,true)then break end
end
sharing.tick(2,true)
assert(type(published)=='string' and #published<=3600,'Actual deferred publication failed: '..sharing.status)
assert(stages>10 and stages<20000 and compression_calls>=3,'Real codec did not cooperate or did not finish')
local result=codec.decode(published)
for _,entry in ipairs(entries)do
    assert(buffers.bytes(result.entries[entry.key].document.data,736)==buffers.bytes(entry.document.data,736),
        'Scheduled publication changed immutable source float bytes')
end
local bytes,reads=published,entry_reads
for _=1,100 do sharing.tick(2,true)end
assert(encodes==1 and published==bytes and entry_reads==reads,'Idle publication repeated encode/snapshot work')
-- Cancel an actual suspended new publication and prove no retained job advances.
revision=2;sharing.tick(2,true)
for _=1,3 do sharing.tick(0,true)end
sharing.close()
local stopped_clock,stopped_encodes,stopped_reads=clock,encodes,entry_reads
for _=1,100 do sharing.tick(0,false)end
assert(clock==stopped_clock and encodes==stopped_encodes and entry_reads==stopped_reads,
    'Closed publication retained active encode/snapshot work')
print('PASS large stock Shared LUT publication: '..stages..' cooperative stages, max measured CPU '
    ..string.format('%.3f',worst*1000)..'ms, '..#bytes..' exact wire bytes; idle and cancellation stop work')
