"""Actual external helper asynchronous launch ownership/races, private Temp only.

Uses stock Lua5.1 stdlib pipe streams; no game, DLL loading, clipboard or policy
changes. Timing separates each short protocol call from OS launch completion.
"""
import base64
import ctypes
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

from test_lua51_platform_external import K, ROOT, children, cpu, handles, opts, process, runtime, until


class Channel:
    def __init__(self, executable, digest):
        self.lua, _, transport = runtime()
        self.channel = transport.start(opts(self.lua, executable, digest), os.getpid())
        self.pid = self.channel.server_pid
        self.handle = process(self.pid)
        self.send = self.lua.eval(b'function(c,b)assert(c.request:write(b));assert(c.request:flush())end')
        self.read = self.lua.eval(b'function(c,n)return c.response:read(n)end')
        self.close_streams = self.lua.eval(b'function(c)pcall(c.request.close,c.request);pcall(c.response.close,c.response)end')
        self.nonce = 0
        self.times = {}
        self.closed = False
        assert self.request(29, self.channel.token + struct.pack('<II', os.getpid(), self.pid))[0] == 0

    def packet(self, operation, payload):
        self.nonce += 1
        return b'ELP1' + struct.pack('<III', self.nonce, operation, len(payload)) + payload

    def request(self, operation, payload=b''):
        packet = self.packet(operation, payload)
        start = time.perf_counter_ns()
        self.send(self.channel, packet)
        header = self.read(self.channel, 16)
        if header is None:
            return None
        assert header[:4] == b'ELR1'
        nonce, status, length = struct.unpack_from('<III', header, 4)
        assert nonce == self.nonce and length <= 1048576
        result = (status, self.read(self.channel, length) if length else b'')
        self.times.setdefault(operation, []).append((time.perf_counter_ns() - start) / 1_000_000)
        return result

    def begin(self, payload, mode=None):
        reply = self.request(31 if mode is None else 243,
            payload if mode is None else struct.pack('<I', mode) + payload)
        assert reply and reply[0] == 0 and len(reply[1]) == 4, reply
        return reply[1]

    def terminal(self, token):
        end = time.monotonic() + 5
        while True:
            reply = self.request(32, token)
            assert reply and reply[0] == 0, reply
            state = struct.unpack_from('<I', reply[1])[0]
            assert len(reply[1]) == {0: 4, 1: 12, 2: 8, 3: 4}[state]
            if state:
                return state, reply[1][4:]
            assert time.monotonic() < end, 'Bounded active launch did not complete'
            time.sleep(.01)

    def close(self):
        if self.closed:
            return
        self.closed = True
        try:
            if K.WaitForSingleObject(self.handle, 0) == 258:
                assert self.request(30) == (0, b'')
            assert K.WaitForSingleObject(self.handle, 3000) == 0
        finally:
            if K.WaitForSingleObject(self.handle, 0) == 258:
                K.TerminateProcess(self.handle, 78)
                K.WaitForSingleObject(self.handle, 3000)
            self.close_streams(self.channel)
            K.CloseHandle(self.handle)


def payload(root, marker, delay=0, hold=60):
    escaped = str(marker).replace("'", "''")
    script = f"Start-Sleep -Milliseconds {delay};[IO.File]::WriteAllText('{escaped}',[string]$PID);Start-Sleep -Seconds {hold}"
    args = ('-NoLogo -NoProfile -NonInteractive -EncodedCommand ' + base64.b64encode(script.encode('utf-16-le')).decode()).encode()
    return struct.pack('<I', len(args)) + args + str(root).encode('utf8')


def exited(handle, message):
    assert K.WaitForSingleObject(handle, 3000) == 0, message


