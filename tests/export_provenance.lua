local ffi = require('ffi')
local X = dofile('src/presets/export_provenance.lua')
local function document(width, value, resource)
    return {
        width = width,
        height = 1,
        resource = resource,
        data = ffi.new('float[?]', width * 4, value or 0),
    }
end
local function fixture()
    local calls = { logs = {}, caches = {}, read = 0, refresh = 0, stop = 0, scan = 0, capture = 0 }
    local stock = document(1, 0, 'stock')
    local colors = document(1, 0.5, 'stock')
    local pattern = document(3, 0.25, 'pattern')
    local b = { unit = 1, mesh = 1, material = 100, save_key = '1:1', original = 11, current = 21, kind = 'armor' }
    local p = { unit = 1, mesh = 1, material = 100, save_key = '1:1', original = 12, current = 22, kind = 'armor' }
    local refused = { unit = 2, save_key = '2:1', original = 13, current = 23, kind = 'helmet' }
    local groups = { { bindings = { b } } }
    local patterns = { { bindings = { p } } }
    local identity, sources = {}, {}
    local modules = {
        engine = { LUT_SLOT = 8 },
        avatar = {},
        binding_provenance_script = 'script',
        binding_provenance_reader = 'reader',
        original_snapshot_reader = 'snapshots',
        windows = {},
        binding_names = { section = function() end, mesh = function() end },
        binding_unit_layout = { parse = function() end },
        gear_catalog = {
            kind = function(binding)
                return binding.kind
            end,
        },
    }
    modules.unit_identity = {
        new = function()
            return {
                resource = function(unit, actual)
                    assert(actual == identity)
                    assert(unit == 1, 'No unique pointer proof')
                    return '0000000000000001'
                end,
            }
        end,
    }
    modules.material_identity = {
        new = function(_, deps)
            assert(deps.single_material(b))
            return {}
        end,
    }
    modules.binding_provenance = {
        kit_override = function(read, game, actual, binding, resource, slot)
            assert(actual == identity and slot == 8 and resource == '0000000000000001')
            assert(read(65536, 1) == 'x')
            return nil, { archive = '0000000000000002' }
        end,
        matches = function(saved, actual)
            return saved == actual
        end,
        new = function(deps)
            assert(type(deps.unit_resource) == 'function' and type(deps.material_source) == 'function')
            return {
                capture = function(binding, spec)
                    calls.capture = calls.capture + 1
                    assert(spec.original)
                    local source = sources[binding] or { binding = binding }
                    sources[binding] = source
                    return source, binding
                end,
            }
        end,
    }
    modules.binding_source_cache = {
        new = function(deps)
            assert(
                deps.binding_provenance == modules.binding_provenance and deps.original_snapshot_reader == 'snapshots'
            )
            assert(
                deps.gear_catalog == nil and deps.unit_identity == nil,
                'Cache received unrelated controller dependencies'
            )
            local cache = { state = 'idle', index_stamp = 'test', valid = true }
            function cache.start(units, force)
                assert(force == true)
                calls.request = units
                cache.state = 'loading'
                return true
            end
            function cache.tick()
                if cache.complete then
                    cache.state = 'ready'
                end
            end
            function cache.validate_scope()
                if not cache.valid then
                    cache.state = 'stale'
                    return false, 'Current loose patch payloads changed'
                end
                return true
            end
            function cache.material(resource)
                return 'material:' .. resource
            end
            function cache.unit(resource)
                return 'unit:' .. resource
            end
            function cache.id_available(_, resource)
                return resource ~= 'occupied'
            end
            function cache.close()
                if cache.cleanup_pending then
                    return false
                end
                cache.state = 'closed'
                return true
            end
            calls.caches[#calls.caches + 1] = cache
            return cache
        end,
    }
    local host = {
        memory = {
            read_into = function(_, size, buffer)
                calls.read = calls.read + 1
                ffi.copy(buffer, ('x'):rep(size), size)
                return true
            end,
        },
        game = {},
        paths = {},
        appearance_read = function() end,
        lua_engine = function()
            return {}
        end,
        current_identity = function()
            return identity
        end,
        material_count = function()
            return 1
        end,
        material_at = function()
            return 100
        end,
        groups = function()
            return groups
        end,
        pattern_groups = function()
            return patterns
        end,
        original = function(object)
            return object == 12 and pattern or stock
        end,
        present = function(binding)
            return not binding.dead
        end,
        binding = function(binding)
            return binding.foreign or binding.current
        end,
        applied_document = function(binding)
            return binding == p and pattern or colors
        end,
        refresh = function(silent)
            assert(silent)
            calls.refresh = calls.refresh + 1
        end,
        stop_identification = function()
            calls.stop = calls.stop + 1
            return true
        end,
        stop_pattern_flash = function()
            calls.stop = calls.stop + 1
            return true
        end,
        scan_patterns = function()
            calls.scan = calls.scan + 1
        end,
        log = function(value)
            calls.logs[#calls.logs + 1] = value
        end,
    }
    return X.new(modules, host), calls, groups, patterns, b, p, refused, stock, colors, pattern
end
local function rejected(fn, needle)
    local ok, why = pcall(fn)
    assert(not ok and tostring(why):find(needle, 1, true), tostring(why))
end

local service, calls, groups, patterns, b, p, refused, stock, colors, pattern = fixture()
assert(service.state() == nil and service.close())
for _, bounds in ipairs({ { 65535, 1 }, { 2 ^ 47, 1 }, { 65536, 0 }, { 65536, 97 } }) do
    rejected(function()
        service.read(bounds[1], bounds[2])
    end, 'Invalid kit snapshot read')
end
assert(calls.read == 0, 'Rejected provenance reads reached native memory')
assert(#service.read(65536, 96) == 96)

local entry = { kind = 'armor', key = b.save_key, original = stock, document = colors }
local pattern_entry = { kind = 'armor', key = 'p:' .. p.save_key, original = pattern, document = pattern }
local provider = service.provider({ entries = { entry, pattern_entry } })
rejected(function()
    provider(entry)
end, X.PENDING)
assert(service.state() == 'loading' and #calls.request == 1)
assert(calls.stop == 0 and calls.scan == 0 and calls.refresh == 0)
local cache = calls.caches[1]
cache.complete = true
assert(service.poll(true) == 'Exact binding sources ready; retry Export')
assert(calls.logs[1]:find('targets=2 matched=2', 1, true))
assert(calls.stop == 0 and calls.scan == 0 and calls.refresh == 0, 'Probe changed the live session')
local source = provider(entry)
assert(source.binding == b and provider(entry) == source and provider(pattern_entry).binding == p)
assert(calls.stop == 2 and calls.scan == 1 and calls.refresh == 1)
assert(service.material('resource') == 'material:resource' and not service.id_available('kind', 'occupied'))

-- Legacy export checks the entire preset before hydrating any selected entry.
local absent = { kind = 'helmet', key = 'missing', original = stock, document = colors }
local before = calls.capture
rejected(function()
    service.provider({ entries = { entry, absent } })(entry)
end, 'complete current gear')
assert(calls.capture == before)
groups[1].bindings[2] = b
rejected(function()
    service.provider({ entries = { entry } })(entry)
end, 'uniquely match')
groups[1].bindings[2] = nil
local wrong = { kind = 'armor', key = b.save_key, original = stock, document = stock }
rejected(function()
    service.provider({ entries = { wrong } })(wrong)
end, 'assigned colors do not match')
entry.binding_provenance = p
rejected(function()
    service.provider({ entries = { entry } })(entry)
end, 'Saved binding provenance differs')
entry.binding_provenance = b
assert(service.provider({ entries = { entry } })(entry).binding == b)

-- Only uniquely proved units are requested; completion probes never refresh.
groups[1].bindings = { b, b, refused }
assert(service.request() and #calls.request == 1)
assert(calls.logs[#calls.logs]:find('omitted unproven units', 1, true))
local before_refresh = calls.refresh
cache.complete = true
service.poll(false)
assert(calls.refresh == before_refresh)
cache.valid = false
rejected(function()
    service.provider({ entries = { entry } })(entry)
end, 'Current loose patch payloads changed; press Load Current Gear to retry')
assert(service.state() == 'stale')
cache.cleanup_pending = true
assert(not service.close() and service.state() == 'stale')
cache.cleanup_pending = nil
assert(service.close() and service.state() == 'closed')

-- A new activation starts independently with no old worker/resolver state.
local other, other_calls = fixture()
assert(other.state() == nil and other_calls.capture == 0)
assert(other.request() and other.state() == 'loading' and #other_calls.caches == 1)
assert(service.state() == 'closed')
print('export provenance activation, bounded reads, async proof and exact hydration contracts passed')
