# Cosmetic blood research

Research date: October 8, 2026. Static inspection only; no blood effect was triggered in the live game.

## Finding

The equipped garment materials contain authored blood controls separate from their LUTs. This gives us a concrete route to investigate **cosmetic blood on the owned Player Preview copy**, without damage events or player-state changes. It does not yet establish a working blood trigger on the actual player.

The screenshot's wound, dismemberment, and blood splatter are separate effects. A blood overlay control will not necessarily reproduce the injury pictured, and the unresolved preview limb caps should not be treated as evidence that blood is already working.

## Controls found in actual game materials

The existing read-only preview research contains these material resources used by the captured leg garments. Their serialized variable records were decoded using the [SDK material layout](https://github.com/Boxofbiscuits97/HD2SDK-CommunityEdition/blob/main/stingray/material.py), then matched against the [SDK shader-variable catalog](https://github.com/Boxofbiscuits97/HD2SDK-CommunityEdition/blob/main/hashlists/shadervariables.txt).

### Cloth material `102255634838df73`

| Runtime variable | Hash | Type | Authored value |
| --- | --- | --- | --- |
| `blood_weights_positive` | `0955ef2e` | Vector3 | `(0, 0, 0)` |
| `blood_weights_negative` | `26102c1e` | Vector3 | `(0, 0, 0)` |
| `blood_color` | `5461f4e2` | Vector3 | Approximately `(0.251, 0, 0.051)` |
| `blood_scale` | `2b05328b` | Scalar | `0.25` |
| `blood_normal_fade` | `0c4b94a3` | Scalar | `0.5` |
| `blood_gunk_normal_intensity` | `d7aaa0c3` | Scalar | Approximately `0.7` |

Its `blood_splatter_tiler` texture slot (`30e2d136`) references texture `e21128ca48e27a13`.

The positive and negative vectors suggest directional coverage weights, but their axis order, useful range, and exact appearance require visual confirmation.

### Skin/cap material `a781f50f508ed81b`

| Runtime variable | Hash | Type | Authored value |
| --- | --- | --- | --- |
| `blood_overlay_amount_forward` | `a2e5da88` | Scalar | `0` |
| `blood_overlay_amount_backward` | `15fbd61a` | Scalar | `0` |
| `blood_overlay_amount_left` | `5b3fcc63` | Scalar | `0` |
| `blood_overlay_amount_right` | `5cbf4915` | Scalar | `0` |
| `blood_overlay_amount_up` | `68d926c7` | Scalar | `0` |
| `blood_overlay_amount_down` | `83701be7` | Scalar | `0` |

Its `blood_overlay_normal_grayscale` texture slot (`a856db0d`) references texture `4656ac419388a0d4`. It also defines blood color, metallic, roughness, normal-blend, and mask controls. It is shared by skin surfaces outside the knees; changing or hiding every occurrence would affect more than the caps.

The catalog uses PascalCase display labels. The lower-case snake-case runtime names above were independently hashed with the [SDK Murmur32 implementation](https://github.com/Boxofbiscuits97/HD2SDK-CommunityEdition/blob/main/utils/hashing.py); every result matched the variable ID serialized in these materials. Passing the PascalCase display label would target a different hash.

## Available API and current boundary

The documented Stingray API provides [Material.set_scalar and Material.set_vector3](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/obj_stingray_Material.html). Epic LUT already uses material setters for GUI rendering. The native Player Preview adapter verifies that each copied material differs from its source before changing copied texture bindings.

A focused future probe can retrieve the cloned mesh's material handle through `stingray.Mesh.material`, verify its identity against the owned copy, check the setter functions exist, and change only the controls actually present in that resource. The adapter can commit the copied mesh using its existing validated commit path.

The generic documented Material API has setters but no scalar/vector getters. Authored archive defaults are **not** a snapshot of a player's current blood state. The game may already have changed those values, and may overwrite them again through its own cosmetic system. This is why direct writes to the actual player's materials are not ready to implement with reliable restoration.

## Smallest useful next experiment

1. Add an optional preview-only diagnostic after the setter and owned-material handle are verified in the running game.
2. On the cloned cloth material, change one blood-weight component at a time and record which surface responds. Use the known blood texture already bound to that material.
3. On the cloned skin material, try one directional overlay amount at a time. Keep wound painting, mesh visibility, and damage systems unchanged.
4. Reset by destroying and rebuilding the owned preview model, which discards its independent material instances. Do not pretend setting all values to zero restores an arbitrary live source.
5. If the visual effect works, expose one collapsed **Preview Effects** section with coverage and Reset. Keep it out of LUT DDS and patch exports because these controls belong to material state, not table pixels.

The actual player's body needs an identified cosmetic-system interface or an exact live-value capture/restore mechanism, local-ownership guards, and separate visual validation. No such blood-specific API was found in the maintained Epic LUT, DBF, or standalone LLL sources searched here.

## Decal alternative

Autodesk documents [runtime decal projectors](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/stingray_help/lighting_rendering/shading_and_materials/project_decals.html), but they affect every intersecting opaque mesh and cannot exclude individual units. Their resource availability and skinned-body behavior in Helldivers 2 are unverified. They are a weaker first experiment than the blood controls already present in the actual garment materials.

## Local evidence

The ignored `dist/blood-research/authored-material-controls.json` records decoded variable types, exact hashes, authored values, and blood texture IDs. Supporting SDK files are downloaded into that ignored folder. Game material binaries remain in the existing ignored research directory; none are included in source or release packages.
