-- Armor-only archive discovery. Uses CowboyBingus's BSD-0-Clause decoders without the automatic matcher.
local C={}
function C.new(m,memory,game,target)
    target=target or 'Armor'
    local ffi=require('ffi');local function read(a,n,b)return memory.read_into(ffi.cast('const uint8_t *',a),n,b)end
    local function u32(b,o)return b[o]+b[o+1]*256+b[o+2]*65536+b[o+3]*16777216 end
    local function ptr(b,o)local v=u32(b,o)+u32(b,o+4)*4294967296;assert(v>=65536 and v<2^47,'Invalid pointer');return v end
    local function hex(b,o)return string.format('%08x%08x',u32(b,o+4),u32(b,o))end
    local self={}
    function self.load(identity,yield)
        local b=ffi.new('uint8_t[96]');assert(read(game+0x33264f8,8,b));local manager=ptr(b,0)
        assert(read(manager,16,b));local list,count=ptr(b,0),u32(b,8);assert(count>0 and count<=4096)
        local kit
        for i=0,count-1 do
            assert(read(list+i*8,8,b));local a=ptr(b,0)
            if read(a,4,b) and u32(b,0)==(identity.target_id or identity.armor) then kit=assert(m.kits.read_kit(read,a,b));break end
            yield()
        end
        assert(kit and kit.kit_type==(target=='Helmet' and m.kits.HELMET or m.kits.ARMOR),'Equipped '..target..' kit unavailable')
        local folder,n=m.files.game_data_folder();local files=m.files.new(folder,n,memory.time)
        local slim=m.slim.open(files,'',yield);self.slim=slim
        local function find(name,kind)
            for _,archive in ipairs({kit.archive,unpack(m.kits.SHARED_ARCHIVES)}) do
                local record=slim.locate(archive,name,kind);if record then return archive,record end
            end
        end
        local function part(archive,record,offset,size)
            assert(size>=0 and size<=1024*1024,'Archive metadata budget exceeded')
            local data=ffi.new('uint8_t[?]',math.max(1,size));slim.part(archive,record,'main',offset,size,data,0);return data
        end
        local hashes,pieces,references={}, {},{}
        for _,piece in ipairs(kit.pieces) do
            local selected_slot=(target=='Helmet' and piece.slot==0) or (target~='Helmet' and piece.slot>=2 and piece.slot<=9)
            if selected_slot and piece.tone==0 and (piece.body==identity.body or piece.body==3) then
                local archive,record=find(piece.path,m.kits.TYPE_UNIT)
                if record then
                    local head=part(archive,record,0,116);local at=u32(head,112)
                    if at>0 then
                        local nmat=u32(part(archive,record,at,4),0);assert(nmat<=64)
                        local tabledata=part(archive,record,at,4+nmat*12)
                        for j=0,nmat-1 do
                            local material=hex(tabledata,4+nmat*4+j*8);local ma,mr=find(material,m.kits.TYPE_MATERIAL)
                            if ma then
                                local mh=part(ma,mr,0,136);local nt=u32(mh,64);assert(nt<=64)
                                local mt=part(ma,mr,0,136+nt*12)
                                for t=0,nt-1 do
                                    local slot=u32(mt,136+t*4);local resource=hex(mt,136+nt*4+t*8)
                                    if slot==m.kits.SLOT_LUT and piece.lut~=m.kits.NO_LUT then resource=piece.lut end
                                    if slot==m.kits.SLOT_PATTERN and piece.pattern and piece.pattern~=m.kits.NO_LUT then resource=piece.pattern end
                                    references[#references+1]={slot=slot,name=resource,material=material,piece=piece.type..':'..piece.slot}
                                    hashes[resource]=hashes[resource]or {slots={}};hashes[resource].slots[slot]=true
                                end
                            end
                        end
                    end
                end
                yield()
            end
        end
        local luts={}
        local unsupported={}
        for name,consumer in pairs(hashes) do
            local a,r=find(name,m.kits.TYPE_TEXTURE)
            if a then
                local ok,info,values=pcall(function()
                    local size=slim.part_size(r,'main');local main=part(a,r,0,size);local described,info=pcall(m.texture.describe,main,size)
                    if not described then
                        if size>=192+148 and u32(main,192)==0x20534444 and u32(main,192+128)==2 then
                            local w,h=u32(main,192+16),u32(main,192+12)
                            info={format=2,width=w,height=h,mips=u32(main,192+28),layers=u32(main,192+140),total=w*h*16,layer_bytes=w*h*16,mip_offsets={[0]=0}}
                        else error(info,0)end
                    end
                    if (info.format~=10 and info.format~=2)or info.layers~=1 or info.width>64 or info.height>32 or info.width<1 or info.height<1 then return info,nil end
                    local pixels=m.texture.pixels(slim,a,r,info)
                    local data
                    if info.format==2 then data=ffi.new('float[?]',info.width*info.height*4);pixels(0,info.width*info.height*16,data,0)
                    else data=m.texture.lut(pixels,info,function(bytes)return ffi.new('uint8_t[?]',bytes)end)end
                    m.dds.validate(data,info.width,info.height)
                    return info,data
                end)
                if ok and values then
                    local lookup=info.width==23 and 'material' or (info.width==3 and info.height==1 and 'pattern' or (info.width==16 and 'cape' or 'unclassified'))
                    luts[#luts+1]={name=name,values=values,width=info.width,height=info.height,lookup_type=lookup,slots=consumer.slots}
                    for _,ref in ipairs(references)do if ref.name==name then pieces[ref.piece]=true end end
                else unsupported[#unsupported+1]={name=name,reason=ok and 'Not a bounded single-layer float lookup' or tostring(info)}end
            else unsupported[#unsupported+1]={name=name,reason='Texture absent from owning/shared archives'}end
            yield()
        end
        slim.close();self.slim=nil;table.sort(luts,function(a,b)return a.name<b.name end)
        assert(#luts>0 and #luts<=32,'No supported armor LUTs')
        return {identity=identity,pieces=pieces,luts=luts,references=references,unsupported=unsupported}
    end
    function self.close()if self.slim then self.slim.close();self.slim=nil end end
    return self
end
return C
