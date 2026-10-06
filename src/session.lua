-- Own binding manager. Immutable per-edit textures are retained to process exit, never reused or freed speculatively.
local S={}
function S.new(m,memory,native,retain)
    local ffi=require('ffi');local small,big=ffi.new('uint8_t[96]'),ffi.new('uint8_t[1024]')
    local function read(a,n,b)return memory.read_into(ffi.cast('const uint8_t *',a),n,b)end
    local function binding(material)return m.engine.binding(read,material,m.engine.LUT_SLOT,small,big)end
    local self={bindings={},catalog=nil,resources={}}
    local function present(b)
        if native.alive(b.unit)==0 then return false end
        for _,v in ipairs(m.engine.unit_materials(native,b.unit))do if v.mesh==b.mesh and v.material==b.material then return true end end
        return false
    end
    function self.restore()
        local pending={};local meshes={}
        for _,b in ipairs(self.bindings)do
            local current=present(b) and binding(b.material)
            if current and (current==b.current or current==b.previous) then
                local ok=pcall(function()m.engine.bind(native,b.material,m.engine.LUT_SLOT,b.original);native.commit(b.mesh)end)
                if not ok or binding(b.material)~=b.original then pending[#pending+1]=b end
            end
        end
        self.bindings=pending
        return #pending==0
    end
    function self.capture(catalog,units)
        assert(self.restore(),'Original binding restoration pending');self.catalog=catalog;self.resources={}
        local names={}
        for _,lut in ipairs(catalog.luts)do local object=m.engine.texture_object(native,lut.name);if object then names[object]=lut end end
        local owned={};local seen={}
        for _,u in ipairs(units)do
            if catalog.pieces[u.type..':'..u.slot] and native.alive(u.unit)~=0 then
                for _,v in ipairs(m.engine.unit_materials(native,u.unit))do
                    local original=binding(v.material);local lut=names[original]
                    if lut then
                        local key=u.unit..':'..v.mesh..':'..v.material
                        if not seen[key] then self.bindings[#self.bindings+1]={unit=u.unit,mesh=v.mesh,material=v.material,original=original,current=original,lut=lut};seen[key]=true end
                        owned[v.material]=true
                    end
                end
            end
        end
        assert(#self.bindings>0,'Armor LUT bindings unavailable or another color writer owns them')
        -- Reject material pointers shared with any non-target local piece (helmet, cape, skin/undergarment).
        for _,u in ipairs(m.avatar.units(memory,catalog.identity,nil,0,9))do
            if not catalog.pieces[u.type..':'..u.slot] and native.alive(u.unit)~=0 then
                for _,v in ipairs(m.engine.unit_materials(native,u.unit))do assert(not owned[v.material],'Armor material shared with excluded local piece')end
            end
        end
    end
    function self.apply(handle)
        assert(self.catalog,'Armor catalogue not ready')
        assert(#self.bindings>0,'Armor bindings must be recaptured after restoration')
        local planned={};local bytes=0
        for _,lut in ipairs(self.catalog.luts)do
            local overrides={};for row=0,lut.height-1 do
                local id=lut.name..'_r'..(row+1)
                if handle.get(id..'_on')then overrides[row]=handle.get(id..'_color')end
            end
            if next(overrides)then
                local data=m.palette.copy(lut.values,lut.width,lut.height,overrides,function(n)return ffi.new('float[?]',n)end,ffi.copy)
                planned[lut.name]={lut=lut,data=data};bytes=bytes+lut.width*lut.height*16
            end
        end
        assert(retain.bytes+bytes<=8*1024*1024 and #retain.records+#self.catalog.luts<=2048,'Session texture budget exhausted; originals can still be restored')
        for _,b in ipairs(self.bindings)do assert(present(b) and binding(b.material)==b.current,'Armor binding ownership changed')end
        for name,p in pairs(planned)do
            -- Reserve and retain even uncertain native failures: native calls may enqueue work before raising.
            retain.bytes=retain.bytes+p.lut.width*p.lut.height*16
            local keep={data=p.data};retain.records[#retain.records+1]=keep
            p.texture=assert(m.engine.create_texture(native,p.lut.width,p.lut.height,p.data,read,small));keep.texture=p.texture
        end
        for _,b in ipairs(self.bindings)do
            local p=planned[b.lut.name];local object=p and p.texture.object or b.original
            -- Record intended ownership before bind, so partial failure remains restorable.
            b.previous=b.current;b.current=object;m.engine.bind(native,b.material,m.engine.LUT_SLOT,object);native.commit(b.mesh)
            assert(binding(b.material)==object,'LUT binding readback failed')
            b.previous=nil
        end
        return true
    end
    return self
end
return S
