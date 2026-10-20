"""Actual production driver + real Lua 5.1/loadlib DLL; private temp files only.

No clipboard, ShellExecute, game API, or FFI calls. A child deadline bounds pipe
deadlocks. Two explicit response faults exercise constructor cleanup while all
native callbacks and underlying Lua file streams remain real.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import sys
import tempfile
import time

from lupa.lua51 import LuaError, LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def worker(directory, library):
    root = Path(directory)
    receipt = json.loads((ROOT / 'dist/native-lua51-platform/build.json').read_text())
    assert hashlib.sha256(Path(library).read_bytes()).hexdigest() == receipt['sha256']
    assert hashlib.sha256((ROOT / 'native/lua51_platform.c').read_bytes()).hexdigest() == receipt['source_sha256']
    lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
    lua.execute(b"""assert(_VERSION == 'Lua 5.1')
        ffi, bit, jit = nil, nil, nil
        for _, name in ipairs({'ffi', 'bit', 'jit'}) do
            package.loaded[name] = nil
            package.preload[name] = function() error('Unexpected native Lua dependency') end
        end
    """)
    module_path = str(ROOT / 'src/platform/native_platform.lua').encode('ascii')
    module = lua.eval(b'dofile')(module_path)
    options = lua.table_from({b'library': str(library).encode('ascii'), b'process_id': os.getpid()})

    def expected_error(callback, *args, contains=None):
        try:
            callback(*args)
        except LuaError as error:
            assert contains is None or contains in str(error), str(error)
        else:
            raise AssertionError('Expected production-driver error')

    # Real setup failure must release the native servers and the Lua owner token.
    wrong_pid = lua.table_from({b'library': str(library).encode('ascii'), b'process_id': 1})
    expected_error(module.new, wrong_pid)
    service = module.new(options)
    assert service.validate_utf8(b'First successful connection') == b'First successful connection'
    # Reject before native open, including from a freshly loaded module. The
    # original connection remains usable rather than having its handles reset.
    expected_error(module.new, options, contains='already open')
    reloaded = lua.eval(b'dofile')(module_path)
    expected_error(reloaded.new, wrong_pid, contains='already open')
    assert service.validate_utf8(b'Connection preserved') == b'Connection preserved'

    work = root / '\u8863\u88c5 \U0001f986'
    encoded = str(work).encode('utf8')
    assert service.stat(encoded) is None
    assert service.directory_exists(encoded) is False
    assert service.mkdir(encoded) is True and service.mkdir(encoded) is True
    assert service.directory_exists(encoded) is True
    assert service.stat(encoded)[b'directory'] is True
    expected_error(service.mkdir_new, encoded, contains='(183)')
    exclusive = str(work / 'exclusive').encode('utf8')
    assert service.mkdir_new(exclusive) is True
    assert service.rmdir(exclusive) == (True, None)

    files = ['B.DDS', 'a.dds', 'slot[1]+(p)-^$.dds', 'helmet \u65e5\u672c\u8a9e.txt']
    for name in files:
        (work / name).write_bytes(b'palette')
    (work / 'capes').mkdir()
    metadata = service.stat(str(work / files[0]).encode('utf8'))
    assert metadata[b'directory'] is False
    assert int(metadata[b'size_hex'], 16) == 7 and len(metadata[b'stamp']) == 16
    listed, directories = service.files(encoded)
    assert list(listed.values()) == sorted(name.encode('utf8') for name in files)
    assert list(directories.values()) == [b'capes']
    listed, directories = service.files(encoded, b'*.dds')
    assert list(listed.values()) == [b'B.DDS', b'a.dds', b'slot[1]+(p)-^$.dds']
    assert list(directories.values()) == []
    listed, _ = service.files(encoded, b'?.DDS')
    assert list(listed.values()) == [b'B.DDS', b'a.dds']
    listed, _ = service.files(encoded, b'slot[1]+(p)-^$.dds')
    assert list(listed.values()) == [b'slot[1]+(p)-^$.dds']
    expected_error(service.files, str(work / 'missing').encode('utf8'), b'bad/path', contains='Invalid file pattern')
    expected_error(service.mkdir, str(work / 'B.DDS').encode('utf8'), contains='(183)')
    removed, why = service.rmdir(encoded)
    assert removed is False and b'(145)' in why

    source, destination = work / 'new \u8272.dds', work / 'existing.dds'
    source.write_bytes(b'new palette')
    destination.write_bytes(b'old palette')
    assert service.replace(str(source).encode('utf8'), str(destination).encode('utf8')) is True
    assert not source.exists() and destination.read_bytes() == b'new palette'
    for text in [b'', b'ASCII', '\u65e5\u672c\u8a9e / \u0394 / \U0001f986'.encode(), b'Q' * 32768]:
        assert service.validate_utf8(text) == text
    expected_error(service.validate_utf8, b'x\0y', contains='Invalid UTF-8 text bounds')
    expected_error(service.validate_utf8, b'Q' * 32769, contains='Invalid UTF-8 text bounds')
    expected_error(service.validate_utf8, b'\xc0\xaf', contains='(1113)')
    expected_error(service.stat, b'x\0y', contains='Invalid Windows path')
    assert service.validate_utf8(b'Operation errors preserve connection') == b'Operation errors preserve connection'

    timings = {}
    for name, callback, argument in [('UTF8', service.validate_utf8, b'Production driver'),
                                     ('stat', service.stat, str(destination).encode('utf8'))]:
        samples = []
        for _ in range(100):
            started = time.perf_counter()
            callback(argument)
            samples.append((time.perf_counter() - started) * 1000)
        timings[name] = {'median_ms': round(statistics.median(samples), 3),
                         'p95_ms': round(sorted(samples)[94], 3), 'max_ms': round(max(samples), 3)}
    assert service.close() is True and service.close() is True
    expected_error(service.stat, encoded, contains='service is closed')
    service = reloaded.new(options)
    assert service.validate_utf8(b'Reopened') == b'Reopened'

    # Actual server loss must produce a bounded error, close the driver, and
    # permit a clean new connection rather than retaining a poisoned stream.
    stop = lua.eval(b'package.loadlib')(str(library).encode('ascii'), b'epic_lut_platform_close')
    assert stop() is None
    expected_error(service.stat, encoded)
    expected_error(service.stat, encoded, contains='service is closed')
    assert service.close() is True
    service = module.new(options)
    assert service.validate_utf8(b'Recovered after transport failure') == b'Recovered after transport failure'
    assert service.close() is True

    # Keep real DLL callbacks/pipe handles, perturb only the received version or
    # status at the explicit test seam, and verify both actual streams close.
    reject_handshake = lua.execute(b"""return function(module, options, mode)
        local original_open = io.open
        local opened, closed = 0, 0
        io.open = function(name, access)
            local stream, why = original_open(name, access)
            if not stream then return stream, why end
            opened = opened + 1
            local proxy = {}
            for _, method in ipairs({'read', 'write', 'flush', 'setvbuf'}) do
                local method_name = method
                proxy[method_name] = function(_, ...)
                    local value = stream[method_name](stream, ...)
                    if access == 'rb' and method_name == 'read' then
                        if mode == 'version' and value == '1' then return '2' end
                        if mode == 'status' and type(value) == 'string' and #value == 16 then
                            return value:sub(1, 8) .. string.char(50, 0, 0, 0) .. value:sub(13)
                        end
                    end
                    return value
                end
            end
            proxy.close = function() closed = closed + 1; return stream:close() end
            return proxy
        end
        local ok, why = pcall(module.new, options)
        io.open = original_open
        assert(not ok and opened == 2 and closed == 2, 'Failed handshake retained real streams')
        assert(tostring(why):find(mode == 'version' and 'Unsupported Windows platform service version'
            or 'Windows platform operation 0 failed', 1, true), tostring(why))
        local service = module.new(options)
        assert(service.validate_utf8('Handshake cleanup complete') == 'Handshake cleanup complete')
        assert(service.close())
        return true
    end""")
    assert reject_handshake(module, options, b'version') is True
    assert reject_handshake(module, options, b'status') is True
    assert not list(root.glob('*request.bin')) and not list(root.glob('*response.bin'))
    print('PASS production native_platform.lua: real stock Lua5.1/DLL; Unicode fs/UTF8, filters, '
          'duplicate/reloaded owner protection, failed setup, version/status cleanup, transport loss, close/reopen; '
          'no clipboard/ShellExecute/game calls')
    print('Production-driver standalone latency:', timings)


def main():
    receipt = json.loads((ROOT / 'dist/native-lua51-platform/build.json').read_text())
    with tempfile.TemporaryDirectory(prefix='epic-platform-driver-') as temporary:
        root = Path(temporary).resolve()
        assert root.parent == Path(tempfile.gettempdir()).resolve() and root.name.startswith('epic-platform-driver-')
        library = root / Path(receipt['dll']).name
        shutil.copyfile(receipt['dll'], library)
        completed = subprocess.run([sys.executable, str(Path(__file__).resolve()), '--worker', str(root), str(library)],
                                   capture_output=True, text=True, timeout=30)
        print(completed.stdout, end='')
        print(completed.stderr, end='', file=sys.stderr)
        assert completed.returncode == 0, 'Production driver failed or exceeded its deadline'
        assert root.parent == Path(tempfile.gettempdir()).resolve() and root.name.startswith('epic-platform-driver-')


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--worker':
        worker(sys.argv[2], sys.argv[3])
    else:
        main()
