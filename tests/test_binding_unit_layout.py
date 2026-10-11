"""Read-only real-fixture comparison with the pinned SDK mesh serializers.

Game assets remain optional local inputs under ignored dist; no game API is called.
"""
import ast
import ctypes
import json
import os
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
SDK = ROOT / 'dist/sdk-reference/5a886256e54db52b5d228335eae20ce796f87fc0'
sys.path.insert(0, str(ROOT))
from tools.lua_runner import LuaRunner


class Stream:
    def __init__(self, data):
        self.data, self.at = data, 0

    def IsReading(self):
        return True

    def IsWriting(self):
        return False

    def tell(self):
        return self.at

    def seek(self, value):
        self.at = value

    def bytes(self, value, size):
        result = self.data[self.at:self.at + size]
        assert len(result) == size
        self.at += size
        return result

    def scalar(self, fmt):
        size = struct.calcsize(fmt)
        return struct.unpack(fmt, self.bytes(None, size))[0]

    def uint32(self, value):
        return self.scalar('<I')

    def int32(self, value):
        return self.scalar('<i')

    def uint64(self, value):
        return self.scalar('<Q')


os.chdir(ROOT)
os.environ['EPIC_LUT_TEST_ROOT'] = str(ROOT)
runner = LuaRunner()
runner.check(ROOT / 'src/presets/binding_unit_layout.lua')
runner.check(ROOT / 'tests/binding_unit_layout.lua', execute=True)
fixtures = sorted((ROOT / 'dist/preview-mesh-research').glob('*.unit.bin'))
if not fixtures or not (SDK / 'stingray/unit.py').is_file():
    print('SKIP optional retained Unit fixture SDK comparison: local SDK/assets unavailable')
    raise SystemExit(0)
tree = ast.parse((SDK / 'stingray/unit.py').read_text(encoding='utf-8'))
classes = [node for node in tree.body if isinstance(node, ast.ClassDef)
           and node.name in ('MeshInfo', 'MeshSectionInfo')]
assert len(classes) == 2
namespace = {'MemoryStream': Stream}
exec(compile(ast.Module(body=classes, type_ignores=[]), 'pinned SDK mesh serializers', 'exec'), namespace)
checks = ["local L=dofile('src/presets/binding_unit_layout.lua')",
          "local function read(path) local f=assert(io.open(path,'rb')); local b=f:read('*a'); f:close(); return b end"]
inline, composite, slots = 0, 0, 0
for path in fixtures:
    data = path.read_bytes()
    checks.append(f"do local layout=L.parse(read({json.dumps(path.as_posix())}))")
    table_at = struct.unpack_from('<I', data, 112)[0]
    count = struct.unpack_from('<I', data, table_at)[0]
    checks.append(f'assert(#layout.sections=={count})')
    for j in range(count):
        section_at, material_at = table_at + 4 + 4*j, table_at + 4 + 4*count + 8*j
        section = struct.unpack_from('<I', data, section_at)[0]
        material = struct.unpack_from('<Q', data, material_at)[0]
        checks.append(f"assert(layout.sections[{j+1}].section=={section} and layout.sections[{j+1}].material=='{material:016x}')")
        checks.append(f'assert(layout.sections[{j+1}].section_offset=={section_at} and layout.sections[{j+1}].material_offset=={material_at})')
    if struct.unpack_from('<Q', data, 16)[0]:
        composite += 1
        checks.append("assert(not layout.supported and layout.unsupported=='composite_geometry' and #layout.meshes==0) end")
        continue
    inline += 1
    mesh_at = struct.unpack_from('<I', data, 100)[0]
    count = struct.unpack_from('<I', data, mesh_at)[0]
    checks.append(f'assert(layout.supported and #layout.meshes=={count})')
    for j in range(count):
        at = mesh_at + struct.unpack_from('<I', data, mesh_at + 4 + 4*j)[0]
        stream = Stream(data)
        stream.seek(at)
        mesh = namespace['MeshInfo']().Serialize(stream)
        checks.append(f'assert(layout.meshes[{j+1}].id=={mesh.MeshID} and layout.meshes[{j+1}].lod=={mesh.LodIndex})')
        checks.append(f'assert(#layout.meshes[{j+1}].material_slots=={mesh.NumMaterials} and #layout.meshes[{j+1}].draw_sections=={mesh.NumSections})')
        for k, section in enumerate(mesh.MaterialIDs):
            slots += 1
            checks.append(f'assert(layout.meshes[{j+1}].material_slots[{k+1}].section=={section} and layout.meshes[{j+1}].material_slots[{k+1}].offset=={at+mesh.MaterialOffset+4*k})')
        for k, section in enumerate(mesh.Sections):
            checks.append(f'assert(layout.meshes[{j+1}].draw_sections[{k+1}].section=={section.ID} and layout.meshes[{j+1}].draw_sections[{k+1}].material_index=={section.MaterialIndex})')
    checks.append('end')
source = '\n'.join(checks).encode()
runner.dll.luaL_loadbuffer.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
state = runner.dll.luaL_newstate()
assert state
try:
    runner.dll.luaL_openlibs(state)
    code = runner.dll.luaL_loadbuffer(state, source, len(source), b'Unit layout SDK comparison')
    if not code:
        code = runner.dll.lua_pcall(state, 0, 0, 0)
    if code:
        raise AssertionError(runner.dll.lua_tolstring(state, -1, None).decode(errors='replace'))
finally:
    runner.dll.lua_close(state)
print(f'PASS pinned SDK Unit layouts: {inline} real inline fixtures, {slots} slot positions, {composite} composite refusals; no input writes')
