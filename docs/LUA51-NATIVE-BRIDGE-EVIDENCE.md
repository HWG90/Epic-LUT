# Lua 5.1 native bridge evidence: build 25988413

Status: reference route identified; target ABI and gameplay behavior unverified.
No native calls, process attachment, deployment, generated provider, or executable
patches were performed for this investigation.

## Identified target

The existing Steam recovery receipt identifies these original files:

- `bin/helldivers2.exe`: SHA256
  `2ce8b3d74c5573088e4211b060ced0963f1fc1e74526e2645399780b8fb13ff7`.
- `data/game/game.dll`: SHA256
  `a457433f0eb766fbe15a6de5a16f0fbbb1fd3c840c5607a5f0b2ebf53b112949`.

File identity does not prove a function-table layout. The older FFI adapters
remain evidence for their explicitly documented earlier build only.

## Current-build static registration pass (2026-10-20)

REA 6.7.0 / Ghidra 12.1.4 inspected the original `data/game/game.dll` above,
without loading it into the game or executing its code. No existing target or
retained analysis was available. The exported PE symbol is a concrete new locator:

| Fact | Exact source coordinate | Confidence |
| --- | --- | --- |
| Export directory | file offset `0x24b32a0`, size 372 bytes | Original PE header/table bytes |
| `get_plugin_api` name | file offset `0x24b3404` | Original NUL-terminated export name |
| Export address-table entry | file offset `0x24b32dc` contains RVA `0x4f6e00` | Original PE table bytes |
| Export body mapping | image base `0x180000000`; VA `0x1804f6e00`; file offset `0x4f6200` | Ghidra source mapping agrees with PE section mapping |
| Callable signature / table layout | unavailable | No function was recovered at that export |

The first 32 original bytes at the mapped export are
`4c16af9d1355e9aa774ed82440bb00418be7089365dfa7eafeb412d854f5b9c6`.
Ghidra completed its default analysis but reported only seven procedures, five
local and two external, and 3,740 defined strings. The export did not become a
procedure, so a function dossier could not be produced. An encrypted or otherwise
transformed on-disk code image is a possible explanation, not a verified finding.
These results do not establish that the API is absent, that its runtime body has
those bytes, or that the export RVA can be called safely.

The observed local procedures were entry `0x181f10d1c`, guard routines
`0x181f10fbc` / `0x181f968f0`, and unnamed procedures `0x181f1179c` /
`0x181f1f2f8`. None establishes engine table registration. Ghidra recorded a PDB
reference to `game.pdb`, GUID `194f3d4f-41df-4c79-ab74-6c89ddc7c03b`, age 1;
PDB loading was unknown, and the original engine symbols/types were unavailable.

Private retained read-only evidence is stored locally at
`dist/reviews/steam25988413-static-bridge-evidence.json` (ignored, not packaged or published).
The source-level findings retain these evidence IDs:

- `ev_ffce49a18c0a7b9f995dc557298427a735a2abbb5b1d978bb484b7cf028a9723`:
  completed inventory and counts.
- `ev_a4d1c971e8de9f0ac3ce20f797de8a59b3b0b34a387e1f8bad20bfd60c63b56f`:
  all seven recovered procedures.
- `ev_89944156dcaf7a1e706decd40a553f9caae1140b8766c241c233c2192cace29e`:
  complete 96-byte read of the mapped export.
- `ev_65e43b6661e7946cfed71a8155bf32a67ba6430fc36e95019aeee5e8eca4a910`:
  export VA to original file offset.

No target-verified LuaApi, RenderBufferApi, ScriptApi, or GetApiFunction layout
was recovered. The useful next evidence is a build-matched developer SDK/header
or an existing supported host that exposes those services through its documented
registration callback. Repeating name searches or copying upstream/old offsets
does not fill this gap. The REA target was closed after exporting the evidence;
no unpacking, process capture, protection changes, hooks, or native probes were
performed.

## Supported plugin design in the upstream SDK

