# R6 weapon LUT discovery

The first live read-only probe mapped the local **BR-14 Adjudicator** to two material LUTs and one Pattern LUT. Its configuration resource is `5fecab819f96a3e8`. The inventory primary remained the target while the player held a secondary, and its verified engine reference matched a genuine Lua Unit returned by the live World.

The cooperative resource scan completed all **2,355 catalog IDs** and resolved these bound tables:

| Material section | Runtime material index | Table resource | Dimensions | LOD bindings |
| --- | --- | --- | --- | --- |
| `m_weapon` (`7c4a4a11`) | 0 | `babd338977faa2ff` | 23 × 8 | 5 |
| `m_weapon` (`7c4a4a11`), Pattern | 0 | `cf0cc31b981786c9` | 3 × 1 | 5 |
| `m_rail` (`06fea65d`) | 1 | `d1c943c12a564150` | 23 × 8 | 5 |

These bindings belong to runtime mesh indices **4–8**. The four shadow meshes at indices **0–3** were excluded. The fifteen bindings resolve to **three unique tables**; preserve every destination when deduplicating their data.

Original DDS data was captured from serialized archive `18235e0c9ec0e636`. This establishes the containing archive. The SDK's base-patch policy targets `9ba626afa44a3aa3`; winning in-game behavior of a generated weapon patch still requires separate installation and verification.

## Link's Link to Memory test bridge

The diagnostic bridge in `tools/links_weapon_probe` uses ApenasLink's Link's Link to Memory addon to run the same guarded R6 identity and discovery modules on the game thread. It is a development tool, not a package dependency. Its initial read-only pass on October 12, 2026 resolved the entire 2,355-ID catalog and captured 25 destinations:

| Equipped weapon | Material LUTs | Pattern LUT | Destinations |
| --- | --- | --- | --- |
| BR-14 Adjudicator | `babd338977faa2ff`, `d1c943c12a564150` (23 × 8) | `cf0cc31b981786c9` (3 × 1) | 15 |
| P/40-K Bolt Pistol (`dbb6c961c59fadc1`) | `77e6377816d402cc` (23 × 8) | `cf0cc31b981786c9` (3 × 1) | 10 |

The support inventory slot was empty. Each listed table has five LOD bindings. Both weapons use the same original Pattern texture; this does not make their material destinations interchangeable. Preserve per-weapon destinations and fork applied textures at those bindings. Never replace the shared stock texture globally.

The pass performed no texture allocations, binds, commits or memory writes. Original DDS headers independently confirmed the dimensions above. These results establish mapping, not rendered editing or export behavior. Logs, live pointers and extracted originals remain in private review output.

## Probe contracts

- [primary_identity.lua](../src/weapons/primary_identity.lua) reads the inventory primary independently of held-weapon selection. It gates the supported executable/build and checks bounded player, avatar, inventory, entity and engine-reference ownership. `validate()` checks build/layout; `snapshot()` supplies the current identity proof.
- [lut_catalog_match.lua](../src/weapons/lut_catalog_match.lua) compares loaded texture objects with exact resource IDs in bounded chunks. It retains every matching alias, checks current identity before and after each chunk, and refuses stale or failed lookups.
- [weapon_lut_probe/main.lua](../tools/weapon_lut_probe/main.lua) connects those adapters to genuine Lua Unit discovery and verified native material/binding reads. It rechecks current identity across yields and performs no native writes.

## Editor candidate

The R6 worktree adds independent local Primary, Secondary and Support discovery and binding sessions. The Weapons workspace routes material and Pattern tables through the existing LUT/Value Editor. Import mapping, Auto-map/rollover, schema 4 presets, Armory previews and EL6 transport retain exact weapon configuration IDs and every LOD destination. Focused fixtures cover raw float32 values, differing palettes within a LOD group, stale ownership and transactional restoration.

Weapon patch encoding isolates its Unit/material assignment even for one palette; a Pattern texture may also be used by garments. Exact assignment and effective source proof are required before creating patch files. The containing DDS archive does not determine the export target.

The integrated UI retains its workflow factories across addon activation. Apply, Restore and import mapping record global Undo/Redo. A material's quick Pattern controls target only that material's certified companion bindings, even when a sibling material shares the same original Pattern texture. The quick swatches read the selected companion's applied values.

Save applied setup stores weapon DDS palettes with complete version 4 assignment proofs in a private setup snapshot. Startup matches configuration, named MeshID, SectionID, material slot, texture role and effective source digests before applying exact subsets. Discovery and cache waiting run cooperatively. Manual weapon edits cancel a queued restore; unavailable, changed or unresolved saved assignments retain the previous snapshot. A cold proof cache cannot silently turn a weapon save into a gear-only setup.

Ordinary Armory palette saves remain available while assignment sources are loading. They report incomplete patch proof; export can reconstruct missing references only against the exact equipped weapon, original texture and unchanged applied palette. Existing complete references remain usable independently of the currently equipped weapon.

## Exact effective assignment sources

Weapon export uses a separate `weapon_effective` cache mode. It resolves the requested Unit and its linked Materials from the current packed and loose-patch scope, preserving complete main/GPU/stream parts and TOC flags. Identical repeated global SectionID associations are deduplicated for identity lookup while their physical rows and offsets remain intact. Conflicting Material IDs or distinct loose overrides refuse; filename order is not treated as archive priority proof. Garment stock-mode caches remain separate.

The supported game exposes a read-only `Mesh.name(genuine_mesh)` query returning a signed int32 MeshID. The identity helper normalizes that representation, matches a unique serialized MeshID, and rechecks the genuine Unit receipt, Mesh pointer, hash, named Material pointer and exact local slot. A numeric runtime mesh index finds a handle only; it never chooses a serialized mesh record. The hash is never passed to numeric `Unit.mesh`, whose numeric argument is an index. Older APIs retain the verified literal-name path.

On October 13, the same production helper proved all 25 material/Pattern assignment chains against the effective Adjudicator and Bolt Pistol Unit layouts in game. This includes a customized Adjudicator LOD with a changed material-slot order and Bolt Pistol meshes with unknown literal names. This is live read-only assignment proof; it does not establish texture creation, restoration or winning patch rendering.

Weapon patch serialization preserves effective Unit/Material bytes and forks assignments at the verified mesh slot. The base archive target follows the SDK's `PatchBaseArchiveOnly` policy for Unit, Material and Texture records, independently of the archive that supplied each source. The exported weapon patch remains a candidate until installation and in-game rendering have been checked.

## Native apply and restore pilot

On October 13, the authorized two-second Adjudicator pilot changed first-row Base RGB to magenta on all five body LOD bindings using the production weapon runtime. It retained one 2,944-byte texture backing buffer, then restored all five exact original native texture pointers. Other captured primary/secondary material and Pattern bindings stayed unchanged, and the game remained running. The user confirmed the visible change and restoration.

This proves the tested body apply/restore path. It does not identify the trigger of the earlier native crash, which occurred before any recorded texture allocations or binds.

The private actual-data export audit also verified all 25 saved assignment references, distinct Pattern forks, preserved Unit/GPU/stream and Material bytes, collision-safe resource IDs and byte-identical repeat output. That archive was not installed as part of this audit.

## Remaining validation

The integrated editor, startup restoration, Pattern edits, held/holstered checks, swaps, drops/replacements, death and respawn still need live acceptance. Secondary/support rendering, remote sharing and winning archive/assignment-aware export behavior also require live proof. Serialized fixtures do not establish in-game results.

Private captures, logs, screenshots, session identities and game data remain outside public source and packages. See [R6-CLEANUP.md](R6-CLEANUP.md) for the branch and feature plan.
