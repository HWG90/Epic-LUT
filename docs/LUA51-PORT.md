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
Named row-preset saves also use an owned row copy with an explicit source
offset, replacing pointer arithmetic that failed on portable arrays. Production
DDS/file-service round trips cover all RGBA channels, exact signed-zero and
subnormal/HDR values, previous-file preservation and rejection before IO for
invalid rows or short owned buffers. Saving retains no alias to later edits.
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


## Public GUI font evidence

The existing production view uses the stock `core/performance_hud/debug` face
through public `Gui.text` and `Gui.text_extents`; these operations appear in the
retained build 25988413 startup inventory and LLL uses this path in its Steam
manager. No replacement native font adapter is necessary for this path.
`ui_font_portable`, `ui_font`, `ui_font_render`, and `native_text_metrics` pass
in actual Lua 5.1 with FFI/bit/jit imports forbidden. They cover owned GUI
cleanup, cached glyph advances and bearings, suspend/reopen/world replacement,
and text/caret/selection geometry. The portable stock-face fixture performs no
extra GUI allocations or text-extents queries across 1,000 unchanged frames.
These are offline production-control-flow checks, not visual game acceptance.

Custom HUD-face parity remains open: the current game build needs a verified
font/atlas/material descriptor or a supported provider. Public GUI availability
does not identify those resources. The legacy exact-build font resolver and
per-GUI ownership guards remain intact; old RVAs are not current-build proof.

## Shared Windows import/export and provenance

The Windows facade now uses explicit services for process identity, executable
location, file listing and receipts, worker ownership and atomic replacement.
Raw FFI entry points remain isolated in legacy_windows. Import, original-source,
preview-worker and saved-setup controllers consume the shared methods.

The native broker additionally provides Unicode binary streams, file-only
removal, rename without overwrite, controlled hidden system-PowerShell workers,
and incremental BCrypt SHA256. Handles are private monotonic tokens with bounded
counts; errors and service shutdown close their owned resources. Closing a worker
releases ownership without terminating it; stop is explicit and scoped to that
worker's job. Hash readers can yield, enforce complete EOF/length proof and cancel
through their exact coroutine owner. Abandoned hash owners are reaped after Lua
GC on a new digest; no idle scan or background reaper is installed.

Core file_io and portable DDS publication use those streams. A failed DDS
replacement retains the active file and its previous copy. Real Lua5.1/native
tests cover exact multi-MiB data, 64MiB boundaries, Unicode paths, sharing locks,
worker lifecycle, malformed/stale tokens, independent SHA256 vectors, reader
errors/yields, cancellation and cleanup. These are standalone host measurements
and contracts, not game-thread performance or gameplay acceptance.

Run the additional native and provenance suites after building the helper:

```
py -3.14 tests/test_lua51_workers.py
py -3.14 tests/test_lua51_streams.py
py -3.14 tests/test_lua51_digest.py
py -3.14 tests/test_lua51_binding_provenance.py
```

## Current game API inventory

An explicitly approved one-shot LLL project captured 682 raw namespace members
from the running game's actual Lua5.1 VM. It called no engine functions, had no
on_update callback and saved only its own configuration. Its installed bytes
matched the reviewed candidate; the project and its settings were then retired
and their hashes rechecked. The capture and deployment/retirement receipt remain
private under dist/engine-api-inventory.

The game exposes Renderer.update_texture_base64, Application.update_raw_buffer
and Mesh.refresh_instance_hash. Their presence does not establish arguments,
RGBA32F support, current-binding readback or renderer lifetime. Material exposes
set_resource/set_texture but no raw member named as a binding getter. The engine
bridge remains unvalidated; no live LUT write was performed during this capture.

## Detached gear buffers and controller composition

Armory mirror serialization and original effect preservation now share the
owned float-buffer boundary. Original restoration previously allocated only the
original row count but copied the taller imported document into it. The copy
now uses the allocated output height; the 8-row import to 5-row original case
is covered with exact bounded buffers on both runtimes. R6 weapon runtime
documents, history and retained recovery copies also use that boundary and
retain private ownership checks, immutable uploads and transaction rollback.
These are production-controller fixtures with an explicitly injected host, not
current-game ownership or rendering proof.

Saved-setup reads, authored-preview cache reads and the update controller accept
the shared file provider. The provenance controller forwards that provider into
its scoped source cache instead of losing it during composition. Its legacy
raw-memory implementation is loaded only if that legacy read is actually used.
Update checks retain one bounded worker and perform no file or worker IO after
completion or while idle. No continuous polling was added by this port.

