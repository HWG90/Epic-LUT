"""Explicit read-only Blender/SDK audit of one unit after archive relocation.

Example: blender --background --factory-startup --python this.py --
 --game-data <data folder> --archive <16hex> --unit <16hex>
No game bytes or export triplets are written to disk.
"""
import argparse
import ctypes
import hashlib
import importlib
import json
from pathlib import Path
import struct
import sys
import types

ROOT = Path(__file__).resolve().parents[1]
SDK = ROOT / 'dist/sdk-reference/5a886256e54db52b5d228335eae20ce796f87fc0'
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / 'tools'))
from game_catalog import Archives, UNIT
from tools.lua_runner import LuaRunner

parser = argparse.ArgumentParser()
parser.add_argument('--game-data')
parser.add_argument('--fixture-root', type=Path)
parser.add_argument('--archive')
parser.add_argument('--unit')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
assert bool(args.game_data) != bool(args.fixture_root), 'Select exact archive input or a retained offline fixture'
fixture_records = None
if args.fixture_root:
    if sys.platform == 'win32':
        args.fixture_root = Path('\\\\?\\' + str(args.fixture_root.resolve()))
    fixture_records = {}
    for line in (args.fixture_root / 'resources.tsv').read_text().splitlines():
        fields = line.split('\t')
        assert len(fields) == 10
        kind, name, archive = fields[:3]
        item = {'resource': name, 'archive': archive}
        for part, filename, digest in zip(('main', 'gpu', 'stream'), fields[3:6], fields[7:10]):
            data = b'' if filename == '-' else (args.fixture_root / filename).read_bytes()
            assert (not data and digest == '-') or hashlib.sha256(data).hexdigest() == digest
            item[part] = data
        item['toc'] = (args.fixture_root / fields[6]).read_bytes()
        assert len(item['toc']) == 80
        assert struct.unpack_from('<QQ', item['toc']) == (int(name, 16), int(kind, 16))
        fixture_records[(kind, name)] = item
    units = [item for (kind, name), item in fixture_records.items()
             if kind == UNIT and (args.unit is None or args.unit == name)]
    assert len(units) == 1, 'Fixture does not identify exactly one reviewed Unit'
    item = units[0]
    args.unit = item['resource']
    assert args.archive is None or args.archive == item['archive']
    args.archive = item['archive']
    parts = {part: item[part] for part in ('main', 'gpu', 'stream')}
    record = {'gpu': (struct.unpack_from('<Q', item['toc'], 32)[0], len(item['gpu']))}
else:
    assert args.archive and args.unit, 'Archive input requires exact archive and Unit IDs'
    reader = Archives(args.game_data)
    try:
        archive, record = reader.find([args.archive], args.unit, UNIT)
        assert archive == args.archive and record, 'Exact reviewed unit is absent from its archive'
        parts = {part: reader.part(archive, record, part, 0, record[part][1])
                 for part in ('main', 'gpu', 'stream')}
    finally:
        reader.close()
for value in (args.archive, args.unit):
    assert len(value) == 16 and all(char in '0123456789abcdef' for char in value)
assert all(len(part) <= 8 * 1024 * 1024 for part in parts.values())
assert struct.unpack_from('<Q', parts['main'], 16)[0] == 0, 'Composite units need their external geometry fixture'

# Import only the pinned serializers, leaving the full Blender addon untouched.
for name, path in (('sdk', SDK), ('sdk.stingray', SDK / 'stingray'), ('sdk.utils', SDK / 'utils')):
    package = types.ModuleType(name)
    package.__path__ = [str(path)]
    sys.modules[name] = package
logger = importlib.import_module('sdk.utils.logger')
logger.PrettyPrint = lambda *values, **kwargs: None
memory = importlib.import_module('sdk.utils.memoryStream')
unit_module = importlib.import_module('sdk.stingray.unit')
import bpy
unit_module.bpy = types.SimpleNamespace(data=bpy.data,
    context=types.SimpleNamespace(scene=types.SimpleNamespace(Hd2ToolPanelSettings=
        types.SimpleNamespace(ImportMaterials=False, SkipMeshImportErrors=False))))

class Manager:
    def GetEntry(self, *values, **kwargs):
        return None

    def Load(self, *values, **kwargs):
        raise AssertionError('This bounded fixture must not fetch external assets')


def deserialize(main, gpu):
    unit = unit_module.StingrayMeshFile()
    unit.NameHash = int(args.unit, 16)
    unit.LoadMaterialSlotNames = False
    unit.Serialize(memory.MemoryStream(main), memory.MemoryStream(gpu), Manager())
    assert unit.NumMeshes > 0 and unit.RawMeshes, 'SDK skipped unit geometry'
    return unit


