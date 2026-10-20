-- Exact read-only weapon assignment sources. Packed Unit/Material records are
-- cached privately by the existing background worker, never stored in presets.
local W = {
    PENDING = 'Reading exact weapon binding sources; retry after the background cache is ready',
    DESTINATION_PENDING = 'Weapon patch destination has not yet been verified in-game',
}
local ffi = require('ffi')
local function hex(value, length, label)
    assert(type(value) == 'string' and #value == (length or 16) and value:match('^%x+$'), 'Invalid ' .. label)
    return value:lower()
end
local function uint(data, at)
    assert(type(data) == 'string' and at >= 0 and at + 4 <= #data, 'Truncated weapon source integer')
    local a, b, c, d = data:byte(at + 1, at + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end
local function id_at(data, at)
    assert(type(data) == 'string' and at >= 0 and at + 8 <= #data, 'Truncated weapon source ID')
    local out = ''
    for index = at + 8, at + 1, -1 do
        out = out .. string.format('%02x', data:byte(index))
    end
    return out
end
function W.new(m, host)
    host = host or {}
    local P, L = assert(m.binding_provenance), assert(m.binding_unit_layout)
    local cache, materials, request_set = nil, nil, {}
    local serializing = false
    local completion = {}
    local self = {}
    local function ensure()
        if cache then
            return cache
        end
        local paths = assert(host.paths, 'Weapon source cache paths unavailable')
        local isolated = {}
        for name, value in pairs(paths) do
            isolated[name] = value
        end
        isolated.cache = paths.cache .. '/weapon-provenance'
        if not paths.directory_exists(isolated.cache) then
            paths.mkdir_new(isolated.cache)
        end
        cache = assert(m.binding_source_cache).new(m, { paths = isolated, log = host.log, mode = 'weapon_effective' })
        return cache
    end
    local function discovery()
        return assert(host.discovery(), 'Weapon discovery unavailable')
    end
    local function descriptors(value)
        local out = {}
        for _, item in ipairs(value or {}) do
            if item.kind == 'weapon' and item.save_key then
                out[#out + 1] = item
            elseif item.bindings then
                for _, b in ipairs(item.bindings) do
                    out[#out + 1] = b
                end
            end
        end
        return out
    end
    local function start(force)
        local list = {}
        for resource, archive in pairs(request_set) do
            list[#list + 1] = { resource = resource, archive = archive }
        end
        assert(#list > 0 and #list <= 64, 'Weapon source request bounds')
        table.sort(list, function(a, b)
            return a.resource < b.resource
        end)
        return ensure().start(list, force == true)
    end
    local function start_required(force)
        local ok, why = start(force)
        if not ok then
            error(why or 'Weapon source worker unavailable', 0)
        end
    end
    function self.request(bindings, force)
        local ok, result, why = pcall(function()
            bindings = descriptors(bindings or host.groups())
            for _, b in ipairs(bindings) do
                assert(
                    b.kind == 'weapon' and not b.remote and discovery().present(b),
                    'Current local weapon source changed'
                )
                local resource = hex(b.unit_resource64, 16, 'weapon Unit resource')
                assert(
                    resource == hex(b.weapon_resource or b.weapon_resource64, 16, 'weapon configuration'),
                    'Weapon configuration differs from genuine Unit resource'
                )
                local hint = host.archive_hint and host.archive_hint(b) or '0000000000000000'
                request_set[resource] = request_set[resource] or hex(hint, 16, 'weapon archive hint')
            end
            return start(force)
        end)
        if not ok then
            return false, tostring(result)
        end
        return result, why
    end
    function self.state()
        return cache and cache.state or 'idle'
    end
    local function ready(resource)
        resource = hex(resource, 16, 'weapon Unit resource')
        local sources = ensure()
        if not request_set[resource] then
            request_set[resource] = '0000000000000000'
            start_required(false)
        end
        if sources.state == 'failed' or sources.state == 'stale' then
            error(sources.error or sources.status or 'Weapon source cache unavailable', 0)
        end
        if sources.state ~= 'ready' then
            error(W.PENDING, 0)
        end
        return sources
    end
    local source_fields = {
        'resource',
        'archive',
        'index_stamp',
        'source_mode',
        'source_kind',
        'source_file',
        'source_scope',
        'toc',
        'main',
        'gpu',
        'stream',
        'main_sha256',
        'gpu_sha256',
        'stream_sha256',
    }
    local function unchanged(snapshot)
        for _, field in ipairs(source_fields) do
            assert(
                snapshot.value[field] == snapshot.fields[field] and snapshot.copy[field] == snapshot.fields[field],
                'Weapon source changed during export batch'
            )
        end
    end
    local function record(value, resource, kind, expected, batch)
        local key = kind .. ':' .. resource
        local saved = batch and batch.records[key]
        if saved then
            assert(value == saved.value, 'Weapon source record replaced during export batch')
            unchanged(saved)
            if expected then
                assert(value.archive == expected.archive, 'Saved weapon source archive differs')
                for _, part in ipairs({ 'main', 'gpu', 'stream' }) do
                    assert(
                        expected[part .. '_sha256'] == value[part .. '_sha256'],
                        'Saved weapon source digest differs'
                    )
                end
            end
            return saved.copy
        end
        assert(
            type(value) == 'table' and value.resource == resource and type(value.toc) == 'string' and #value.toc == 80,
            'Exact weapon pristine source unavailable'
        )
        assert(id_at(value.toc, 0) == resource and id_at(value.toc, 8) == kind, 'Weapon source TOC identity differs')
        local sources = ensure()
        assert(
            sources.mode == 'weapon_effective'
                and value.source_mode == sources.mode
                and value.source_scope == sources.scope_sha256,
            'Weapon source mode or current patch scope differs'
        )
        local source_file = value.source_file
        assert(type(source_file) == 'string', 'Weapon source file receipt unavailable')
        if value.source_kind == 'packed' then
            assert(source_file == value.archive, 'Weapon packed source identity differs')
        else
            assert(
                value.source_kind == 'loose' and source_file:match('^' .. value.archive .. '%.patch_%d+$'),
                'Weapon loose source identity differs'
            )
        end
        for _, spec in ipairs({ { 'main', 56 }, { 'stream', 60 }, { 'gpu', 64 } }) do
            local bytes = value[spec[1]] or ''
            assert(
                type(bytes) == 'string' and #bytes <= P.MAX_PART and uint(value.toc, spec[2]) == #bytes,
                'Weapon source part bounds differ'
            )
            local digest = value[spec[1] .. '_sha256']
            assert(
                #bytes == 0 and digest == nil or hex(digest, 64, 'weapon source digest') == P.digest(bytes),
                'Weapon pristine source digest changed'
            )
            if expected then
                assert(expected[spec[1] .. '_sha256'] == digest, 'Saved weapon source digest differs')
            end
        end
        assert(#value.main > 0, 'Weapon source main part unavailable')
        hex(value.archive, 16, 'weapon source archive')
        hex(value.index_stamp, 64, 'weapon source index')
        if expected then
            assert(value.archive == expected.archive, 'Saved weapon source archive differs')
        end
        if batch then
            batch.record_count = batch.record_count + 1
            assert(batch.record_count <= 4160, 'Weapon export source count exceeds its limit')
            local fields, copy = {}, {}
            for _, field in ipairs(source_fields) do
                fields[field], copy[field] = value[field], value[field]
            end
            batch.records[key] = { value = value, fields = fields, copy = copy, toc_digest = P.digest(value.toc) }
            return copy
        end
        return value
    end
    local function texture(material, slot)
        local main = material.main
        assert(#main >= 136, 'Truncated weapon Material source')
        local count = uint(main, 64)
        assert(count <= 64 and 136 + count * 12 <= #main, 'Weapon Material texture table bounds')
        local seen, selected = {}, nil
        for index = 0, count - 1 do
            local name = uint(main, 136 + index * 4)
            assert(not seen[name], 'Repeated weapon Material texture slot')
            seen[name] = true
            if name == slot then
                selected = id_at(main, 136 + count * 4 + index * 8)
            end
        end
        return selected or P.NO_MATERIAL_TEXTURE
    end
    local function named()
        if materials then
            return materials
        end
        local E = assert(host.lua_engine(), 'Lua named weapon APIs unavailable')
        materials = assert(m.material_identity).new(E, {
            unit_identity = {
                handle = function(ref, binding)
                    assert(binding.unit == ref and discovery().present(binding), 'Named weapon Unit changed')
                    return binding.receipt.lua_unit, binding.receipt
                end,
                validate = function(receipt)
                    assert(discovery().validate(receipt), 'Named weapon Unit receipt changed')
                end,
            },
            section_name = assert(m.binding_names).section,
            mesh_name = m.binding_names.mesh,
            mesh_id = type(E.Mesh.name) == 'function' and E.Mesh.name or nil,
            single_material = function(b)
                return tonumber(host.native.materials(b.mesh)) == 1
                    and tonumber(host.native.material(b.mesh, 0)) == b.material
                    and tonumber(host.native.materials(b.mesh)) == 1
            end,
        })
        return materials
    end
    local function hydrate(refs, original, batch)
        refs = P.validate(refs, 'weapon', refs.key, original)
        local sources = ready(refs.unit.resource)
        assert(refs.index_stamp == sources.index_stamp, 'Saved weapon game index changed')
        local unit = record(assert(sources.unit(refs.unit.resource)), refs.unit.resource, P.UNIT, refs.unit, batch)
        local material = record(
            assert(sources.material(refs.material.resource)),
            refs.material.resource,
            P.MATERIAL,
            refs.material,
            batch
        )
        local layout = batch and batch.layouts[unit.resource] or L.parse(unit.main)
        if batch and not layout then
            layout = L.parse(unit.main)
        end
        if batch then
            batch.layouts[unit.resource] = layout
        end
        assert(layout.supported, 'Composite weapon binding provenance is unsupported')
        local selected_mesh, selected_slot
        for _, mesh in ipairs(layout.meshes) do
            if mesh.id == refs.mesh_id then
                assert(not selected_mesh, 'Ambiguous saved weapon MeshID')
                selected_mesh = mesh
                for _, slot in ipairs(mesh.material_slots) do
                    if slot.index == refs.material_slot then
                        assert(not selected_slot, 'Ambiguous saved weapon material slot')
                        selected_slot = slot
                    end
                end
            end
        end
        assert(
            selected_mesh
                and selected_slot
                and selected_slot.section == refs.section
                and selected_slot.material == refs.material.resource
                and selected_slot.mapped,
            'Saved weapon named assignment differs from pristine Unit'
        )
        local stock = texture(material, refs.texture_slot)
        assert(stock == refs.material_texture, 'Saved weapon Material texture changed')
        if refs.unit_override then
            assert(type(host.unit_override) == 'function', 'Serialized weapon Unit override proof unavailable')
            local override = host.unit_override(unit, layout, refs)
            assert(
                override
                    and override.verified == true
                    and override.resource == refs.original_texture
                    and override.offset == refs.unit_override_offset
                    and id_at(unit.main, override.offset) == override.resource,
                'Serialized weapon Unit override locator changed'
            )
        else
            assert(
                stock == refs.original_texture and stock ~= P.NO_MATERIAL_TEXTURE,
                'Weapon stock texture differs from effective original'
            )
        end
        local hydrated = {}
        for field, value in pairs(refs) do
            hydrated[field] = value
        end
        hydrated.verified, hydrated.mesh_verified = true, true
        hydrated.unit, hydrated.material = unit, material
        hydrated.material_slot_offset = selected_slot.offset
        hydrated.unit_override_verified = refs.unit_override or nil
        return hydrated, refs
    end
    function self.capture(binding, context)
        context = context or {}
        assert(binding.kind == 'weapon' and not binding.remote, 'Only current local weapon capture is supported')
        local original = context.original or host.original(binding)
        assert(original and original.resource, 'Original weapon texture metadata unavailable')
        local resource = hex(binding.weapon_resource or binding.weapon_resource64, 16, 'weapon configuration')
        assert(
            resource == hex(binding.unit_resource64, 16, 'genuine weapon Unit'),
            'Weapon configuration differs from Unit'
        )
        local slot, key = binding.slot, context.key or (binding.slot == P.PATTERN and 'p:' or '') .. binding.save_key
        assert(
            (slot == P.LUT or slot == P.PATTERN)
                and context.kind ~= 'armor'
                and context.kind ~= 'helmet'
                and context.kind ~= 'cape'
                and key == (slot == P.PATTERN and 'p:' or '') .. binding.save_key,
            'Weapon capture destination changed'
        )
        assert(
            discovery().present(binding) and discovery().binding(binding) == binding.current,
            'Live weapon binding changed'
        )
        local sources = ready(resource)
        local unit = record(assert(sources.unit(resource)), resource, P.UNIT)
        local layout = L.parse(unit.main)
        assert(layout.supported, 'Composite weapon binding provenance is unsupported')
        local proof = named().resolve(binding, assert(layout.unique_sections), binding, layout.meshes)
        assert(
            proof.mesh_verified and proof.material_slot_offset and proof.mesh_id and proof.material_slot,
            'Exact weapon MeshID/material-slot identity unavailable'
        )
        local material = record(assert(sources.material(proof.material)), proof.material, P.MATERIAL)
        local stock, effective = texture(material, slot), hex(original.resource, 16, 'original weapon texture')
        local override
        if stock ~= effective then
            assert(
                type(host.unit_override) == 'function',
                'Weapon texture differs from stock; serialized Unit override proof required'
            )
            override = host.unit_override(unit, layout, {
                binding = binding,
                section = proof.section,
                mesh_id = proof.mesh_id,
                material_slot = proof.material_slot,
                texture_slot = slot,
            })
            assert(
                override
                    and override.verified == true
                    and override.resource == effective
                    and type(override.offset) == 'number'
                    and id_at(unit.main, override.offset) == effective,
                'Serialized weapon Unit override proof unavailable'
            )
        end
        local refs = P.validate({
            version = 4,
            kind = 'weapon',
            key = key,
            texture_slot = slot,
            original_texture = effective,
            section = proof.section,
            index_stamp = sources.index_stamp,
            unit = unit,
            material = material,
            weapon_slot = binding.weapon_slot,
            weapon_resource = resource,
            mesh_id = proof.mesh_id,
            material_slot = proof.material_slot,
            material_texture = stock,
            unit_override = override ~= nil,
            unit_override_texture = override and override.resource,
            unit_override_offset = override and override.offset,
        }, 'weapon', key, original)
        local hydrated = hydrate(refs, original)
        assert(
            discovery().present(binding) and discovery().binding(binding) == binding.current,
            'Weapon changed during source capture'
        )
        return hydrated, refs
    end
    local function saved_refs(entry)
        local stored = entry.binding_provenance
        local refs = type(stored) == 'string' and P.decode(stored, 'weapon', entry.key, entry.original)
            or P.validate(stored, 'weapon', entry.key, entry.original)
        assert(
            refs.weapon_resource == entry.weapon_resource and refs.weapon_slot == entry.weapon_slot,
            'Saved weapon configuration differs from assignment proof'
        )
        return refs
    end
    local function pixels(document)
        assert(
            document
                and document.data
                and (document.width == 23 or document.width == 3)
                and type(document.height) == 'number'
                and document.height >= 1
                and document.height <= 64
                and document.height % 1 == 0
                and (document.width ~= 3 or document.height == 1),
            'Saved weapon LUT pixels unavailable'
        )
        return ffi.string(document.data, document.width * document.height * 16)
    end
    -- Missing assignment sidecars follow the same current-match policy as legacy
    -- garment presets. Palette saves remain useful while the worker is loading;
    -- export certifies every missing destination without rewriting that preset.
    local function prepare_saved(entries)
        local selected, preferences, missing, receipts = {}, {}, {}, {}
        for _, entry in ipairs(entries) do
            if entry.kind == 'weapon' then
                local resource = hex(entry.weapon_resource, 16, 'saved weapon configuration')
                local refs = entry.binding_provenance and saved_refs(entry)
                local archive = refs and refs.unit.archive or '0000000000000000'
                assert(
                    not preferences[resource]
                        or preferences[resource] == archive
                        or preferences[resource] == '0000000000000000'
                        or archive == '0000000000000000',
                    'Conflicting saved weapon source archives'
                )
                if not preferences[resource] or archive ~= '0000000000000000' then
                    preferences[resource] = archive
                end
                if refs then
                    selected[entry] = refs
                else
                    missing[#missing + 1] = entry
                end
            end
        end
        assert(next(preferences), 'Preset has no weapon assignments')
        for resource, archive in pairs(preferences) do
            local captured = cache and cache.state == 'ready' and cache.unit(resource)
            -- A zero archive is a lookup hint, not an unverified destination.
            -- Keep a ready effective cache whose actual archive already matches.
            if not captured or (archive ~= '0000000000000000' and captured.archive ~= archive) then
                request_set[resource] = archive
            end
        end
        start_required(false)
        local sources = ready(next(preferences))
        if sources.prepare_scope then
            if sources.scope_error then error(sources.scope_error, 0) end
            local prepared = sources.prepare_scope()
            if not prepared then error(W.PENDING, 0) end
        end
        local valid, why = sources.validate_scope()
        if not valid then
            error(why, 0)
        end
        if #missing > 0 then
            local current = {}
            for _, binding in ipairs(descriptors(host.groups())) do
                if binding.kind == 'weapon' and not binding.remote then
                    local key = (binding.slot == P.PATTERN and 'p:' or '') .. binding.save_key
                    current[key] = current[key] or {}
                    current[key][#current[key] + 1] = binding
                end
            end
            for _, entry in ipairs(missing) do
                local candidates = current[entry.key]
                local binding = candidates and #candidates == 1 and candidates[1]
                local saved = {
                    key = entry.key,
                    kind = entry.kind,
                    weapon_slot = entry.weapon_slot,
                    weapon_resource = entry.weapon_resource,
                    document = entry.document,
                    bytes = pixels(entry.document),
                    original = entry.original,
                    resource = entry.original and entry.original.resource,
                    width = entry.original and entry.original.width,
                    height = entry.original and entry.original.height,
                    patch_source = entry.original and entry.original.patch_source,
                }
                local target = {}
                for _, key in ipairs({
                    'unit',
                    'mesh',
                    'material',
                    'original',
                    'current',
                    'slot',
                    'save_key',
                    'weapon_slot',
                    'weapon_resource',
                    'unit_resource64',
                }) do
                    target[key] = binding and binding[key]
                end
                local function check()
                    assert(
                        entry.binding_provenance == nil
                            and entry.kind == saved.kind
                            and saved.kind == 'weapon'
                            and entry.key == saved.key
                            and entry.weapon_slot == saved.weapon_slot
                            and entry.weapon_resource == saved.weapon_resource
                            and entry.document == saved.document
                            and pixels(entry.document) == saved.bytes
                            and entry.original == saved.original
                            and binding
                            and binding.weapon_slot == entry.weapon_slot
                            and binding.weapon_resource == entry.weapon_resource
                            and binding.unit_resource64 == entry.weapon_resource
                            and entry.key == (binding.slot == P.PATTERN and 'p:' or '') .. binding.save_key,
                        'Saved weapon preset does not uniquely match the current weapon; assignments were not retargeted'
                    )
                    for key, value in pairs(target) do
                        assert(binding[key] == value, 'Current weapon target changed during legacy export')
                    end
                    assert(
                        discovery().present(binding) and discovery().binding(binding) == binding.current,
                        'Current weapon binding changed before legacy export'
                    )
                    -- Read the current host snapshot, never a cached group document.
                    local original = host.original(binding)
                    assert(
                        original
                            and entry.original
                            and original.resource == saved.resource
                            and original.width == saved.width
                            and original.height == saved.height
                            and original.patch_source == saved.patch_source
                            and entry.original.resource == saved.resource
                            and entry.original.width == saved.width
                            and entry.original.height == saved.height
                            and entry.original.patch_source == saved.patch_source,
                        'Saved weapon original differs from current installed sources; assignments were not retargeted'
                    )
                    local active = binding.current ~= binding.original and binding.document or original
                    assert(
                        active
                            and active.width == entry.document.width
                            and active.height == entry.document.height
                            and pixels(active) == pixels(entry.document),
                        'Apply this legacy weapon preset to its matching weapon first; saved colors differ from the active binding'
                    )
                    return original
                end
                local original = check()
                local _, refs = self.capture(binding, { kind = 'weapon', key = entry.key, original = original })
                check()
                selected[entry], receipts[entry] = refs, check
            end
        end
        local function refs_for(entry)
            local refs = assert(selected[entry], 'Export entry is not in the verified weapon preset')
            if receipts[entry] then
                receipts[entry]()
                return refs
            end
            return saved_refs(entry)
        end
        return selected, sources, refs_for
    end
    function self.provider(preset)
        assert(
            type(preset) == 'table' and type(preset.entries) == 'table' and #preset.entries <= 4096,
            'Weapon preset source bounds'
        )
        local selected, _, refs_for = prepare_saved(preset.entries)
        local hydrated = {}
        return function(entry)
            local refs = assert(selected[entry], 'Export entry is not in the certified weapon preset')
            local current_refs = refs_for(entry)
            assert(
                entry.kind == 'weapon'
                    and P.matches(refs, current_refs)
                    and refs.weapon_resource == entry.weapon_resource
                    and refs.weapon_slot == entry.weapon_slot,
                'Weapon export assignment changed'
            )
            local sources = ready(refs.unit.resource)
            local valid, why = sources.validate_scope()
            assert(valid, why)
            hydrated[entry] = hydrate(refs, entry.original)
            return hydrated[entry]
        end
    end
    function self.with_export_batch(entries, serialize)
        assert(not serializing, 'Nested weapon export batches are unsupported')
        assert(
            type(entries) == 'table' and #entries > 0 and #entries <= 4096 and type(serialize) == 'function',
            'Invalid weapon export batch'
        )
        local batch = { records = {}, layouts = {}, selected = {}, hydrated = {}, record_count = 0, active = true }
        local selected, sources, refs_for = prepare_saved(entries)
        batch.selected = selected
        local stamp, scope = sources.index_stamp, sources.scope_sha256
        local function current()
            assert(batch.active, 'Weapon export batch has ended')
            assert(
                cache == sources
                    and sources.state == 'ready'
                    and sources.mode == 'weapon_effective'
                    and sources.index_stamp == stamp
                    and sources.scope_sha256 == scope,
                'Weapon export source scope changed'
            )
        end
        local function resolve(entry)
            current()
            local refs = assert(batch.selected[entry], 'Export entry is not in the certified weapon batch')
            assert(P.matches(refs, refs_for(entry)), 'Weapon export assignment changed during serialization')
            if not batch.hydrated[entry] then
                batch.hydrated[entry] = hydrate(refs, entry.original, batch)
            end
            return batch.hydrated[entry]
        end
        local callbacks = {
            provenance = resolve,
            patch_archive = function(values)
                current()
                assert(
                    type(values) == 'table' and #values > 0 and #values <= 4096,
                    'Invalid weapon export batch subset'
                )
                local found = false
                for _, entry in ipairs(values) do
                    if entry.kind == 'weapon' then
                        resolve(entry)
                        found = true
                    end
                end
                assert(found, 'No weapon export bindings requested')
                return hex(assert(m.patch_export).BASE_ARCHIVE, 16, 'weapon patch destination')
            end,
            material_source = function(resource)
                current()
                local value = sources.material(resource)
                return value and record(value, hex(resource, 16, 'weapon Material'), P.MATERIAL, nil, batch) or nil
            end,
        }
        -- A single resume rejects yielding callbacks; no ambient batch state or
        -- active proof lease survives into another asynchronous export action.
        local thread = coroutine.create(function()
            return serialize(callbacks)
        end)
        serializing = true
        local ok, result = coroutine.resume(thread)
        serializing = false
        if ok and coroutine.status(thread) ~= 'dead' then
            ok, result = false, 'Weapon export serialization must not yield'
        end
        local final_ok, final_why = pcall(function()
            current()
            local unchanged_scope, reason = sources.validate_scope()
            if not unchanged_scope then
                error(reason, 0)
            end
            for entry in pairs(batch.selected) do
                assert(
                    P.matches(batch.selected[entry], refs_for(entry)),
                    'Weapon export assignment changed during serialization'
                )
            end
            for _, snapshot in pairs(batch.records) do
                unchanged(snapshot)
                for _, part in ipairs({ 'main', 'gpu', 'stream' }) do
                    local bytes = snapshot.fields[part] or ''
                    assert(
                        #bytes == 0 and snapshot.fields[part .. '_sha256'] == nil
                            or P.digest(bytes) == snapshot.fields[part .. '_sha256'],
                        'Weapon source digest changed during export batch'
                    )
                end
                assert(
                    P.digest(snapshot.fields.toc) == snapshot.toc_digest,
                    'Weapon source TOC changed during export batch'
                )
            end
        end)
        batch.active = false
        for _, proof in pairs(batch.hydrated) do
            proof.verified, proof.mesh_verified, proof.unit_override_verified = nil, nil, nil
        end
        if not final_ok then
            error(final_why, 0)
        end
        if not ok then
            error(result, 0)
        end
        return result
    end
    function self.material(resource)
        return assert(ensure().material(resource))
    end
    function self.unit(resource)
        return assert(ensure().unit(resource))
    end
    function self.id_available(kind, resource)
        return ensure().id_available(kind, resource)
    end
    -- One-shot subscribers run only when the existing worker completes.
    function self.when_ready(callback)
        assert(type(callback) == 'function', 'Source completion callback required')
        local token = { callback = callback }
        assert(#completion < 8, 'Too many pending source actions')
        completion[#completion + 1] = token
        return function() token.callback = nil end
    end
    function self.poll(waiting)
        if not cache then
            return nil
        end
        local ok, why = pcall(cache.tick)
        if #completion > 0 and (not ok or cache.state == 'failed' or cache.state == 'stale'
            or cache.state == 'ready' and (not cache.busy or not cache.busy())) then
            local ready = ok and cache.state == 'ready'
            local callbacks = completion
            completion = {} -- A callback may request another bounded worker job.
            for _, token in ipairs(callbacks) do
                if token.callback then
                    local called, problem = pcall(token.callback, ready, ready and nil or (cache.error or why or cache.status))
                    if not called and host.log then host.log('Source completion failed: ' .. tostring(problem)) end
                end
            end
        end
        if waiting then
            if not ok then
                return 'Weapon binding source cache update failed: ' .. tostring(why)
            elseif cache.state == 'ready' and not cache.scope_error then
                if cache.scope_ready and not cache.scope_ready() then
                    return 'Verifying weapon patch sources; queued export is waiting'
                end
                return 'Exact weapon binding sources ready'
            elseif cache.state == 'failed' or cache.state == 'stale' then
                return cache.error or cache.status
            end
        end
    end
    function self.close()
        completion = {}
        return not cache or cache.close()
    end
    function self.patch_archive(entries)
        if cache and (cache.state == 'failed' or cache.state == 'stale') then
            return nil, cache.error or cache.status or 'Weapon source cache unavailable'
        end
        if not cache or cache.state ~= 'ready' then
            return nil, W.PENDING
        end
        local ok, result = pcall(function()
            assert(
                type(entries) == 'table' and #entries > 0 and #entries <= 4096,
                'No weapon export bindings requested'
            )
            return self.with_export_batch(entries, function(batch)
                return batch.patch_archive(entries)
            end)
        end)
        if not ok then
            return nil, tostring(result)
        end
        return result
    end
    return self
end
return W
