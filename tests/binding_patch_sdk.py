"""Read-only cross-check of synthetic records against the pinned SDK serializers.

Run tests/binding_patch_export.lua first. SDK source and proof binaries remain
offline test inputs, never runtime dependencies or packaged game assets.
"""
import ast
import importlib.util
from pathlib import Path
import struct
import sys
import types

ROOT = Path(__file__).resolve().parents[1]
SDK = ROOT / 'dist/sdk-reference/5a886256e54db52b5d228335eae20ce796f87fc0'


class Stream:
    def __init__(self, data, writing=False):
        self.Data = bytearray(data)
        self.Location = 0
        self.writing = writing

    def IsReading(self):
        return not self.writing

    def IsWriting(self):
        return self.writing

    def tell(self):
        return self.Location

    def seek(self, value):
        self.Location = value

    def bytes(self, value, size=None):
        size = len(value) if size is None else size
        at = self.Location
        self.Location += size
        assert self.Location <= len(self.Data)
        if self.writing:
            assert len(value) == size
            self.Data[at:self.Location] = value
            return value
        return self.Data[at:self.Location]

    def scalar(self, value, fmt):
        size = struct.calcsize(fmt)
        encoded = struct.pack(fmt, value)
        return struct.unpack(fmt, self.bytes(encoded, size))[0]

    def uint32(self, value):
        return self.scalar(value, '<I')

    def uint64(self, value):
        return self.scalar(value, '<Q')

    def float32(self, value):
        return self.scalar(value, '<f')


# The real material serializer needs only these stream/logging adapters.
for name in ('sdk', 'sdk.stingray', 'sdk.utils'):
    module = types.ModuleType(name)
    module.__path__ = []
    sys.modules[name] = module
memory = types.ModuleType('sdk.utils.memoryStream')
memory.MemoryStream = Stream
sys.modules[memory.__name__] = memory
logger = types.ModuleType('sdk.utils.logger')
logger.PrettyPrint = lambda *args, **kwargs: None
sys.modules[logger.__name__] = logger
spec = importlib.util.spec_from_file_location('sdk.stingray.material', SDK / 'stingray/material.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
material_bytes = (ROOT / 'tests/tmp/binding-material-proof.bin').read_bytes()
material = module.StingrayMaterial()
material.Serialize(Stream(material_bytes))
assert material.NumTextures == 2
assert [texture.ID for texture in material.TextureTypes] == [0x81d4c49d, 0x7e662968]
assert material.TexIDs[1] == int('0011223344556677', 16)
output = Stream(bytes(len(material_bytes)), writing=True)
material.Serialize(output)
assert bytes(output.Data) == material_bytes

# Execute the exact unit material-table field block, without importing Blender
# or reserializing mesh geometry. All other unit bytes stay opaque to our writer.
tree = ast.parse((SDK / 'stingray/unit.py').read_text(encoding='utf-8'))
mesh = next(node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == 'StingrayMeshFile')
serialize = next(node for node in mesh.body if isinstance(node, ast.FunctionDef) and node.name == 'Serialize')
count_index = next(index for index, node in enumerate(serialize.body)
                   if isinstance(node, ast.Assign) and any(isinstance(target, ast.Attribute)
                       and target.attr == 'NumMaterials' for target in node.targets))
end_index = next(index for index in range(count_index + 1, len(serialize.body))
                 if isinstance(serialize.body[index], ast.Assign)
                 and any(isinstance(target, ast.Attribute) and target.attr == 'MaterialIDs'
                         for target in serialize.body[index].targets))
block = ast.FunctionDef(name='material_table', args=ast.arguments(posonlyargs=[],
    args=[ast.arg(arg='self'), ast.arg(arg='f')], kwonlyargs=[], kw_defaults=[], defaults=[]),
    body=serialize.body[count_index - 1:end_index + 1], decorator_list=[])
namespace = {}
exec(compile(ast.fix_missing_locations(ast.Module(body=[block], type_ignores=[])),
             str(SDK / 'stingray/unit.py'), 'exec'), namespace)
unit_bytes = (ROOT / 'tests/tmp/binding-unit-proof.bin').read_bytes()
unit = types.SimpleNamespace(MaterialsOffset=struct.unpack_from('<I', unit_bytes, 112)[0],
                             SectionsIDs=[], MaterialIDs=[])
namespace['material_table'](unit, Stream(unit_bytes))
assert unit.SectionsIDs == [101, 102, 103]
assert len(set(unit.MaterialIDs)) == 3
assert unit.MaterialIDs[2] == int('1234567890abcdef', 16)
output = Stream(unit_bytes, writing=True)
output.seek(unit.MaterialsOffset)
namespace['material_table'](unit, output)
assert bytes(output.Data) == unit_bytes
print('PASS pinned SDK cross-check: full material serializer and exact unit SectionID/MaterialIDs field block round-trip synthetic patched records without geometry changes')
