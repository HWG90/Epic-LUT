local ffi = require('ffi')
local C = dofile('src/gear/shared_lut_codec.lua')
local dds = dofile('src/core/dds.lua')
local state = 20261015
local function random() state = state * 48271 % 2147483647; return state end
local documents = {}
for n = 1, 32 do
    local bits = ffi.new('uint32_t[368]')
    for i = 0, 367 do
        bits[i] = 0x3f000000 + (i % 24) * 8191
    end
    bits[0], bits[1], bits[2], bits[3] = 0x80000000, 0x40500000, 0xbe000000, 0x3f400000
    bits[20] = 0x3f000000 + n * 1049
    local data = ffi.new('float[368]'); ffi.copy(data, bits, 1472)
    documents[n] = {width=23,height=4,data=data}
end
local entries = {}
for mesh = 0, 63 do
    for material = 0, 63 do
        entries[#entries + 1] = {key='0:2:'..mesh..':'..material, document=documents[material % 32 + 1]}
    end
end
for i = #entries, 2, -1 do local j = random() % i + 1;entries[i],entries[j] = entries[j],entries[i] end
local codec = C.new()
local begin = os.clock()
local packet = codec.encode({body=17,armor=29,helmet=43},entries)
local elapsed = os.clock()-begin
local old = math.min(codec.packet_sizes.full,codec.packet_sizes.sparse,codec.packet_sizes.xor,codec.packet_sizes.dictionary)
print('STRESS',old,'->',#packet,'seconds',elapsed)
for k,v in pairs(codec.packet_sizes) do print(k,v) end
assert(old>C.MAX_TEXT and #packet<=C.MAX_TEXT and packet:match('^7x?|'))
local result=codec.decode(packet)
local count=0;for _ in pairs(result.entries) do count=count+1 end
assert(count==4096 and #result.documents==32)
for _,entry in ipairs(entries) do assert(ffi.string(result.entries[entry.key].document.data,1472)==ffi.string(entry.document.data,1472)) end
local output=os.getenv('EPIC_LUT_STRESS_OUTPUT')
if output then
 local manifest={'EPIC-OUTFIT\t1'}
 for i,doc in ipairs(documents) do local f=assert(io.open(output..string.format('/lut%03d.dds',i),'wb'));f:write(dds.encode(doc.data,23,4));f:close() end
 local ids={};for i,doc in ipairs(documents) do ids[doc]=i end
 for _,entry in ipairs(entries) do manifest[#manifest+1]='armor\t'..entry.key..'\t'..string.format('lut%03d.dds',ids[entry.document]) end
 local f=assert(io.open(output..'/preset.tsv','wb'));f:write(table.concat(manifest,'\n'));f:close()
end
-- Random F32 data is a control, not a claim that arbitrary entropy can fit.
for _,doc in ipairs(documents) do
 local bits=ffi.cast('uint32_t *',doc.data)
 for i=0,367 do bits[i]=0x3f000000+random()%0x800000 end
end
local entropy=C.new();assert(not pcall(entropy.encode,{body=17,armor=29,helmet=43},entries))
print('PASS max-count sharing stress: 32 exact LUTs,4096 shuffled destinations,HDR/alpha/signed zero; entropy refused without truncation')

-- Force EL7 for a tiny Pattern so raw boundary mutations remain bounded.
local forced=C.new({compress=function(raw)
    return raw:sub(1,3)=='EL7' and raw or string.rep('x',4000)
end,decompress=function(raw,size) assert(#raw==size);return raw end})
local pattern={width=3,height=1,data=ffi.new('float[12]')}
local encoded=forced.encode({body=1,armor=2,helmet=3},{{key='p:0:1:63:63',document=pattern}})
assert(encoded:match('^7|') and forced.decode(encoded).entries['p:0:1:63:63'])
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function unbase(s)
 local out={}
 for at=1,#s,4 do
  local a,b,c,d=s:sub(at,at+3):byte(1,4)
  local function digit(v) if v==61 then return 0 end return assert(alphabet:find(string.char(v),1,true))-1 end
  local n=digit(a)*262144+digit(b)*4096+digit(c)*64+digit(d)
  out[#out+1]=string.char(math.floor(n/65536))
  if c~=61 then out[#out+1]=string.char(math.floor(n/256)%256) end
  if d~=61 then out[#out+1]=string.char(n%256) end
 end
 return table.concat(out)
end
local function base(s)
 local out={}
 for at=1,#s,3 do
  local a,b,c=s:byte(at,at+2);local n=a*65536+(b or 0)*256+(c or 0)
  out[#out+1]=alphabet:sub(math.floor(n/262144)+1,math.floor(n/262144)+1)
   ..alphabet:sub(math.floor(n/4096)%64+1,math.floor(n/4096)%64+1)
   ..(b and alphabet:sub(math.floor(n/64)%64+1,math.floor(n/64)%64+1) or '=')
   ..(c and alphabet:sub(n%64+1,n%64+1) or '=')
 end
 return table.concat(out)
end
local raw=unbase(encoded:match('^7|%d+|(.+)$'))
local function reject(value)
 assert(not pcall(forced.decode,'7|'..#value..'|'..base(value)),'Malformed binding mask accepted')
end
local function put(at,value) return raw:sub(1,at-1)..string.char(value)..raw:sub(at+1) end
reject(put(16,2)) -- Unknown weapon flag.
reject(put(18,0)) -- Zero declared bindings with a nonempty mask.
reject(raw:sub(1,-2)) -- Truncated mask.
reject(raw..'x') -- Trailing data.
reject(put(#raw,0)) -- Empty mask group / lost destination.
reject(put(#raw-512,33)) -- Invalid document index in group header.
reject(put(#raw-514,128)) -- Unknown group kind/flag bits.
reject(put(#raw,192)) -- Two destinations with one declared binding.
print('PASS masked wire guards:flags,counts,truncation,trailing data,empty/invalid groups and excess destinations')
