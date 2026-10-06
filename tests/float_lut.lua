local ffi=require('ffi');local D=dofile('src/dds.lua');local S=dofile('src/semantics.lua');local P=dofile('src/palette.lua');local Doc=dofile('src/document.lua')
local n=23*8*4;local original=ffi.new('float[?]',n)
for i=0,n-1 do original[i]=(i%101-40)/17 end
original[0]=500000;original[3]=2;original[13*4]=8.5;original[13*4+1]=100000000;original[13*4+2]=-12.5;original[13*4+3]=.46
local bytes=D.encode(original,23,8);local decoded,w,h=D.decode(bytes,23,8)
assert(w==23 and h==8 and ffi.string(original,n*4)==ffi.string(decoded,n*4),'Float DDS round trip changed HDR/negative values')
local recolor=P.copy(original,23,8,{[0]='#FF0080'},function(count)return ffi.new('float[?]',count)end,ffi.copy)
for i=3,n-1 do assert(recolor[i]==original[i],'Base recolor changed an untouched value')end
local changed=ffi.new('float[?]',n);for i=0,n-1 do changed[i]=-123 end
local protected=S.protect(original,changed,23,8)
for row=1,8 do for col=1,23 do for ch=1,4 do local i=S.index(row,col,ch,23,8)
    assert(protected[i]==(S.safe_cell(col,ch)and changed[i]or original[i]),'Effect protection changed wrong channel')
end end end
assert(protected[3]==2 and protected[13*4]==8.5 and protected[13*4+1]==100000000 and protected[13*4+2]==-12.5)
assert(not pcall(D.decode,bytes:sub(1,-2),23,8));assert(not pcall(D.decode,bytes,23,5))
local bad=ffi.new('float[?]',n);ffi.copy(bad,original,n*4);bad[9]=0/0;assert(not pcall(D.encode,bad,23,8))
local model=Doc.new(D);local lut={name='0123456789abcdef',width=23,height=8,values=original}
model.attach({luts={lut}},'tests/presets',{})
model.edit(lut.name,{[4]=.25});assert(model.documents[lut.name].data[4]==.25);model.undo();assert(model.documents[lut.name].data[4]==original[4]);model.redo();assert(model.documents[lut.name].data[4]==.25)
model.row_copy(lut.name,1);model.row_paste(lut.name,2)
for i=0,23*4-1 do assert(model.documents[lut.name].data[23*4+i]==model.documents[lut.name].data[i])end
local Presets=dofile('src/presets.lua');local catalog={identity={target_kind='helmet',target_id=234,armor=123,body=0},luts={lut}}
local get={get=function(id)if id:match('_color$')then return '#112233'else return true end end}
local preset=Presets.encode(catalog,get,model);local values,docs=Presets.decode(preset,catalog)
assert(ffi.string(docs[lut.name],n*4)==ffi.string(model.documents[lut.name].data,n*4),'Full preset changed HDR/emissive floats')
local armor_catalog={identity={target_kind='armor',target_id=234,body=0},luts={lut}}
assert(not pcall(Presets.decode,preset,armor_catalog),'Helmet preset accepted on armor')
assert(not pcall(Presets.decode,preset:gsub('float\t0123456789abcdef\t1\t1[^\n]*\n',''),catalog),'Missing float cell accepted')
assert(values.enabled and values.preserve_effects)
print('PASS: full-float HDR/negative DDS round trip, untouched emissive/mode preservation, default effect protection, malformed rejection, undo/redo and row copy/paste')
