"""Portable LZNT1 compatibility against Windows' actual ntdll implementation.
No game access, Lua FFI emulation, third-party decoder or installed tools.
"""
import ctypes
import random
import statistics
import time
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
nt = ctypes.WinDLL('ntdll')
u32, u16, status = ctypes.c_uint32, ctypes.c_uint16, ctypes.c_int32
nt.RtlGetCompressionWorkSpaceSize.argtypes = [u16, ctypes.POINTER(u32), ctypes.POINTER(u32)]
nt.RtlGetCompressionWorkSpaceSize.restype = status
nt.RtlCompressBuffer.argtypes = [u16, ctypes.c_void_p, u32, ctypes.c_void_p, u32, u32,
                                ctypes.POINTER(u32), ctypes.c_void_p]
nt.RtlCompressBuffer.restype = status
nt.RtlDecompressBuffer.argtypes = [u16, ctypes.c_void_p, u32, ctypes.c_void_p, u32, ctypes.POINTER(u32)]
nt.RtlDecompressBuffer.restype = status
workspace_size, fragment = u32(), u32()
assert nt.RtlGetCompressionWorkSpaceSize(2, ctypes.byref(workspace_size), ctypes.byref(fragment)) == 0
workspace = ctypes.create_string_buffer(workspace_size.value)

def native_compress(data, format=2):
    active_workspace = workspace
    if format != 2:
        needed, fragment = u32(), u32()
        assert nt.RtlGetCompressionWorkSpaceSize(format, ctypes.byref(needed), ctypes.byref(fragment)) == 0
        active_workspace = ctypes.create_string_buffer(needed.value)
    output, final = ctypes.create_string_buffer(len(data) + 4096), u32()
    result = nt.RtlCompressBuffer(format, data, len(data), output, len(output), 4096,
                                 ctypes.byref(final), active_workspace)
    assert result in (0, 0x117), hex(result & 0xffffffff)  # STATUS_BUFFER_ALL_ZEROS retains valid output
    return output.raw[:final.value]

def native_decompress(data, size):
    output, final = ctypes.create_string_buffer(size), u32()
    result = nt.RtlDecompressBuffer(2, output, size, data, len(data), ctypes.byref(final))
    assert result == 0 and final.value == size, (hex(result & 0xffffffff), final.value, size)
    return output.raw[:size]

def runtime():
    lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
    lua.execute(b"ffi,bit,jit=nil,nil,nil;local original=require;function require(name) assert(name~='ffi' and name~='bit' and name~='jit');return original(name)end")
    return lua

