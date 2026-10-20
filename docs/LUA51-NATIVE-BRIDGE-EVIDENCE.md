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
