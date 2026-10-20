"""Real BCrypt SHA256 through production Lua5.1 driver and provenance dispatch.
Private test DLL/pipes only; independent hashlib oracle; no game/clipboard/UI.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import time

from lupa.lua51 import LuaError, LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def worker(directory, library):
    receipt = json.loads((ROOT / 'dist/native-lua51-platform/build.json').read_text())
    assert hashlib.sha256(Path(library).read_bytes()).hexdigest() == receipt['sha256']
    assert hashlib.sha256((ROOT / 'native/lua51_platform.c').read_bytes()).hexdigest() == receipt['source_sha256']
    lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
    lua.execute(b"""assert(_VERSION=='Lua 5.1');ffi,bit,jit=nil,nil,nil
        for _,name in ipairs({'ffi','bit','jit'}) do
            package.loaded[name]=nil;package.preload[name]=function()error('Unexpected native Lua dependency')end
        end
    """)
    dofile = lua.eval(b'dofile')
    module = dofile(str(ROOT / 'src/platform/native_platform.lua').encode('ascii'))
    options = lua.table_from({b'library': str(library).encode('ascii'), b'process_id': os.getpid()})
    service = module.new(options)
    cooperative = dofile(str(ROOT / 'src/core/cooperative.lua').encode('ascii'))
    lua.globals()[b'm'] = lua.table_from({b'platform': service, b'cooperative': cooperative})
    provenance = dofile(str(ROOT / 'src/presets/binding_provenance.lua').encode('ascii'))
    reader = lua.eval(b"""function(bytes,size,receipt)
        local at=1
        return function()
            receipt.calls=receipt.calls+1
            if at>#bytes then receipt.eof=true;return nil end
            local chunk=bytes:sub(at,at+size-1);at=at+#chunk;return chunk
        end
    end""")
    samples = [b'', b'abc', b'\0\xff\r\n\x1a', bytes(range(256)) * 256,
               bytes(range(256)) * 256 + b'boundary', b'Q' * (8 * 1024 * 1024)]
    started = time.perf_counter()
    for data in samples:
        expected = hashlib.sha256(data).hexdigest().encode()
        assert service.digest(data) == expected
        assert provenance.digest(data) == expected
        for size in [1, 65536] if len(data) < 100 else [65535, 65536]:
            box = lua.table_from({b'calls': 0})
            assert provenance.digest(reader(data, size, box), len(data)) == expected
            assert box[b'eof'] and box[b'calls'] == (len(data) + size - 1) // size + 1
    vector_ms = (time.perf_counter() - started) * 1000

    def fails(callback, *args, contains=None):
        try:
            callback(*args)
        except LuaError as error:
            assert contains is None or contains in str(error), str(error)
        else:
            raise AssertionError('Digest failure was silently accepted')

    for bad in [b'X' * (8 * 1024 * 1024 + 1), lua.table()]:
        fails(service.digest, bad)
    for expected in [-1, 0.5, float('nan'), 9007199254740992]:
        fails(service.digest, reader(b'abc', 3, lua.table_from({b'calls': 0})), expected)
    for factory in [b"function()return ''end", b"function()return false end",
                    b"function()return string.rep('x',65537)end", b"function()error('reader failed')end"]:
        for _ in range(9):
            fails(service.digest, lua.eval(factory))
    for expected in [2, 4]:
        fails(service.digest, reader(b'abc', 3, lua.table_from({b'calls': 0})), expected)
    assert service.digest(b'After failed readers') == hashlib.sha256(b'After failed readers').hexdigest().encode()

    # Production provenance -> provider -> actual BCrypt remains yield-safe in
    # stock Lua 5.1, and consumes the final nil after the advertised byte count.
    staged = lua.execute(b"""return function(digest,bytes,expected)
        local at,calls,slices=1,0,0
        local thread=coroutine.create(function()
            return digest(function()
                calls=calls+1;coroutine.yield('slice')
                if at>#bytes then return nil end
                local chunk=bytes:sub(at,at+65535);at=at+#chunk;return chunk
            end,#bytes)
        end)
        while coroutine.status(thread)~='dead' do
            local ok,value=coroutine.resume(thread);assert(ok,value)
            if coroutine.status(thread)=='dead' then assert(value==expected)
            else assert(value=='slice');slices=slices+1 end
        end
        assert(calls==slices and slices>=2);return slices
    end""")
    staged_bytes = bytes(range(256)) * 513
    slices = staged(provenance.digest, staged_bytes, hashlib.sha256(staged_bytes).hexdigest().encode())
    cancel = lua.execute(b"""return function(service)
        local thread=coroutine.create(function()
            return service.digest(function()coroutine.yield('pending');return 'abc'end,3)
        end)
        local ok,value=coroutine.resume(thread);assert(ok and value=='pending')
        assert(service.cancel_digest(thread)==1 and service.cancel_digest(thread)==0)
        ok,value=coroutine.resume(thread);assert(not ok and tostring(value):find('cancelled'))
        -- Abandoned jobs are weakly owned and reaped only on the next explicit
        -- digest. No timer, scan, or work is scheduled while the service is idle.
        local abandoned={}
        for i=1,8 do
            abandoned[i]=coroutine.create(function()
                return service.digest(function()coroutine.yield('abandoned');return 'x'end,1)
            end)
            ok,value=coroutine.resume(abandoned[i]);assert(ok and value=='abandoned')
        end
        abandoned=nil;collectgarbage('collect');collectgarbage('collect')
        assert(#service.digest('reaped')==64)
        local suspended=coroutine.create(function()
            return service.digest(function()coroutine.yield('shutdown');return 'x'end,1)
        end)
        ok,value=coroutine.resume(suspended);assert(ok and value=='shutdown')
        assert(service.close());ok,value=coroutine.resume(suspended)
        assert(not ok and tostring(value):find('cancelled'))
        return true
    end""")
    assert cancel(service) is True
    service = module.new(options)
    assert service.digest(b'Reopened crypto') == hashlib.sha256(b'Reopened crypto').hexdigest().encode()
    assert service.close()

    # Raw framing tests independent native limits, stale token retirement, and
    # malformed messages that the production Lua facade refuses to construct.
    load = lua.eval(b'package.loadlib')
    start = load(str(library).encode('ascii'), b'epic_lut_platform_open')
    invoke = load(str(library).encode('ascii'), b'epic_lut_platform')
    stop = load(str(library).encode('ascii'), b'epic_lut_platform_close')
    base = rf'\\.\pipe\EpicLutPlatform-{os.getpid()}'
    start()
    output, incoming = open(base + '-request', 'wb', buffering=0), open(base + '-response', 'rb', buffering=0)
    sequence = 0

    def exchange(op, payload=b'', status=0):
        nonlocal sequence
        sequence += 1
        output.write(b'ELP1' + struct.pack('<III', sequence, op, len(payload)) + payload)
        invoke()
        header = incoming.read(16)
        magic, nonce, result, size = struct.unpack('<4sIII', header)
        assert (magic, nonce, result) == (b'ELR1', sequence, status), (op, result, status)
        assert size <= 1048576
        body = incoming.read(size) if size else b''
        assert len(body) == size
        return body

    begin = lambda exact: bytes([exact is not None]) + struct.pack('<Q', exact or 0)
    tokens = [exchange(22, begin(None)) for _ in range(8)]
    exchange(22, begin(None), 4)
    for token in tokens:
        exchange(25, token);exchange(24, token, 6)
    token = exchange(22, begin(3));exchange(23, token + b'abc')
    assert exchange(24, token) == hashlib.sha256(b'abc').hexdigest().encode()
    exchange(24, token, 6)
    for bad, status in [(b'', 13), (begin(9007199254740992), 13), (b'\2' + b'\0' * 8, 13),
                        (b'\0' + struct.pack('<Q', 1), 13)]:
        exchange(22, bad, status)
    for payload, status in [(b'', 13), (b'x' * 65537, 13), (b'abcd', 223)]:
        token = exchange(22, begin(3));exchange(23, token + payload, status);exchange(25, token, 6)
    token = exchange(22, begin(3));exchange(23, token + b'ab');exchange(24, token, 13);exchange(25, token, 6)
    token = exchange(22, begin(0))
    assert exchange(24, token) == hashlib.sha256(b'').hexdigest().encode()
    old = exchange(22, begin(None))
    output.close();incoming.close();stop();start()
    output, incoming = open(base + '-request', 'wb', buffering=0), open(base + '-response', 'rb', buffering=0)
    new = exchange(22, begin(None));assert new != old
    exchange(24, old, 6);exchange(25, new)
    output.close();incoming.close();stop()
    print('PASS real BCrypt + Lua5.1 digest: independent hashlib vectors through actual provenance, '
          '8MiB strings, bounded readers/EOF, yielding reader slices=' + str(slices) + ', explicit cancellation, '
          'weak abandoned-job reap, eight-state/native generation/bounds/malformed cleanup, close/reopen')
    print('Standalone independent-vector workload milliseconds:', round(vector_ms, 3))


def main():
    receipt = json.loads((ROOT / 'dist/native-lua51-platform/build.json').read_text())
    with tempfile.TemporaryDirectory(prefix='epic-bcrypt-digest-') as directory:
        root = Path(directory).resolve()
        assert root.parent == Path(tempfile.gettempdir()).resolve() and root.name.startswith('epic-bcrypt-digest-')
        library = root / Path(receipt['dll']).name
        shutil.copyfile(receipt['dll'], library)
        result = subprocess.run([sys.executable, str(Path(__file__).resolve()), '--worker', str(root), str(library)],
                                capture_output=True, text=True, timeout=45)
        print(result.stdout, end='');print(result.stderr, end='', file=sys.stderr)
        assert result.returncode == 0, 'Digest test failed or exceeded its deadline'
        assert root.parent == Path(tempfile.gettempdir()).resolve() and root.name.startswith('epic-bcrypt-digest-')


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--worker':
        worker(sys.argv[2], sys.argv[3])
    else:
        main()
