"""Bounded production XPRESS decode, with Windows ntdll as independent oracle.

The runtime module imports no native library. ctypes is only the offline oracle.
Algorithm reference: Microsoft MS-XCA2.4.4 Plain LZ77 Decompression Processing.
"""
from pathlib import Path
import ctypes
import random
import struct
import sys
import unittest

from lupa.lua51 import LuaRuntime as Lua51
from lupa.luajit21 import LuaRuntime as LuaJIT

ROOT = Path(__file__).resolve().parents[1]


def decoder(runtime):
    lua = runtime(encoding=None, unpack_returned_tuples=True)
    lua.execute(b"""
        ffi,bit,jit=nil,nil,nil
        require=function(name)error('Forbidden native import: '..name)end
    """)
    return lua.execute((ROOT / 'src/core/xpress.lua').read_bytes())


def literals(data):
    result = bytearray()
    for at in range(0, len(data), 32):
        group = data[at:at + 32]
        result += struct.pack('<I', (1 << (32 - len(group))) - 1) + group
    if len(data) % 32 == 0:
        result += b'\xff' * 4
    return bytes(result)


class XpressDecoder(unittest.TestCase):
    def setUp(self):
        self.modules = [decoder(Lua51), decoder(LuaJIT)]

    def check(self, packed, raw):
        for module in self.modules:
            self.assertEqual(module[b'decompress'](packed, len(raw)), raw)

    def bad(self, packed, size):
        for module in self.modules:
            with self.assertRaises(Exception):
                module[b'decompress'](packed, size)

    def test_literals_and_flag_group_boundaries(self):
        for length in [0, 1, 2, 15, 16, 31, 32, 33, 63, 64, 65, 8192, 65536]:
            raw = bytes(index % 256 for index in range(length))
            self.check(literals(raw), raw)

    def test_overlapping_matches_and_all_length_extensions(self):
        # One literal then a match at distance1; remaining flag bits terminate.
        prefix = struct.pack('<I', 0x7fffffff) + b'a'
        for length in range(3, 10):
            self.check(prefix + struct.pack('<H', length - 3), b'a' * (length + 1))
        for length in range(10, 25):
            self.check(prefix + b'\x07\0' + bytes([length - 10]), b'a' * (length + 1))
        for length in [25, 26, 278, 279]:
            self.check(prefix + b'\x07\0\x0f' + bytes([length - 25]), b'a' * (length + 1))
        for length in [280, 4096, 65535]:
            self.check(prefix + b'\x07\0\x0f\xff' + struct.pack('<H', length - 3), b'a' * (length + 1))
        self.check(prefix + b'\x07\0\x0f\xff\0\0' + struct.pack('<I', 65532), b'a' * 65536)
        # The high half of the first length byte belongs to the second match.
        self.check(prefix + b'\x07\0\x31\x07\0', b'a' * (1 + 11 + 13))

    def test_truncated_offsets_lengths_and_exact_size(self):
        prefix = struct.pack('<I', 0x7fffffff) + b'a'
        valid = prefix + b'\x07\0\x0f\xff' + struct.pack('<H', 4093)
        for at in range(len(valid)):
            self.bad(valid[:at], 4097)
        self.bad(struct.pack('<I', 0xffffffff) + b'\0\0', 3)
        self.bad(prefix + struct.pack('<H', 8), 4)  # distance2 after one byte
        self.bad(prefix + b'\x07\0\x0f\xff\x15\0', 23)
        self.bad(prefix + b'\x07\0\x0f\xff\0\0' + struct.pack('<I', 2**32 - 1), 65536)
        self.bad(literals(b'a'), 0)
        self.bad(literals(b'a'), 2)
        self.bad(literals(b'a') + b'garbage', 1)
        self.bad(literals(b'a'), -1)
        self.bad(literals(b'a'), 65537)
        self.bad(literals(b'a'), 1.5)
        self.bad(b'\xff' * (65536 + 8192 + 5), 65536)
        for module in self.modules:
            module[b'MAX_RAW'] = 2**32
            module[b'MAX_PACKED'] = 2**32
        self.bad(literals(b'a'), 65537)
        self.bad(b'\xff' * (65536 + 8192 + 5), 65536)

    @unittest.skipUnless(sys.platform == 'win32', 'Windows ntdll oracle required')
    def test_windows_xpress_compressor_roundtrip(self):
        native = ctypes.WinDLL('ntdll')
        ulong = ctypes.c_ulong
        native.RtlGetCompressionWorkSpaceSize.argtypes = [ctypes.c_ushort, ctypes.POINTER(ulong), ctypes.POINTER(ulong)]
        native.RtlCompressBuffer.argtypes = [ctypes.c_ushort, ctypes.c_void_p, ulong, ctypes.c_void_p,
                                           ulong, ulong, ctypes.POINTER(ulong), ctypes.c_void_p]
        workspace_size, fragment_size = ulong(), ulong()
        self.assertEqual(native.RtlGetCompressionWorkSpaceSize(3, ctypes.byref(workspace_size), ctypes.byref(fragment_size)), 0)
        workspace = ctypes.create_string_buffer(workspace_size.value)
        rng = random.Random(25988413)
        payloads = [b'a' * 16, b'abc' * 50, bytes(range(256)) * 256, b'\0' * 65536]
        for length in [16, 17, 31, 32, 33, 64, 255, 256, 257, 4096, 8192, 16384, 65536]:
            raw = rng.randbytes(length)
            payloads += [raw, (raw[:max(1, length // 7)] * 8)[:length]]
        for raw in payloads:
            with self.subTest(size=len(raw)):
                source = ctypes.create_string_buffer(raw)
                target = ctypes.create_string_buffer(131072)
                size = ulong()
                status = native.RtlCompressBuffer(3, source, len(raw), target, len(target), 4096,
                                                  ctypes.byref(size), workspace)
                self.assertEqual(status, 0)
                packed = target.raw[:size.value]
                self.check(packed, raw)
                self.bad(packed[:-1], len(raw))
                self.bad(packed, len(raw) - 1)


if __name__ == '__main__':
    unittest.main()
