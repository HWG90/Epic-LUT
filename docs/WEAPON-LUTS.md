# R6 weapon LUT discovery

The first live read-only probe mapped the local **BR-14 Adjudicator** to two material LUTs and one Pattern LUT. Its configuration resource is `5fecab819f96a3e8`. The inventory primary remained the target while the player held a secondary, and its verified engine reference matched a genuine Lua Unit returned by the live World.

The cooperative resource scan completed all **2,355 catalog IDs** and resolved these bound tables:

| Material section | Runtime material index | Table resource | Dimensions | LOD bindings |
| --- | --- | --- | --- | --- |
| `m_weapon` (`7c4a4a11`) | 0 | `babd338977faa2ff` | 23 × 8 | 5 |
| `m_weapon` (`7c4a4a11`), Pattern | 0 | `cf0cc31b981786c9` | 3 × 1 | 5 |
| `m_rail` (`06fea65d`) | 1 | `d1c943c12a564150` | 23 × 8 | 5 |

These bindings belong to runtime mesh indices **4–8**. The four shadow meshes at indices **0–3** were excluded. The fifteen bindings resolve to **three unique tables**; preserve every destination when deduplicating their data.

Original DDS data was captured from serialized archive `18235e0c9ec0e636`. This establishes the containing archive. The winning patch export destination still requires independent provenance validation.

## Probe contracts

- [primary_identity.lua](../src/weapons/primary_identity.lua) reads the inventory primary independently of held-weapon selection. It gates the supported executable/build and checks bounded player, avatar, inventory, entity and engine-reference ownership. `validate()` checks build/layout; `snapshot()` supplies the current identity proof.
- [lut_catalog_match.lua](../src/weapons/lut_catalog_match.lua) compares loaded texture objects with exact resource IDs in bounded chunks. It retains every matching alias, checks current identity before and after each chunk, and refuses stale or failed lookups.
- [weapon_lut_probe/main.lua](../tools/weapon_lut_probe/main.lua) connects those adapters to genuine Lua Unit discovery and verified native material/binding reads. It rechecks current identity across yields and performs no native writes.

## Editor candidate

The R6 worktree adds independent local Primary, Secondary and Support discovery and binding sessions. The Weapons workspace routes material and Pattern tables through the existing LUT/Value Editor. Import mapping, Auto-map/rollover, schema 4 presets, Armory previews and EL6 transport retain exact weapon configuration IDs and every LOD destination. Focused fixtures cover raw float32 values, differing palettes within a LOD group, stale ownership and transactional restoration.

Weapon patch encoding must isolate its Unit/material assignment even for one palette; a Pattern texture may also be used by garments. It requires a separate verified patch destination and never substitutes the garment export archive from the containing DDS archive. Until that destination is proven, a weapon patch export refuses before creating files.

## Remaining validation

This result proves source and live native binding discovery for the tested Adjudicator. The editor candidate still needs live scoped writes/restoration, held/holstered checks, swaps, drops/replacements, death and respawn. Secondary/support rendering, remote sharing and winning archive/assignment-aware export behavior also require live proof. Serialized fixtures do not establish in-game results.

Private captures, logs, screenshots, session identities and game data remain outside public source and packages. See [R6-CLEANUP.md](R6-CLEANUP.md) for the branch and feature plan.
