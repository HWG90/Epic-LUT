"""Exercise the production DDS/buffer modules in real Lua 5.1 and LuaJIT.

Uses only the existing Python/lupa installation. Python struct is the independent
IEEE754 oracle; neither runtime receives a mock FFI or bit library.
"""
from pathlib import Path
import math
import os
import random
import struct
import unittest

from lupa.lua51 import LuaRuntime as Lua51
from lupa.luajit21 import LuaRuntime as LuaJIT

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)


def load(runtime, *, native=False):
    lua = runtime(encoding=None, unpack_returned_tuples=True)
    if native:
        lua.execute(b"require('ffi')")  # Legacy caller, never the portable module.
    else:
        lua.execute(b"""
            ffi, bit, jit = nil, nil, nil
            local original = require
            function require(name)
                assert(name ~= 'ffi' and name ~= 'bit' and name ~= 'jit', 'Forbidden dependency: ' .. name)
                return original(name)
            end
        """)
    dds = lua.execute((ROOT / 'src/core/dds.lua').read_bytes())
    buffer = lua.eval(b"require('src.core.float_buffer')")
    return lua, dds, buffer


def image(payload, width=64, height=64, *, half=False, mips=1):
    words = [124, 0x100f, height, width, width * (8 if half else 16), 0, mips]
    words += [0] * 11
    words += [32, 4, 0x30315844, 0, 0, 0, 0, 0, 0x1000, 0, 0, 0, 0, 10 if half else 2, 3, 0, 1, 0]
    return b'DDS ' + struct.pack('<36I', *words) + payload


