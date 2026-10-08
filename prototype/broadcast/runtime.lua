-- Bundled by build.py; manual console API, no idle polling or editor changes.
local ffi = require('ffi')
local api, memory, game, native, session, root
local revision = 0
-- Keep GPU backing data alive even if the loader drops this chunk after disabling.
local retain = rawget(_G,'EpicLUTBroadcastRetain') or {cache={}, records={}, bytes=0}
local small, big = ffi.new('uint8_t[16]'), ffi.new('uint8_t[1024]')
local function read(address, size, buffer)
    return memory.read_into(m.engine.at(address), size, buffer)
end
local function binding(b) return m.engine.binding(read, b.material, m.engine.LUT_SLOT, small, big) end
local function present(b)
    for _, v in ipairs(m.engine.unit_materials(native, b.unit)) do
        if v.mesh == b.mesh and v.material == b.material then return true end
    end
    return false
end
local function word(n)
    return string.char(n%256, math.floor(n/256)%256, math.floor(n/65536)%256, math.floor(n/16777216)%256)
end
local function u32(s, o)
    local a,b,c,d=s:byte(o+1,o+4); assert(d, 'Truncated broadcast')
    return a+b*256+c*65536+d*16777216
end
local function file(path, limit)
    local f=assert(io.open(path,'rb')); local s=f:read(limit+1); f:close()
    assert(#s<=limit,'Broadcast file too large'); return s
end
local function roster() return m.remote.list(memory, game, m.avatar) end
local function gather(identity)
    local out={}
    for _, u in ipairs(m.avatar.units(memory, identity, nil, 0, 9)) do
        for _, v in ipairs(m.engine.unit_materials(native,u.unit)) do
            local b={unit=u.unit,mesh=v.mesh,material=v.material,helmet=u.slot==0}
            local object=binding(b)
            if object and object~=0 then b.original=object; b.current=object; out[#out+1]=b end
        end
    end
    return out
end
local function start()
    assert(not api, 'Broadcast prototype already active')
    assert(not rawget(_G,'EpicLUTBroadcast'), 'Another broadcast prototype is active')
    memory=m.bingus_memory.new(m.bingus_runtime)
    local ok,why=memory.verify_build({
        exe_sha256='F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06',
        game_sha256='2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E'})
    assert(ok,why)
    _G.EpicLUTBroadcastRetain=retain
    game=memory.address(assert(memory.module('game.dll')))
    native=assert(m.engine.open(memory,game,memory.address(assert(memory.module()))))
    root=assert(os.getenv('LOCALAPPDATA'))..'/Epic LUT/broadcast-poc'
    session=m.binding_session.new({retain=retain,present=present,binding=binding,
        key=function(b) return b.unit..':'..b.mesh..':'..b.material end,
        create_texture=function(w,h,data) return m.engine.create_texture(native,w,h,data,read,small) end,
        bind=function(b,object) m.engine.bind(native,b.material,m.engine.LUT_SLOT,object); native.commit(b.mesh) end})
    api={}
    function api.peers() return roster() end
    function api.publish(path,scope)
        assert(scope=='armor' or scope=='helmet','Choose armor or helmet')
        local bytes=file(path,m.dds.MAX_BYTES)
        m.dds.decode(bytes) -- validate before sending
        local own
        for _,p in ipairs(roster()) do if p.owned then assert(not own); own=p end end
        assert(own,'Local player unavailable')
        revision=revision+1
        local packet='ELB1'..word(own.peer_low)..word(own.peer_high)..word(scope=='armor' and 1 or 2)
            ..word(revision)..word(#bytes)..bytes
        local f=assert(io.open(root..'/outgoing.tmp','wb'),'Start the Python peer first')
        assert(f:write(packet)); f:close()
        os.remove(root..'/outgoing.bin'); assert(os.rename(root..'/outgoing.tmp',root..'/outgoing.bin'))
        return own.peer,revision
    end
    function api.restore() return session.restore() end
    function api.receive(expected_peer)
        assert(type(expected_peer)=='string' and expected_peer:match('^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$'),
            'Supply the remote peer ID from peers()')
        local packet=file(root..'/incoming.bin',m.dds.MAX_BYTES+24)
        assert(packet:sub(1,4)=='ELB1' and #packet==24+u32(packet,20),'Invalid broadcast envelope')
        local peer=string.format('%08x%08x',u32(packet,8),u32(packet,4))
        assert(peer==expected_peer:lower(),'Received preset belongs to another peer')
        local scope=u32(packet,12); assert(scope==1 or scope==2)
        local data,w,h=m.dds.decode(packet:sub(25))
        local people=roster(); local selected,other_materials
        other_materials={}
        for _,p in ipairs(people) do
            if p.peer==peer then assert(not p.owned,'Remote-only receive'); selected=p
            else for _,b in ipairs(gather(p)) do other_materials[b.material]=true end end
        end
        assert(selected,'Peer is not in this session')
        -- Release the previous operation before gathering fresh original bindings.
        assert(session.restore(),'Previous bindings could not be restored')
        local targets,seen={},{}
        local selected_bindings=gather(selected)
        for _,b in ipairs(selected_bindings) do
            if b.helmet~=(scope==2) then other_materials[b.material]=true end
        end
        for _,b in ipairs(selected_bindings) do
            if b.helmet==(scope==2) then
                assert(not other_materials[b.material],'Shared material: independent recoloring is unavailable')
                if not seen[b.material] then targets[#targets+1]=b; seen[b.material]=true end
            end
        end
        return session.apply({data=data,width=w,height=h},targets)
    end
    _G.EpicLUTBroadcast=api
end
return {name='Epic LUT Broadcast POC',author='Goose',on_enable=function() start() end,
    on_disable=function()
        if session then assert(session.restore(),'Broadcast restore pending; keep module loaded') end
        _G.EpicLUTBroadcast=nil; api=nil
        -- Retain native buffers for the lifetime of this module; no speculative GPU retirement.
    end}
