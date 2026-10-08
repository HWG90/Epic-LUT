# Player preview candidate

The implementation consists of an independent lifecycle controller, garment-copy
module and native adapter. It is excluded from normal release packages.
`tools/build_player_preview.py --base <editor mod.lua>` creates a separate F6
candidate around an existing editor. Never use an already wrapped candidate as
its base.

The model adapter must assemble an owned character from the local player's body,
armor, helmet and cape kit identifiers. Spawning the avatar resource alone is not
equivalent to constructing its attached gear. It must not register the copy as a
network player or reuse the live player's units.

The controller creates an owned world, assembled model, camera, texture target,
viewport and floating panel. Cleanup runs in reverse order, including failed setup.
Failed cleanup receipts are retained and prevent reopening until cleanup succeeds.
Palette revisions update the copy once per change. Rendering is submitted only
from the render callback. Gear changes require closing and rebuilding the preview.

The garment adapter duplicates the already loaded equipped resources into its own
world, copies their scene graphs and root-relative transforms, and preserves mesh
visibility and material texture bindings. It refuses shared source material
instances. It does not create another network avatar. The initial model is frozen;
cape assembly, rotation and dragging remain unfinished.

## Current evidence and rollback

The October 7 candidate loaded and copied 18 equipped pieces successfully in game.
Its owned camera, target and viewport were created and rendering submitted. Game
back-buffer captures confirmed that the floating GUI was visible after moving it
from the main world to the editor's UI world. The portrait remained blank: this
does not prove successful character rendering.

That candidate subsequently crashed with access violation
`helldivers2.exe+0x99d7cd`, reading address `0x58` through a null RAX. Dump evidence
and the exact installed candidate were saved in the ignored
`dist/releases/player-preview-candidate` review folder. The fault instruction is
a native null dereference; the leading frame alone does not identify the initiating
Lua operation or prove cleanup as its cause.

The latest pre-preview installed editor was restored and its normal reload was
confirmed. Its SHA256 is
`5df5ff9db354a24fe600bf5193d3c62d1e2673fad7b83d1cc6a8f6d588f53fb6`.
The preview trigger file was removed. The current source includes an untested
alternative using a default viewport and owned lights; that alternative was NOT
installed at the time of the crash and must not be described as tested.

Next work: review rendering context and deferred cleanup, isolate portrait render
resources, establish visible model pixels, then validate color updates and the
floating panel controls. The existing Armory viewport writes to shared screen
output and cannot be treated as a ready-made portrait texture.

Offline lifecycle tests do not establish native rendering or model assembly.
Lua error containment cannot catch a native engine crash.

## October 8 findings

The second test crashed on its first submission, before cleanup. The game's own
CRS dump is the primary evidence: integer divide by zero (`0xc0000094`) at
`helldivers2.exe+0x8e2b06` on the renderer thread. The later Windows dump captured
an additional failure in the crash handler; it must not be used as the primary
fault. The faulting jitter calculation truncates `8 * (output_width / reference_width)^2`.
At 384 / 3840 it becomes 0.08, then integer zero, which becomes the divisor.

The candidate now uses a back-buffer-sized target and a full viewport rectangle.
Its small GUI portrait samples a central UV crop. The running game survived this
single-frame test and subsequent captures, but the portrait was still empty.
A diagnostic composite confirmed black target pixels; visible model rendering
remains unproven. The next task is to inspect cloned geometry/camera bounds and
render-output routing rather than continue guessing at cleanup.

Live source inspection found 18 pieces, 91 visible meshes, 402 scene nodes and
4 player-root nodes. The copy now bakes world-node poses under its own root so
it does not depend on the player's cross-unit bone links.

Shutdown originally called a nonexistent `engine.create` helper. The correct
adapter is `engine.create_texture(native,width,height,data,read,buffer)`.
The running owner was recovered with a bounded, owner-checked compatibility shim.
Its pending queue drained and panel, viewport, camera, pieces, world and target
were released without restarting the game. The maintained candidate uses the
correct helper; render failures defer cleanup to update, and targets outlive worlds.

The investigation is now a separate `epic_player_preview` LLL mod. The normal
editor is no longer wrapped or replaced. Build with
`python tools/build_player_preview.py --standalone`, optionally `--inspect-only`;
run `python tools/verify_player_preview.py` for focused offline verification.
The temporary recovery mod has been replaced by an inert descriptor.

## Geometry and output routing

The gameplay actor's four-node root uses a different origin from its visual
garments. Normalizing garment poses against that actor placed every copied root
about 229 metres from the fixed preview camera. Normalization now uses an armor
garment's shared visual root; live logs confirm copied roots at `(0,0,0)`.
The camera is fitted to the rotated bounds of the copied meshes instead of a
fixed assumed position. Offline tests explicitly cover differing gameplay and
visual origins.

