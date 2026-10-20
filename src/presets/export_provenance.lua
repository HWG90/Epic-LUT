-- One editor activation's exact binding-source resolver and background cache.
-- Named identity, bounded reads and owned worker cleanup retain their existing
-- implementations; the controller supplies only current session transitions.
local buffers = m and m.float_buffer or require('src.core.float_buffer')
local X = {
    PENDING = 'Reading exact binding sources; retry Export after the background cache is ready',
}
local function unavailable(cache)
    return tostring(cache.error or cache.status or 'Exact binding sources unavailable')
        .. '; press Load Current Gear to retry'
end
function X.new(modules, host)
    local cache, resolver, unit_identity, probe_requested
    local self = {}
    function self.unit_resource(unit, identity)
        local helper = assert(unit_identity, 'Verified Lua Unit identity unavailable')
        identity = identity or assert(host.current_identity(), 'Current local avatar unavailable')
        return helper.resource(unit, identity)
    end
    function self.read(address, size)
        assert(
            type(address) == 'number'
                and address >= 65536
                and address < 2 ^ 47
                and type(size) == 'number'
                and size >= 1
                and size <= 96,
            'Invalid kit snapshot read'
        )
        -- This legacy raw-memory fallback is selected only by an explicit read.
        local ffi = require('ffi')
        local buffer = ffi.new('uint8_t[?]', size)
        return host.memory.read_into(ffi.cast('const uint8_t *', address), size, buffer) and ffi.string(buffer, size)
            or nil
    end
    function self.ensure()
        if resolver then
            return resolver
        end
        if
            not (
                modules.binding_provenance
                and modules.binding_source_cache
                and modules.binding_provenance_script
                and modules.binding_provenance_reader
                and modules.unit_identity
                and modules.material_identity
                and modules.binding_unit_layout
                and modules.binding_names
            )
        then
            return nil, 'Verified named Lua binding identity unavailable'
        end
        local ready, units, materials = pcall(function()
            local E = assert(host.lua_engine(), 'Lua Unit APIs unavailable')
            local units = modules.unit_identity.new(E, {
                avatar = modules.avatar,
                memory = host.memory,
                game = host.game,
                read = host.appearance_read,
            })
            local materials = modules.material_identity.new(E, {
                unit_identity = units,
                section_name = modules.binding_names.section,
                mesh_name = modules.binding_names.mesh,
                single_material = function(b)
                    return host.material_count(b.mesh) == 1
                        and tonumber(host.material_at(b.mesh, 0)) == b.material
                        and host.material_count(b.mesh) == 1
                end,
            })
            return units, materials
        end)
        if not ready then
            return nil, tostring(units)
        end
        local sources = modules.binding_source_cache.new({
            binding_provenance = modules.binding_provenance,
            binding_provenance_script = modules.binding_provenance_script,
            binding_provenance_reader = modules.binding_provenance_reader,
            original_snapshot_reader = modules.original_snapshot_reader,
            windows = modules.windows,
            paths = modules.paths,
            file_io = modules.file_io,
            platform = modules.platform,
        }, { paths = host.paths, log = host.log })
        local proof = modules.binding_provenance.new({
            engine = modules.engine,
            present = host.present,
            binding = host.binding,
            unit_source = sources.unit,
            material_source = sources.material,
            unit_resource = self.unit_resource,
            identity = host.current_identity,
            kit_override = function(b, hash, slot)
                local identity = assert(host.current_identity(), 'Current kit identity unavailable')
                return modules.binding_provenance.kit_override(self.read, host.game, identity, b, hash, slot)
            end,
            material_identity = materials,
            layout = modules.binding_unit_layout.parse,
        })
        cache, resolver, unit_identity = sources, proof, units
        return resolver
    end
    function self.request()
        local proof, why = self.ensure()
        if not proof then
            return false, why
        end
        local identity = assert(host.current_identity(), 'Current kit identity unavailable')
        local units, seen, refused = {}, {}, nil
        for _, group in ipairs(host.groups()) do
            for _, b in ipairs(group.bindings) do
                if not seen[b.unit] then
                    seen[b.unit] = true
                    local ok, value = pcall(function()
                        local hash = self.unit_resource(b.unit, identity)
                        local _, kit = modules.binding_provenance.kit_override(
                            self.read,
                            host.game,
                            identity,
                            b,
                            hash,
                            modules.engine.LUT_SLOT
                        )
                        return { resource = hash, archive = kit.archive }
                    end)
                    if ok then
                        units[#units + 1] = value
                    else
                        refused = refused or tostring(value)
                    end
                end
            end
        end
        if #units == 0 then
            return false, refused or 'No current units have a unique kit source proof'
        end
        if refused and host.log then
            host.log('Binding source request omitted unproven units: ' .. refused:sub(1, 512))
        end
        local ok, reason = cache.start(units, true)
        if ok then
            probe_requested = true
        end
        return ok, reason
    end
    function self.probe()
        if not probe_requested or not cache or cache.state ~= 'ready' then
            return
        end
        probe_requested = nil
        local counts = { targets = 0, matched = 0, unmatched = 0, ambiguous = 0, kit_override = 0, unready = 0 }
        local reasons, seen_reasons = {}, {}
        -- Explicit-request completion is read-only: no refresh/discovery,
        -- highlight stop, document mutation or binding write belongs here.
        for _, pool in ipairs({
            { targets = host.groups(), pattern = false },
            { targets = host.pattern_groups(), pattern = true },
        }) do
            for _, group in ipairs(pool.targets) do
                for _, b in ipairs(group.bindings) do
                    local original = host.original(b.original)
                    local kind, key = modules.gear_catalog.kind(b), (pool.pattern and 'p:' or '') .. b.save_key
                    counts.targets = counts.targets + 1
                    local ok, why = pcall(resolver.capture, b, {
                        kind = kind,
                        key = key,
                        original = original,
                    })
                    if ok then
                        counts.matched = counts.matched + 1
                    else
                        why = tostring(why)
                        local category = why:find('Active kit texture override', 1, true) and 'kit_override'
                            or why:find('matches=0', 1, true) and 'unmatched'
                            or why:find('pointer proof', 1, true) and 'ambiguous'
                            or 'unready'
                        counts[category] = counts[category] + 1
                        local distinct = category .. ':' .. why:gsub('^.-:%d+: ', '')
                        if #reasons < 8 and not seen_reasons[distinct] then
                            seen_reasons[distinct] = true
                            reasons[#reasons + 1] = (kind .. ':' .. key .. ' texture=' .. tostring(
                                original and original.resource or '-'
                            ) .. ' ' .. why):sub(1, 384)
                        end
                    end
                end
            end
        end
        if host.log then
            host.log(
                'BINDING_PROVENANCE_PROBE index='
                    .. cache.index_stamp
                    .. ' targets='
                    .. counts.targets
                    .. ' matched='
                    .. counts.matched
                    .. ' unmatched='
                    .. counts.unmatched
                    .. ' ambiguous='
                    .. counts.ambiguous
                    .. ' kit_overrides='
                    .. counts.kit_override
                    .. ' unready='
                    .. counts.unready
                    .. (#reasons > 0 and ' reasons=' .. table.concat(reasons, ' | ') or '')
            )
        end
    end
    function self.provider(preset)
        local hydrated, matches = {}
        local function prepare()
            local proof, why = self.ensure()
            assert(proof, why or 'Verified named Lua binding identity unavailable')
            if cache.state == 'failed' or cache.state == 'stale' then
                error(unavailable(cache), 0)
            end
            if cache.state == 'idle' or cache.state == 'closed' then
                local started, reason = self.request()
                assert(started, reason or 'Exact binding source request could not start')
            end
            if cache.state == 'loading' then
                error(X.PENDING, 0)
            end
            assert(cache.state == 'ready', unavailable(cache))
            local valid, reason = cache.validate_scope()
            if not valid then
                cache.error = reason or cache.status or 'Current binding source scope changed'
                error(unavailable(cache), 0)
            end
            assert(host.stop_identification(), 'Highlight restoration pending')
            assert(host.stop_pattern_flash(), 'Pattern highlight restoration pending')
            host.refresh(true)
            host.scan_patterns()
            local current = {}
            for _, pool in ipairs({
                { targets = host.groups(), pattern = false },
                { targets = host.pattern_groups(), pattern = true },
            }) do
                for _, group in ipairs(pool.targets) do
                    for _, b in ipairs(group.bindings) do
                        local key = modules.gear_catalog.kind(b) .. ':' .. (pool.pattern and 'p:' or '') .. b.save_key
                        current[key] = current[key] or {}
                        current[key][#current[key] + 1] = b
                    end
                end
            end
            local found = {}
            -- Legacy manifests need the complete saved target set and stock
            -- metadata to match before independent named/pointer hydration.
            for _, entry in ipairs(preset.entries) do
                local candidates = current[entry.kind .. ':' .. entry.key]
                local b = candidates and #candidates == 1 and candidates[1]
                local original = b and host.original(b.original)
                assert(
                    b
                        and original
                        and entry.original
                        and original.resource == entry.original.resource
                        and original.width == entry.original.width
                        and original.height == entry.original.height,
                    'Saved preset does not uniquely match the complete current gear; binding assignments were not retargeted'
                )
                assert(host.present(b) and host.binding(b) == b.current, 'Current binding changed before export')
                found[entry] = { binding = b, original = original }
            end
            matches = found
            return proof
        end
        return function(entry)
            local proof = matches and resolver or prepare()
            local target = assert(matches[entry], 'Export entry is not in the verified preset')
            if not hydrated[entry] then
                if not entry.binding_provenance then
                    local current = host.applied_document(target.binding) or target.original
                    assert(
                        current
                            and current.width == entry.document.width
                            and current.height == entry.document.height
                            and buffers.bytes(current.data, current.width * current.height * 4)
                                == buffers.bytes(entry.document.data, entry.document.width * entry.document.height * 4),
                        'Apply this legacy preset to the current gear first; its assigned colors do not match the active binding context'
                    )
                end
                local source, refs = proof.capture(target.binding, {
                    kind = entry.kind,
                    key = entry.key,
                    original = target.original,
                })
                if entry.binding_provenance then
                    assert(
                        modules.binding_provenance.matches(entry.binding_provenance, refs),
                        'Saved binding provenance differs from current pristine assets/kit; no assignments guessed'
                    )
                end
                hydrated[entry] = source
            end
            return hydrated[entry]
        end
    end
    function self.material(resource)
        return assert(cache, 'Exact material source cache unavailable').material(resource)
    end
    function self.id_available(kind, resource)
        return assert(cache, 'Binding collision catalog unavailable').id_available(kind, resource)
    end
    function self.state()
        return cache and cache.state
    end
    function self.validate_scope()
        return assert(cache, 'Exact binding source cache unavailable').validate_scope()
    end
    function self.poll(waiting)
        if not cache then
            return
        end
        local result
        local ticked, tick_error = pcall(cache.tick)
        if waiting then
            if not ticked then
                result = 'Binding source cache update failed: ' .. tostring(tick_error)
            elseif cache.state == 'ready' then
                result = 'Exact binding sources ready; retry Export'
            elseif cache.state == 'failed' or cache.state == 'stale' then
                result = unavailable(cache)
            end
        end
        local ok, why = pcall(self.probe)
        if not ok and host.log then
            host.log('Binding provenance probe unavailable: ' .. tostring(why):sub(1, 512))
        end
        return result
    end
    function self.close()
        return not cache or cache.close()
    end
    return self
end
return X
