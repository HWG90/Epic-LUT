# Epic LUT: stock Lua 5.1 port in progress

Target: shipped Windows Steam build 25988413, embedded Lua 5.1 without ffi/bit/jit.
Shared changes are maintained in both R5 and R6 branches. This is a source-level
port in progress, not a working game build or a published release.

## Current functional changes

A shared `core/float_buffer` provides zero-based float32 arrays, exact little-endian
bytes, ties-to-even rounding, signed zero/subnormal preservation, bounded copying
and private allocation provenance. Numeric tables cannot forge owned-array proof.
The common path never imports ffi/bit/jit. Legacy LuaJIT may reuse already-loaded
FFI solely for its existing cdata backend.

DDS read/write and validation, independent editor documents/history, LUT and
Pattern editors, row/selection/scalar clipboards, effect preservation, preset
capture/apply bookkeeping, region-identification copies and prepared immutable
binding uploads now use that boundary. Native binding operations remain explicit
injected services; existing ownership/receipt/rollback/lifetime checks are retained.
R6 additionally uses portable buffers for weapon palette copy/fit and an arithmetic
lifecycle mask for slot recovery, with 1000 idle ticks causing no restore calls.

ZIP CRC and binding-export CRC/FNV resource fingerprints no longer require bit.
They initialize lazily on actual export. Archive bytes and collision-retry IDs
match the legacy writer. SharedLUT serialization/dictionary/baseline/XOR handling
uses exact portable bytes. Portable LZNT1 encoding/decoding and XPRESS decoding
are cross-checked against Windows compression APIs; the portable compression
code itself loads no DLL.
Publication forwards cooperative yields through protected calls using Lua 5.1
coroutines, avoiding the old non-yieldable pcall boundary. Expensive work runs only
for changed state and reuses palette bytes within each job. Offline staged tests
measure CPU slices separately from end-to-end latency; deployed timing is unproven.

## Frontend and Windows services

Portable adapters now consume LLL's public shared-input and project-config
contracts. Input is leased only for an active menu; hidden frames perform no
pointer sampling or cleanup retries. Settings remain in an isolated namespace,
unchanged saves do no writes, and legacy migration requires explicit bytes.
The existing LuaJIT input, clipboard and folder implementations are isolated
behind explicit legacy adapters rather than removed.

The Windows service is a separately built Lua 5.1 C module. It provides bounded
Unicode filesystem operations and clipboard access through same-process named
pipes, with no file IPC, worker thread, game-memory access or periodic work.
The production Lua driver and native protocol tests use private temporary
folders; they do not touch the OS clipboard, launch Explorer, or run the game.
The regular package builders still select the existing native runtime. Including
these modules in source does not activate the new service or establish new-build
engine compatibility.

## Verification commands

Run using existing Python 3.14/lupa; install nothing:

```
py -3.14 tools/check_lua51.py
py -3.14 tests/test_lua51_dds.py
py -3.14 tests/test_lua51_documents.py
py -3.14 tests/test_lua51_binding_patch_export.py
py -3.14 tests/test_lua51_lznt1.py
py -3.14 tests/test_lua51_xpress.py
py -3.14 tools/test_lua51_host_contract.py
```

The separate Windows platform helper uses the existing Visual Studio tools:

```
py -3.14 tools/build_lua51_platform.py
py -3.14 tests/test_lua51_platform_native.py
py -3.14 tests/test_lua51_platform_driver.py
```

The DDS oracle covers 16,384 finite binary32 words, every finite binary16 word,
independent rounding cases, malformed/mip input and bounds. Portable editor and
binding-session fixtures execute the real production controllers with explicit
host fixtures and forbidden native imports; they do not emulate FFI or prove GPU
rendering. Existing LuaJIT regression suites also exercise the changed paths.
The broad suite retains the previously observed legacy full_editor failure;
`dist/lua51-regressions.json` records current results. The font-metric fixture
passes when its original UTF-8 bytes are executed, avoiding Python ANSI decoding.
The real 155-binding publication fixture serializes two palette copies; the larger
10-LUT fixture preserves a 410-byte wire packet across 2,819 forced cooperative
stages. Offline CPU slices vary with the host and test load; forced stages are not
deployed frame-time or end-to-end latency measurements. Synchronous encoding
still performs the entire job, so production publication must retain its
cooperative scheduling.

## Required completion evidence

The objective remains all functions working under the new runtime. Parser checks,
headless fixtures and module exports do not establish that objective. Completion
still needs all of:

- A verified25988413 engine adapter for local actor/equipment identities, exact
  texture read/upload/lifetime, owned material binding receipts and mesh commits.
- Supported death/equip/transition events and R6 private weapon appearance leases;
  keep unchanged state idle, without repeated scans or reapplication.
- Stock frontend/input/font/clipboard/dialog/process/file-service integration,
  retaining existing imports, exports, settings and asynchronous worker behavior.
- Current-build Player Preview/native rendering/cleanup and loader composition
  for each maintained package target. Old RVAs and native DLLs are not proof.
- End-to-end activation, all editor actions, preset save/restart, native Armory,
  ammo reload, death/respawn and ship/mission transitions in the actual runtime.
- Deployed performance and transition checks, including any new spikes.

The inspected LLL helper exposes filesystem and leased pointer input internally;
it deliberately provides no game-memory or texture service. Public mod.read,
mod.config/mod.set and shared input contracts are documented and exercised in
LUA51-HOST-CONTRACT.md. Do not invent handles, emulate FFI, use old layouts as new
proof, introduce hooks or weaken ownership just to make a fixture pass.

The current source backport and Git update do not deploy files, publish a
release, send game input, or change native settings. Photo, other components
and private review copies remain outside this writer's scope.