Inspected primary reference: AutodeskGames/stingray-plugin-api-samples commit
[`e9d937a013e4aa1f25b6f7d9bdee0ca985455cfd`](https://github.com/AutodeskGames/stingray-plugin-api-samples/tree/e9d937a013e4aa1f25b6f7d9bdee0ca985455cfd).
This is a 2017 upstream engine SDK, not an HD2 build-specific SDK.

- [plugin_api.h](https://github.com/AutodeskGames/stingray-plugin-api-samples/blob/e9d937a013e4aa1f25b6f7d9bdee0ca985455cfd/stingray_sdk/engine_plugin_api/plugin_api.h)
  lines 193-195 document `setup_game(GetApiFunction)`. Lua API ID is 1.
  `LuaApi.add_module_function` at line 310 registers an ordinary `lua_CFunction`
  as `stingray.<module>.<name>()`. The same table supplies Lua stack/string
  operations and `getunit` (line 545), avoiding FFI and Lua-state layout guesses.
- The same header identifies RenderBuffer API ID 26. Lines 1974-1986 provide
  `create_buffer`, `update_buffer`, `destroy_buffer`, and `lookup_resource`.
- [render_plugin/plugin.cpp](https://github.com/AutodeskGames/stingray-plugin-api-samples/blob/e9d937a013e4aa1f25b6f7d9bdee0ca985455cfd/samples/render_plugin/plugin.cpp)
  creates a texture at line 377, binds its render resource at line 400, and
  obtains the engine tables/registers Lua entry points at lines 430-446.
- [c_api_material.h](https://github.com/AutodeskGames/stingray-plugin-api-samples/blob/e9d937a013e4aa1f25b6f7d9bdee0ca985455cfd/stingray_sdk/engine_plugin_api/c_api/c_api_material.h)
  declares `set_resource`. It does not declare a current texture-binding getter.

These references establish an upstream architecture for a native Lua module.
They do not establish that the current HD2 fork exposes compatible table layouts.
The existing LLL `sdk/hd2se/include/hd2se_plugin.h` explicitly describes itself as
CONTRACT ONLY and says it implements no native host or Lua binding installation.
It cannot serve as an existing engine bridge.

## Concrete incompatibilities that prevent copying the old adapters

| Surface | Inspected upstream header | Earlier Epic LUT adapter |
| --- | --- | --- |
| Unit lifecycle callbacks | PluginApi fields 16/17; `(CApiUnit **, unsigned)` | callback array fields 23/24; `(world, list, count)` |
| ScriptApi Mesh pointer | field 22, byte offset 176 on x64 | byte offset 232 |
| RenderBuffer create_buffer | field 9, byte offset 72 on x64 | byte offset 96 |
| Mesh commit | no member in inspected public MeshCApi | required native function at a build-specific table slot |

Header sources are `plugin_api.h` lines 149-225 and 1939-1989,
[plugin_c_api.h](https://github.com/AutodeskGames/stingray-plugin-api-samples/blob/e9d937a013e4aa1f25b6f7d9bdee0ca985455cfd/stingray_sdk/engine_plugin_api/plugin_c_api.h)
lines 38-68, and
[c_api_mesh.h](https://github.com/AutodeskGames/stingray-plugin-api-samples/blob/e9d937a013e4aa1f25b6f7d9bdee0ca985455cfd/stingray_sdk/engine_plugin_api/c_api/c_api_mesh.h).
The differing fields are positive evidence against assuming ABI parity. They
are not proof that any one layout is correct for 25988413.

## Remaining service proof

A working port still requires target-build evidence for:

1. Engine-provided `GetApiFunction`, Lua registration/stack table, and their
   lifecycle. A loaded DLL or standard `luaopen` callback alone proves none of
   these interfaces.
2. Render-buffer creation/format/resource identity and queued data lifetime;
   original texture pixels/readback; current material binding reads; exact mesh
   enumeration and commit semantics. Setters alone cannot support ownership-safe
   rollback, undo, export provenance, or cleanup.
3. Current local avatar/garment/equipment ownership and generation-aware handles.
   Generic world Unit enumeration cannot identify the local owner safely.
4. Correct unit/world/equipment lifecycle notifications with main-thread delivery.
   Unchanged state must remain idle; unsupported events cannot be replaced with
   an unbounded scan or repeated reapplication.
5. R6 only: private weapon appearance configuration, selector leases, equip-slot
   identity, and transition recovery. The generic render API does not establish
   these game-specific services.

Once verified, an engine plugin can expose narrow Lua functions with immutable
binary strings and opaque owner/generation tokens. No game address should be
represented as a Lua number, accepted from callers, or reconstructed from old
RVAs. Native writes and texture retirement still require their existing owner
checks and renderer completion proof.

## Main executable static follow-up

The separately fingerprinted main executable above also completed a first
REA/Ghidra analysis. It recovered 18 procedures: entry/guard routines, BCrypt
imports, delay-load thunks and two unnamed locals. No identified Lua engine
registration or texture-wrapper body was recovered. The recorded PDB reference
was stingray_win64_release.pdb, GUID 5d28b30e-5958-4709-8745-1005cd5880bf, age 1;
symbol loading was unknown. The procedure count does not establish an absent
API or a callable runtime layout. No unpacking or protection changes were tried.

The private receipt is
`dist/reviews/steam25988413-main-exe-static-evidence.json`, SHA256
`b719839c7e90c47f05fd382840c743bb1f157408fcca64534e88ad279d1cb57a`.
Both static targets are closed. This route has not supplied the missing runtime
contracts and is not being repeated as another name search.
