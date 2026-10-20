"""Real external EXE + stock Lua5.1 stdlib launch/pipe tests, private Temp only.

No game, DLL load, clipboard mutation, UI dialog, installation, or policy change.
Child deadlines bound failures. Test-only stalled operations are a separate build.
"""
import base64
import ctypes
from ctypes import wintypes as W
import hashlib
import json
import os
from pathlib import Path
import shutil
import statistics
import struct
import subprocess
import sys
import tempfile
import time

from lupa.lua51 import LuaError, LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
K = ctypes.WinDLL('kernel32', use_last_error=True)
K.OpenProcess.argtypes = [W.DWORD, W.BOOL, W.DWORD]; K.OpenProcess.restype = W.HANDLE
K.CloseHandle.argtypes = [W.HANDLE]
K.WaitForSingleObject.argtypes = [W.HANDLE, W.DWORD]
K.TerminateProcess.argtypes = [W.HANDLE, W.UINT]
K.GetProcessTimes.argtypes = [W.HANDLE] + [ctypes.POINTER(W.FILETIME)] * 4
K.GetProcessHandleCount.argtypes = [W.HANDLE, ctypes.POINTER(W.DWORD)]
class ProcessEntry(ctypes.Structure):
    _fields_=[('dwSize',W.DWORD),('cntUsage',W.DWORD),('pid',W.DWORD),('heap',ctypes.c_size_t),
        ('module',W.DWORD),('threads',W.DWORD),('parent',W.DWORD),('priority',W.LONG),('flags',W.DWORD),('exe',W.WCHAR*260)]
K.CreateToolhelp32Snapshot.argtypes=[W.DWORD,W.DWORD];K.CreateToolhelp32Snapshot.restype=W.HANDLE
K.Process32FirstW.argtypes=[W.HANDLE,ctypes.POINTER(ProcessEntry)]
K.Process32NextW.argtypes=[W.HANDLE,ctypes.POINTER(ProcessEntry)]


def children(parent):
    snapshot=K.CreateToolhelp32Snapshot(2,0)
    assert snapshot and snapshot!=ctypes.c_void_p(-1).value
    item=ProcessEntry();item.dwSize=ctypes.sizeof(item);result=[]
    try:
        valid=K.Process32FirstW(snapshot,ctypes.byref(item))
        while valid:
            if item.parent==parent:result.append(item.pid)
            valid=K.Process32NextW(snapshot,ctypes.byref(item))
    finally:K.CloseHandle(snapshot)
    return result


def process(pid):
    handle = K.OpenProcess(0x100000 | 0x1000 | 1, False, pid)
    assert handle, ('OpenProcess', pid, ctypes.get_last_error())
    return handle


def cpu(handle):
    values = [W.FILETIME() for _ in range(4)]
    assert K.GetProcessTimes(handle, *(ctypes.byref(v) for v in values))
    return sum((v.dwHighDateTime << 32) + v.dwLowDateTime for v in values[2:]) / 10_000_000


def handles(handle):
    count = W.DWORD(); assert K.GetProcessHandleCount(handle, ctypes.byref(count)); return count.value


def error(callback, *args, text=None):
    try:
        callback(*args)
    except LuaError as exc:
        assert text is None or text in str(exc), str(exc)
        return
    raise AssertionError('Expected rejection')


def runtime():
    lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
    lua.execute(b"assert(_VERSION=='Lua 5.1');ffi,bit,jit=nil,nil,nil; package.loadlib=function()error('No DLL loading permitted')end")
    module = lua.execute((ROOT / 'src/platform/native_platform.lua').read_bytes())
    transport = lua.execute((ROOT / 'src/platform/external_platform.lua').read_bytes())
    return lua, module, transport


def opts(lua, executable, digest, pid=None):
    return lua.table_from({b'backend': b'external', b'service': str(executable).encode('utf8'),
        b'sha256': digest.encode(), b'process_id': pid or os.getpid()})


def until(predicate, reason, limit=10):
    end = time.monotonic() + limit
    while not predicate():
        assert time.monotonic() < end, reason
        time.sleep(0.02)


