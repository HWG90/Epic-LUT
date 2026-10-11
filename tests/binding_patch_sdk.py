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

    def int32(self, value):
        return self.scalar(value, '<i')

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
# Execute exact mesh serializers too: a SectionID is selected by its local
# material index, and the global table supplies that SectionID's material ID.
mesh_classes = [node for node in tree.body if isinstance(node, ast.ClassDef)
                and node.name in ('MeshInfo', 'MeshSectionInfo')]
namespace['MemoryStream'] = Stream
exec(compile(ast.Module(body=mesh_classes, type_ignores=[]), str(SDK / 'stingray/unit.py'), 'exec'), namespace)


def tables(data):
    unit = types.SimpleNamespace(MaterialsOffset=struct.unpack_from('<I', data, 112)[0],
                                 SectionsIDs=[], MaterialIDs=[])
    namespace['material_table'](unit, Stream(data))
    mesh_at = struct.unpack_from('<I', data, 100)[0]
    count = struct.unpack_from('<I', data, mesh_at)[0]
    meshes = []
    for index in range(count):
        at = mesh_at + struct.unpack_from('<I', data, mesh_at + 4 + index * 4)[0]
        reader = Stream(data)
        reader.seek(at)
        meshes.append((at, namespace['MeshInfo']().Serialize(reader)))
    return unit, meshes


old_material = int('1234567890abcdef', 16)
for stem, baseline_section in [('binding-unit', 103), ('binding-unit-shared', 101)]:
    unit_bytes = (ROOT / f'tests/tmp/{stem}-proof.bin').read_bytes()
    pristine = (ROOT / f'tests/tmp/{stem}-original-proof.bin').read_bytes()
    original, old_meshes = tables(pristine)
    unit, meshes = tables(unit_bytes)
    assert original.SectionsIDs == [101, 102, 103]
    assert unit.SectionsIDs[:3] == original.SectionsIDs
    assert unit.MaterialIDs[:3] == original.MaterialIDs == [old_material] * 3
    assert len(unit.SectionsIDs) == 5 and len(set(unit.SectionsIDs)) == 5
    assert len(set(unit.MaterialIDs)) == 3
    lookup = dict(zip(unit.SectionsIDs, unit.MaterialIDs))
    selected = [mesh.MaterialIDs[0] for _, mesh in meshes[:2]]
    assert selected[0] != selected[1]
    assert all(section not in original.SectionsIDs for section in selected)
    assert lookup[selected[0]] != lookup[selected[1]]
    assert meshes[2][1].MaterialIDs == [baseline_section]
    assert lookup[baseline_section] == old_material
    expected_prefix = bytearray(pristine)
    ending = struct.unpack_from('<I', unit_bytes, 96)[0]
    original_ending = struct.unpack_from('<I', pristine, 96)[0]
    struct.pack_into('<I', expected_prefix, 96, ending)
    struct.pack_into('<I', expected_prefix, 112, unit.MaterialsOffset)
    for index, section in enumerate(selected):
        struct.pack_into('<I', expected_prefix, meshes[index][0] + 128, section)
    assert unit_bytes[:len(pristine)] == expected_prefix
    assert unit.MaterialsOffset >= len(pristine)
    table_end = unit.MaterialsOffset + 4 + 12 * len(unit.SectionsIDs)
    original_table_end = original.MaterialsOffset + 4 + 12 * len(original.SectionsIDs)
    assert unit_bytes[table_end:] == pristine[original_table_end:]
    assert ending == table_end + original_ending - original_table_end
    for (_, before), (_, after) in zip(old_meshes, meshes):
        assert before.MeshID == after.MeshID
        assert before.NumMaterials == after.NumMaterials == 1
        assert before.NumSections == after.NumSections == 1
        assert [(section.MaterialIndex, section.VertexOffset, section.NumVertices,
                 section.IndexOffset, section.NumIndices, section.GroupIndex)
                for section in before.Sections] == [
                    (section.MaterialIndex, section.VertexOffset, section.NumVertices,
                     section.IndexOffset, section.NumIndices, section.GroupIndex)
                    for section in after.Sections]
        assert after.Sections[0].ID == after.MaterialIDs[0]
    output = Stream(unit_bytes, writing=True)
    output.seek(unit.MaterialsOffset)
    namespace['material_table'](unit, output)
    for at, mesh in meshes:
        output.seek(at)
        mesh.Serialize(output)
    assert bytes(output.Data) == unit_bytes
print('PASS pinned SDK cross-check: full material and exact mesh/global section serializers round-trip isolated synthetic forks; original table, unselected/baseline slots and geometry metadata remain unchanged')
