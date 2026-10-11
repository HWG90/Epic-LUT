-- Binding identity proofs. Ordinal keys never select a serialized SectionID.
-- Kit offsets are the already-reviewed vendor/kits.lua / legacy/catalog.lua ABI.
local P = { MAX_BYTES = 4096, MAX_PART = 8 * 1024 * 1024 }
P.UNIT, P.MATERIAL = 'e0a48d0be9a7453f', 'eac0b497876adedf'
P.LUT, P.PATTERN = 0x7e662968, 0x81d4c49d
-- SHA256 uses the Windows BCrypt API already used by bingus_memory.
-- These OS calls neither operate on game objects nor allocate game resources.
function P.digest(bytes, expected_bytes)
    assert(
        type(bytes) == 'function' or type(bytes) == 'string' and #bytes <= P.MAX_PART,
        'Invalid binding digest payload'
    )
    assert(
        expected_bytes == nil
            or type(bytes) == 'function'
                and type(expected_bytes) == 'number'
                and expected_bytes >= 0
                and expected_bytes <= 9007199254740991
                and expected_bytes % 1 == 0,
        'Invalid binding digest expected length'
    )
    local ffi = require('ffi')
    if not pcall(ffi.typeof, 'epic_binding_hash_marker') then
        ffi.cdef([[
            typedef struct epic_binding_hash_marker { int unused; } epic_binding_hash_marker;
            int32_t epic_binding_BCryptOpenAlgorithmProvider(void **, const uint16_t *, const uint16_t *, uint32_t) __asm__("BCryptOpenAlgorithmProvider");
            int32_t epic_binding_BCryptCloseAlgorithmProvider(void *, uint32_t) __asm__("BCryptCloseAlgorithmProvider");
            int32_t epic_binding_BCryptCreateHash(void *, void **, void *, uint32_t, const void *, uint32_t, uint32_t) __asm__("BCryptCreateHash");
            int32_t epic_binding_BCryptHashData(void *, const void *, uint32_t, uint32_t) __asm__("BCryptHashData");
            int32_t epic_binding_BCryptFinishHash(void *, void *, uint32_t, uint32_t) __asm__("BCryptFinishHash");
            int32_t epic_binding_BCryptDestroyHash(void *) __asm__("BCryptDestroyHash");
        ]])
    end
    local lib = ffi.load('bcrypt')
    local algorithm, hash = ffi.new('void *[1]'), ffi.new('void *[1]')
    local ok, result = pcall(function()
        local name = ffi.new('uint16_t[7]', { 83, 72, 65, 50, 53, 54, 0 })
        assert(lib.epic_binding_BCryptOpenAlgorithmProvider(algorithm, name, nil, 0) == 0, 'Binding SHA256 unavailable')
        assert(
            lib.epic_binding_BCryptCreateHash(algorithm[0], hash, nil, 0, nil, 0, 0) == 0,
            'Binding SHA256 creation failed'
        )
        if type(bytes) == 'function' then
            local total, limit = 0, expected_bytes or 512 * 1024 * 1024
            while true do
                local chunk = bytes()
                if chunk == nil then
                    break
                end
                assert(type(chunk) == 'string' and #chunk > 0 and #chunk <= 65536, 'Invalid binding digest chunk')
                assert(#chunk <= limit - total, 'Binding digest file exceeds its limit')
                total = total + #chunk
                assert(lib.epic_binding_BCryptHashData(hash[0], chunk, #chunk, 0) == 0, 'Binding SHA256 update failed')
            end
            assert(expected_bytes == nil or total == expected_bytes, 'Binding digest file length differs')
        else
            assert(lib.epic_binding_BCryptHashData(hash[0], bytes, #bytes, 0) == 0, 'Binding SHA256 update failed')
        end
        local digest = ffi.new('uint8_t[32]')
        assert(lib.epic_binding_BCryptFinishHash(hash[0], digest, 32, 0) == 0, 'Binding SHA256 finish failed')
        local out = ''
        for i = 0, 31 do
            out = out .. string.format('%02x', digest[i])
        end
        return out
    end)
    if hash[0] ~= nil then
        lib.epic_binding_BCryptDestroyHash(hash[0])
    end
    if algorithm[0] ~= nil then
        lib.epic_binding_BCryptCloseAlgorithmProvider(algorithm[0], 0)
    end
    assert(ok, result)
    return result
end
local function integer(n, label)
    assert(type(n) == 'number' and n >= 0 and n <= 4294967295 and n % 1 == 0, 'Invalid ' .. label)
    return n
end
local function hex(value, n, label)
    assert(type(value) == 'string' and #value == n and value:match('^%x+$'), 'Invalid ' .. label)
    return value:lower()
end
local function uint(data, at)
    assert(type(data) == 'string' and at >= 0 and at + 4 <= #data, 'Truncated provenance integer')
    local a, b, c, d = data:byte(at + 1, at + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end
local function id_at(data, at)
    assert(type(data) == 'string' and at >= 0 and at + 8 <= #data, 'Truncated provenance ID')
    local out = ''
    for i = at + 8, at + 1, -1 do
        out = out .. string.format('%02x', data:byte(i))
    end
    return out
end
local function fields(key)
    local t, slot, mesh, material = key:match('^(%d+):(%d+):(%d+):(%d+)$')
    assert(t and #key <= 128, 'Invalid provenance binding key')
    return integer(tonumber(t), 'unit type'),
        integer(tonumber(slot), 'garment slot'),
        integer(tonumber(mesh), 'mesh index'),
        integer(tonumber(material), 'material index')
end
local function shape(kind, key, slot, original)
    assert(kind == 'armor' or kind == 'helmet' or kind == 'cape', 'Invalid provenance gear family')
    assert(type(key) == 'string', 'Invalid provenance binding key')
    local pattern = key:sub(1, 2) == 'p:'
    fields(pattern and key:sub(3) or key)
    assert(slot == (pattern and P.PATTERN or P.LUT), 'Provenance texture slot differs from saved target')
    if original then
        assert(hex(original.resource, 16, 'original texture') ~= '0000000000000000', 'Original texture unavailable')
    end
end
local function ref(record)
    assert(type(record) == 'table', 'Missing pristine resource reference')
    return {
        resource = hex(record.resource, 16, 'resource ID'),
        archive = hex(record.archive, 16, 'resource archive'),
        main_sha256 = hex(record.main_sha256, 64, 'main digest'),
        gpu_sha256 = record.gpu_sha256 and hex(record.gpu_sha256, 64, 'GPU digest') or nil,
        stream_sha256 = record.stream_sha256 and hex(record.stream_sha256, 64, 'stream digest') or nil,
    }
end
function P.validate(value, kind, key, original)
    assert(
        type(value) == 'table' and (value.version == 1 or value.version == 2) and value.kit_override == false,
        'Unsupported binding provenance'
    )
    kind, key = kind or value.kind, key or value.key
    assert(value.kind == kind and value.key == key, 'Provenance destination differs from saved target')
    shape(kind, key, value.texture_slot, original)
    local texture = hex(value.original_texture, 16, 'original texture')
    assert(not original or texture == original.resource:lower(), 'Provenance original texture differs')
    local kit = assert(value.kit, 'Missing kit override proof')
    local result = {
        version = value.version,
        kind = kind,
        key = key,
        texture_slot = value.texture_slot,
        original_texture = texture,
        section = integer(value.section, 'SectionID'),
        kit_override = false,
        index_stamp = hex(value.index_stamp, 64, 'resource index digest'),
        unit = ref(value.unit),
        material = ref(value.material),
        kit = {
            id = integer(kit.id, 'kit ID'),
            body = integer(kit.body, 'body type'),
            archive = hex(kit.archive, 16, 'kit archive'),
        },
    }
    if value.version == 2 then
        result.mesh_id = integer(value.mesh_id, 'MeshName ID')
        result.material_slot = integer(value.material_slot, 'mesh material slot')
        assert(result.material_slot < 64, 'Mesh material slot exceeds its limit')
    else
        assert(value.mesh_id == nil and value.material_slot == nil, 'Mesh assignment requires provenance version2')
    end
    return result
end
function P.encode(value, kind, key, original)
    local v = P.validate(value, kind, key, original)
    local out = {
        'EPIC-BINDING\t' .. v.version,
        v.kind,
        v.key,
        tostring(v.texture_slot),
        v.original_texture,
        tostring(v.section),
        v.index_stamp,
        tostring(v.kit.id),
        tostring(v.kit.body),
        v.kit.archive,
    }
    for _, r in ipairs({ v.unit, v.material }) do
        for _, k in ipairs({ 'resource', 'archive', 'main_sha256', 'gpu_sha256', 'stream_sha256' }) do
            out[#out + 1] = r[k] or '-'
        end
    end
    if v.version == 2 then
        out[#out + 1], out[#out + 2] = tostring(v.mesh_id), tostring(v.material_slot)
    end
    local text = table.concat(out, '\n')
    assert(#text <= P.MAX_BYTES, 'Binding provenance exceeds its limit')
    return text
end
function P.decode(text, kind, key, original)
    assert(
        type(text) == 'string' and #text <= P.MAX_BYTES and not text:find('\r'),
        'Invalid binding provenance sidecar'
    )
    local rows = {}
    for line in (text .. '\n'):gmatch('(.-)\n') do
        rows[#rows + 1] = line
    end
    local version = rows[1] == 'EPIC-BINDING\t1' and 1 or rows[1] == 'EPIC-BINDING\t2' and 2
    assert(version and #rows == (version == 1 and 20 or 22), 'Invalid binding provenance schema')
    local function record(at)
        return {
            resource = rows[at],
            archive = rows[at + 1],
            main_sha256 = rows[at + 2],
            gpu_sha256 = rows[at + 3] ~= '-' and rows[at + 3] or nil,
            stream_sha256 = rows[at + 4] ~= '-' and rows[at + 4] or nil,
        }
    end
    return P.validate({
        version = version,
        kind = rows[2],
        key = rows[3],
        texture_slot = tonumber(rows[4]),
        original_texture = rows[5],
        section = tonumber(rows[6]),
        index_stamp = rows[7],
        kit_override = false,
        kit = { id = tonumber(rows[8]), body = tonumber(rows[9]), archive = rows[10] },
        unit = record(11),
        material = record(16),
        mesh_id = version == 2 and tonumber(rows[21]) or nil,
        material_slot = version == 2 and tonumber(rows[22]) or nil,
    }, kind, key, original)
end
function P.matches(saved, current)
    saved, current = P.validate(saved), P.validate(current)
    if saved.version == 1 and current.version == 2 then
        current.version, current.mesh_id, current.material_slot = 1, nil, nil
    end
    return P.encode(saved) == P.encode(current)
end
local function source(record, resource, kind)
    assert(
        type(record) == 'table' and record.resource == resource and type(record.toc) == 'string' and #record.toc == 80,
        'Exact pristine binding source unavailable'
    )
    assert(id_at(record.toc, 0) == resource and id_at(record.toc, 8) == kind, 'Binding source TOC identity differs')
    for _, spec in ipairs({ { 'main', 56 }, { 'stream', 60 }, { 'gpu', 64 } }) do
        local data = record[spec[1]] or ''
        assert(
            type(data) == 'string' and #data <= P.MAX_PART and uint(record.toc, spec[2]) == #data,
            'Binding source part bounds differ'
        )
    end
    assert(#record.main > 0, 'Binding source main record unavailable')
    ref(record)
    return record
end
local function texture(record, wanted)
    assert(#record.main >= 136, 'Truncated material source')
    local count = uint(record.main, 64)
    assert(count >= 1 and count <= 64 and 136 + count * 12 <= #record.main, 'Material texture table exceeds its bounds')
    local result, seen
    seen = {}
    for i = 0, count - 1 do
        local slot = uint(record.main, 136 + i * 4)
        assert(not seen[slot], 'Ambiguous repeated material texture slot')
        seen[slot] = true
        if slot == wanted then
            result = id_at(record.main, 136 + count * 4 + i * 8)
        end
    end
    return result
end
-- read(address,size) -> exact bytes or nil; all pointers/counts remain bounded.
function P.kit_override(read, game, identity, binding, unit_hash, texture_slot)
    assert(type(identity) == 'table', 'Current kit identity unavailable')
    assert(texture_slot == P.LUT or texture_slot == P.PATTERN, 'Unsupported kit texture slot')
    unit_hash = hex(unit_hash, 16, 'live unit resource')
    local kind = binding.cape and 'cape' or binding.helmet and 'helmet' or 'armor'
    local kit_id = integer(identity[kind], 'current kit ID')
    local unit_type, garment_slot = fields(binding.save_key)
    local function bytes(address, n)
        assert(
            type(address) == 'number' and address >= 65536 and address < 2 ^ 47 and address % 1 == 0,
            'Invalid kit pointer'
        )
        local data = read(address, n)
        assert(type(data) == 'string' and #data == n, 'Kit record unreadable')
        return data
    end
    local function pointer(data, at)
        local value = uint(data, at) + uint(data, at + 4) * 4294967296
        assert(value >= 65536 and value < 2 ^ 47, 'Invalid kit pointer')
        return value
    end
    local manager = pointer(bytes(game + 0x33264f8, 8), 0)
    local header = bytes(manager, 16)
    local list, count = pointer(header, 0), uint(header, 8)
    assert(count >= 1 and count <= 4096, 'Kit catalogue count exceeds its bounds')
    local kit
    for i = 0, count - 1 do
        local at = pointer(bytes(list + i * 8, 8), 0)
        local record = bytes(at, 64)
        if uint(record, 0) == kit_id then
            assert(not kit, 'Ambiguous repeated current kit ID')
            kit = record
        end
    end
    assert(
        kit and uint(kit, 40) == (kind == 'armor' and 0 or kind == 'helmet' and 1 or 2),
        'Current kit record differs from family'
    )
    local body_count = uint(kit, 56)
    assert(body_count >= 1 and body_count <= 8, 'Kit body count exceeds its bounds')
    local bodies = pointer(kit, 48)
    local matches, override = 0, nil
    for i = 0, body_count - 1 do
        local body = bytes(bodies + i * 24, 24)
        local body_type, n = uint(body, 0), uint(body, 16)
        assert(n <= 32, 'Kit piece count exceeds its bounds')
        if n > 0 and (kind == 'helmet' or body_type == identity.body or body_type == 3) then
            local pieces = pointer(body, 8)
            for j = 0, n - 1 do
                local piece = bytes(pieces + j * 96, 96)
                if id_at(piece, 0) == unit_hash and uint(piece, 8) == garment_slot and uint(piece, 12) == unit_type then
                    matches = matches + 1
                    override = id_at(piece, texture_slot == P.PATTERN and 32 or 24)
                end
            end
        end
    end
    assert(matches == 1, 'Current unit has no unique kit piece proof')
    return override ~= '0000000000000000',
        { id = kit_id, body = integer(identity.body, 'body type'), archive = id_at(kit, 32) }
end
function P.new(deps)
    assert(
        deps.engine and deps.unit_source and deps.material_source and deps.unit_resource and deps.kit_override,
        'Binding provenance dependencies unavailable'
    )
    local self = {}
    function self.capture(binding, context)
        assert(
            deps.material_identity
                and type(deps.material_identity.resolve) == 'function'
                and type(deps.layout) == 'function'
                and type(deps.identity) == 'function',
            'Verified named Lua binding identity APIs unavailable'
        )
        local kind, key, original = context.kind, context.key, context.original
        assert(original and original.resource, 'Original live texture metadata unavailable')
        assert(
            kind == (binding.cape and 'cape' or binding.helmet and 'helmet' or 'armor'),
            'Live provenance family changed'
        )
        local slot = binding.slot or deps.engine.LUT_SLOT
        shape(kind, key, slot, original)
        assert(key == (slot == P.PATTERN and 'p:' or '') .. binding.save_key, 'Live provenance key changed')
        local object = binding.current
        assert(deps.present(binding) and deps.binding(binding) == object, 'Live provenance binding changed')
        local identity = assert(deps.identity(), 'Current local avatar identity unavailable')
        local unit_hash = hex(deps.unit_resource(binding.unit, identity), 16, 'live unit resource')
        local unit = source(deps.unit_source(unit_hash), unit_hash, P.UNIT)
        local kit_override, kit = deps.kit_override(binding, unit_hash, slot)
        assert(kit_override == false, 'Active kit texture override requires kit-aware export')
        local layout = deps.layout(unit.main)
        local _, _, mesh_index = fields(binding.save_key)
        assert(
            binding.mesh_index == nil or binding.mesh_index == mesh_index,
            'Runtime mesh index differs from binding key'
        )
        local runtime_binding = {}
        for name, value in pairs(binding) do
            runtime_binding[name] = value
        end
        runtime_binding.mesh_index = mesh_index
        local proof = deps.material_identity.resolve(
            runtime_binding,
            layout.sections,
            identity,
            layout.supported and layout.meshes or nil
        )
        local match = { section = integer(proof.section, 'named SectionID') }
        local candidate
        for _, entry in ipairs(layout.sections) do
            if entry.section == match.section then
                candidate = entry
            end
        end
        assert(
            candidate and candidate.material == proof.material,
            'Named material identity differs from pristine Unit table'
        )
        match.material = source(deps.material_source(proof.material), proof.material, P.MATERIAL)
        assert(
            texture(match.material, slot) == original.resource:lower(),
            'Pristine named material texture differs from live original'
        )
        assert(
            deps.present(binding)
                and deps.binding(binding) == object
                and hex(deps.unit_resource(binding.unit, identity), 16, 'live unit resource') == unit_hash,
            'Live provenance binding changed during capture'
        )
        local check, kit_after = deps.kit_override(binding, unit_hash, slot)
        assert(
            check == false
                and kit_after.id == kit.id
                and kit_after.body == kit.body
                and kit_after.archive == kit.archive,
            'Worn kit changed during provenance capture'
        )
        local hydrated = {
            version = 1,
            kind = kind,
            key = key,
            verified = true,
            texture_slot = slot,
            original_texture = original.resource:lower(),
            section = match.section,
            unit = unit,
            material = match.material,
            kit_override = false,
            mesh_verified = proof.mesh_verified == true,
        }
        if proof.mesh_verified then
            hydrated.mesh_id, hydrated.material_slot = proof.mesh_id, proof.material_slot
            hydrated.material_slot_offset = proof.material_slot_offset
        end
        local refs = P.validate({
            version = proof.mesh_verified and 2 or 1,
            kind = kind,
            key = key,
            texture_slot = slot,
            original_texture = hydrated.original_texture,
            section = match.section,
            unit = unit,
            material = match.material,
            kit_override = false,
            index_stamp = unit.index_stamp,
            kit = kit,
            mesh_id = hydrated.mesh_id,
            material_slot = hydrated.material_slot,
        }, kind, key, original)
        return hydrated, refs
    end
    return self
end
return P