def worker(folder, executable, digest, blocked):
    root = Path(folder)
    lua, module, transport = runtime()
    options = opts(lua, executable, digest)
    malformed=lua.execute(b"""return function(provider,options,pid,line)
        local old_open,old_popen=io.open,io.popen
        local opened,closed=0,0
        io.open=function(...)opened=opened+1;error('Malformed receipt opened pipe')end
        io.popen=function()return {read=function()return line end,close=function()closed=closed+1 end}end
        local ok,why=pcall(provider.start,options,pid)
        io.open,io.popen=old_open,old_popen
        assert(not ok and opened==0 and closed==1,tostring(why))
        return true
    end""")
    for image in [b'a',b'00',b'61',b'aa'*131065]:
        assert malformed(transport,options,os.getpid(),b'ELX1 '+str(os.getpid()).encode()+b' 1234 '+b'a'*64+b' '+image)
    command = transport.command(options, os.getpid())
    script = base64.b64decode(command.split(b' -EncodedCommand ')[1]).decode('utf-16-le')
    assert str(executable).replace("'", "''") in script
    assert 'ExecutionPolicy' not in script and 'Add-Type' not in script
    # One-pass placeholders must never rewrite strings inside a real path.
    weird = root / "SERVICE HASH CLIENT @{HASH} David's \u8863\u88c5 \U0001f986" / Path(executable).name
    weird.parent.mkdir(); shutil.copyfile(executable, weird)
    weird_options = opts(lua, weird, digest)
    encoded = transport.command(weird_options, os.getpid())
    decoded = base64.b64decode(encoded.split(b' -EncodedCommand ')[1]).decode('utf-16-le')
    assert str(weird).replace("'", "''") in decoded
    error(transport.command, opts(lua, 'C:/' + 'x' * 20000 + '.exe', digest), os.getpid(), text='command-line limit')
    error(module.new, opts(lua, executable, '0' * 64), text='hash differs')
    started = time.perf_counter(); service = module.new(weird_options); startup_ms = (time.perf_counter() - started) * 1000
    assert service.process_id() == os.getpid()
    assert Path(service.executable_path().decode('utf8')) == Path(sys.executable)
    error(module.new, options, text='already open')
    assert service.validate_utf8(b'Owner retained') == b'Owner retained'
    payload = b'abc\0\xff' * 420000
    path = str(root / '\u6b66\u5668 \U0001f986.dds').encode('utf8')
    stream = service.open(path, b'wb')
    assert lua.eval(b'function(s,a,b)return assert(s:write(a,b,123))==s end')(stream,payload[:1_000_000],payload[1_000_000:])
    assert stream.flush(stream) is True and stream.close(stream) is True
    stream = service.open(path, b'rb')
    assert stream.read(stream, b'*a') == payload + b'123'
    assert stream.seek(stream, b'set', 0) == 0
    reader=lua.eval(b'function(s)return function()return s:read(65536)end end')(stream)
    assert service.digest(reader, len(payload) + 3) == hashlib.sha256(payload + b'123').hexdigest().encode()
    assert stream.close(stream) is True
    assert service.digest(b'hello') == hashlib.sha256(b'hello').hexdigest().encode()
    replacement = root / '\u65b0.dds'; replacement.write_bytes(b'new')
    assert service.replace(str(replacement).encode('utf8'), path) is True
    assert Path(path.decode('utf8')).read_bytes() == b'new'
    exclusive = str(root / 'exclusive').encode()
    assert service.mkdir_new(exclusive) is True
    error(service.mkdir_new, exclusive, text='(183)')
    assert service.rmdir(exclusive) == (True, None)
    assert service.close() is True and service.close() is True
    # No foreign PID or image can authorize this process's pipe connection.
    foreign = subprocess.run([sys.executable, __file__, '--foreign', str(executable), digest, str(os.getpid())],
        capture_output=True, text=True, timeout=15, creationflags=subprocess.CREATE_NO_WINDOW)
    assert foreign.returncode == 0, foreign.stdout + foreign.stderr
    bad_image = subprocess.run([str(executable), '--client', str(os.getpid()), '--token', 'a'*64,
        '--image', (str(sys.executable)+'wrong').encode('utf8').hex()], timeout=5, creationflags=subprocess.CREATE_NO_WINDOW)
    assert bad_image.returncode == 5

    # Raw transport still uses real Lua-created pipe streams. It allows exact
    # framing faults/fragmentation independent of the production encoder.
    channel = transport.start(options, os.getpid())
    server_handle = process(channel.server_pid)
    send = lua.eval(b"function(c,b)assert(c.request:write(b));assert(c.request:flush())end")
    read = lua.eval(b"function(c,n)return c.response:read(n)end")
    close = lua.eval(b"function(c)c.request:close();c.response:close()end")

    def request(op, data=b'', nonce=1, split=False):
        packet = b'ELP1' + struct.pack('<III', nonce, op, len(data)) + data
        if split:
            send(channel, packet[:5]); time.sleep(0.015)
            send(channel, packet[5:16]); time.sleep(0.015)
            for at in range(16, len(packet), 4096): send(channel, packet[at:at+4096])
        else: send(channel, packet)
        header = read(channel, 16)
        if header is None: return None
        assert header[:4] == b'ELR1'
        identity, status, count = struct.unpack_from('<III', header, 4)
        assert identity == nonce and count <= 1048576
        return status, read(channel, count) if count else b''

    identity = channel.token + struct.pack('<II', os.getpid(), channel.server_pid)
    assert request(29, identity) == (0, struct.pack('<II', os.getpid(), channel.server_pid) + str(sys.executable).encode('utf8'))
    full = b'A' * 1048576
    assert request(1, full, 2, split=True) == (0, full)
    samples = []
    for index in range(30):
        start = time.perf_counter(); assert request(1, b'IPC', index+3) == (0, b'IPC'); samples.append((time.perf_counter()-start)*1000)
    before_cpu = cpu(server_handle); before_handles = handles(server_handle); time.sleep(0.35)
    idle_cpu = cpu(server_handle) - before_cpu
    assert idle_cpu < 0.03, 'External helper did CPU work while idle'
    assert handles(server_handle) == before_handles
    # A stalled partial frame is retired by a native transfer deadline.
    send(channel, b'ELP1' + struct.pack('<III', 100, 1, 12) + b'partial')
    assert K.WaitForSingleObject(server_handle, 5000) == 0
    assert read(channel, 16) is None
    close(channel); K.CloseHandle(server_handle)

    # Wrong private token is denied before dispatching any OS operation.
    channel = transport.start(options, os.getpid()); server_handle = process(channel.server_pid)
    assert request(29, b'0'*64 + struct.pack('<II', os.getpid(), channel.server_pid))[0] == 5
    assert K.WaitForSingleObject(server_handle, 2000) == 0
    close(channel); K.CloseHandle(server_handle)

    # Actual server loss returns EOF and retires the driver's owner lease.
    service = module.new(options)
    operation_timings={}
    for name,callback in [('stat',lambda:service.stat(path)),('sha256_32k',lambda:service.digest(b'H'*32768))]:
        timings=[]
        for _ in range(15):
            start=time.perf_counter();callback();timings.append((time.perf_counter()-start)*1000)
        operation_timings[name]={'median_ms':round(statistics.median(timings),3),'max_ms':round(max(timings),3)}
    # Derive the uniquely owned service PID from its one active child, recorded
    # independently by Windows process-parent metadata, not a faked response.
    command = ['powershell.exe', '-NoLogo', '-NoProfile', '-NonInteractive', '-Command',
        "Get-CimInstance Win32_Process -Filter \"Name LIKE 'EpicLutLua51Service%'\" | Where-Object {$_.CommandLine -match '--client " + str(os.getpid()) + " --token'} | Select-Object -ExpandProperty ProcessId"]
    result = subprocess.run(command, capture_output=True, text=True, timeout=10, creationflags=subprocess.CREATE_NO_WINDOW)
    pids = [int(v) for v in result.stdout.split()]
    assert len(pids) == 1, result.stdout
    handle = process(pids[0]); assert K.TerminateProcess(handle, 77)
    assert K.WaitForSingleObject(handle, 2000) == 0; K.CloseHandle(handle)
    error(service.validate_utf8, b'Broken pipe')
    assert service.close() is True
    service = module.new(options)

    def launch(marker, delay=0, hold=0):
        script = "if("+str(delay)+"){Start-Sleep -Milliseconds "+str(delay)+"};[IO.File]::WriteAllText('"+str(marker).replace("'","''")+"',[string]$PID);if("+str(hold)+"){Start-Sleep -Seconds "+str(hold)+"}"
        args = '-NoLogo -NoProfile -NonInteractive -EncodedCommand ' + base64.b64encode(script.encode('utf-16-le')).decode()
        return service.launch_worker(args.encode(), str(root).encode('utf8')), args

    owned, _ = launch(root / 'owned.txt', hold=5)
    until((root/'owned.txt').exists, 'Owned worker not launched')
    assert owned.running() is True and owned.stop() is True
    until(lambda:not owned.running(), 'Owned worker did not stop')
    assert owned.close() is True
    detached, worker_args = launch(root / 'detached.txt', delay=500)
    assert detached.close() is True
    assert service.close() is True
    until((root/'detached.txt').exists, 'Service retirement killed a detached worker')
    assert int((root/'detached.txt').read_text()) == detached.pid

    # Compile-only injected stalled dispatch uses the exact production watchdog.
    injected = json.loads((Path(blocked) / 'build.json').read_text())
    block_options = opts(lua, injected['exe'], injected['sha256'])
    for operation in [249, 250, 251, 254, 30]:
        channel = transport.start(block_options, os.getpid()); server_handle = process(channel.server_pid)
        assert request(29, channel.token + struct.pack('<II', os.getpid(), channel.server_pid))[0] == 0
        data = b''
        if operation in [250,254]:
            marker = root / 'must-not-escape.txt'
            script = "Start-Sleep -Seconds 5;[IO.File]::WriteAllText('"+str(marker).replace("'","''")+"','leaked')"
            args = ('-NoLogo -NoProfile -NonInteractive -EncodedCommand ' + base64.b64encode(script.encode('utf-16-le')).decode()).encode()
            data = struct.pack('<I', len(args)) + args + str(root).encode('utf8')
        if operation == 251:data=str(root/'ambiguous-completed-effect').encode('utf8')
        if operation == 30:assert request(252,b'',2)==(0,b'')
        start = time.monotonic()
        if operation==254:
            send(channel,b'ELP1'+struct.pack('<III',3,operation,len(data))+data)
            until(lambda:bool(children(channel.server_pid)),'Suspended worker never appeared',limit=2)
            suspended=children(channel.server_pid);assert len(suspended)==1
            suspended_handle=process(suspended[0])
            assert read(channel,16) is None
            assert K.WaitForSingleObject(suspended_handle,2000)==0,'Atomic provisional job left a suspended child alive'
            K.CloseHandle(suspended_handle)
        else:assert request(operation, data, 3) is None
        assert K.WaitForSingleObject(server_handle, 1000) == 0 and time.monotonic()-start < 5
        close(channel); K.CloseHandle(server_handle)
    # A launched child whose receipt cannot be delivered remains provisional.
    channel=transport.start(block_options,os.getpid());server_handle=process(channel.server_pid)
    assert request(29,channel.token+struct.pack('<II',os.getpid(),channel.server_pid))[0]==0
    began,escaped=root/'unreported-started.txt',root/'unreported-escaped.txt'
    script="[IO.File]::WriteAllText('"+str(began).replace("'","''")+"','started');Start-Sleep -Seconds 3;[IO.File]::WriteAllText('"+str(escaped).replace("'","''")+"','escaped')"
    args=('-NoLogo -NoProfile -NonInteractive -EncodedCommand '+base64.b64encode(script.encode('utf-16-le')).decode()).encode()
    data=struct.pack('<I',len(args))+args+str(root).encode('utf8')
    send(channel,b'ELP1'+struct.pack('<III',2,253,len(data))+data)
    until(began.exists,'Unreported worker fixture did not actually start',limit=2)
    close(channel)
    assert K.WaitForSingleObject(server_handle,5000)==0;K.CloseHandle(server_handle)
    time.sleep(2)
    assert not (root/'must-not-escape.txt').exists(), 'Unacknowledged worker escaped timed-out ownership'
    assert not escaped.exists(),'Worker detached before its receipt was delivered'
    assert (root/'ambiguous-completed-effect').is_dir(), 'Fixture did not exercise an already completed effect'
    # A client that exits without close must release the actual owned service.
    owner_exit=subprocess.run([sys.executable,__file__,'--owner-exit',str(executable),digest],
        capture_output=True,text=True,timeout=15,creationflags=subprocess.CREATE_NO_WINDOW)
    assert owner_exit.returncode==0,owner_exit.stderr
    child_pid=int(owner_exit.stdout.strip())
    child_handle=K.OpenProcess(0x100000|0x1000,False,child_pid)
    if child_handle:
        assert K.WaitForSingleObject(child_handle,2000)==0,'Service survived actual client exit'
        K.CloseHandle(child_handle)
    timings = {'startup_ms': round(startup_ms, 3), 'ipc_median_ms': round(statistics.median(samples), 3),
        'ipc_max_ms': round(max(samples), 3), 'idle_cpu_seconds': idle_cpu,
        'operations':operation_timings,'game_performance_measured': False}
    print('PASS external stock Lua5.1: actual hidden launcher/EXE/pipes, exact identity, Unicode/binary IO, atomic replacement, '
        'SHA256, max/fragmented transfers, deadline/EOF/token faults, idle silence, isolated workers/detach, blocked dispatch and provisional-worker cleanup')
    print(json.dumps(timings, sort_keys=True))


