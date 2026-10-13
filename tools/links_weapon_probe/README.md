# Read-only Links weapon probe

This diagnostic adapter uses Link's Link to Memory to run the reviewed Epic LUT identity and discovery modules. It does not add a production dependency or modify the installed Epic LUT package.

Prepare using the physical Python runtime and `tools/links_weapon_probe/prepare.py`. Preparation copies six modules verbatim under unique `r6_weapon_probe_*` names, the diagnostic script, vendor license, private texture ID catalog and source hash manifest into `%LOCALAPPDATA%/LinksLinkToMemory`. It sends no addon commands.

The controlling worker can run `run r6_weapon_probe` in one batch using the addon's normal driver, or explicitly pass `--run` to the helper. Keep other addon drivers and background tests stopped while running. The helper refuses an already running batch; it does not stop another worker.

The script captures primary, secondary and support independently. It uses genuine Lua Unit handles matched to exact inventory identities, then validates native mesh/material locators and both texture slots. It queries at most eight catalog IDs per frame, records every exact alias and rejects identity or binding changes. A per-frame coroutine completes within 90 seconds. Receipts and Lua handles remain in memory; only read-only TSV data is saved as `r6_weapon_probe.tsv`.

TSV records include module bases, image sizes and timestamps; the prepared source manifest; slot/config/Unit IDs; material and Pattern row positions, native object aliases and stable save keys. Pattern and material share a locator key: always retain the family column. Texture dimensions and pixel contents must come from the matched original DDS, not native pointer guesses.

When the supported game's `Mesh.name` API is available, the probe records its raw signed value and normalized uint32 MeshID for every genuine mesh, including unbound meshes. It rechecks these hashes with receipts and pointers around catalog chunks. A missing API retains the earlier binding-only diagnostic; a malformed or changed hash refuses. MeshIDs identify serialized records independently of runtime order and are never used as numeric `Unit.mesh` arguments.

The exposed native adapter contains only alive/mesh/material/resource queries. There are no binding writes, commits, game texture allocations, privacy census calls, hooks, input controls, loadout changes or background tasks. The vendor engine adapter verifies current-build function addresses before calls; its FFI queries are outside Link's `native()` call log. A zero addon journal alone is not proof of read-only behavior: the script's limited query call set is the additional source proof.

Do not commit or package the private prepared catalog, reports or game data. Only this helper, script, README and fixture belong in public source.

## Optional explicit RGB apply/restore pilot

After read-only mapping proves the current primary and body texture, prepare with `--pilot-resource <body texture ID> --expected-weapon <primary configuration ID> --pilot-dds <exact cached game-ID-original.dds>`. This additionally copies the production `weapon_runtime`, `binding_session` and DDS modules, an original DDS encoded as text, configuration, source hash manifest and `r6_weapon_pilot.lua`. Preparation still sends no commands. The ordinary `--run` continues to run the read-only probe; it does not activate the pilot.

The controlling worker must inspect and explicitly issue `run r6_weapon_pilot`. The pilot requires a 23 x 8 body LUT with exactly five current primary LOD bindings. It changes only row 1 Base RGB to magenta, preserving Alpha and every other float32 byte, then restores after two seconds. The production runtime performs its private-material census before native allocation and validates ownership before each write. Reports contain original/applied/restored objects by save key and prove all other loaded weapon and Pattern bindings stay unchanged.

Stop/error cleanup attempts exact original restoration. Every allocated backing array and texture receipt stays referenced until the game exits, including failed restoration; this diagnostic never adds a renderer destruction API. The pilot can recolor the player's primary briefly and makes native texture allocation/binding calls. It is distinct from the read-only probe and must be executed deliberately. Native calls through the vendor adapter do not appear in Link's own call log, so use the script's binding report and retained receipts as additional evidence.

Offline checks: run `test_prepare.py`; execute `fixture.lua` and `pilot_fixture.lua` with the repository LuaRunner. The pilot fixture uses the real runtime/session/discovery and covers apply/restore, unchanged destinations, private-material rejection before allocation and failed cleanup retaining its GPU backing.
