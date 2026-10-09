# Player Preview render path

The Helldivers Lua API does not expose `Camera.projection`. Epic derives its
private shader matrices from the plain position, FOV, near and far values saved
alongside the existing owned-camera setters. It uses no camera/matrix getters
for that preparation. A permanent preparation error latches the portrait closed
until an explicit retry, preventing automatic docking from reopening it every
frame.

Epic LUT now selects the game's `ui_3d` viewport for its copied player model.
This is the forward UI pipeline used by the native Armory's Game Default view.
The portrait remains Epic LUT's own model, camera, viewport and colour target;
it does not take over the Armory model widget or reuse its actor.

## What Transmog's two choices actually do

Inspected upstream: [HD2-Transmog, revision
f469851dcb5bf241a08be5329728ca649710896c](https://github.com/tyrypyrking/HD2-Transmog/tree/f469851dcb5bf241a08be5329728ca649710896c).

| Choice | Behaviour |
| --- | --- |
| Game default | `armory_extras.lua:set_model('game')` disables `ArmoryModelRender`, restores the native canvas on the Armory image, and leaves the game's own rendering running. |
| Full render | `armory_model_render.lua` replaces the large-model image with an owned target, submits a `default` viewport, applies its lighting and display composition, and temporarily gates the native UI renderer. |

The inspected game configuration gives `ui_3d` five layers: depth clear,
shadow clear, shadows, `ui_3d_pre`, and `ui_3d`. Its colour layers write the
viewport's `output_rt`. The gameplay `default` configuration has 158 passes,
including temporal rendering and passes addressing shared `output_target`.
See upstream [render-path implementation](https://github.com/tyrypyrking/HD2-Transmog/blob/f469851dcb5bf241a08be5329728ca649710896c/src/armory_model_render.lua)
and [configuration checks](https://github.com/tyrypyrking/HD2-Transmog/blob/f469851dcb5bf241a08be5329728ca649710896c/tests/test_const_config.py).

## Epic LUT's change

`player_preview_native.lua` creates `ui_3d`, binds the private portrait with
`Viewport.set_output_render_target`, clears that target, and submits its own
camera through the existing build-checked Application dispatch. It no longer
copies shared gameplay `output_target` into the portrait after submission.

The first candidate changed only the viewport and output routing. It produced
an empty portrait in-game: selecting `ui_3d` alone did not initialize its
per-material camera constants or select the native UI submission context.

The current candidate also prepares those constants on Epic-owned materials
and submits the verified large-model UI flags/context. It removes gameplay
TAA and the extra global colour-copy dependency. This is still a candidate,
not a measured flicker fix. Back-buffer-sized targets are retained to isolate
the rendering change from resolution and allocation changes.

The initialized UI-world lease is unchanged. Epic only owns the units and
resources it creates there. It never releases that world, writes a native UI
camera slot, changes Armory actors, or takes the scene-manager render gate.
Lease checks, lost-context retention and the render-queue cleanup fence remain
in place before viewport, camera, model or target destruction.

## Material differences and validation

The native UI shader path is simpler than the full gameplay renderer. A
material without `ui_3d` shader passes can disappear; upstream explicitly
identifies hair as an example. This tradeoff also exists in the game's native
Game Default model.

Transmog's `preview_native_backend.lua` is a separate **thumbnail** backend:
it prepares material camera fields through the native unit helper, borrows
the UI environment and shared camera slots, and submits the
`thumbnail_ui_3d` context. Epic uses the large-model contract instead.

Bounded, read-only code inspection of the installed game established:

| Native code | Verified contract |
| --- | --- |
| `game.dll+0x1390778` / `+0x139079f` | Large-model `ui_3d` context `0x1a43b7a8`, flags `0x800f`; thumbnail context is different. |
| `game.dll+0x138f110` | Unit helper ignores its caller's scene pointer and uses the global scene manager. Epic does not call it. |
| `game.dll+0x138f250` | Inner helper accepts `(scene, material, camera_slot, scenario, light_preset)` and reads inline constants from the supplied scene buffer. |
| `game.dll+0x139949e` | Large actors use scenario `0` and select lighting from their actor record's `+0x90` field. |

`player_preview_ui.lua` supplies a private 0x3c48-byte constants buffer.
The camera record stride is 0xf4; Transmog's 0xb0 constant is a **read length**,
not another slot layout. Epic fills the private view/projection/combined
matrix, camera position/direction, resolution and full render rectangle from
its owned camera. It reads only the selected native lighting preset's
0x434-byte block and the eight shadow-resolution bytes. The selected lighting
is relocated into private preset 0, rather than assuming the game's chosen
preset is zero.

The helper writes scenario, camera/rect/resolution, four shadow matrices and
four light vectors to independently owned material instances. Lighting
positions and shadow transforms are rebased for the copied garments' 100-unit
offset. Native camera slots, lights, actors, viewport and world pointers are
never copied into or changed by this buffer. Constants are refreshed only
when the portrait camera changes; affected meshes commit before submission.
The buffer survives until the existing render-queue cleanup fence completes.

Entry signatures and selector/submission bytes are checked before these
contracts are used. Missing camera APIs, changed code or unavailable lighting
are reported as preview errors rather than silently presenting an empty
target. The owned shading environment remains separate from the native UI
environment; matching native colour grade/IBL still needs visual comparison.

Offline checks cover viewport selection, private target routing, the absence
of a shared gameplay colour copy, dispatch signatures, ownership guards and
cleanup fencing. In-game acceptance must still confirm:

1. Armor, helmet and cape appear, and edited LUT colours update the portrait.
2. Moving, resizing, rotating and panning do not flicker or display another
   game view.
3. Opening the Armory while the portrait is open does not contaminate either
   view; closing the editor completes cleanup before returning game input.
4. Missing material cases are recorded separately from texture/loading errors.

No game functions were executed and no process memory was changed to establish
these contracts. Only named code ranges were captured after verifying the game
process, module paths and signatures; captures remain in ignored research
output. Offline checks do not establish visible in-game rendering.
