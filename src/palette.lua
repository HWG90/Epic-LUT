-- Own editor logic. Only primary-color RGB (column zero) changes; alpha and all other columns stay exact.
local P={}
function P.rgb(hex)
    assert(type(hex)=='string' and hex:match('^#%x%x%x%x%x%x$'),'Invalid RGB color')
    return tonumber(hex:sub(2,3),16)/255,tonumber(hex:sub(4,5),16)/255,tonumber(hex:sub(6,7),16)/255
end
function P.hex(values,row,width)
    local at=row*width*4
    local function byte(v) return math.floor(math.max(0,math.min(1,v))*255+0.5) end
    return string.format('#%02X%02X%02X',byte(values[at]),byte(values[at+1]),byte(values[at+2]))
end
function P.copy(original,width,height,overrides,allocate,copy)
    assert(width==23 and height>=1 and height<=32,'Unsupported LUT dimensions')
    local out=allocate(width*height*4);copy(out,original,width*height*16)
    for row,hex in pairs(overrides) do
        assert(type(row)=='number' and row%1==0 and row>=0 and row<height,'Invalid LUT row')
        local r,g,b=P.rgb(hex);local at=row*width*4;out[at],out[at+1],out[at+2]=r,g,b
    end
    return out
end
return P
