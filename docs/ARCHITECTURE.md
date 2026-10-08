# Runtime architecture

Epic LUT targets LuaJIT's Lua 5.1 ABI. Modules return a table; dependencies are supplied explicitly. Runtime code cannot rely on filesystem require paths: build.py bundles its declared inventory into one loader model.

## Ownership boundaries

- `direct_editor.lua`: coordinates the active edit session, gear selection, UI actions and background jobs. This is still the principal extraction target.
- `gear_catalog.lua`: discovers local material groups, preserves original identities for owned writes, and filters selected/gear-wide application scopes without UI mutations.
- `binding_session.lua`: owns Epic LUT binding writes, immutable retained texture buffers, per-operation rollback and restoration. It never guesses foreign ownership. The controller supplies native callbacks; tests can supply ordinary Lua tables.
- `table_index.lua`: cooperatively decodes a snapshot of imported paths, retaining resource metadata and skipping cached documents.
- `import_job.lua`: owns one external worker, cancellation, retries, timeouts and shutdown; emits results without editing palettes.
- `armory_collection.lua`: named collection previews, selection, save, rename and confirmation dialogs; native application stays in the controller.
- `import_protocol.lua`: validates bounded worker progress/results and constructs result/progress/cancel paths. It does not mutate session state or call native APIs.
- `basic_state.lua`: independent editor documents and history copies. History copying preserves resource metadata and original pixels, deduplicates shared documents, and accounts for both pixel buffers.
- `editor_registry.lua`: stable editor control IDs and presentation schema; requires named session callbacks and performs no gear writes.
- `lut_files.lua`: validated DDS names, row-preset offsets and full-document exports shared by editor and controller.
- `file_io.lua`: bounded reads and deterministic handle cleanup, used by document and preset loading.
- `configuration.lua`: assembles Configuration using the existing preferences store. Editor actions remain registered for custom layouts; presentation aliases must not mutate source controls.
- `control_help.lua`: immutable UI guidance shared by custom views. Do not rebuild static descriptions during draw calls.
- `basic_view.lua`, `import_view.lua`, `armory_view.lua`: layout and hit targets. Mutation goes through injected callbacks and registered controls.
- `lut_editor.lua`: document mutation, selection, pixel clipboard and local history.
- `lut_editor_view.lua`: grid, row controls and panels; receives only the editor operations and semantic/render helpers it uses.
- `lut_editor_controls.lua`: registry schema and callbacks that delegate to the editor operations.
- `outfit_presets.lua`, `direct_setup.lua`: disk formats and validation. Native application belongs to the session controller.
- `player_preview_input.lua`: owns mouse/wheel wrappers and restores only wrappers it still owns.
- `player_preview*.lua`: preview model, controls, rendering and lifecycle. It owns copied garments and its render resources, not the borrowed game world's simulation.

## Working conventions

Use module-local state for a service instance. Keep dependency injection at construction boundaries. Avoid runtime filesystem module loading and new globals. `package.loaded` entries are reserved for deliberate cross-addon services and retained native-resource lifetime.

Native writes must validate liveness and ownership first. Roll back only writes owned by the operation. Never free queued texture buffers or borrowed worlds to reduce memory usage. Treat callback failures as actionable errors; keep retry state when cleanup cannot safely finish.

UI draws should be read-only apart from view-local layout state. Reuse immutable labels and descriptions. Preserve stable IDs, stored settings and native resource identity during refactors. Avoid introducing aliases that become a second authority for the same preference.

Keep closures small: Lua 5.1 limits captured upvalues. Extract named operations/services instead of routing new responsibilities through the module injection table as a long-term substitute for clear interfaces.

## Verification

`verify.py` compiles all source, vendor/menu and generated loader Lua, then executes an explicit list of editor contracts in isolated LuaJIT states. Source basenames never decide whether a file executes. `tools/lua_runner.py` centralizes ctypes ABI setup and always closes failed validation states.

`tools/verify_player_preview.py` runs preview ownership/lifecycle tests. `tests/test_direct_zip.py` exercises the real Windows worker. `tests/test_release.py` checks BSL archives, the matching loose model, metadata, dependencies and package hygiene.

Build both loader candidates. Integrated preview builds share the native adapters already in the editor bundle; standalone preview tests still declare their own dependencies. Offline checks do not establish visual or game-transition acceptance.

## Maintenance rules

1. Keep result acceptance in the controller as an explicit session transition; indexing and worker lifetime stay in services.
2. Keep active edit fields in the private `edit` session record; do not add scattered document/target/revision globals.
3. Keep reducing controller callback bodies into explicit session operations as new behavior is added.
4. Keep new DDS export paths routed through `lut_files.lua` and bounded loading through `file_io.lua`.
5. Keep preview input ownership in `player_preview_input.lua` and preserve the frontend close-order handshake.
6. Keep the pinned formatter gate and documented FFI exceptions current.

These rules describe how to extend the cleaned architecture. Large native ownership changes still require separate live validation.


The maintained bundle inventory is in `tools/module_inventory.py`. Run `python tools/format_lua.py --check` with StyLua 2.5.2 at the documented development-tool path (or `--stylua`). Three FFI-heavy files are excluded because AST verification warns; do not bypass that check to force formatting. Legacy MCM sources remain available for their regression tests, outside the release module inventory.


## Source folders

- `src/core`: DDS/color semantics, document copies, history and bounded IO.
- `src/editor`: controller, views, registry definitions and guidance.
- `src/gear`: local binding ownership, discovery, original snapshots and region indication.
- `src/imports`: worker messages/lifetime, resource matching and table indexing.
- `src/presets`: Armory collections and named DDS storage.
- `src/platform`: Windows APIs, preferences, paths and standalone frontend.
- `src/preview`: player model, render adapter, controls, input and lifecycle.
- `src/loaders`: BSL startup and lifecycle bridge.
- `src/legacy`: earlier MCM/catalog/companion implementation retained for compatibility contracts; excluded from normal bundles.

`tools/module_inventory.py` maps module names to folders. Runtime modules still use injected dependencies; folder moves do not introduce filesystem `require` dependencies.