The default render layer also names `output_target` directly. The candidate
copies this named output into its privately owned GUI target with the shipped
copy generator. Visible character pixels have not yet been verified after the
origin correction. Another crash was reported during this test, and F6 was
pressed accidentally. The installed test mod was replaced with an inert
descriptor before restart. Development hotkey activation is now disconnected;
future tests use explicit single-frame requests.

Next: identify the primary exception for the latest crash, inspect the native
render submission contract and independently validate output routing. Keep the
separate test mod isolated from the concurrently edited LUT editor.

## Initialized-context candidate

A build-checked native submission adapter now validates Application API update
and render addresses and their 32-byte signatures before use. Its world
unboxing and exact eight submission arguments have focused offline coverage;
live read-only preflight matched the inspected implementation. A single draw
through that path still crashed, so the call wrapper alone is not a verified fix.

Read-only inspection then resolved the engine's initialized UI render world
through its scene-manager identity, without a hard-coded world index. This
context was available during normal ship use. The next candidate leases that
context and creates its own garment copies, camera, viewport and target. Copies
are moved 100 units away from the game preview actors and framed by their bounds.
The adapter never releases the borrowed world or updates its simulation; it
updates/destroys only its own units and resources. Tests explicitly reject
release of the borrowed world, and liveness checks precede rendering/cleanup.

The initialized-context candidate now renders the independently copied model.
A game back-buffer capture proves visible character geometry, and David
confirmed that Armor/Helmet color edits also change the copied character.
Repeated candidate reloads drained the render queue and released owned
resources while the game remained responsive. These are development results,
not proof of stability across every game screen or equipment transition.

## Floating-panel controls

The separate LLL test mod exposes `epic.player_preview.v1` only while enabled.
Basic and Import / Apply show an optional Player Preview toggle when that
service is present. F6 now toggles the pop-out on other pages and switches
dock/pop-out mode on LUT Editor. `preview_key=117` in
`settings/epic_lut_preferences.ini` is its default Windows virtual-key code;
Configuration also exposes a keybind control, and the footer shows its label.
The portrait has a draggable title, X close button and bounded zoom controls.
Dragging its lower-right grip scales the window with a fixed portrait aspect
ratio and screen bounds. Right-dragging the model orbits the camera through
a full 360 degrees; left-drag pans within 25 percent of the frame in either
direction. Mouse wheel zoom applies only over the panel. Camera component
poses are updated directly without running the borrowed world's simulation.
The title offers Pop Out / Dock; the dock fills the grid's reserved right area.
Pointer handling uses the editor's existing focused input and suppresses
click-through into its palettes. Closing restores the original input function.
Panel position, size, rotation and zoom survive reopen within a run; no settings are written.
Losing focus or hiding the editor cancels a pending drag. Once per second,
the preview compares worn kit IDs and garment unit IDs to its captured source;
an equipment change schedules a bounded rebuild instead of displaying old gear.

Offline checks cover dragging, close hit testing, zoom limits, cleanup and
native ownership. The installed controls and model are visible in a game
capture. Actual pointer interaction and context-loss recovery still need live
verification. Recovery retries at most three times when a copied garment or
source disappears, and explicit close cancels retries.

`tools/build_player_preview.py --standalone` also produces an isolated LLL test
ZIP containing only the generated Lua mod, setup notes and CowboyBingus license.
It excludes captures, logs, dumps, game assets and saved settings.

## Armory transition crash - candidate disabled

David reported a crash entering game Armory with the pop-out open. The game
process exited; the final preview log ends after its fence drained, panel
released, and viewport release began. The two Windows dumps report
`0xc0000026` in ntdll; the corresponding game dump is zero bytes, so it does
not establish the primary cause. Exact installed code and logs are preserved
privately under the candidate evidence folder. The installed sidecar has been
replaced by an inert descriptor, and the previous ZIP is labeled unsafe.

Guards now close with the editor before game UI transitions, validate
both the scene-manager lease and underlying native world identity before
rendering/editing/viewport destruction, and skip stale-handle cleanup when that
lease is lost. A potentially referenced target is retained instead of freed;
the retained-target count is capped and further opens require restart.
Offline regression checks cover lost-lease cleanup without native destructor
calls and editor-close input restoration. The paired guarded build was installed
after its editor and sidecar hooks matched. David then confirmed that opening
the game Armory terminal after closing Epic LUT succeeded without crashing;
the live log records complete cleanup through target release. This proves the
reported sequence once, not every possible game transition.

The standalone frontend now asks `before_editor_close()` before releasing game
input. If preview cleanup is pending, it keeps input captured and retries on
the next update. A focused test proves that input is not released until cleanup
returns true. This removes the observed cursor-release-before-viewport-cleanup
ordering. Rotation and bidirectional dock/pop-out verification remain pending.
