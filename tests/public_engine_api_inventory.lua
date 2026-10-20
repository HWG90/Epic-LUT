-- All engine functions and metamethods are traps. Reflection must call none.
local inventory = dofile('tools/capture_public_engine_api.lua')
local calls = 0
local function forbidden() calls = calls + 1; error('Engine call during reflection') end
local sr = setmetatable({
    Material = setmetatable({ set_resource = forbidden, current = forbidden, version = 1 }, { __index = forbidden }),
    RenderBuffer = { update_buffer = forbidden, create_buffer = forbidden },
    Float32Array = forbidden,
}, { __index = forbidden })
local capture = inventory.collect(sr, _VERSION)
assert(calls == 0 and capture.entries == 5 and capture.runtime == 'Lua 5.1')
assert(capture.namespaces.Material.kind == 'table')
assert(table.concat(capture.namespaces.Material.members, ',') == 'current:function,set_resource:function,version:number')
assert(capture.namespaces.Float32Array.kind == 'function' and #capture.namespaces.Float32Array.members == 0)
assert(capture.namespaces.Mesh.kind == 'nil', 'Virtual namespace lookup was invoked')
sr.Material.version = 2
assert(capture.namespaces.Material.members[3] == 'version:number')
local oversized = {}
for i = 1, 4097 do oversized['member' .. i] = forbidden end
assert(not pcall(inventory.collect, { Material = oversized }, _VERSION))
assert(calls == 0, 'Budget failure invoked an engine function')
print('PASS public engine API inventory: one-shot bounded metadata, owned capture and zero engine calls/metamethods')
