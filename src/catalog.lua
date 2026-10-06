-- Armor-only archive discovery. Uses CowboyBingus's BSD-0-Clause decoders without the automatic matcher.
local C={}
function C.new(m,memory,game)
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
            if read(a,4,b) and u32(b,0)==identity.armor then kit=assert(m.kits.read_kit(read,a,b));break end
            yield()
        end
        assert(kit and kit.kit_type==m.kits.ARMOR,'Equipped armor kit unavailable')
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
        local hashes,pieces={},{}
        for _,piece in ipairs(kit.pieces) do
            if piece.slot>=2 and piece.slot<=9 and piece.tone==0 and (piece.body==identity.body or piece.body==3) then
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
                                    if u32(mt,136+t*4)==m.kits.SLOT_LUT then
                                        local lut=piece.lut~=m.kits.NO_LUT and piece.lut or hex(mt,136+nt*4+t*8)
                                        hashes[lut]=true;pieces[piece.type..':'..piece.slot]=true
                                    end
                                end
                            end
                        end
                    end
                end
                yield()
            end
        end
        local luts={}
        for name in pairs(hashes) do
            local a,r=find(name,m.kits.TYPE_TEXTURE);assert(a,'Original armor LUT unavailable')
            local size=slim.part_size(r,'main');local main=part(a,r,0,size);local info=m.texture.describe(main,size)
            assert(info.width==23 and info.height>=1 and info.height<=32 and info.layers==1,'Unsupported armor LUT')
            local pixels=m.texture.pixels(slim,a,r,info)
            local values,w,h=m.texture.lut(pixels,info,function(bytes)return ffi.new('uint8_t[?]',bytes)end)
            luts[#luts+1]={name=name,values=values,width=w,height=h};yield()
        end
        slim.close();self.slim=nil;table.sort(luts,function(a,b)return a.name<b.name end)
        assert(#luts>0 and #luts<=32,'No supported armor LUTs')
        return {identity=identity,pieces=pieces,luts=luts}
    end
    function self.close()if self.slim then self.slim.close();self.slim=nil end end
    return self
end
return C