def child(root, executable, digest, blocked):
    root = Path(root)
    times = {31: [], 32: [], 33: []}
    completion = []
    c = Channel(executable, digest)
    try:
        baseline_handles = handles(c.handle)
        assert c.request(31, b'') == (13, b'')
        for operation in [32, 33]:
            assert c.request(operation) == (13, b'')
            assert c.request(operation, b'\0' * 4) == (6, b'')
        # Three serial real launches measure protocol time separately from the
        # hidden process's native startup and script-ready latency.
        for index in range(3):
            marker = root / f'async \u8863\u88c5 \U0001f986-{index}.txt'
            start = time.perf_counter()
            token = c.begin(payload(root, marker))
            state, receipt = c.terminal(token)
            completion.append((time.perf_counter() - start) * 1000)
            assert state == 1
            worker_token, pid = struct.unpack('<II', receipt)
            worker_handle = process(pid)
            try:
                until(marker.exists, 'Actual asynchronous worker did not run')
                assert int(marker.read_text()) == pid
                assert c.request(32, token) == (6, b'')
                assert c.request(33, token) == (6, b'')
                worker_bytes = struct.pack('<I', worker_token)
                assert c.request(13, worker_bytes) == (0, struct.pack('<I', 1))
                assert c.request(14, worker_bytes) == (0, b'')
                exited(worker_handle, 'Stopped asynchronous worker survived')
                assert c.request(15, worker_bytes) == (0, b'')
            finally:
                K.CloseHandle(worker_handle)
            if index==0:
                # Windows creates retained thread-pool infrastructure on the
                # first overlapping request/launch timers. Measure stability
                # after that one-time OS initialization, not before it.
                baseline_handles=handles(c.handle)
        # UTF8/filesystem failures are asynchronous terminal results, never
        # fabricated workers. Their future token is consumed exactly once.
        for raw, expected in [(struct.pack('<I', 1) + b'\xff' + str(root).encode(), 1113),
                              (payload(root / 'missing', root / 'never.txt'), 2)]:
            token = c.begin(raw)
            state, reason = c.terminal(token)
            assert state == 2 and struct.unpack('<I', reason)[0] == expected, (state, reason, expected)
            assert c.request(32, token) == (6, b'')
        # Cancel a completed but unconsumed launch; its process remains owned.
        marker = root / 'ready-cancel.txt'
        token = c.begin(payload(root, marker))
        until(marker.exists, 'Ready cancellation did not start an actual worker')
        worker_handle = process(int(marker.read_text()))
        try:
            assert c.request(33, token) == (0, b'')
            assert c.terminal(token) == (3, b'')
            assert K.WaitForSingleObject(worker_handle,0)==0, 'Cancelled result preceded actual worker exit'
        finally:
            K.CloseHandle(worker_handle)
        # No per-launch thread, job, timer or handle remains after consumption.
        before = cpu(c.handle)
        time.sleep(.35)
        idle_cpu = cpu(c.handle) - before
        assert idle_cpu < .03, 'Completed asynchronous launches did idle work'
        assert handles(c.handle) == baseline_handles, (handles(c.handle), baseline_handles)
        for op in times:
            times[op].extend(c.times.get(op, []))
    finally:
        c.close()

    injected = json.loads((Path(blocked) / 'build.json').read_text())
    c = Channel(injected['exe'], injected['sha256'])
    try:
        # Cancellation while still preparing, and after atomic CreateProcess
        # but before ResumeThread, have distinct real ownership paths.
        token = c.begin(payload(root, root / 'before-never.txt'), mode=2)
        assert c.request(32, token) == (0, struct.pack('<I', 0))
        assert c.request(33, token) == (0, b'')
        assert c.terminal(token) == (3, b'')
        assert not (root / 'before-never.txt').exists()
        token = c.begin(payload(root, root / 'suspended-never.txt'), mode=3)
        until(lambda: bool(children(c.pid)), 'Cancellation fixture never created suspended child', limit=2)
        child_pids = children(c.pid)
        assert len(child_pids) == 1
        suspended = process(child_pids[0])
        try:
            assert c.request(33, token) == (0, b'')
            assert c.terminal(token) == (3, b'')
            assert K.WaitForSingleObject(suspended,0)==0, 'Cancelled result preceded suspended-child exit'
            assert not (root / 'suspended-never.txt').exists()
        finally:
            K.CloseHandle(suspended)
        # Capacity is shared with sync workers, including futures that have
        # merely reserved capacity; neither launch API can bypass eight slots.
        status, receipt = c.request(12, payload(root, root / 'capacity-owned.txt'))
        assert status == 0
        worker_token, worker_pid = struct.unpack('<II', receipt)
        owned = process(worker_pid)
        try:
            tokens = [c.begin(payload(root, root / f'capacity-never-{i}.txt'), mode=2) for i in range(7)]
            assert c.request(31, payload(root, root / 'capacity-overflow.txt')) == (4, b'')
            assert c.request(12, payload(root, root / 'sync-overflow.txt')) == (4, b'')
            for token in tokens:
                assert c.request(33, token) == (0, b'')
            for token in tokens:
                assert c.terminal(token) == (3, b'')
            worker_bytes = struct.pack('<I', worker_token)
            assert c.request(14, worker_bytes) == (0, b'')
            exited(owned, 'Capacity fixture worker survived stop')
            assert c.request(15, worker_bytes) == (0, b'')
            assert all(not (root / f'capacity-never-{i}.txt').exists() for i in range(7))
        finally:
            K.CloseHandle(owned)
    finally:
        c.close()

    # A launch blocked after creating its real suspended child cannot block
    # the main pipe. Its own finite watchdog retires the helper and atomic job.
    c = Channel(injected['exe'], injected['sha256'])
    try:
        token = c.begin(payload(root, root / 'watchdog-never.txt'), mode=1)
        until(lambda: bool(children(c.pid)), 'Async watchdog fixture created no actual child', limit=2)
        child_pids = children(c.pid)
        assert len(child_pids) == 1
        suspended = process(child_pids[0])
        try:
            assert c.request(32, token) == (0, struct.pack('<I', 0))
            assert c.request(33, token) == (0, b'')
            assert K.WaitForSingleObject(c.handle, 4500) == 0, 'Background launch escaped its watchdog'
            exited(suspended, 'Async watchdog left a suspended child alive')
            assert c.read(c.channel,16) is None
        finally:
            K.CloseHandle(suspended)
    finally:
        c.close()

    # Both lost receipt windows are real protocol disconnects. Begin delivery
    # never leaks its future; ready promotion never leaks an unreported worker.
    for operation in [244, 245]:
        c = Channel(injected['exe'], injected['sha256'])
        marker = root / f'unreported-{operation}.txt'
        try:
            raw = payload(root, marker)
            if operation == 245:
                token = c.begin(raw)
                until(marker.exists, 'Ready disconnect fixture never ran')
                data = token
            else:
                data = raw
            c.send(c.channel, c.packet(operation, data))
            until(marker.exists, 'Begin disconnect fixture never ran')
            child_handle = process(int(marker.read_text()))
            try:
                c.close_streams(c.channel)
                assert K.WaitForSingleObject(c.handle, 4000) == 0
                exited(child_handle, 'Lost async receipt detached an unreported worker')
            finally:
                K.CloseHandle(child_handle)
        finally:
            c.close()

    # Explicit service retirement during in-flight creation and abrupt helper
    # loss both close the protected job without waiting for the stalled thread.
    for kill in [False, True]:
        c = Channel(injected['exe'], injected['sha256'])
        try:
            c.begin(payload(root, root / f'loss-never-{kill}.txt'), mode=1)
            until(lambda: bool(children(c.pid)), 'In-flight loss fixture created no child', limit=2)
            child_pids = children(c.pid)
            assert len(child_pids) == 1
            child_handle = process(child_pids[0])
            try:
                if kill:
                    assert K.TerminateProcess(c.handle, 77)
                else:
                    assert c.request(30) == (0, b'')
                exited(c.handle, 'Helper loss/close did not retire its process')
                exited(child_handle, 'Helper loss/close left a pending child alive')
            finally:
                K.CloseHandle(child_handle)
        finally:
            c.close()

    owner = subprocess.run([sys.executable, __file__, '--owner-exit', str(executable), digest, str(root)],
        capture_output=True, text=True, timeout=15, creationflags=subprocess.CREATE_NO_WINDOW)
    assert owner.returncode == 0, owner.stdout + owner.stderr
    pids = json.loads(owner.stdout)
    for name, pid in pids.items():
        handle = K.OpenProcess(0x100000 | 0x1000 | 1, False, pid)
        if handle:
            try:
                exited(handle, f'{name} survived actual client exit with an unconsumed future')
            finally:
                K.CloseHandle(handle)
        else:
            assert ctypes.get_last_error() == 87
    timing = {str(op): {'count': len(values), 'median_ms': round(statistics.median(values), 4),
        'max_ms': round(max(values), 4)} for op, values in times.items()}
    print('PASS async actual Lua51/EXE: real workers, errors, pending/ready cancellation, shared capacity, '
          'lost begin/result receipts, background watchdog, helper/host loss, service close, zero idle work')
    print(json.dumps({'calls': timing, 'launch_completion_ms': [round(n, 4) for n in completion],
        'idle_cpu_seconds': idle_cpu, 'game_performance_measured': False}, sort_keys=True))