lua = runtime()
codec = lua.execute((ROOT / 'src/core/lznt1.lua').read_bytes())
rng = random.Random(25988413)
fixtures = []
for size in [1, 2, 3, 15, 16, 17, 31, 32, 33, 255, 256, 257, 511, 512, 513,
             1023, 1024, 1025, 2047, 2048, 2049, 4095, 4096, 4097, 8191, 8192, 65536]:
    fixtures.append(bytes([0]) * size)
    fixtures.append((bytes(range(256)) * ((size + 255) // 256))[:size])
    fixtures.append(rng.randbytes(size))
for size in [33, 257, 4096, 8192, 65536]:
    motif = rng.randbytes(41)
    fixtures.append((motif * ((size + len(motif) - 1) // len(motif)))[:size])
# Official MS-XCA section3.3 example, including overlapping matches and terminalNUL.
example = b'F# F# G A A G F# E D D E F# F# E E F# F# G A A G F# E D D E F# E D D E E F# D E F# G F# D E F# G F# E D E A F# F# G A A G F# E D D E F# E D D\0'
reference = bytes.fromhex('38 b0 88 46 23 20 00 20 47 20 41 00 10 a2 47 01 a0 45 20 44 00 08 45 01 50 79 00 c0 45 20 05 24 13 88 05 b4 02 4a 44 ef 03 58 02 8c 09 16 01 48 45 00 be 00 9e 00 04 01 18 90 00')
assert len(example) == 142
assert codec.decompress(reference, len(example)) == native_decompress(reference, len(example)) == example
fixtures.append(example)
compress_times, decompress_times, ratios = [], [], []
for raw in fixtures:
    started = time.perf_counter(); packed = codec.compress(raw); compress_times.append(time.perf_counter() - started)
    assert native_decompress(packed, len(raw)) == raw
    assert codec.decompress(packed, len(raw)) == raw
    stock = native_compress(raw)
    started = time.perf_counter(); unpacked = codec.decompress(stock, len(raw)); decompress_times.append(time.perf_counter() - started)
    assert unpacked == raw
    assert codec.decompress(stock + b'\0\0', len(raw)) == raw
    ratios.append((len(raw), len(packed), len(stock)))

# Header/truncation/displacement/signature/chunk-expansion failures are atomic.
malformed = [b'', b'\x00', b'\x00\x00', b'\x00\x20x', b'\x01\x30x',
             b'\x02\xb0\x01\x00\x00', b'\x00\xb0\x00',
             b'\x03\xb0\x02A\xff\x0f', b'\x00\x30A\x00\x30B']
for data in malformed:
    try: codec.decompress(data, 16)
    except Exception: pass
    else: raise AssertionError(('Malformed LZNT1 accepted', data.hex()))
codec[b'MAX_RAW'], codec[b'MAX_COMPRESSED'], codec[b'MAX_CHAIN'] = 2**31, 2**31, 2**31
for raw in [b'', b'x' * 65537]:
    try: codec.compress(raw)
    except Exception: pass
    else: raise AssertionError('Compression bounds ignored')
for tag in [b'x', b'invalid']:
    try: codec.decompress(reference, len(example), tag)
    except Exception: pass
    else: raise AssertionError('Unsupported compression tag accepted')
print('PASS portable LZNT1: official overlap vector,', len(fixtures), 'cross-ntdll vectors, chunk/token boundaries, raw/repeated/random64KiB, malformed input and exact-size bounds')
print('Stock Lua5.1 maximum compression/decompression CPU ms:', round(max(compress_times) * 1000, 3), round(max(decompress_times) * 1000, 3))
print('64KiB size comparisons (raw, portable, ntdll):', [row for row in ratios if row[0] == 65536])

# The real stock Shared LUT codec uses this backend by default. Check actual
# wire compression and source->receiver pixels, not the token serialization fixture.
import base64
import os
os.chdir(ROOT)
shared, entries, identity, buffers = lua.execute(b"""
    local buffers = dofile('src/core/float_buffer.lua')
    local C = dofile('src/gear/shared_lut_codec.lua')
    local originals, entries = {}, {}
    for n=1,10 do
        local base={width=23,height=8,data=buffers.new(736),resource=string.format('%016x',n)}
        local edited={width=23,height=8,data=buffers.new(736)}
        for i=0,735 do base.data[i]=math.sin(i*17+n*31)*4+i/1000 end
        buffers.copy(edited.data,base.data,736)
        edited.data[n*4],edited.data[n*4+1],edited.data[n*4+3]=2.75,-0.125,0.375
        originals[base.resource]=base
        entries[n]={key='0:1:'..n..':0',document=edited,original=base}
    end
    return C.new(nil,function(resource)return originals[resource]end),entries,{body=123,armor=456,helmet=789},buffers
""")
started=time.perf_counter(); packet=shared.encode(identity,entries); elapsed=time.perf_counter()-started
version, size, encoded=packet.split(b'|')
assert b'x' not in version and len(packet)<=3600
raw=native_decompress(base64.b64decode(encoded),int(size))
assert raw[:3]==b'EL'+version
result=shared.decode(packet)
for entry in entries.values():
    doc=result[b'entries'][entry[b'key']][b'document']
    assert buffers.bytes(doc[b'data'],736)==buffers.bytes(entry[b'document'][b'data'],736)
print('PASS actual stock Shared LUT -> Windows LZNT1 wire:',len(packet),'bytes; ten exact baseline LUTs; encode CPU ms:',round(elapsed*1000,3))

# Incoming legacy tagged XPRESS remains readable under stock Lua5.1.
x_packet=version+b'x|'+size+b'|'+base64.b64encode(native_compress(raw,3))
x_result=shared.decode(x_packet)
for entry in entries.values():
    doc=x_result[b'entries'][entry[b'key']][b'document']
    assert buffers.bytes(doc[b'data'],736)==buffers.bytes(entry[b'document'][b'data'],736)
print('PASS actual Windows XPRESS -> stock Shared LUT tagged packet:',len(x_packet),'bytes')