class DDSCompatibility(unittest.TestCase):
    def environments(self):
        yield 'Lua 5.1 portable', load(Lua51)
        yield 'LuaJIT portable', load(LuaJIT)
        yield 'LuaJIT legacy buffers', load(LuaJIT, native=True)

    def test_binary32_exact_roundtrip(self):
        rng = random.Random(0x25988413)
        words = [0, 0x80000000, 1, 0x80000001, 0x7fffff, 0x807fffff,
                 0x800000, 0x80800000, 0x7f7fffff, 0xff7fffff, 0x3f800000, 0xbf800000]
        while len(words) < 64 * 64 * 4:
            value = rng.getrandbits(32)
            if value & 0x7f800000 != 0x7f800000:
                words.append(value)
        payload = struct.pack('<%dI' % len(words), *words)
        encoded = image(payload)
        for name, (lua, dds, _) in self.environments():
            with self.subTest(runtime=name):
                data, width, height = dds.decode(encoded)
                self.assertEqual((width, height), (64, 64))
                self.assertEqual(dds.encode(data, width, height), encoded)
                self.assertTrue(lua.eval(b'function(data) return 1 / data[1] == -math.huge end')(data))

    def test_every_finite_binary16_value(self):
        values = [word for word in range(65536) if word & 0x7c00 != 0x7c00]
        for name, (_, dds, _) in self.environments():
            for start in range(0, len(values), 16384):
                batch = values[start:start + 16384]
                batch += [0] * (16384 - len(batch))
                half_payload = struct.pack('<16384H', *batch)
                expected = b''.join(struct.pack('<f', struct.unpack('<e', struct.pack('<H', word))[0]) for word in batch)
                with self.subTest(runtime=name, first_word=start):
                    data, width, height = dds.decode(image(half_payload, half=True))
                    self.assertEqual(dds.encode(data, width, height)[148:], expected)

    def test_float_rounding_and_overlap(self):
        rng = random.Random(0x51)
        values = [0., -0., 2. ** -150, -(2. ** -150), 3 * 2. ** -150,
                  1 + 2. ** -24, 1 + 3 * 2. ** -24, -(1 + 3 * 2. ** -24)]
        for _ in range(8000):
            value = math.ldexp(rng.uniform(-1, 1), rng.randint(-165, 128))
            if abs(value) <= 3.4028234663852886e38:
                values.append(value)
        expected = b''.join(struct.pack('<f', value) for value in values)
        for name, (lua, _, buffer) in self.environments():
            with self.subTest(runtime=name):
                data = buffer.new(len(values))
                assign = lua.eval(b'function(data, index, value) data[index] = value end')
                for index, value in enumerate(values):
                    assign(data, index, value)
                self.assertEqual(buffer.bytes(data, len(values)), expected)
                buffer.copy(data, data, 7, 1, 0)
                self.assertEqual(buffer.bytes(data, 8), expected[:4] + expected[:28])
                buffer.copy(data, data, 7, 0, 1)
                self.assertEqual(buffer.bytes(data, 7), expected[:28])
                buffer.copy(data, expected, 4, 3, 1)
                self.assertEqual(buffer.bytes(data, 4, 3), expected[4:20])
                with self.assertRaises(Exception):
                    buffer.copy(data, expected[:3], 1)

    def test_strict_validation_and_mips(self):
        valid = image(bytes(4 * 4 * 16), 4, 4)
        rejects = [b'', valid[:-1], valid + b'\0']
        for offset, word in [(4, 123), (76, 31), (16, 65), (12, 0), (28, 5),
                             (24, 2), (8, 0x80100f), (112, 0x200),
                             (128, 28), (132, 4), (136, 4), (140, 2),
                             (148, 0x7f800000), (148, 0xff800000), (148, 0x7fc00000)]:
            modified = bytearray(valid)
            struct.pack_into('<I', modified, offset, word)
            rejects.append(bytes(modified))
        for word in (0x7c00, 0xfc00, 0x7e00):
            rejects.append(image(struct.pack('<H', word) + bytes(30), 2, 2, half=True))
        for name, (lua, dds, buffer) in self.environments():
            with self.subTest(runtime=name):
                for bad in rejects:
                    with self.assertRaises(Exception):
                        dds.decode(bad)
                with self.assertRaises(Exception):
                    dds.decode(valid, 2, 2)
                with self.assertRaises(Exception):
                    dds.encode(buffer.new(3), 1, 1)
                with self.assertRaises(Exception):
                    dds.encode(lua.table_from({0: 0, 1: 0, 2: 0}), 1, 1)
                for width, height in ((0, 1), (1.5, 1), (1, 65), (float('nan'), 1)):
                    with self.assertRaises(Exception):
                        dds.encode(buffer.new(4), width, height)
                mip_payload = bytes((4 * 4 + 2 * 2 + 1) * 16)
                data, width, height = dds.decode(image(mip_payload, 4, 4, mips=3))
                self.assertEqual(dds.encode(data, width, height)[148:], bytes(4 * 4 * 16))

    def test_owned_array_proof_and_bounds(self):
        mapping_path = ROOT / 'src/editor/weapon_mapping.lua'
        for name, (lua, _, buffer) in self.environments():
            with self.subTest(runtime=name):
                for count in (None, -1, 0.5, 16385, 2 ** 53, float('inf'), float('nan'), b'4', True):
                    with self.assertRaises(Exception):
                        buffer.new(count)
                data = buffer.new(92)
                self.assertEqual(buffer.count(data), 92)
                forged = lua.eval(b"function() local t={_float_count=92}; for i=0,91 do t[i]=0 end; return t end")()
                self.assertIsNone(buffer.count(forged))
                self.assertIsNone(buffer.count(lua.table()))
                original = buffer.bytes(data, 92)
                for source, count, destination_offset, source_offset in (
                        (original, 2, 91, 0), (original, 2, 0, 91),
                        (data, 93, 0, 0), (data, 1, -1, 0)):
                    with self.assertRaises(Exception):
                        buffer.copy(data, source, count, destination_offset, source_offset)
                    self.assertEqual(buffer.bytes(data, 92), original)
                if lua.eval(b'function(value) return type(value) == "table" end')(data):
                    self.assertIsNone(lua.eval(b'rawget')(data, b'_float_count'))
                    assign = lua.eval(b'function(value, index) value[index]=3 end')
                    for index in (-1, 92, 1.5, b'_float_count'):
                        with self.assertRaises(Exception):
                            assign(data, index)
                        self.assertEqual(buffer.bytes(data, 92), original)
                    counterfeit = lua.eval(b'function(value) return setmetatable({},getmetatable(value)) end')(data)
                    self.assertIsNone(buffer.count(counterfeit))
                if mapping_path.is_file():
                    mapping = lua.execute(mapping_path.read_bytes())
                    valid_document = lua.table_from({b'width': 23, b'height': 1, b'data': data})
                    self.assertEqual(mapping.bytes(valid_document), original)
                    forged_document = lua.table_from({b'width': 23, b'height': 1, b'data': forged})
                    with self.assertRaises(Exception):
                        mapping.bytes(forged_document)
                    valid_document[b'original'] = forged
                    with self.assertRaises(Exception):
                        mapping.copy(valid_document)


if __name__ == '__main__':
    unittest.main()
