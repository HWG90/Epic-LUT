# Stock Lua 5.1 host contract for Epic LUT

Target: Windows Steam build 25988413. Inspected October 20, 2026 against
maintained LLL source `cebd16c0ace0dca72e4728ccfd385e093d88d812` through the
canonical `DBF-Suite/LLL` junction. Its owner is
`OneDrive/Documents/ChatGPT/Future Project/LiveLuaLoader/release/manager-groups`.
This is source/API evidence; it does not establish Epic LUT gameplay acceptance.

## Public contracts usable now

The Steam VM has standard Lua 5.1 `io`, `os`, `package`, and `debug` libraries.
LLL's captured stock inventory (`dist/reviews/current-steam-recovery/live-startup-proof.txt`)
shows `io.open`, file streams, `io.popen`, `os.getenv`, `os.remove`, and `os.rename`.
Neither `ffi`, `bit`, nor `jit` is available. An exported function's presence does
not prove its argument semantics or suitability for asynchronous game-thread work.

For a modular LLL project, `mod` supplies these APIs in `src/project.lua`:

| API | Contract |
| --- | --- |
| `mod.dir`, `mod.config_dir`, `mod.config_path` | Project source path and loader-owned persistent config location. Config is outside the mod source tree. |
| `mod.config` | Defaults merged with saved settings; same table identity is retained after a successful save. |
| `mod.read(relative_path)` | Reads a project-relative file through LLL's bounded reader, at most 16 MiB. Absolute paths, traversal, backslashes, control characters and paths above 240 bytes are refused. |
| `mod.set(key, value)` | Validates serializable data, preserves other config keys, creates the owned config directory, then writes JSON through the host's atomic replacement API. A failed write does not publish the new config. |
| `mod.require(name)` | Per-instance declared-module loading/cache in project scope. No global package-path mutation. |
| `mod.log(message)` | Loader's existing report/log path. |

This gives portable preference/config persistence without inventing a new native
bridge. It does not transparently read or migrate `%LOCALAPPDATA%/Epic LUT`'s
existing directory tree. Standard `io.open` can read known paths with bounded
reads/seeks, but UTF-8 Windows pathname support has not been established by these
tests. The old FFI UTF-16 adapter's Unicode guarantee must not be silently dropped.

`LiveLuaLoader` and `CowboyBingusModLoader` share `capabilities`, `build`,
`input_service`, and `after_startup(function)`. Managed entries return
`{live_lua_api=1, on_enable=..., on_update=..., on_disable=...}`; these are mod
lifecycle calls, not avatar/equipment/death notifications. Read the actual
service and capability before using it. Source: `src/manager.lua`,
`src/after_startup.lua`, `docs/STEAM-LUA51.md`.

## Shared input

Use the published `loader.input_service` when `capabilities.shared_input` is true.
Do not instantiate `steam/transport.lua` or connect a second helper pipe.
Both pipe clients must be from the same process and the helper permits only one
connection. The loader initializes this service before enabling consumers.

| Call | Return/behavior |
| --- | --- |
| `acquire(owner, 'menu' or 'camera')` | Opaque token, or `nil, reason, cleanup_token`. Owner is 1-128 printable bytes. Game must already have focus. It refuses manager/MCM/other-owner conflicts. |
| `snapshot(token)` | Reused `sample` table or `nil, reason`; at most one helper sample per frame. Read immediately, never retain/mutate. Repeated reads drain wheel/dx/dy only once. |
| `owns(token)` | Active read authority; false after revocation even if restoration is pending. |
| `release(token)` | `ok, reason`; failed restoration retains the token for explicit retry, without an automatic retry loop. |
| `status()` | `owner`, `mode`, `active`, `pending_restore`, `reason`. |

Sample fields: `valid`, `x`, `y`, `width`, `height`, `buttons`, `wheel`, `dx`, `dy`.
Coordinates are client pixels from top left; wheel uses signed Windows units;
buttons are bit flags 1/2/4/8/16. Camera deltas are raw relative mouse counts.
Menu snapshots have zero dx/dy. Acquire on open, sample only while active,
release on hide/disable/reload. No helper sampling happens for an inactive
consumer. This replaces Epic LUT's FFI cursor reader, not keyboard isolation:
the host currently suppresses gameplay mouse look, but not gameplay movement
keys. Keyboard keystroke API presence is captured; native player/action blocking
is unfinished. Sources: `src/steam/input_service.lua`, `src/steam/capture.lua`,
`docs/STEAM-INPUT-SERVICE.md`.

## Private helper capabilities are not a public platform service

`src/steam/platform.lua` creates the following private `P` functions. They are
not exported on the loader or `mod`; publishing a supported shared contract is
LLL-owner work. Do not reach into private closure upvalues to obtain them.

| Function | Existing semantics |
| --- | --- |
| `read(path, limit=64 MiB)` | Ordinary Lua binary read with length check. |
| `write(path, bytes)` | Helper op 5: CREATE_NEW temporary file, then atomic replacement with write-through; no shell. |
| `mkdir(path)` | Op 3; returns true both for creation and ERROR_ALREADY_EXISTS. This does not implement Epic's exclusive `mkdir_new`. |
| `stat(path)` | Op 2; file-only identity stamp, not size/attribute metadata. Directories return nil. |
| `files(directory, pattern)` | Op 1; returns files, identity stamps, directories; wildcard filter is applied in Lua. |
| `directories(directory)` | Third result of files. |
| `hash(bytes)` | Op 6; exact resource hash returned as 16 hex digits, not SHA256. |
| `archive(path)` | At most 64 MiB; explicit `read(offset, count)` and close with accounting. |
| `changed(directory)`, `unwatch(path)`, `close_watches()` | Native directory notifications plus a shared 0.45-second generation check while the loader's existing source watch runs. This is not an equipment lifecycle event and not an Epic LUT recovery route. |

The external helper only dispatches ops 0-12: proof, listing, stat, mkdir,
watch, write, resource hash, unwatch, notification generations, close watches,
pointer sample/release/relative sample. There is no filesystem remove-directory
or exclusive-directory-create operation. Source: `native/steam_service.c`,
`native/steam_files.c`, `native/steam_pointer.c`. No game-memory reader or
native game-function dispatcher is present.

## Missing platform contracts

There is no published clipboard get/set service, open/save file dialog, async
owned worker launch/stop/status, shell folder-opening API, or filesystem
listing/mkdir service available to mods. `io.popen`/`os.execute` presence is not
evidence of safe nonblocking replacements for `windows.launch_worker`; do not
launch a blocking dialog on the game thread. `Application.open_url_in_browser`
appears in the engine inventory but folder-opening semantics are unverified.
Engine memory, texture creation and appearance lifecycle capabilities are a
separate contract and are not supplied by this filesystem/input helper.

Keep these genuinely unavailable services visible as port work; absence of FFI
must not be hidden behind a successful syntax test or functions that silently
drop the requested behavior. A future service must preserve Unicode/path and
resource ownership, bounded request/data sizes, cancellation, and idle silence.

## Offline evidence

Run from either Epic LUT maintained checkout:

```powershell
py -3.14 tools/test_lua51_host_contract.py
```

The check executes LLL's actual `project.lua`, `config.lua` and `metadata.lua`
under `lupa.lua51`, with filesystem effects injected in memory. It verifies
relative-read validation, config save/restart with other values preserved, and
failure isolation. It does not launch the helper or game. LLL's existing
`tests/test_steam_input_service.py` (13 tests) and
`tests/test_steam_capture_service.py` (6 tests) also pass under Lua 5.1. These
validate the broker/capture state machine; they are not Epic LUT live acceptance.
