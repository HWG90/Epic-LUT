"""Production Unicode streams + core file/DDS APIs against a real Lua5.1 DLL.
Only private temporary files; no game, clipboard, ShellExecute, or worker launch.
"""
import ctypes
import hashlib
import json
import os
import msvcrt
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import time

from lupa.lua51 import LuaError, LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MAX_FILE = 64 * 1024 * 1024
MAX_POSITION = 2 ** 53 - 1


def sparse_file(path, size, markers):
    """Mark the private NTFS test file sparse before extending beyond 4 GiB."""
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    control = kernel.DeviceIoControl
    control.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_uint32,
                        ctypes.c_void_p, ctypes.c_uint32, ctypes.POINTER(ctypes.c_uint32), ctypes.c_void_p]
    control.restype = ctypes.c_int
    with path.open('w+b') as output:
        returned = ctypes.c_uint32()
        assert control(msvcrt.get_osfhandle(output.fileno()), 0x900C4, None, 0, None, 0,
                       ctypes.byref(returned), None), ctypes.get_last_error()
        output.truncate(size)
        for offset, data in markers:
            output.seek(offset);output.write(data)


def worker(directory, library):
    root = Path(directory)
    receipt = json.loads((ROOT / 'dist/native-lua51-platform/build.json').read_text())
    assert hashlib.sha256(Path(library).read_bytes()).hexdigest() == receipt['sha256']
    assert hashlib.sha256((ROOT / 'native/lua51_platform.c').read_bytes()).hexdigest() == receipt['source_sha256']
    lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
    lua.execute(b"""assert(_VERSION=='Lua 5.1'); ffi,bit,jit=nil,nil,nil
        for _,name in ipairs({'ffi','bit','jit'}) do
            package.loaded[name]=nil;package.preload[name]=function()error('Native Lua dependency')end
        end
    """)
    loadfile = lua.eval(b'dofile')
    module = loadfile(str(ROOT / 'src/platform/native_platform.lua').encode('ascii'))
    options = lua.table_from({b'library': str(library).encode('ascii'), b'process_id': os.getpid()})
    service = module.new(options)
    files = loadfile(str(ROOT / 'src/core/file_io.lua').encode('ascii')).new(service)
    call = lua.eval(b'function(object,name,...) return object[name](object,...) end')
    identity = lua.eval(b'function(a,b) return rawequal(a,b) end')
    failed = lambda value: isinstance(value, tuple) and value[0] is None and isinstance(value[1], bytes)
    missing = str(root / '\u4e0d\u5728\U0001f986.dds').encode()
    assert failed(service.open(missing, b'rb'))
    assert failed(files.read(missing, 100, True))
    try:
        files.read(missing, 100)
    except LuaError:
        pass
    else:
        raise AssertionError('Required missing file was accepted')
    assert failed(service.open(missing, b'rt'))

    work = root / '\u8863\u88c5 \U0001f986'
    assert service.mkdir(str(work).encode())
    rename_source, rename_destination = work / '\u79fb\u52d5.bin', work / '\u65e2\u5b58.bin'
    rename_source.write_bytes(b'source');rename_destination.write_bytes(b'destination')
    assert failed(service.rename(str(rename_source).encode(), str(rename_destination).encode()))
    assert rename_source.read_bytes() == b'source' and rename_destination.read_bytes() == b'destination'
    assert service.remove(str(rename_destination).encode()) is True
    assert service.rename(str(rename_source).encode(), str(rename_destination).encode()) is True
    assert not rename_source.exists() and rename_destination.read_bytes() == b'source'
    assert service.remove(str(rename_destination).encode()) is True
    assert failed(service.remove(str(rename_destination).encode()))
    assert failed(service.remove(str(work).encode())) and work.is_dir()
    name = work / '\u5927\u304d\u3044 palette.bin'
    path = str(name).encode()
    payload = bytes(range(256)) * 8193 + b'\0\xff\r\n\x1aend'
    assert len(payload) > 2 * 1024 * 1024
    started = time.perf_counter()
    assert files.write(path, payload) is True
    write_ms = (time.perf_counter() - started) * 1000
    assert name.read_bytes() == payload
    started = time.perf_counter()
    assert files.read(path, len(payload)) == payload
    read_ms = (time.perf_counter() - started) * 1000
    try:
        files.read(path, len(payload) - 1)
    except LuaError as error:
        assert 'File size budget exceeded' in str(error)
    else:
        raise AssertionError('Core read budget was ignored')
    stream = service.open(path, b'rb')
    assert stream[b'handle'] is None and stream[b'token'] is None
    assert call(stream, b'read', 0) == b''
    assert call(stream, b'read', 3) == payload[:3]
    assert call(stream, b'seek') == 3
    assert call(stream, b'seek', b'cur', -2) == 1
    assert call(stream, b'read', 2) == payload[1:3]
    assert call(stream, b'seek', b'end', -7) == len(payload) - 7
    assert call(stream, b'read', 100) == payload[-7:]
    assert call(stream, b'read', 1) is None and call(stream, b'read', 0) is None
    assert call(stream, b'read', b'*a') == b''
    assert call(stream, b'seek', b'set', 0) == 0
    assert call(stream, b'read', b'*a') == payload
    # Read opens permit other readers but prevent simultaneous foreign writes.
    try:
        with name.open('wb'):
            pass
    except PermissionError:
        pass
    else:
        raise AssertionError('Read stream permitted a foreign writer')
    assert call(stream, b'flush') is True
    assert call(stream, b'close') is True and call(stream, b'close') is True
    assert failed(call(stream, b'read', 1))

    empty = str(work / '\u7a7a.bin').encode()
    assert files.write(empty, b'') is True and files.read(empty, 0) == b''
    stream = service.open(empty, b'rb')
    assert call(stream, b'read', b'*a') == b'' and call(stream, b'read', 1) is None
    assert call(stream, b'close') is True
    stream = service.open(path, b'ab')
    assert call(stream, b'seek', b'set', 0) == 0
    assert identity(call(stream, b'write', b'append\0'), stream)
    assert call(stream, b'flush') is True
    assert call(stream, b'close') is True
    assert name.read_bytes() == payload + b'append\0'
    variadic_path = str(work / 'variadic manifest.bin').encode()
    stream = service.open(variadic_path, b'wb')
    assert identity(call(stream, b'write'), stream), 'Zero-argument write did not return its stream'
    values = [b'prefix\0', 12.5, 0, -3, -0.0, 1e25, b'\nrows\n', b'']
    expected = lua.execute(b"""return function(...) local file=assert(io.tmpfile())
        assert(file:write(...))
        assert(file:seek('set',0)==0);local bytes=file:read('*a');assert(file:close());return bytes
    end""")(*values)
    assert identity(call(stream, b'write', *values), stream)
    assert call(stream, b'close') is True and Path(variadic_path.decode()).read_bytes() == expected
    for bad in [lua.table(), None, float('nan'), float('inf'), -float('inf')]:
        stream = service.open(variadic_path, b'ab')
        assert failed(call(stream, b'write', b'MUST NOT APPEND', bad))
        assert call(stream, b'close') is True and Path(variadic_path.decode()).read_bytes() == expected
    # Unsupported reads, permission errors, and invalid seeks retire ownership.
    for mode, method, args in [(b'rb', b'read', [b'*l']), (b'rb', b'write', [b'x']),
                               (b'wb', b'read', [1]), (b'rb', b'seek', [b'set', -1]),
                               (b'rb', b'read', [MAX_FILE + 2])]:
        stream = service.open(empty, mode)
        assert failed(call(stream, method, *args))
        assert failed(call(stream, b'seek', b'cur', 0))
        assert call(stream, b'close') is True
    # Native ownership budget is private and does not grow with public fields.
    module[b'MAX_PAYLOAD'] = 2 ** 30
    opened = [service.open(path, b'rb') for _ in range(8)]
    assert failed(service.open(path, b'rb'))
    assert call(opened.pop(), b'close') is True
    extra = service.open(path, b'rb')
    assert call(extra, b'close') is True
    for stream in opened:
        assert call(stream, b'close') is True

    large = work / 'exact64.bin'
    with large.open('wb') as output:
        output.truncate(MAX_FILE)
    # F.read asks limit+1; the EOF probe must still permit an exact64MiB file.
    result = files.read(str(large).encode(), MAX_FILE)
    assert len(result) == MAX_FILE and result == b'\0' * MAX_FILE
    del result
    stream = service.open(str(large).encode(), b'rb')
    assert call(stream, b'seek', b'end') == MAX_FILE
    assert call(stream, b'read', 1) is None and call(stream, b'close') is True
    with large.open('ab') as output:
        output.write(b'x')
    stream = service.open(str(large).encode(), b'rb')
    assert call(stream, b'seek', b'end') == MAX_FILE + 1
    assert call(stream, b'seek', b'cur', -1) == MAX_FILE
    assert call(stream, b'read', 2) == b'x' and call(stream, b'close') is True
    assert failed(service.open(str(large).encode(), b'ab'))
    # A whole-file read remains allocation-bounded even though its read-only
    # stream can hash arbitrarily larger archives through small chunks.
    stream = service.open(str(large).encode(), b'rb')
    assert failed(call(stream, b'read', b'*a')) and call(stream, b'close') is True
    expected_hash = hashlib.sha256()
    with large.open('rb') as source:
        while chunk := source.read(65536):
            expected_hash.update(chunk)
    lua.globals()[b'm'] = lua.table_from({b'platform': service, b'file_io': files,
        b'cooperative': loadfile(str(ROOT / 'src/core/cooperative.lua').encode('ascii'))})
    provenance = loadfile(str(ROOT / 'src/presets/binding_provenance.lua').encode('ascii'))
    hash_file = lua.execute(b"""return function(service,digest,path,expected)
        local stream=assert(service.open(path,'rb'))
        local size=assert(stream:seek('end'));assert(stream:seek('set',0)==0)
        local reads,slices=0,0
        local thread=coroutine.create(function()
            return digest(function()
                reads=reads+1
                if reads%64==0 then coroutine.yield('slice') end
                return stream:read(65536)
            end,size)
        end)
        while coroutine.status(thread)~='dead' do
            local ok,value=coroutine.resume(thread);assert(ok,value)
            if coroutine.status(thread)=='dead' then assert(value==expected)
            else assert(value=='slice');slices=slices+1 end
        end
        assert(stream:close() and slices>1);return size,reads,slices
    end""")
    hashed_size, hash_reads, hash_slices = hash_file(service, provenance.digest, str(large).encode(),
                                                   expected_hash.hexdigest().encode())
    assert hashed_size == MAX_FILE + 1 and hash_reads == 1026 and hash_slices == 16

    # The >4GiB file is sparse: only marker bytes occupy storage, and every
    # read is tiny. Exact 64-bit positions never imply a whole-file allocation.
    wide_file = work / '\u5927\u304d\u3044 sparse archive.bin'
    cross_at, cross = 2 ** 32 - 7, b'crossing the 4GiB boundary'
    wide_size = 2 ** 32 + 123
    sparse_file(wide_file, wide_size, [(cross_at, cross), (wide_size - 7, b'ending!')])
    wide_path = str(wide_file).encode()
    stream = service.open(wide_path, b'rb')
    assert call(stream, b'seek', b'end') == wide_size
    assert call(stream, b'seek', b'set', cross_at) == cross_at
    assert call(stream, b'read', len(cross)) == cross
    assert call(stream, b'seek', b'cur', -len(cross)) == cross_at
    assert call(stream, b'seek', b'end', -7) == wide_size - 7
    assert call(stream, b'read', 8) == b'ending!'
    assert call(stream, b'seek', b'set', MAX_POSITION) == MAX_POSITION
    assert call(stream, b'read', 1) is None
    assert call(stream, b'seek', b'cur', -MAX_POSITION) == 0
    assert call(stream, b'close') is True
    for whence, offset in [(b'set', -1), (b'set', 2 ** 53), (b'end', MAX_POSITION),
                            (b'cur', float('nan')), (b'set', float('inf'))]:
        stream = service.open(wide_path, b'rb')
        assert failed(call(stream, b'seek', whence, offset))
        assert failed(call(stream, b'read', 1)) and call(stream, b'close') is True
    # A write beyond the native bound fails before publishing any extra byte.
    stream = service.open(empty, b'wb')
    assert call(stream, b'seek', b'set', MAX_FILE - 1) == MAX_FILE - 1
    assert failed(call(stream, b'write', b'xx'))
    assert call(stream, b'close') is True
    assert Path(empty.decode()).stat().st_size == 0
    stream = service.open(empty, b'wb')
    too_large = lua.eval(b'string.rep')(b'x', MAX_FILE + 1)
    assert failed(call(stream, b'write', too_large))
    del too_large
    assert call(stream, b'close') is True
    stream = service.open(empty, b'wb')
    oversized_arguments = lua.eval(b'string.rep')(b'x', MAX_FILE // 2 + 1)
    assert failed(call(stream, b'write', oversized_arguments, oversized_arguments))
    del oversized_arguments
    assert call(stream, b'close') is True and Path(empty.decode()).stat().st_size == 0

    # Actual portable DDS publication uses this provider for Unicode stream IO
    # and actual MoveFileEx replacement; the previous copy remains exact.
    lua.globals()[b'm'] = lua.table_from({b'platform': service, b'file_io': files,
        b'float_buffer': loadfile(str(ROOT / 'src/core/float_buffer.lua').encode('ascii'))})
    dds = loadfile(str(ROOT / 'src/core/dds.lua').encode('ascii'))
    buffer = lua.globals()[b'm'][b'float_buffer'].new(4)
    for index, value in enumerate([0.125, 0.25, 0.5, 1]):
        buffer[index] = value
    dds_path = str(work / '\u8272 \U0001f986.dds').encode()
    original = dds.encode(buffer, 1, 1)
    assert dds.write(dds_path, buffer, 1, 1) == dds_path
    buffer[0] = 0.75
    edited = dds.encode(buffer, 1, 1)
    assert dds.write(dds_path, buffer, 1, 1) == dds_path
    assert Path(dds_path.decode()).read_bytes() == edited
    assert Path(dds_path.decode() + '.previous').read_bytes() == original
    decoded, packed = dds.read(dds_path, 1, 1)
    assert decoded[0] == 0.75 and packed == edited
    assert not Path(dds_path.decode() + '.pending').exists()

    # Production direct_setup publishes its manifest with f:write(version,
    # rows,newline). This guards every argument through the actual native API.
    setup_paths = lua.table_from({b'settings': str(work / 'settings').encode(),
                                 b'presets': str(work / 'presets').encode()})
    assert service.mkdir(setup_paths[b'settings']) and service.mkdir(setup_paths[b'presets'])
    setup_model = lua.table_from({b'platform': service, b'file_io': files, b'dds': dds,
        b'float_buffer': lua.globals()[b'm'][b'float_buffer'],
        b'windows': loadfile(str(ROOT / 'src/platform/windows.lua').encode('ascii')).new(service)})
    setup = loadfile(str(ROOT / 'src/gear/direct_setup.lua').encode('ascii')).new(setup_model, setup_paths)
    lua.execute(b"""return function(model,paths,setup)
        local armor={width=23,height=1,data=model.float_buffer.new(92)}
        local pattern={width=3,height=1,data=model.float_buffer.new(12)}
        armor.data[0],armor.data[91],pattern.data[11]=-1.25,2.375,0.5
        local bindings={{save_key='0:1:0:0',texture=armor},{save_key='p:0:1:0:0',texture=pattern}}
        assert(setup.save(bindings,{})==2)
        local plan=setup.read()
        assert(plan['0:1:0:0'] and plan['p:0:1:0:0'],'Applied setup manifest body disappeared')
        local manifest=model.file_io.read(paths.settings..'/direct-applied.tsv',524288)
        assert(manifest:find('0:1:0:0\\t',1,true) and manifest:find('p:0:1:0:0\\t',1,true))
        for key,name in pairs(plan) do
            local wanted=key:sub(1,2)=='p:' and pattern or armor
            local data=model.dds.read(paths.presets..'/'..name,wanted.width,1)
            assert(model.float_buffer.bytes(data,wanted.width*4)==model.float_buffer.bytes(wanted.data,wanted.width*4))
        end
        armor.data[0]=0.25;assert(setup.save(bindings,{})==2)
        local latest=setup.read();assert(latest['0:1:0:0'] and latest['p:0:1:0:0'])
        assert(model.dds.read(paths.presets..'/'..latest['0:1:0:0'],23,1)[0]==0.25)
        setup.clear();assert(next(setup.read())==nil)
    end""")(setup_model, setup_paths, setup)

    stream = service.open(path, b'rb')
    assert service.close() is True
    assert failed(call(stream, b'read', 1)) and call(stream, b'close') is True
    service = module.new(options)
    stream = service.open(path, b'rb')
    stop = lua.eval(b'package.loadlib')(str(library).encode('ascii'), b'epic_lut_platform_close')
    stop()
    assert failed(call(stream, b'read', 1)) and call(stream, b'close') is True
    assert service.close() is True

    # Raw real-pipe framing checks native generation and malformed-request bounds,
    # which the production driver correctly prevents its callers from constructing.
    start = lua.eval(b'package.loadlib')(str(library).encode('ascii'), b'epic_lut_platform_open')
    invoke = lua.eval(b'package.loadlib')(str(library).encode('ascii'), b'epic_lut_platform')
    connect = lua.execute(b"""return function(callback, base)
        local output=assert(io.open(base..'-request','wb'));assert(output:setvbuf('no'))
        local input=assert(io.open(base..'-response','rb'));assert(input:setvbuf('no'))
        return {
            exchange=function(bytes)
                assert(output:write(bytes));assert(output:flush());callback()
                local h=assert(input:read(16));assert(#h==16)
                local a,b,c,d=h:byte(13,16);local size=a+b*256+c*65536+d*16777216
                assert(size<=1048576);local body=size>0 and assert(input:read(size)) or ''
                assert(#body==size);return h..body
            end,
            close=function()output:close();input:close()end
        }
    end""")
    start()
    pipe_base = rf'\\.\pipe\EpicLutPlatform-{os.getpid()}'.encode()
    client = connect(invoke, pipe_base)
    sequence = 0

    def exchange(operation, body=b'', expected=0):
        nonlocal sequence
        sequence += 1
        reply = client.exchange(b'ELP1' + struct.pack('<III', sequence, operation, len(body)) + body)
        magic, nonce, status, size = struct.unpack('<4sIII', reply[:16])
        assert (magic, nonce, status, len(reply)) == (b'ELR1', sequence, expected, 16 + size)
        return reply[16:]

    token = exchange(16, b'\0' + path)
    assert len(token) == 4
    exchange(17, token + struct.pack('<I', 1048577), 234)
    exchange(21, token, 6)
    token = exchange(16, b'\0' + path)
    exchange(19, token + struct.pack('<Ii', 3, 0), 13)
    exchange(21, token, 6)
    token = exchange(16, b'\0' + path)
    assert exchange(19, token + struct.pack('<Ii', 0, 3)) == struct.pack('<I', 3), 'Legacy seek19 receipt changed'
    exchange(21, token)
    for seek_payload, status in [(b'', 13), (struct.pack('<Iq', 3, 0), 13),
                            (struct.pack('<Iq', 0, -1), 223),
                            (struct.pack('<Iq', 0, 2 ** 53), 13),
                            (struct.pack('<Iq', 0, -2 ** 53), 13),
                            (struct.pack('<Iq', 0, 2 ** 63 - 1), 13),
                            (struct.pack('<Iq', 0, -2 ** 63), 13),
                            (struct.pack('<Iq', 2, MAX_POSITION), 223)]:
        token = exchange(16, b'\0' + wide_path)
        exchange(28, token + seek_payload, status)
        exchange(21, token, 6)
    token = exchange(16, b'\0' + wide_path)
    assert exchange(28, token + struct.pack('<Iq', 0, cross_at)) == struct.pack('<Q', cross_at)
    assert exchange(17, token + struct.pack('<I', len(cross))) == cross
    assert exchange(28, token + struct.pack('<Iq', 0, MAX_POSITION)) == struct.pack('<Q', MAX_POSITION)
    exchange(28, token + struct.pack('<Iq', 1, 1), 223)
    exchange(21, token, 6)
    token = exchange(16, b'\1' + empty)
    exchange(28, token + struct.pack('<Iq', 0, 2 ** 32), 223)
    exchange(21, token, 6)
    assert Path(empty.decode()).stat().st_size == 0
    token = exchange(16, b'\0' + path)
    exchange(17, token + b'x', 13)
    exchange(21, token, 6)
    exchange(16, b'\3' + path, 13)
    exchange(16, b'\0\xff', 1113)
    exchange(16, b'\0x\0y', 13)
    old_token = exchange(16, b'\0' + path)
    client.close();stop();start();client = connect(invoke, pipe_base)
    new_token = exchange(16, b'\0' + path)
    assert old_token != new_token
    exchange(17, old_token + struct.pack('<I', 1), 6)
    exchange(28, old_token + struct.pack('<Iq', 0, 0), 6)
    assert exchange(17, new_token + struct.pack('<I', 3)) == payload[:3]
    exchange(21, new_token)
    client.close();stop()
    # Service cleanup must release sharing locks for the actual OS as well.
    with name.open('ab') as output:
        output.write(b'closed')
    print('PASS real Lua5.1 Unicode streams: 2MiB+ binary exactness, core F.read/write, '
          '64MiB allocation/write cap, >64MiB streamed SHA256, sparse >4GiB seek/read, '
          'exact positions to2^53-1, seek19 compatibility, seek28 malformed/overflow/stale cleanup, '
          'seek/append, private eight-handle/generation budget, '
          'malformed/permission/error/transport cleanup, files-only remove/nonoverwriting rename, '
          'variadic/finite-number write parity with stock IO, pre-write argument/budget rejection, '
          'actual DDS publication and production direct_setup save/read/replace roundtrip')
    print('Standalone 2MiB+ production F.write/read milliseconds:', round(write_ms, 3), round(read_ms, 3))


def main():
    receipt = json.loads((ROOT / 'dist/native-lua51-platform/build.json').read_text())
    with tempfile.TemporaryDirectory(prefix='epic-unicode-streams-') as directory:
        root = Path(directory).resolve()
        assert root.parent == Path(tempfile.gettempdir()).resolve() and root.name.startswith('epic-unicode-streams-')
        library = root / Path(receipt['dll']).name
        shutil.copyfile(receipt['dll'], library)
        result = subprocess.run([sys.executable, str(Path(__file__).resolve()), '--worker', str(root), str(library)],
                                capture_output=True, text=True, timeout=45)
        print(result.stdout, end='');print(result.stderr, end='', file=sys.stderr)
        assert result.returncode == 0, 'Unicode stream test failed or exceeded its deadline'
        assert root.parent == Path(tempfile.gettempdir()).resolve() and root.name.startswith('epic-unicode-streams-')


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--worker':
        worker(sys.argv[2], sys.argv[3])
    else:
        main()
