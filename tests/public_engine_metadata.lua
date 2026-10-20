-- Hostile engine functions/metamethods are traps, including child-table paths.
local capture_module = dofile('tools/capture_public_engine_metadata.lua')
local calls = 0
local function forbidden() calls = calls + 1;error('Forbidden metadata side effect') end
local meta = { __index=forbidden, __pairs=forbidden, __tostring=forbidden, __call=forbidden,
    __eq=forbidden, __doc='Static API documentation', __signature='update(resource, bytes)', GLOBALS=_G }
local descriptor = setmetatable({ FORMAT='RGBA32F', RB_FLOAT_COMPONENT=4, create=forbidden,
    _name='RenderBuffer', description='line one\nline two', arbitrary='not an API constant',
    data={ SECRET='do not read' }, live={ SECRET='private object' },
    ESCAPED='\\x41"', TOO_LONG=string.rep('z', 1025), metadata={ signature={ returns='Float32Array' } } }, meta)
descriptor.__index = descriptor
descriptor.CYCLE = { AGAIN=descriptor }
local sr = setmetatable({ Renderer=descriptor, RenderBuffer=descriptor,
    Material=setmetatable({}, { __metatable='protected marker', __tostring=forbidden }),
    Float32Array=forbidden, Mesh={ DOC={ DOC={ DOC={ SIGNATURE='too deep' } } } },
    Unit={ ENUMS={ [1]='not documentation', VALUE=8 }, global_alias=_G, ALIASED_GLOBAL=_G,
        PLAYER={ SECRET='uppercase private' }, rEgIsTrY={ SECRET='mixed private' },
        STATE={ SECRET='uppercase state' }, DaTa={ SECRET='mixed data' } } }, { __index=forbidden })
local old_pairs, old_tostring = pairs, tostring
pairs, tostring = forbidden, forbidden
local result = capture_module.collect(sr, _VERSION)
pairs, tostring = old_pairs, old_tostring
assert(calls == 0 and result.schema == 1 and result.runtime == _VERSION)
assert(result.bytes == #result.text and result.bytes <= result.max_bytes and result.max_depth == 2)
local function has(value) return result.text:find(value, 1, true) ~= nil end
assert(has('Renderer.FORMAT:string="RGBA32F"') and has('Renderer.RB_FLOAT_COMPONENT:number=4'))
assert(has('Renderer._name:string="RenderBuffer"') and has('line one\\x0aline two'))
assert(has('ESCAPED:string="\\x5cx41\\x22"') and has('TOO_LONG:string [string limit]'))
assert(has('__signature:string="update(resource, bytes)"') and has('signature.returns:string="Float32Array"'))
assert(has('Renderer.__index:table ->#1') and has('RenderBuffer:table ->#1'))
assert(has('Material.@metatable:string') and not has('protected marker'))
assert(has('[depth limit]') and not has('too deep') and not has('not an API constant'))
assert(not has('do not read') and not has('private object') and not has('not documentation') and has('[global scope omitted]'))
assert(not has('uppercase private') and not has('mixed private') and not has('uppercase state') and not has('mixed data'),
    'Reserved private aliases were followed through the constant/container path')
descriptor.FORMAT = 'changed'
assert(has('"RGBA32F"'), 'Captured text aliases the input')
for _ = 1, 1000 do assert(calls == 0) end
assert(type(capture_module.on_update) == 'nil' and type(capture_module.on_enable) == 'nil')

local oversized = {}
for i = 1, 10000 do oversized['M' .. i] = forbidden end
local bounded = capture_module.collect({ Unit=oversized }, _VERSION)
assert(bounded.entries <= 512 and bounded.truncated and bounded.bytes <= bounded.max_bytes)
local binary = string.rep(string.char(1), 1024)
local large, leaves = {}, {}
for i = 1, 120 do leaves['VALUE_' .. i] = binary end
for i = 1, 120 do large['TABLE_' .. i] = leaves end
bounded = capture_module.collect({ Renderer=large }, _VERSION)
assert(bounded.truncated and bounded.max_bytes == 24576 and bounded.bytes <= bounded.max_bytes
    and bounded.entries <= bounded.max_entries and bounded.text:find('\\x01', 1, true))
local escaped_capture = bounded
local graph = {}
for i = 1, 300 do graph['T_' .. i] = { signature='x' } end
bounded = capture_module.collect({ Renderer=graph }, _VERSION)
assert(bounded.nodes <= bounded.max_nodes and bounded.truncated)
assert(calls == 0, 'Reflection or budget handling called an engine/metamethod')

-- Actual public LLL config persistence/reload, including worst ASCII JSON
-- escaping and 12 KiB of unrelated settings. No parallel JSON implementation.
local root = os.getenv('EPIC_LLL_TEST_ROOT')
    or assert(os.getenv('USERPROFILE')) .. '/OneDrive/Documents/GitHub/DBF-Suite/LLL'
LLL_METADATA, LLL_CONFIG = dofile(root .. '/src/metadata.lua'), dofile(root .. '/src/config.lua')
local Project = dofile(root .. '/src/project.lua')
local disk = { ['C:/fixture/main.lua']='return mod',
    ['C:/fixture/config/defaults.cfg']='{"unrelated":"' .. string.rep('a', 12288) .. '"}' }
local platform = { native_ffi=false, settings='C:/settings',
    read=function(path, limit) local bytes=disk[path];return bytes and #bytes<=limit and bytes or nil end,
    write=function(path, bytes) disk[path]=bytes;return true end, mkdir=function() return true end }
local entry, spec = { id='metadata_fixture', dir='C:/fixture' },
    { entry='main.lua', defaults='config/defaults.cfg', modules={} }
local public = Project.instantiate(platform, entry, Project.snapshot(platform, entry, spec), function() end)
assert(public.set('capture', escaped_capture) == true)
local saved = assert(disk['C:/settings/metadata_fixture/config.cfg'])
assert(#saved < 65536 and Project.snapshot(platform, entry, spec))
local worst = { text=string.rep('\\"', escaped_capture.max_bytes/2), bytes=escaped_capture.max_bytes,
    schema=1, runtime=_VERSION, max_bytes=escaped_capture.max_bytes, truncated=true }
assert(#worst.text == escaped_capture.max_bytes and public.set('capture', worst) == true)
saved = assert(disk['C:/settings/metadata_fixture/config.cfg'])
assert(#saved < 65536 and #saved <= 2*escaped_capture.max_bytes + 12288 + 1024)
assert(Project.snapshot(platform, entry, spec), 'Worst escaped bounded capture cannot reload through actual LLL')
print('PASS public engine metadata: raw-only constants/docs/metatables, cycles, private/global omission, depth/entry/node/byte budgets and zero engine calls')
