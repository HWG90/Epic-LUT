-- Armor-only archive discovery. Uses CowboyBingus's BSD-0-Clause decoders without the automatic matcher.
local C={}
function C.read_rgba32f(pixels,width,height)
    local ffi=require('ffi');local data=ffi.new('float[?]',width*height*4)
    -- Archive readers advance byte offsets across chunks/stream parts.
    pixels(0,width*height*16,ffi.cast('uint8_t *',data),0)
    return data
end
function C.new(m,memory,game,target,trace)
    target=target or 'Armor'
    local ffi=require('ffi');local self={}
    local function phase(message)self.phase=message;if trace then trace(message)end end
    local function read(a,n,b)return memory.read_into(ffi.cast('const uint8_t *',a),n,b)end
    local function u32(b,o)return b[o]+b[o+1]*256+b[o+2]*65536+b[o+3]*16777216 end
    local function ptr(b,o)local v=u32(b,o)+u32(b,o+4)*4294967296;assert(v>=65536 and v<2^47,'Invalid pointer');return v end
    function self.load(identity,yield)
        phase('kit lookup')
        local b=ffi.new('uint8_t[96]');assert(read(game+0x33264f8,8,b));local manager=ptr(b,0)
        assert(read(manager,16,b));local list,count=ptr(b,0),u32(b,8);assert(count>0 and count<=4096)
        local kit
        for i=0,count-1 do
            assert(read(list+i*8,8,b));local a=ptr(b,0)
            if read(a,4,b)and u32(b,0)==(identity.target_id or identity.armor)then kit=assert(m.kits.read_kit(read,a,b));break end
            yield()
        end
        assert(kit and kit.kit_type==(target=='Helmet'and m.kits.HELMET or m.kits.ARMOR),'Equipped kit unavailable')
        assert(#kit.pieces>0,'Equipped kit has no pieces')
        local folder=assert(m.paths and m.paths.files,'Discovery workspace unavailable')
        self.client=m.native_import.new(folder,'catalog'..target:lower())
        self.client.discover(kit,identity.body,target:lower());phase('waiting for archive worker')
        local began=os.time();local next_poll=0;local manifest
        while not manifest do
            if memory.time()>=next_poll then
                next_poll=memory.time()+0.1
                local message,_,metadata=self.client.poll()
                if message then assert(metadata and metadata.catalog,message);manifest=metadata.catalog end
            end
            assert(os.time()-began<120,'Archive worker timed out; check the private file-service logs')
            if not manifest then yield()end
        end
        assert(manifest:match('^catalog%-%w+%.tsv$'),'Invalid discovery manifest filename')
        local f=assert(io.open(folder..'/'..manifest,'rb'));local text=f:read(131073);f:close();assert(#text<=131072,'Discovery manifest exceeds budget')
        local result={identity=identity,luts={},pieces={},references={},unsupported={}};local seen={}
        phase('loading validated original LUTs')
        for line in text:gmatch('[^\r\n]+')do
            local kind=line:match('^([^\t]+)')
            if kind=='lut'then
                local name,w,h,lookup,file,slots=line:match('^lut\t([%x]+)\t(%d+)\t(%d+)\t([%w_]+)\t([%w_-]+%.dds)\t([%d,]+)$')
                assert(name and #name==16,'Invalid discovered LUT');w,h=tonumber(w),tonumber(h)
                assert(not seen[name]and file==manifest:gsub('%.tsv$','')..'-'..name..'.dds'and #result.luts<32,'Invalid discovery payload');seen[name]=true
                assert(lookup=='material'or lookup=='pattern'or lookup=='cape'or lookup=='unclassified','Invalid lookup classification')
                local data=m.dds.read(folder..'/'..file,w,h);local slot_set={}
                for slot in slots:gmatch('%d+')do local value=tonumber(slot);assert(value<=4294967295);slot_set[value]=true end
                result.luts[#result.luts+1]={name=name,width=w,height=h,values=data,lookup_type=lookup,slots=slot_set}
            elseif kind=='piece'then local piece=assert(line:match('^piece\t(%d+:%d+)$'));result.pieces[piece]=true
            elseif kind=='reference'then
                local slot,name,material,piece=line:match('^reference\t(%d+)\t([%x]+)\t([%x]+)\t(%d+:%d+)$')
                assert(slot and #name==16 and #material==16 and #result.references<4096,'Invalid texture reference')
                assert(tonumber(slot)<=4294967295,'Invalid texture slot')
                result.references[#result.references+1]={slot=tonumber(slot),name=name,material=material,piece=piece}
            elseif kind=='unsupported'then
                local name,reason=line:match('^unsupported\t([%x]+)\t([^\t]+)$');assert(name and #name==16,'Invalid unsupported texture record')
                result.unsupported[#result.unsupported+1]={name=name,reason=reason}
            else error('Unknown discovery manifest record',0)end
        end
        assert(#result.luts>0,'No supported equipped LUTs');phase('archive worker discovery complete')
        return result
    end
    function self.close()self.client=nil end
    return self
end
return C
