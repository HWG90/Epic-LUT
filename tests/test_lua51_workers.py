"""Owned, hidden PowerShell workers via the real stock-Lua platform driver.

Only test-created scripts/files and child processes are used. No game process,
clipboard, Explorer, UI dialog, debugger or installation is involved.
"""
from pathlib import Path
import hashlib
import json
import os
import shutil
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
    lua.execute(b"assert(_VERSION=='Lua 5.1');ffi,bit,jit=nil,nil,nil")
    module = lua.execute((ROOT / 'src/platform/native_platform.lua').read_bytes())
    service = module.new(lua.table_from({b'library':str(library).encode(), b'process_id':os.getpid()}))
    assert service.process_id() == os.getpid()
    assert Path(service.executable_path().decode()) == Path(sys.executable)
    script = root / 'owned-worker.ps1'
    script.write_text('param([string]$Output,[int]$Delay=0,[int]$Hold=0)\n'
        'if($Delay){Start-Sleep -Milliseconds $Delay}\n'
        '[System.IO.File]::WriteAllText($Output,[string]$PID)\n'
        'if($Hold){Start-Sleep -Seconds $Hold}\n', encoding='utf8')
    live = []

    def launch(name, delay=0, hold=0):
        target = root / name
        args = ('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+str(script)
            +'" -Output "'+str(target)+'" -Delay '+str(delay)+' -Hold '+str(hold))
        process = service.launch_worker(args.encode('utf8'), str(root).encode('utf8'))
        live.append(process)
        assert process.pid > 0 and process.pid != os.getpid()
        return process, target

    def until(predicate, why):
        deadline = time.monotonic()+12
        while not predicate():
            assert time.monotonic() < deadline, why
            time.sleep(0.025)

    try:
        try:
            service.launch_worker(b'bad\x00arguments', str(root).encode())
            raise AssertionError('NUL worker arguments accepted')
        except LuaError:
            pass
        one, first = launch('first.txt', hold=10)
        two, second = launch('second.txt', hold=10)
        until(lambda:first.exists() and second.exists(), 'Owned workers did not start')
        assert int(first.read_text()) == one.pid and int(second.read_text()) == two.pid
        assert one.running() is True and two.running() is True
        assert one.stop() is True
        until(lambda:not one.running(), 'Stopped worker remained alive')
        assert two.running() is True, 'Stopping one worker affected another owner'
        assert one.close() is True and one.close() is True
        assert one.running() is False and one.stop() is True
        assert two.stop() is True
        until(lambda:not two.running(), 'Second worker did not stop')
        assert two.close() is True
        detached, marker = launch('closed-but-running.txt', delay=500)
        assert detached.close() is True
        until(marker.exists, 'close() terminated a running worker')
        assert int(marker.read_text()) == detached.pid
        finished, marker = launch('finished.txt')
        until(lambda:marker.exists() and not finished.running(), 'Natural completion failed')
        assert finished.stop() is True and finished.close() is True
    finally:
        for process in live:
            try:
                process.stop()
                process.close()
            except LuaError:
                pass
        service.close()
    print('PASS real Lua5.1 workers: executable identity, hidden system PowerShell, owned tokens, '
        'isolated stop, natural completion, close without termination, idempotent cleanup')


if __name__ == '__main__':
    if len(sys.argv) == 4 and sys.argv[1] == '--worker':
        worker(sys.argv[2], sys.argv[3])
    else:
        receipt = json.loads((ROOT / 'dist/native-lua51-platform/build.json').read_text())
        with tempfile.TemporaryDirectory(prefix='epic-lua51-workers-') as folder:
            library = Path(folder) / Path(receipt['dll']).name
            shutil.copyfile(receipt['dll'], library)
            run = subprocess.run([sys.executable, __file__, '--worker', folder, str(library)],
                capture_output=True, text=True, timeout=45)
            print(run.stdout, end='')
            print(run.stderr, end='', file=sys.stderr)
            raise SystemExit(run.returncode)