def geometry(unit):
    fields = ('VertexPositions', 'VertexNormals', 'VertexTangents', 'VertexBiTangents',
              'VertexUVs', 'VertexColors', 'VertexBoneIndices', 'VertexWeights', 'Indices')
    rows = [{field: getattr(mesh, field) for field in fields} for mesh in unit.RawMeshes]
    digest = hashlib.sha256(json.dumps(rows, separators=(',', ':'), allow_nan=False).encode()).hexdigest()
    return digest, sum(len(mesh.VertexPositions) for mesh in unit.RawMeshes), sum(len(mesh.Indices) for mesh in unit.RawMeshes)


before = deserialize(parts['main'], parts['gpu'])
table_at = struct.unpack_from('<I', parts['main'], 112)[0]
count = struct.unpack_from('<I', parts['main'], table_at)[0]
first_material_at = table_at + 4 + count * 4
old_material = struct.unpack_from('<Q', parts['main'], first_material_at)[0]
new_material = old_material ^ 0x0101010101010101
assert new_material != old_material
edited_main = bytearray(parts['main'])
struct.pack_into('<Q', edited_main, first_material_at, new_material)

# Run the actual Lua resource writer, with a preceding record ensuring that the
# unit's physical TOC/GPU/stream offsets change. Return only in-memory slices.
runner = LuaRunner()
runner.dll.lua_pushlstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t]
runner.dll.lua_setfield.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_char_p]
runner.dll.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
runner.dll.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
runner.dll.lua_tolstring.restype = ctypes.c_void_p
state = runner.dll.luaL_newstate()
try:
    runner.dll.luaL_openlibs(state)
    for name, data in (('unit_main', bytes(edited_main)), ('unit_gpu', parts['gpu']),
                       ('unit_stream', parts['stream']), ('unit_id', args.unit.encode())):
        runner.dll.lua_pushlstring(state, data, len(data))
        runner.dll.lua_setfield(state, -10002, name.encode())
    code = b"""
local B=dofile('src/presets/binding_patch_export.lua')
local p=B.archive('9ba626afa44a3aa3',{
 {resource='0000000000000001',type=B.TEXTURE,main=string.rep('x',340),gpu=string.rep('g',79),stream=string.rep('s',71)},
 {resource=unit_id,type=B.UNIT,main=unit_main,gpu=unit_gpu,stream=unit_stream}})
local function u(s,at) local a,b,c,d=s:byte(at+1,at+4);return a+b*256+c*65536+d*16777216 end
local at=72+u(p.main,4)*32+80
local main,gpu,stream=u(p.main,at+16),u(p.main,at+32),u(p.main,at+24)
assert(gpu==128 and stream==128)
return p.main:sub(main+1,main+u(p.main,at+56)),
 p.gpu:sub(gpu+1,gpu+u(p.main,at+64)),p.stream:sub(stream+1,stream+u(p.main,at+60))
"""
    error = runner.dll.luaL_loadstring(state, code)
    error = error or runner.dll.lua_pcall(state, 0, 3, 0)
    assert not error, 'Actual Lua archive writer rejected the read-only fixture'
    relocated = []
    for index in (1, 2, 3):
        size = ctypes.c_size_t()
        pointer = runner.dll.lua_tolstring(state, index, ctypes.byref(size))
        relocated.append(ctypes.string_at(pointer, size.value))
finally:
    runner.dll.lua_close(state)
assert relocated == [bytes(edited_main), parts['gpu'], parts['stream']]
after = deserialize(relocated[0], relocated[1])
assert geometry(before) == geometry(after), 'SDK geometry changed after unit material-ID edit and physical relocation'
assert after.MaterialIDs[0] == new_material and before.MaterialIDs[0] == old_material
assert after.MaterialIDs[1:] == before.MaterialIDs[1:] and after.SectionsIDs == before.SectionsIDs
digest, vertices, triangles = geometry(after)
print('PASS full pinned SDK unit deserialize: exact unit', args.unit, 'meshes', after.NumMeshes,
      'vertices', vertices, 'triangles', triangles, 'geometry_sha256', digest,
      'original archive GPU offset', record['gpu'][0], 'relocated GPU offset128;',
      'one verified material-table field differs; raw parts remain in memory; no export/game files written')

