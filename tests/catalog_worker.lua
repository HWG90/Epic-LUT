local ffi=require('ffi');local C=dofile('src/catalog.lua');local DDS=dofile('src/dds.lua')
local name='0123456789abcdef';local folder='tests/tmp/files';local values=ffi.new('float[?]',23*2*4)
for i=0,23*2*4-1 do values[i]=(i-90)/8 end
DDS.write(folder..'/catalog-test-'..name..'.dds',values,23,2)
local f=assert(io.open(folder..'/catalog-test.tsv','wb'));f:write('lut\t'..name..'\t23\t2\tmaterial\tcatalog-test-'..name..'.dds\t1,2\npiece\t0:2\nreference\t1\t'..name..'\t1111111111111111\t0:2\nunsupported\t2222222222222222\tNot a float lookup\n');f:close()
local clock,polls,started=0,0,0
local kit={kit_type='Armor',archive='aaaaaaaaaaaaaaaa',pieces={{path='bbbbbbbbbbbbbbbb'}}}
local memory={time=function()clock=clock+.2;return clock end,read_into=function(a,n,b)
 assert(n<=ffi.sizeof(b),'Native snapshot overrun');ffi.fill(b,n);a=tonumber(ffi.cast('uintptr_t',a))
 if a==0x10000+0x33264f8 then ffi.cast('uint64_t *',b)[0]=0x20000
 elseif a==0x20000 then ffi.cast('uint64_t *',b)[0]=0x30000;ffi.cast('uint32_t *',b)[2]=1
 elseif a==0x30000 then ffi.cast('uint64_t *',b)[0]=0x40000
 elseif a==0x40000 then ffi.cast('uint32_t *',b)[0]=123
 else error('Unexpected native snapshot address')end;return true
end}
local m={paths={files=folder},kits={ARMOR='Armor',HELMET='Helmet',read_kit=function()return kit end},dds=DDS,
 slim={open=function()error('In-game archive decoder was used')end},
 native_import={new=function(at,kind)
 assert(at==folder and kind=='catalogarmor');return {discover=function(actual,body,target)assert(actual==kit and body==0 and target=='armor');started=started+1 end,
 poll=function()polls=polls+1;if polls>2 then return 'Ready',1,{catalog='catalog-test.tsv'}end end}
 end}}
local catalog=C.new(m,memory,0x10000,'Armor');local identity={target_id=123,body=0};local result
local job=coroutine.create(function()result=catalog.load(identity,coroutine.yield)end)
local frames=0;repeat local ok,why=coroutine.resume(job);assert(ok,why);frames=frames+1 until coroutine.status(job)=='dead'
assert(frames==3 and started==1 and result.identity==identity and #result.luts==1 and result.pieces['0:2']and #result.references==1 and #result.unsupported==1)
assert(result.luts[1].slots[1]and result.luts[1].slots[2]);assert(ffi.string(result.luts[1].values,23*2*16)==ffi.string(values,23*2*16),'Worker float data changed')
catalog.close()
f=assert(io.open(folder..'/catalog-test.tsv','wb'));f:write('lut\tbad\n');f:close();polls=3
assert(not pcall(catalog.load,identity,function()end),'Malformed worker metadata was accepted')
print('PASS: asynchronous catalogue waits, exact original float data, all slot/reference metadata, bounded snapshots, malformed rejection and no in-game archive decode')
