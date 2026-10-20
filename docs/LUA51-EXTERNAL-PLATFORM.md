# Explicit external OS-service backend

This source-only backend runs the shared Windows platform operations in a
separate EXE. It does not load a DLL into the consumer, access game memory,
install hooks, modify code-integrity policy, or change the default runtime.
No game deployment or gameplay acceptance is established by the tests below.

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
without terminating a successful worker. During an unacknowledged launch only,
a provisional job has kill-on-close, assigned atomically with process creation,
so a blocked launch cannot leave a suspended child after the watchdog exits.
A successfully written worker receipt removes that provisional flag; failed
receipt delivery terminates the unreported worker. Service retirement preserves
successfully detached workers.

## Standalone validation

```powershell
py -3.14 tools/build_lua51_platform_service.py
py -3.14 tests/test_lua51_platform_external.py
```

The test copies the real EXE into private Temp and uses actual stock Lua 5.1
`io.popen`/`io.open` streams, with `package.loadlib` forbidden. It checks Unicode
and binary IO, atomic replacement, SHA256 versus Python hashlib, exact client
identity, wrong token/foreign PID/image rejection, maximum fragmented transfers,
partial-frame expiry, killed server, abrupt owner exit, idle CPU/handle stability,
and owned worker stop/detach. It does not change the clipboard or open a dialog.

A separate test-only compile defines blocked dispatch/close operations. The
production build contains none of those operations. Tests prove EOF after a
noncancellable dispatch, provisional-worker cleanup, explicit-close timeout,
and an ambiguous response after an already completed filesystem side effect.

`dist/native-lua51-platform-service/build.json` records exact shared-source,
host-source and EXE hashes. `test-timing.json` records one-shot startup, steady
IPC/stat/hash latency, and a separate idle CPU sample. These are standalone
measurements, not deployed game performance. Observed one-shot startup samples
were sub-second to approximately two seconds, varying with host load; they are
separate from subsequent request timings. This backend remains opt-in and has
not been activated in the game.
