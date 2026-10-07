-- Bounded little-endian DDS float interchange; no image decoder or code execution in game.
local ffi=require('ffi')
local bit=require('bit')
local D={MAX_BYTES=1024*1024}
local function u32(s,o)
    assert(o>=0 and o+4<=#s,'Truncated DDS header')
    local a,b,c,d=s:byte(o+1,o+4);return a+b*256+c*65536+d*16777216
end
local function word(n)
    return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)
end
local function half(n)
    local sign=n>=32768 and -1 or 1;local e=math.floor(n/1024)%32;local f=n%1024
    if e==0 then return sign*f*2^-24 end
    assert(e~=31,'Nonfinite DDS value');return sign*(1+f/1024)*2^(e-15)
end
function D.validate(data,w,h)
    assert(w>=1 and w<=64 and h>=1 and h<=32 and w%1==0 and h%1==0,'Unsupported LUT dimensions')
    for i=0,w*h*4-1 do local v=tonumber(data[i]);assert(v==v and math.abs(v)~=math.huge,'Nonfinite LUT value')end
end
function D.decode(s,expected_w,expected_h)
    assert(type(s)=='string' and #s<=D.MAX_BYTES and #s>=128 and s:sub(1,4)=='DDS ','Invalid DDS')
    assert(u32(s,4)==124 and u32(s,76)==32,'Invalid DDS header sizes')
    local w,h=u32(s,16),u32(s,12);local mip=u32(s,28)
    assert(u32(s,24)<=1 and bit.band(u32(s,8),0x800000)==0 and u32(s,112)==0,'Only 2D LUTs are supported; cube and volume textures are unsupported')
    local format,offset=u32(s,84),128
    if format==0x30315844 then
        assert(#s>=148 and u32(s,132)==3 and u32(s,136)==0 and u32(s,140)==1,'Unsupported DDS texture kind')
        format=u32(s,128);offset=148
    elseif format==113 then format=10 elseif format==116 then format=2 else error('DDS requires RGBA16F or RGBA32F',0)end
    assert(format==2 or format==10,'DDS requires RGBA16F or RGBA32F')
    assert(w>=1 and w<=64 and h>=1 and h<=32,'DDS dimensions exceed LUT bounds')
    if expected_w then assert(w==expected_w and h==expected_h,'DDS dimensions do not match selected LUT')end
    local levels=math.max(1,mip);local max_levels=1;local extent=math.max(w,h)
    while extent>1 do max_levels=max_levels+1;extent=math.floor(extent/2)end
    assert(levels<=max_levels,'DDS mip count exceeds texture dimensions')
    local n=w*h*4;local size=n*(format==2 and 4 or 2);local total=0
    for level=0,levels-1 do total=total+math.max(1,math.floor(w/2^level))*math.max(1,math.floor(h/2^level))*4*(format==2 and 4 or 2)end
    assert(#s==offset+total,'DDS payload size mismatch')
    local out=ffi.new('float[?]',n)
    if format==2 then ffi.copy(out,s:sub(offset+1,offset+size),size)
    else local b=ffi.new('uint16_t[?]',n);ffi.copy(b,s:sub(offset+1,offset+size),size);for i=0,n-1 do out[i]=half(tonumber(b[i]))end end
    D.validate(out,w,h);return out,w,h
end
function D.encode(data,w,h)
    D.validate(data,w,h)
    local words={124,0x100f,h,w,w*16,0,1}
    for i=1,11 do words[#words+1]=0 end
    for _,v in ipairs({32,4,0x30315844,0,0,0,0,0,0x1000,0,0,0,0,2,3,0,1,0})do words[#words+1]=v end
    local chunks={'DDS '};for _,v in ipairs(words)do chunks[#chunks+1]=word(v)end
    chunks[#chunks+1]=ffi.string(data,w*h*16);return table.concat(chunks)
end
function D.read(path,w,h)
    local f=assert(io.open(path,'rb'),'LUT file not found');local bytes=f:read(D.MAX_BYTES+1);f:close()
    return D.decode(bytes,w,h),bytes
end
function D.write(path,data,w,h)
    local bytes=D.encode(data,w,h);local tmp=path..'.pending';local f=assert(io.open(tmp,'wb'));assert(f:write(bytes));assert(f:close())
    -- Windows rename does not overwrite; preserve the old file if replacement fails.
    local old=io.open(path,'rb');if old then local previous=old:read('*a');old:close()
        local b=assert(io.open(path..'.previous','wb'));assert(b:write(previous));assert(b:close());assert(os.remove(path))
    end
    local ok,why=os.rename(tmp,path)
    if not ok then os.rename(path..'.previous',path);error(why,0)end
    return path
end
return D