if __name__ == '__main__':
    if len(sys.argv)==5 and sys.argv[1]=='--foreign':
        lua,module,_=runtime()
        error(module.new,opts(lua,sys.argv[2],sys.argv[3],int(sys.argv[4])))
        print('PASS foreign actual pipe-client PID denied')
    elif len(sys.argv)==4 and sys.argv[1]=='--owner-exit':
        lua,module,transport=runtime()
        lua.globals()[b'actual_external']=transport
        lua.execute(b"m={external_platform={start=function(o,p)local c=actual_external.start(o,p);external_pid=c.server_pid;return c end}}")
        service=module.new(opts(lua,sys.argv[2],sys.argv[3]))
        print(int(lua.globals()[b'external_pid']),flush=True)
        os._exit(0)
    elif len(sys.argv) == 6 and sys.argv[1] == '--worker':
        worker(*sys.argv[2:])
    else:
        receipt = json.loads((ROOT / 'dist/native-lua51-platform-service/build.json').read_text())
        assert not receipt['test_block_injection']
        assert hashlib.sha256((ROOT/'native/lua51_platform_service.c').read_bytes()).hexdigest() == receipt['source_sha256']
        assert hashlib.sha256((ROOT/'native/lua51_platform.c').read_bytes()).hexdigest() == receipt['shared_source_sha256']
        with tempfile.TemporaryDirectory(prefix='epic-external-private-') as folder:
            root = Path(folder); executable = root / Path(receipt['exe']).name; shutil.copyfile(receipt['exe'], executable)
            blocked = root / 'blocked-only'
            subprocess.run([sys.executable, str(ROOT/'tools/build_lua51_platform_service.py'), '--test-block', '--output', str(blocked)], check=True, capture_output=True, timeout=60)
            child = subprocess.run([sys.executable, __file__, '--worker', folder, str(executable), receipt['sha256'], str(blocked)],
                capture_output=True, text=True, timeout=120, creationflags=subprocess.CREATE_NO_WINDOW)
            print(child.stdout, end=''); print(child.stderr, end='', file=sys.stderr)
            if child.returncode==0:
                timing=json.loads(child.stdout.splitlines()[-1]);timing.update({key:receipt[key] for key in ['sha256','source_sha256','shared_source_sha256']})
                (ROOT/'dist/native-lua51-platform-service/test-timing.json').write_text(json.dumps(timing,indent=2),encoding='utf8')
            raise SystemExit(child.returncode)
