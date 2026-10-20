# Explicit external OS-service backend

This explicit backend runs the shared Windows platform operations in a
separate EXE. It does not load a DLL into the consumer, access game memory,
install hooks, modify code-integrity policy, or change the default runtime.
Standalone tests do not establish gameplay acceptance. The separate OS-only
game probe is recorded below.

## Selection

`native_platform.new` retains the existing `{library=absolute_dll}` default.
The separate route requires all of these explicit options:

```lua
local service = native_platform.new({
    backend = 'external',
    service = absolute_content_addressed_exe,
    sha256 = exact_build_receipt_sha256,
    process_id = current_process_id,
})
```

Production bootstrap can select the same route with
`model.platform_backend='external'`, `model.native_platform_name=<EXE basename>`,
and `model.native_platform_sha256=<exact receipt SHA256>`. The existing context
directory supplies its absolute path; the ordinary current-process API supplies
the PID. `external_platform` must be present in the model/module inventory.
No existing builder or installed loader selects this backend automatically.

The returned platform surface is unchanged: Unicode binary streams, file and
directory operations, atomic replacement, SHA256, clipboard and owned workers.
The current public LLL shared input/config services remain separate. This
backend supplies no engine texture, effective-material or lifecycle service.

## Launch and identity

The ordinary stock Lua `io.popen` route follows LLL's existing external-service
architecture. A one-shot hidden System32 PowerShell process verifies the exact
EXE SHA256, retaining a read-sharing-only image handle through describe/start
and readiness to prevent image replacement. It generates a private 256-bit
instance token using Windows cryptography and starts the EXE hidden. No shell
policy flag, runtime compiler, second LLL pipe, or private loader API is used.

The helper queries the actual client's executable path with
`PROCESS_QUERY_LIMITED_INFORMATION`, retains that process handle with
`SYNCHRONIZE`, and verifies its path again against the launch description.
Both actual named-pipe client PIDs must match the retained client. The first
request proves the instance token and the expected helper/client PIDs; the
response must match the launch receipt's identities and executable path.
The helper uses the authenticated client for executable-path responses and
foreground clipboard authorization. It never substitutes its own image/window.

Pipe names include the private token and use exclusive first-instance,
local-only servers. Every request keeps the existing nonce/status/length
protocol and 1 MiB native transfer bound. OS operations are included from
`native/lua51_platform.c`, rather than maintained in a second implementation.
The old DLL's compiled bytes remain unchanged by these conditional additions.

## Work and retirement

With no request, the EXE blocks on an overlapped pipe read and the retained
client-process handle. There is no idle timer or periodic poll. Connect and
readiness waits are bounded to eight seconds. These deadlines start after EXE
hashing/description; they are not an end-to-end launch-time guarantee.
The final encoded launcher command is refused above Windows' command limit.

Partial request/response transfers have a three-second deadline. Active OS
dispatch and explicit close also arm a one-shot three-second watchdog. It
requests synchronous-I/O cancellation, permits 500 ms of cleanup, then exits
only this helper if the operation cannot return. Closing the helper's pipes
unblocks the consumer's ordinary Lua read. No dispatch timer remains while idle.
OS side effects can already have completed when a timeout loses its response;
that result is ambiguous and the driver never automatically retries it.

EOF, actual client exit, malformed framing and explicit close retire the
service's file/hash/process handles. No raw native handle crosses the protocol.
Workers retain the existing eight-slot token ownership and stop-versus-close
semantics: `stop` terminates the owned job, while `close` releases ownership
without terminating a successful worker. The job has kill-on-close assigned
atomically with process creation, so a blocked launch cannot leave a suspended
child after the watchdog exits. Receipt delivery retains this protection: an
acknowledged worker remains owned until explicit `worker.close()` successfully
removes the job limit before releasing its handles. A failed detach preserves
the token and owner for an explicit cleanup decision. Failed receipt delivery
terminates the unreported worker; unexpected helper/client exit and service
retirement terminate still-owned jobs. Explicitly detached workers survive.

### Asynchronous worker creation

The external EXE additionally supports explicit asynchronous launch. The old
synchronous operation 12 and the existing DLL remain compatible. Operations
31–33 are external-only; 22–25 remain the digest protocol.

| Operation | Request | Successful response |
| --- | --- | --- |
| 31 begin | Existing operation-12 payload: argument byte count, UTF-8 arguments, UTF-8 working folder | Future token, one little-endian `u32` |
| 32 result | Future token `u32` | State `u32`: 0 pending; 1 followed by worker token and PID; 2 followed by Win32 error; 3 cancelled |
| 33 cancel | Future token `u32` | Empty acknowledgement of the cancellation request |