Read-only archive streams support exact integer sizes and positions through
2^53-1; wide seek has its own operation and keeps the earlier 32-bit operation
unchanged. This does not increase allocation or output budgets: each Lua read or
write remains bounded to 64MiB, native transfers to 1MiB, and written files to
64MiB. Real NTFS sparse files over 4GiB and incremental provenance SHA256 above
64MiB are verified without loading the entire source.

Preset manifests, raw DDS folders, patch triplets, shared preset ZIPs and Paydex
rows now use explicit shared file operations. Every production patch-export
constructor forwards that provider. Portable manifest publication atomically
replaces the target and retains the prior copy on failure; rename/export name
selection remains unchanged. Focused fixtures forbid global filesystem calls
and exercise successful publication, replacement failure and owned cleanup.

Known access and sharing errors propagate through optional snapshot reads; only
missing files are optional. Atomic publication therefore cannot replace an
unreadable active file while silently omitting its previous copy. Native stream
writes preserve multi-part Lua file writes, validate the full argument list and
allocation budget before the first transfer, and are covered by actual saved
setup manifest/DDS round trips. The modular LLL builder reads UTF-8 explicitly
to preserve source text under Windows Python's default legacy code page.

## Runtime service selection and remaining activation gates

Direct Editor now starts a shared runtime-services lease before creating paths
and preferences. The same platform and settings objects reach the model and
frontend context. It closes a created platform only after consumer cleanup has
finished; borrowed services remain with their owner. A failed constructor that
cannot close its native owner returns a retained, unready lease for ordinary
cleanup. No timer or background recovery loop is added. Public modular loader
storage remains explicit; legacy MDL settings are not migrated implicitly.

Direct Editor detached pixel copies, import comparisons, saved-byte baselines
and its retained fence pixel use float_buffer. Legacy scratch-buffer allocation
is deferred until the existing exact-build verification succeeds. The descriptor
can load and reject an unsupported build under stock Lua 5.1 without importing
FFI. R6 Weapon Bridge also uses portable highlight buffers and arithmetic event
masks, retaining all native privacy/ownership checks.

The one-shot tools/lua51_platform_smoke.lua exercises the production bootstrap,
Unicode binary IO, atomic replace/rename, independent SHA256 and owned loader
settings. Its native test uses the actual Windows DLL in a private standalone
Lua 5.1 process. The separately approved one-shot LLL test reached the game's
Lua 5.1 VM, but Windows rejected package.loadlib with error 577 (digital
signature verification) before any helper export ran. Its failure capture was
preserved and its hash-verified project/settings retired. The standalone result
does not establish that this DLL can run inside the current game. No signing or
code-integrity policy was changed. Further deployments follow the task's
authorization and retain separate installation and runtime evidence.

An explicit [external OS-service backend](LUA51-EXTERNAL-PLATFORM.md) now shares
those operations with a separate EXE, using ordinary Lua process launch and pipe
streams. Standalone tests use the real service with DLL loading forbidden;
they cover authenticated ownership, bounded active failures and idle silence.
This route remains opt-in. Its corrected OS-only probe passed in the game's
Lua 5.1 VM: Unicode binary IO, atomic replace/rename, independent SHA256 and
the public loader-settings round trip. Helper exit and owned-file retirement
were verified. The probe loads every dependency explicitly; its integration
test now forbids global imports and checkout-path fallback. This establishes
the tested OS-service path, not engine rendering or gameplay acceptance.

A further one-shot raw metadata capture inspected six fixed public engine
namespaces in the running Lua 5.1 VM. It returned 256 entries across seven tables
and 8,778 bytes of metadata without truncation or engine-function calls. The
capture includes numeric format/view constants and Float32Array's constructor
metamethod, but no upload signatures, completion/lifetime rules or effective
binding getter. It therefore does not establish a safe LUT binding provider.
The temporary project/settings were retired and their hashes verified. The
collector's text budget also accounts for JSON escaping under the loader's
64KiB config-read limit; large hostile captures are covered separately.

Full current-runtime activation is still unproven. Regular package builders
eagerly select legacy engine/avatar/lobby/Armory modules and the old input DLL.
They do not yet select a complete new engine provider. Remaining work includes
current effective binding readback and float texture lifetimes, local actor and
equipment identity, supported death/equip notifications, Player Preview/native
submission, lobby transport, and end-to-end deployed performance. The shared
OS bootstrap does not supply or emulate those game-specific services.