if __name__ == '__main__':
    if len(sys.argv) == 5 and sys.argv[1] == '--owner-exit':
        c = Channel(sys.argv[2], sys.argv[3])
        marker = Path(sys.argv[4]) / 'host-future.txt'
        c.begin(payload(marker.parent, marker))
        until(marker.exists, 'Host-exit future worker did not actually run')
        print(json.dumps({'helper': int(c.pid), 'worker': int(marker.read_text())}), flush=True)
        os._exit(0)
    elif len(sys.argv) == 6 and sys.argv[1] == '--child':
        child(*sys.argv[2:])
    else:
        receipt = json.loads((ROOT / 'dist/native-lua51-platform-service/build.json').read_text())
        assert not receipt['test_block_injection']
        assert hashlib.sha256((ROOT / 'native/lua51_platform_service.c').read_bytes()).hexdigest() == receipt['source_sha256']
        assert hashlib.sha256((ROOT / 'native/lua51_platform.c').read_bytes()).hexdigest() == receipt['shared_source_sha256']
        with tempfile.TemporaryDirectory(prefix='epic-async-private-') as folder:
            root = Path(folder)
            executable = root / Path(receipt['exe']).name
            shutil.copyfile(receipt['exe'], executable)
            blocked = root / 'blocked-only'
            subprocess.run([sys.executable, str(ROOT / 'tools/build_lua51_platform_service.py'), '--test-block',
                '--output', str(blocked)], check=True, capture_output=True, timeout=60)
            run = subprocess.run([sys.executable, __file__, '--child', folder, str(executable), receipt['sha256'], str(blocked)],
                capture_output=True, text=True, timeout=120, creationflags=subprocess.CREATE_NO_WINDOW)
            print(run.stdout, end='')
            print(run.stderr, end='', file=sys.stderr)
            if run.returncode == 0:
                timing = json.loads(run.stdout.splitlines()[-1])
                timing['sha256'] = receipt['sha256']
                (ROOT / 'dist/native-lua51-platform-service/async-timing.json').write_text(json.dumps(timing, indent=2))
            raise SystemExit(run.returncode)