Pending results are four bytes; ready results are twelve; failed results are
eight; cancelled results are four. A terminal result consumes the future exactly
once. The worker receipt has the same ownership contract as synchronous launch.
Unknown, consumed and stale future tokens are refused. Cancellation acknowledges
the request promptly; a later terminal state 3 confirms native launch cleanup.
Cancellation after the worker receipt has transferred ownership is refused;
the worker's explicit stop/close methods then control its lifetime.

Each begin copies its bounded request and starts a finite helper-owned thread.
That thread never mutates the shared worker table. Result promotes a completed
launch into a worker only after the launch thread has stopped. Pending futures,
ready but unconsumed futures, and synchronous/asynchronous owned workers share
one eight-slot budget. Atomic process/job assignment and kill-on-close protect
the child throughout creation, cancellation and receipt delivery. A lost begin
or result response retires the service and kills any unreported owned launch.

Every active launch has its own three-second one-shot watchdog with 500 ms
cancellation grace; an uncancellable operation terminates only this helper.
Completion removes that watchdog immediately, without waiting for a result
request. Service retirement cancels pending launches and exits without joining
a blocked creation thread; process exit closes its protected jobs and threads
together. No launch thread or launch timer remains after completion/consumption.
There is no idle status loop. Callers make bounded result requests only while
they explicitly own active launch work, then cache the terminal result.

## Standalone validation

```powershell
py -3.14 tools/build_lua51_platform_service.py
py -3.14 tests/test_lua51_platform_external.py
py -3.14 tests/test_lua51_async_workers.py
py -3.14 tests/test_lua51_external_project.py
```

The test copies the real EXE into private Temp and uses actual stock Lua 5.1
`io.popen`/`io.open` streams, with `package.loadlib` forbidden. It checks Unicode
and binary IO, atomic replacement, SHA256 versus Python hashlib, exact client
identity, wrong token/foreign PID/image rejection, maximum fragmented transfers,
partial-frame expiry, killed server, abrupt owner exit, idle CPU/handle stability,
and owned worker stop/detach. Acknowledged long-running workers are verified to
exit on helper loss, actual client exit and explicit service retirement, while
an explicitly closed worker survives retirement. It does not change the
clipboard or open a dialog.

A separate test-only compile defines blocked dispatch/close operations. The
production build contains none of those operations. Tests prove EOF after a
noncancellable dispatch, provisional-worker cleanup, explicit-close timeout,
an injected detach failure that preserves the token/job for explicit stop,
and an ambiguous response after an already completed filesystem side effect.
The asynchronous suite checks real process creation, UTF-8/filesystem errors,
pending and ready cancellation, suspended-child cancellation, shared capacity,
lost begin/result replies, background watchdogs, service/client loss and idle
handle/CPU stability. `async-timing.json` separates begin/result/cancel request
latency from complete OS worker creation; those are standalone measurements.

`dist/native-lua51-platform-service/build.json` records exact shared-source,
host-source and EXE hashes. `test-timing.json` records one-shot startup, steady
IPC/stat/hash latency, and a separate idle CPU sample. These are standalone
measurements, not deployed game performance. Observed one-shot startup samples
were sub-second to approximately two seconds, varying with host load; they are
separate from subsequent request timings. This backend remains opt-in and has
no full-runtime gameplay acceptance.

## OS-only game probe status

The corrected isolated one-shot completed the full OS-service smoke in the
game's stock Lua 5.1 runtime. The unchanged external EXE
`1771465861bcddc373e59cff1ccbe4cec27fe7b8e0c191333c2b8ba2e8c29161`
passed Unicode binary write/read of 1280 bytes, atomic replacement, rename,
the independent SHA256 vector, and its owned loader-store roundtrip. Normal
cleanup, platform closure and the actual helper's exit were verified. The
temporary project and its owned settings were retired with hashes checked.

Loader entry health recorded 1068 ms for this entire one-shot. That includes
startup and smoke work; it is neither steady-state request latency nor a
gameplay performance measurement. This establishes the tested OS-service route,
not armor/weapon binding, recovery, or full Epic LUT runtime acceptance.

An earlier probe failed before digest because its prepared project omitted the
model's cooperative dependency. Its standalone candidate fixture allowed a
global repository import, which concealed that packaging error. The public
`test_lua51_external_project.py` now runs the actual LLL project/config code with
the real EXE in private Temp. Its working directory is private, both package
paths are empty, and global `require`, `dofile`, and DLL loading are forbidden.
Only declared project modules, including cooperative and the production smoke
runner, can load. It reproduces the missing dependency as a failure, verifies
cleanup, and passes the corrected complete OS smoke. Repeat enable and actual
config reload perform no additional launch or settings write; helper exit is
checked independently. These hermetic standalone checks and the completed
OS-only game probe remain separate from gameplay and deployed performance.
