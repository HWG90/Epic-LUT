# Public engine API reference findings

The approved build-25988413 Lua 5.1 inventory contains 682 raw members in the
selected namespaces. Its private source is
`dist/engine-api-inventory/captured-config.cfg`. It proves member presence/types,
not accepted arguments, return values, side effects, or successful LUT behavior.
This follow-up made no engine calls and did not change the native broker.

## Documented upstream surfaces

The following are primary Autodesk references for the upstream engine. Current
HD2 compatibility still needs separate evidence.

| Surface | Documented meaning | LUT implication |
| --- | --- | --- |
| `Mesh.material(mesh, slot)` | Returns a Material for a named or numeric slot; `has_material` / `num_materials` establish valid slots. | Candidate public mesh/material enumeration, not texture readback. [Mesh reference](https://help.autodesk.com/cloudhelp/2021/ENU/Max-Interactive-Help/lua_ref/obj_stingray_Mesh.html) |
| `Material.id(material)` | Returns the material ID. | Identity alone does not reveal a texture assignment. [Material reference](https://help.autodesk.com/cloudhelp/2021/ENU/Max-Interactive-Help/lua_ref/obj_stingray_Material.html) |
| `Material.set_resource(material, slot, resource)` | Assigns a RenderResource to a named texture slot. | Documented setter; current getter absent from the captured Material raw table. [Material reference](https://help.autodesk.com/cloudhelp/2021/ENU/Max-Interactive-Help/lua_ref/obj_stingray_Material.html) |
| `Material.set_texture(material, slot, texture)` | Assigns a texture resource name to a named slot. | The local `vendor/menu/view.lua` also supplies IdString64 values for a GUI font atlas; that source usage is not a gear-binding test. [Material reference](https://help.autodesk.com/cloudhelp/2021/ENU/Max-Interactive-Help/lua_ref/obj_stingray_Material.html) |
| `Unit.query_material(unit, start, end, contexts)` | Performs a raycast and returns material context IDs. | It is not a current texture-binding getter. `material_id(name)` supports that raycast query. [Unit reference](https://help.autodesk.com/cloudhelp/2021/ENU/Max-Interactive-Help/lua_ref/obj_stingray_Unit.html) |
| `Unit.get_property(unit, properties...)` | Reads a numeric property path. | No documented resource/texture-object getter; do not assume it returns LUT bindings. [Unit reference](https://help.autodesk.com/cloudhelp/2021/ENU/Max-Interactive-Help/lua_ref/obj_stingray_Unit.html) |
| `Application.get_data(indices...)` | Reads the global script-data object used by `set_data`. | It does not expose C-function signatures or render-buffer internals. [Application reference](https://help.autodesk.com/cloudhelp/2021/ENU/Max-Interactive-Help/lua_ref/ns_stingray_Application.html) |
| `RenderBuffer.create_buffer(validity, view, stride, data)` | Creates a buffer from a numeric table; `update_buffer(handle, component_type, data)` changes it. | Presence of texture constants does not establish supported texture-view creation. [RenderBuffer reference](https://help.autodesk.com/cloudhelp/2021/ENU/Max-Interactive-Help/lua_ref/obj_stingray_RenderBuffer.html) |
| `Renderer.create_resource(type, format, width, height)` | Upstream documentation limits it to `render_target` and `R8G8B8A8`; `resource(name)` resolves an existing GPU resource. | These documented arguments do not establish an RGBA32F LUT creation/update path. [Renderer reference](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/ns_stingray_Renderer.html) |

A [2017 Autodesk developer response](https://forums.autodesk.com/t5/stingray-forum-read-only/version-1-6-and-procedural-meshes/m-p/6742727/highlight/true)
reported that Lua `create_buffer` supported vertex/index views, with procedural
textures available through C++. This is historical evidence against assuming
every exposed RB constant is supported by the Lua creator, not proof of a
limitation in the current HD2 fork.

## Captured extensions with unverified signatures

The current inventory includes `Application.update_raw_buffer`,
`Mesh.refresh_instance_hash`, `Renderer.update_texture_base64`,
`Mesh.material_slot_id`, `Material.id64`, and `Unit.resource_name`. Exact HD2
signatures and semantics were not found in the inspected official reference
pages or the focused Epic LUT / canonical LLL source searches. In particular:

- `refresh_instance_hash` must not be treated as a proven mesh-commit replacement
  merely because its name suggests a refresh.
- `update_raw_buffer` / `update_texture_base64` do not prove arbitrary float-LUT
  writes, dimensions, ownership, or queued-data lifetime.
- `Material.id64` / `Unit.resource_name` may assist resource identity once their
  contract is established; neither name supplies current texture pixels.

Lua 5.1's [debug information contract](https://www.lua.org/manual/5.1/manual.html#lua_Debug)
has no general C-function parameter/signature schema. The inspected LLL source
uses debug information for source/log identity, not engine API documentation.
No loader-owned argument-metadata service was identified. Calling undocumented
functions with guessed arguments to obtain errors would be another live probe,
not a consequence of the metadata-only inventory approval.

## Remaining proof boundary

Public enumeration and setters are promising. A complete ownership-safe LUT
implementation still needs evidence for current effective texture assignments,
original pixel acquisition, RGBA32F texture creation/update, refresh/retirement
semantics, and local-owner lifecycle identity. Serialized stock resources can
supply verified original data, but cannot establish a live assignment after
kit overrides, private weapon configuration, or another mod's changes.

The next useful source evidence is an authored HD2 Lua call site or build-matched
API declaration for the unverified extensions. No current signature or complete
provider is inferred from the member names alone.

## Additional authored HD2 call shape

A distinct public-source pass found
[GooseGadgets wall_terminal.lua:398-431](https://github.com/HWG90/GooseGadgets/blob/9025f45aac89beea9fc39f69ffcf1ec26a2a3cc8/Bridge%20Combat/terminal-0.1.14/compat/lll-0.1.14/src/wall_terminal.lua#L398)
at revision 9025f45aac89beea9fc39f69ffcf1ec26a2a3cc8. It creates a
render_target/R8G8B8A8 resource, obtains Unit.mesh then Mesh.material, assigns
Material.set_resource(material, 'input_image', texture), and calls
Mesh.refresh_instance_hash(mesh). This supplies authored setter/refresh argument
shapes, not target-25988413 execution, RGBA32F creation, readback or retirement
proof. No LUT adapter was inferred from the terminal implementation.

Focused primary-source searches at recorded revisions of HD2Runtime,
HD2WeaponEditor, HD2SDK-AQ-Edition, HellDivers2-SDK, BingusSharedLoader and
VanillaPlusMegapack found no additional authored update_texture_base64,
update_raw_buffer or float-texture upload contract. Repeating namespace searches
is not a replacement for those missing contracts.