if fixture_records is not None:
    # Real retained Unit/material bytes and controlled synthetic palettes prove
    # per-mesh splitting without exporting game assets or touching the game.
    selected = None
    for section, material_id in zip(before.SectionsIDs, before.MaterialIDs):
        material_source = fixture_records.get(('eac0b497876adedf', f'{material_id:016x}'))
        if material_source is None:
            continue
        main = material_source['main']
        n = struct.unpack_from('<I', main, 64)[0]
        slots = struct.unpack_from('<' + 'I' * n, main, 136)
        if 0x81d4c49d not in slots:
            continue
        users = [(index, mesh, mesh.MaterialIDs.index(section))
                 for index, mesh in enumerate(before.MeshInfoArray) if section in mesh.MaterialIDs]
        if len(users) >= 3:
            texture = struct.unpack_from('<Q', main, 136 + n * 4 + slots.index(0x81d4c49d) * 8)[0]
            selected = section, material_id, material_source, texture, users
            break
    assert selected is not None, 'Retained fixture lacks three meshes sharing one Pattern material section'
    section, material_id, material_source, texture, users = selected
    baseline_user, changed_users = users[0], users[1:3]
    unit_source = fixture_records[(UNIT, args.unit)]
    globals_ = {'unit_id': args.unit.encode(), 'material_id': f'{material_id:016x}'.encode(),
                'texture_id': f'{texture:016x}'.encode(), 'section_id': str(section).encode()}
    for prefix, source in (('unit', unit_source), ('material', material_source)):
        for part in ('main', 'gpu', 'stream', 'toc'):
            globals_[prefix + '_' + part] = source[part]
    for number, (mesh_index, mesh, slot_index) in enumerate(changed_users, 1):
        at = before.MeshInfoOffset + before.MeshInfoOffsets[mesh_index]
        globals_['mesh_' + str(number)] = str(mesh.MeshID).encode()
        globals_['slot_' + str(number)] = str(slot_index).encode()
        globals_['offset_' + str(number)] = str(at + 128 + slot_index * 4).encode()
    state = runner.dll.luaL_newstate()
    try:
        runner.dll.luaL_openlibs(state)
        for name, data in globals_.items():
            runner.dll.lua_pushlstring(state, data, len(data))
            runner.dll.lua_setfield(state, -10002, name.encode())
        code = b"""
local ffi=require('ffi')
local D=dofile('src/core/dds.lua')
local P=dofile('src/presets/patch_export.lua')
local B=dofile('src/presets/binding_patch_export.lua')
local L=dofile('src/presets/binding_unit_layout.lua')
local unit={resource=unit_id,main=unit_main,gpu=unit_gpu,stream=unit_stream,toc=unit_toc}
local material={resource=material_id,main=material_main,gpu=material_gpu,stream=material_stream,toc=material_toc}
local baseline={width=3,height=1,data=ffi.new('float[12]')}
local original={resource=texture_id,width=3,height=1,
 patch_source='0123456789abcdef\\n'..string.rep('\\0',192)..D.encode(baseline.data,3,1):sub(1,148)}
local entries={}
for index=1,2 do
 local document={width=3,height=1,data=ffi.new('float[12]')}
 for channel=0,11 do document.data[channel]=index+channel/7 end
 local key='p:0:0:'..index..':0'
 entries[index]={kind='helmet',key=key,document=document,original=original,
  binding_source={version=1,verified=true,mesh_verified=true,kind='helmet',key=key,
   section=tonumber(section_id),mesh_id=tonumber(index==1 and mesh_1 or mesh_2),
   material_slot=tonumber(index==1 and slot_1 or slot_2),
   material_slot_offset=tonumber(index==1 and offset_1 or offset_2),
   original_texture=texture_id,texture_slot=0x81d4c49d,kit_override=false,unit=unit,material=material}}
end
entries[3]={kind='helmet',key='p:0:0:0:0',document=baseline,original=original}
local patch=P.encode_set(D,entries,{binding_writer=B,unit_layout=L,
 id_available=function(_,resource)return resource~=unit_id and resource~=material_id and resource~=texture_id end,
 original_patch=function(entry)return P.encode(D,baseline,entry.original)end})
local changed,clones={},{}
for _,record in ipairs(patch.records)do
 if record.type==B.UNIT then changed=record end
 if record.type==B.MATERIAL then clones[#clones+1]=record.main end
end
assert(#clones==2 and patch.count==6)
local reordered=P.encode_set(D,{entries[3],entries[2],entries[1]},{binding_writer=B,unit_layout=L,
 id_available=function(_,resource)return resource~=unit_id and resource~=material_id and resource~=texture_id end,
 original_patch=function(entry)return P.encode(D,baseline,entry.original)end})
assert(patch.main==reordered.main and patch.gpu==reordered.gpu and patch.stream==reordered.stream)
return changed.main,changed.gpu,changed.stream,clones[1],clones[2]
"""
        error = runner.dll.luaL_loadstring(state, code)
        error = error or runner.dll.lua_pcall(state, 0, 5, 0)
        if error:
            size = ctypes.c_size_t()
            pointer = runner.dll.lua_tolstring(state, -1, ctypes.byref(size))
            raise AssertionError(ctypes.string_at(pointer, size.value).decode(errors='replace'))
        split = []
        for index in range(1, 6):
            size = ctypes.c_size_t()
            pointer = runner.dll.lua_tolstring(state, index, ctypes.byref(size))
            split.append(ctypes.string_at(pointer, size.value))
    finally:
        runner.dll.lua_close(state)
    split_main, split_gpu, split_stream, *material_clones = split
    assert split_gpu == parts['gpu'] and split_stream == parts['stream']
    split_unit = deserialize(split_main, split_gpu)
    assert geometry(before) == geometry(split_unit), 'SDK geometry changed during per-mesh material splitting'
    assert split_unit.SectionsIDs[:len(before.SectionsIDs)] == before.SectionsIDs
    assert split_unit.MaterialIDs[:len(before.MaterialIDs)] == before.MaterialIDs
    assert len(split_unit.SectionsIDs) == len(before.SectionsIDs) + 2
    new_section_ids = split_unit.SectionsIDs[len(before.SectionsIDs):]
    assert len(set(new_section_ids)) == 2 and not set(new_section_ids).intersection(before.SectionsIDs)
    expected_prefix = bytearray(parts['main'])
    struct.pack_into('<I', expected_prefix, 96, split_unit.EndingOffset)
    struct.pack_into('<I', expected_prefix, 112, split_unit.MaterialsOffset)
    for mesh_index, mesh, slot_index in changed_users:
        after_mesh = split_unit.MeshInfoArray[mesh_index]
        new_section = after_mesh.MaterialIDs[slot_index]
        assert new_section in new_section_ids
        at = before.MeshInfoOffset + before.MeshInfoOffsets[mesh_index] + 128 + slot_index * 4
        struct.pack_into('<I', expected_prefix, at, new_section)
    assert split_main[:len(parts['main'])] == expected_prefix, 'Unknown/geometry bytes changed outside exact local slot words'
    original_table_end = before.MaterialsOffset + 4 + before.NumMaterials * 12
    split_table_end = split_unit.MaterialsOffset + 4 + split_unit.NumMaterials * 12
    assert split_main[split_table_end:] == parts['main'][original_table_end:]
    assert split_unit.EndingOffset == split_table_end + before.EndingOffset - original_table_end
    assert split_unit.UnReversedData2 == before.UnReversedData2 and split_unit.EndingBytes == before.EndingBytes
    baseline_index, _, baseline_slot = baseline_user
    assert split_unit.MeshInfoArray[baseline_index].MaterialIDs[baseline_slot] == section
    assert dict(zip(split_unit.SectionsIDs, split_unit.MaterialIDs))[section] == material_id
    material_module = importlib.import_module('sdk.stingray.material')
    before_material = material_module.StingrayMaterial()
    before_material.Serialize(memory.MemoryStream(material_source['main']))
    pattern_index = next(i for i, slot in enumerate(before_material.TextureTypes) if slot.ID == 0x81d4c49d)
    clone_textures = []
    for clone in material_clones:
        parsed = material_module.StingrayMaterial()
        parsed.Serialize(memory.MemoryStream(clone))
        assert parsed.TexIDs[:pattern_index] == before_material.TexIDs[:pattern_index]
        assert parsed.TexIDs[pattern_index + 1:] == before_material.TexIDs[pattern_index + 1:]
        clone_textures.append(parsed.TexIDs[pattern_index])
        expected_material = bytearray(material_source['main'])
        struct.pack_into('<Q', expected_material, 136 + before_material.NumTextures * 4 + pattern_index * 8,
                         parsed.TexIDs[pattern_index])
        assert clone == expected_material, 'Material fork changed bytes beyond its exact Pattern texture ID'
    assert len(set(clone_textures)) == 2 and texture not in clone_textures
    print('PASS full pinned SDK real-fixture split:', args.unit, 'two changed meshes',
          [index for index, _, _ in changed_users], 'baseline mesh', baseline_index,
          'original sections/materials/order and unknown bytes preserved; geometry_sha256', geometry(split_unit)[0],
          'GPU/stream identical; only exact mesh slot words/two header pointers, appended table and copied trailer differ;',
          'controlled synthetic palettes; no export/game files written')
