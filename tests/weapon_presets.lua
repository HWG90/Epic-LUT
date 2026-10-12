local F = dofile('tests/weapon_services_fixture.lua')
local Mapping = dofile('src/editor/weapon_mapping.lua')
local W = dofile('src/presets/weapon_presets.lua')
local DDS = dofile('src/core/dds.lua')
local Outfit = dofile('src/presets/outfit_presets.lua')
local Provenance = dofile('src/presets/binding_provenance.lua')
local modules = {
    weapon_mapping = Mapping,
    outfit_targets = dofile('src/presets/outfit_targets.lua'),
    dds = DDS,
    binding_provenance = Provenance,
}
local f = F.new()
local material = f.group(1, 'material', 1, '0000000000000001', 0, 2)
local pattern = f.group(1, 'pattern', 1, '0000000000000002', 0, 2)
f.set_document(material.bindings[1], F.document(23, 8, 10))
f.set_document(material.bindings[2], F.document(23, 8, 20))
local service = W.new(modules, f.host)
local entries, summary = service.capture(f.groups)
assert(#entries == 4 and summary.count == 4 and entries[1].document.data[0] == 10 and entries[2].document.data[0] == 20)
assert(entries[1].key == '3:1:0:0' and entries[2].key == '3:1:1:0' and entries[3].key == 'p:3:1:0:0')
assert(entries[3].document == entries[4].document, 'Captured identical Pattern documents were duplicated')
material.bindings[1].document.data[0] = 77
assert(entries[1].document.data[0] == 10, 'Saved weapon entries borrowed the mutable editor buffer')
local plans, context = service.plan({ entries = entries }, f.groups)
assert(
    #plans == 3 and #plans[1].targets == 1 and #plans[2].targets == 1 and #plans[3].targets == 2,
    'Heterogeneous weapon LODs were collapsed into a group-first palette'
)
service.apply({ entries = entries }, f.groups)
assert(f.calls == 1 and material.bindings[1].document.data[0] == 10 and material.bindings[2].document.data[0] == 20)
local before = f.calls
local _, frozen = service.plan({ entries = entries }, f.groups)
entries[1].document.data[0] = 99
assert(not pcall(frozen.validate) and f.calls == before, 'Mutated preset bytes passed frozen plan validation')
entries[1].document.data[0] = 10
local current_id = entries[1].weapon_resource
entries[1].weapon_resource = 'ffffffffffffffff'
assert(
    not pcall(service.apply, { entries = entries }, f.groups) and f.calls == before,
    'Preset retargeted to a different weapon configuration'
)
entries[1].weapon_resource = current_id
local saved_doc = entries[1].document
entries[1].document = F.document(23, 7, 1)
assert(
    not pcall(service.apply, { entries = entries }, f.groups) and f.calls == before,
    'Preset resized a weapon LUT silently'
)
entries[1].document = saved_doc
f.foreign(material.bindings[1])
assert(not pcall(service.apply, { entries = entries }, f.groups) and f.calls == before)
-- Exact saved anchors can adapt another LOD of the same weapon/resource only.
f = F.new()
material = f.group(1, 'material', 1, '0000000000000001', 0, 4)
service = W.new(modules, f.host)
local uniform = service.capture(f.groups)
material.bindings[1].save_key, material.bindings[1].mesh_index = '3:1:4:0', 4
local adapted = service.plan({ entries = uniform }, f.groups)
assert(#adapted == 1 and #adapted[1].targets == 4)
material.source_resource, material.source_document.resource = 'ffffffffffffffff', 'ffffffffffffffff'
assert(not pcall(service.plan, { entries = uniform }, f.groups), 'Same weapon adapted to another original LUT resource')
-- A real schema4 store handles persistence; the service invalidates the library
-- cache only after successful atomic manifest publication.
f = F.new()
material = f.group(1, 'material', 1, '0000000000000001', 2.75, 2)
local store = Outfit.new(
    { dds = DDS, file_io = dofile('src/core/file_io.lua'), windows = {
        files = function()
            return {}
        end,
    } },
    'tests/tmp/presets'
)
local invalidations = 0
f.host.outfits, f.host.invalidate =
    store, function(name)
        assert(name == 'Weapon Service Save')
        invalidations = invalidations + 1
    end
service = W.new(modules, f.host)
local stored = service.save('Weapon Service Save')
assert(
    invalidations == 1
        and #stored.entries == 2
        and stored.entries[1].weapon_resource == f.config[1]
        and stored.entries[1].document.data[0] == 2.75
)
store.delete('Weapon Service Save')
-- V4 references are optional for an ordinary save, but any supplied proof must
-- describe the exact captured weapon, key and original role.
material.source_document.patch_source = '0123456789abcdef\n'
    .. ('\0'):rep(192)
    .. DDS.encode(material.source_document.data, 23, 8):sub(1, 148)
f.host.provenance = function(_, context)
    return {
        version = 4,
        kind = 'weapon',
        key = context.key,
        weapon_resource = f.config[1],
        weapon_slot = 1,
        texture_slot = Provenance.LUT,
        original_texture = context.original.resource,
        section = 101,
        index_stamp = ('a'):rep(64),
        unit = { resource = f.config[1], archive = '0123456789abcdef', main_sha256 = ('b'):rep(64) },
        material = { resource = '2222222222222222', archive = '0123456789abcdef', main_sha256 = ('c'):rep(64) },
        mesh_id = 99,
        material_slot = 0,
        material_texture = context.original.resource,
        unit_override = false,
    }
end
local certified, certified_summary = service.capture()
assert(certified_summary.provenance_count == 2 and certified[1].binding_provenance.version == 4)
f.host.provenance = function()
    error('Source cache still reading')
end
local ordinary, ordinary_summary = service.capture()
assert(
    #ordinary == 2
        and ordinary_summary.provenance_count == 0
        and ordinary_summary.provenance_error:find('Source cache still reading', 1, true)
)
-- Mixed application requires one host transaction, never two independent writes.
local mixed_entries = { ordinary[1], ordinary[2], { kind = 'armor', key = '0:1:0:0', document = F.document(23, 8, 1) } }
assert(
    not pcall(service.apply, { entries = mixed_entries }) and f.calls == 0,
    'Mixed preset applied weapons without the garment transaction coordinator'
)
local mixed_calls = 0
f.host.apply_mixed_plan = function(plan, context)
    mixed_calls = mixed_calls + 1
    assert(context.validate() and #plan == 1 and #context.garment_entries == 1)
    return 'one coordinated transaction'
end
assert(
    service.apply({ entries = mixed_entries }) == 'one coordinated transaction' and mixed_calls == 1 and f.calls == 0
)
local exported
f.host.exporter = {
    save = function(...)
        exported = { ... }
        return 'export-result'
    end,
}
assert(
    service.export('Weapon Export', { entries = ordinary }, 3, 1, 5) == 'export-result'
        and exported[1] == 'Weapon Export'
        and exported[3] == 3
        and exported[5] == 5
)
print(
    'PASS weapon presets: immutable per-LOD capture, exact subset application, same-weapon LOD/resource guards, real schema4 persistence/cache, optional v4 proofs and coordinated export/mixed apply hooks'
)
