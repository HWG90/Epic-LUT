# R6 code cleanup checkpoint

The cleanup preserves R5 controls, stored settings, DDS/preset formats and native ownership rules. R6 is not published by this checkpoint.

## R6 feature direction

Develop R6 on `r6/weapon-lut-editing` in the linked OneDrive `Epic-LUT-R6` worktree. R5.x maintenance continues on `main` in `Epic-LUT`. Commit R5 fixes there, then merge `main` into the R6 branch to carry those fixes forward. Keep weapon development and R6 release preparation on the feature branch.

Weapon LUT editing is the headline feature for R6. The proposed starting scope is the local player's equipped primary, secondary and support weapons. Reuse the table and Value Editor, exact RGBA editing, history and binding-session restoration.

The first milestone is read-only weapon discovery: prove the owning player, equipped slot, live Unit, material section, texture resource and supported LUT dimensions. Check held and holstered representations, weapon switches, dropped/replaced weapons, death and respawn before enabling writes. The current avatar collector enumerates garment arrays; weapon discovery needs its own verified path.

Release work then connects verified weapon targets to:

- Live color, material and compatible camo controls, with weapon-specific labels confirmed from their tables.
- Import mapping and Auto-map, scoped to the selected weapon's proven LUT destinations.
- Named presets and assignment-aware patch exports, with old outfit presets retained.
- Shared LUT appearances, using explicit weapon identities and destinations in a versioned sharing format.

Weapon families must be explicit in discovery, presets and sharing. Current garment-only schemas and the shared destination bounds cannot represent weapons by adding a selector alone. Shared changes retain BSL, modular LLL and MDL package parity; rendered weapon edits and exported assignments need in-game verification.

## Implemented

- Native writes and restoration: `binding_session.lua`.
- Local gear discovery/application scopes: `gear_catalog.lua`.
- Worker protocol/lifetime/cooperative indexing: `import_protocol.lua`, `import_job.lua`, `table_index.lua`.
- Armory collection management: `armory_collection.lua`; native application remains coordinated by the editor.
- Configuration and stable control definitions: `configuration.lua`, `editor_registry.lua`.
- LUT editing split from view/control schema: `lut_editor.lua`, `lut_editor_view.lua`, `lut_editor_controls.lua`.
- Bounded file reads/named DDS storage: `file_io.lua`, `lut_files.lua`.
- Preview input ownership: `player_preview_input.lua`; cleanup ordering preserved.
- Shared immutable control help; private edit-session record and operations table.
- History document copying deduplicates aliases and accounts for original buffers.
- Integrated preview reuses native adapter modules, each embedded once.
- Pinned StyLua style, explicit bundle inventory and isolated shared LuaJIT test runner.

## Acceptance evidence

Editor contracts cover stock/current palettes, scoped painting, undo/redo, cumulative application, original restoration, foreign ownership, stale membership and partial native failure. Additional tests exercise the extracted services directly.

Preview tests cover source/model ownership, render submission, pointer isolation, recovery and wrapper restoration. Real Windows ZIP worker tests check extraction, resource metadata, large sidecars and unsafe paths. BSL packaging tests check the envelope, native DLL, matching loose model and absence of personal/game files. The bundle-inventory test requires each declared module exactly once.

Formatting checks cover maintained Lua and fixtures. Three FFI-heavy files remain unchanged because StyLua AST verification warns; upstream adapters remain verbatim.

Candidates: `dist/Epic-LUT-R6-Cleanup-LLL.zip` and `dist/Epic-LUT-R6-Cleanup-BSL.zip`. They retain R5 version metadata because this is a review checkpoint. Installed R5 and GitHub releases are unchanged.

Offline acceptance does not establish game-screen or visual acceptance. Native ownership behavior was preserved, not newly certified in-game.
