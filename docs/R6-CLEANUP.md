# R6 code cleanup checkpoint

The cleanup preserves R5 controls, stored settings, DDS/preset formats and native ownership rules. R6 is not published by this checkpoint.

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
