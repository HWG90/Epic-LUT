# Player Preview poses

Player Preview starts in Idle. Its footer pose selector offers Idle, Salute, Wave, Taunt and High Five in docked and floating previews. Emotes hold a selected frame of the game's authored clip. The preview creates no additional avatar, animation component or simulation world; pose writes affect its existing independent garment copies.

```powershell
python build.py --loader mdl --preview-animation --output Epic-LUT-Garment-Animation-MDL.zip
python build.py --preview-animation --output Epic-LUT-Garment-Animation-BSL.zip
```

The managed development workflow installs matching packages with guarded backups. Selecting the first emote starts a background PowerShell/.NET worker that reads the exact animation/rig resources from the installed game into a local cache. Idle starts no worker. No Python or downloaded animation assets are required. Use one Epic LUT copy and its normal loader lifecycle. Open Player Preview, choose each pose, then check rotation, pan, a live LUT edit, switching back to Idle, closing/reopening and Alt-Tab. Missing pose capabilities leave the static portrait available. Visual acceptance remains an in-game check.

## Motion and ownership

The model records each newly spawned garment's original hierarchy before the static preview flattens its bones under the portrait root. Immutable pose snapshots and bounded named mappings supply the animation driver. The driver changes only independently owned garment nodes; it preserves the portrait root, garment basis and equipped units.

Joint poses are resolved across the complete set of owned garments. The helmet, torso, upper arm, forearm and glove can each supply a different part of the salute chain. A single garment need not contain the complete skeleton. A bounds-checked CPU sampler decodes the authored position, rotation and scale tracks, including all finger bones, and resolves the complete actor hierarchy before retargeting it to the separate copied garments. Captured boss/hips supplies a common rigid placement rather than the starting limb pose.

The body holds its selected authored frame indefinitely. Entry and exit do not repeat, and held body tracks do not advance. The sampler resolves the authored transforms directly rather than creating an engine animation component. No physical cloth simulation is run. The driver updates in focused callbacks with a bounded delta; returning from Alt-Tab starts with zero delta. The existing portrait camera, LUT synchronization, controls and per-frame redraw path stay shared. A pose change retires the previous copied model through its normal render fence before rebuilding; the latest selection wins while retirement is pending.

Callbacks with no delta use the existing measured frame clock; numeric one-argument callbacks are also accepted. Diagnostic one-frame requests end on closing and do not freeze later UI openings.

Model/world membership, source liveness, bone counts and captured ownership are checked before pose writes. The driver owns Lua pose state rather than additional native units/worlds. Retirement stops those writes first and preserves the normal renderer fence before garment destruction. Pending cleanup dismisses the editor and releases its cursor without discarding native receipts.

Tests cover compressed/uncompressed animation channels, exact hand/finger orientation, rig forward kinematics, segmented garment retargeting, nonunit scale, preserved roots, cape motion, immutable math values, pause/delta bounds, malformed data and stale ownership. Integrated fixtures cover redraws, camera controls, focus suspension, static fallback and the renderer fence.

## October 9 crash investigation

The previous candidate independently spawned `content/fac_helldivers/cha_avatar/avatar_helldiver` (`4d1c334d294dfa97`) into a bare `Application.new_world()`. Its first native test crashed. That path has been removed from the active animation service.

The saved dump reports `0xc0000005` at `helldivers2.exe+0x7feba1`. Instructions in the faulting function index a global component table with `0xffffffff` before checking it, then allocate skeleton-dependent storage and retain a unit-like ID. The captured bone count is 90. This strongly suggests failure during animation-component creation in a world whose game-specific manager was unavailable; the dump does not contain enough caller code to identify the precise exported API. Resource availability and post-spawn checks could not protect a crash inside spawning itself. Lua `pcall` does not contain a native access violation.

The generic Stingray API documents bare world creation, string resource/node/event arguments and animation/scene updates. Those contracts alone do not establish Helldivers' native initialization requirements. [Application reference](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/ns_stingray_Application.html), [Unit reference](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/obj_stingray_Unit.html), [World reference](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/obj_stingray_World.html).

The authored sampler uses the clips identified by the captured graph: `lineup_idle` (base layer 0/state 59), `action_salute_01` (layer 8/state 176), authored completion into hold 178, and `action_salute_exit` into exit 177 and then state 0. Its ordered clips are `759c08277f1296d0`, `070b422612518deb`, `e32b270524630569` and `39250e5b6313a0b2`. These facts were decoded with bounds checks against SDK revision [5a886256](https://github.com/Boxofbiscuits97/HD2SDK-CommunityEdition/tree/5a886256e54db52b5d228335eae20ce796f87fc0). Game resources, dumps and captured binaries remain ignored evidence and are excluded from packages.

The selectable catalog also uses `action_wave_01` (layer 8/state 199, `f7d81dbe0142b9ee` at 0.58 seconds), `emote_taunt` (layer 8/state 135, `a4950a590f729419` at 0.4 seconds), and the High Five offer hold (layer 8/state 139, `75205314048dcdaa` at zero). All three clips decode against the same 90-bone rig with non-additive transforms. The selected frames were checked through bounded decoding and joint transforms; their visual appearance still requires in-game acceptance.
