-- A rejected forward bind must preserve the prior owned texture and permit
-- Restore; a foreign replacement is never adopted or overwritten by rollback.
local ffi = require('ffi')
local B = dofile('src/gear/binding_session.lua')
local function fixture()
    local current, writes, failure = 10, 0
    local session = B.new({
        retain = { cache = {}, records = {}, bytes = 0 },
        present = function()
            return true
        end,
        binding = function()
            return current
        end,
        key = function()
            return 'material'
        end,
        create_texture = function(_, _, data)
            return { object = 100 + data[0], data = data }
        end,
        bind = function(_, object)
            writes = writes + 1
            if failure then
                if failure == 'foreign' then
                    current = 999
                end
                error('bind rejected', 0)
            end
            current = object
        end,
    })
    local b = { original = 10, current = 10 }
    local old = { width = 23, height = 1, data = ffi.new('float[92]') }
    old.data[0] = 1
    session.apply(old, { b })
    local wanted = { width = 23, height = 1, data = ffi.new('float[92]') }
    wanted.data[0] = 2
    return session,
        b,
        old,
        wanted,
        function(value)
            failure = value
        end,
        function()
            return current, writes
        end
end
do
    local session, b, old, wanted, fail, read = fixture()
    local texture = b.texture
    fail('unchanged')
    local ok = pcall(session.apply, wanted, { b })
    local current, writes = read()
    assert(not ok and current == 101 and writes == 2, 'Rejected bind caused an unnecessary native rollback')
    assert(
        b.current == 101 and b.previous == nil and b.texture == texture and b.document == old,
        'Rejected bind lost the prior owned metadata'
    )
    fail(nil)
    assert(
        session.restore() and read() == 10,
        'Restore could not remove the prior texture after a rejected replacement'
    )
end
do
    local session, b, old, wanted, fail, read = fixture()
    fail('foreign')
    assert(not pcall(session.apply, wanted, { b }))
    local current, writes = read()
    assert(current == 999 and writes == 2 and b.current == 102, 'Rollback adopted or overwrote a foreign binding')
    fail(nil)
    assert(session.restore())
    current, writes = read()
    assert(current == 999 and writes == 2, 'Restore overwrote a foreign binding after the failed apply')
end
print('PASS binding rollback: already-old native state restores prior metadata; foreign replacements remain untouched')

do
    local current, allocations, writes = 10, 0, 0
    local retain={cache={},records={},bytes=0}
    local session=B.new({retain=retain,present=function() return true end,
        binding=function() return current end,key=function() return 'one' end,
        create_texture=function(_,_,data) allocations=allocations+1;return {object=100,data=data} end,
        bind=function(_,object) writes=writes+1;current=object end})
    local b={current=10,original=10}
    local doc={width=23,height=8,data=ffi.new('float[736]')}
    local plan=session.prepare(doc,{b})
    assert(current==10 and writes==0 and allocations==1,'Preparation changed a material')
    session.commit(plan)
    for i=1,1000 do session.apply(doc,{b}) end
    assert(allocations==1 and writes==1 and #session.owned==1 and #retain.records==1,
        'Unchanged palette reallocated or rebound')
    local stale=session.prepare(doc,{b});current=999
    assert(not pcall(session.commit,stale) and writes==1,'Prepared plan overwrote foreign ownership')
    local ok=pcall(session.prepare,{width=1/0,height=8,data=doc.data},{b})
    assert(not ok and allocations==1)
end
print('PASS shared apply pipeline: prepare makes no writes, exact reuse stays idle, stale commit and dimensions fail closed')
