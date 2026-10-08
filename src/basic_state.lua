-- Independent editor copies, keyed by target and original resource object.
local B={}
local ffi=require('ffi')
function B.clone(source,label)
    local data=ffi.new('float[?]',source.width*source.height*4)
    ffi.copy(data,source.data,source.width*source.height*16)
    return {data=data,width=source.width,height=source.height,source=label or source.source,revision=0}
end
function B.copy(destination,source)
    assert(destination.width==source.width,'Palette columns differ')
    local rows=math.min(destination.height,source.height)
    ffi.copy(destination.data,source.data,rows*destination.width*16)
    destination.revision=(destination.revision or 0)+1
    return rows
end
function B.new()
    local self={documents={}}
    function self.get(key,source,label)
        if not self.documents[key]and source then self.documents[key]=B.clone(source,label)end
        return self.documents[key]
    end
    function self.clear()for key in pairs(self.documents)do self.documents[key]=nil end end
    return self
end
return B
