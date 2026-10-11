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
parser.add_argument('--game-data', required=True)
parser.add_argument('--archive', required=True)
parser.add_argument('--unit', required=True)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
for value in (args.archive, args.unit):
    assert len(value) == 16 and all(char in '0123456789abcdef' for char in value)

reader = Archives(args.game_data)
try:
    archive, record = reader.find([args.archive], args.unit, UNIT)
    assert archive == args.archive and record, 'Exact reviewed unit is absent from its archive'
    parts = {part: reader.part(archive, record, part, 0, record[part][1])
             for part in ('main', 'gpu', 'stream')}
finally:
    reader.close()
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
