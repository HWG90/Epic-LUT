# Epic LUT

Live armor and helmet float-LUT editing through MCM, with a local DDS/EXR/archive companion.

**Discovery and implementation credit: [CowboyBingus](https://github.com/CowboyBingus/MatchYourColors).** Epic LUT builds on the float-LUT discovery, resource binding, armor discovery and file-decoding work in Match Your Colors. The measured native adapters are reused under its Zero-Clause BSD license, preserved in `vendor/LICENSE`. The numbered-row editor, MCM integration, immutable lifetime policy and preset interchange are additions; we do not claim the original LUT discovery.

## Use

Requires Live Lua Loader (or compatible MDL API 2 lifecycle), DBF-MCM with RGB color controls, and the batch setter supplied in `tools/mcm-set-many.lua` for preset imports. Supported native contract: Steam build 25480438, verified by executable/game SHA-256 and function-table addresses.

Open **MCM > Epic LUT > Semantics / grid cell** for armor, or **Helmet – Semantics / grid cell**. Select an actual LUT resource, numbered row/region and semantic field. A committed RGB/float change automatically enables that row and live application. Opening/canceling a picker is inert. The old per-LUT row-page tree is removed; all discovered lookup resources remain in the selector. The full-float document is authoritative for rendering.

**Restore original colors** disables application while retaining the document. **Reset Custom LUT Rows** resets stored/displayed values from preserved originals and clears overrides. Disabled rows render their originals. Legacy RGB metadata is retained for preset compatibility, not as another overriding render layer.

Armor and helmet have independent target-qualified discovery, documents, settings and restoration. The original **CowboyBingus – Match Your Colors** options are mounted through their original handles/setters/callbacks/persistence. Its mod is retained; competing armor/helmet modes pause the corresponding editor without silently changing the original mode.

**Preserve emission, modes and unknown effects** is on by default. It permits researched recoloring/camo controls and retains the other originals at rendering. Unavailable fields are disabled with a reason. Emission is not a confirmed RGB picker: its R channel is a researched strength parameter, other channels/dependencies are uncertain. Base RGB can tint glow. File HDR/signed values are not normalized or clamped. Deliberate material editing requires unlocking preservation. See the [mapping reference](docs/MAPPING.md).

Targets are equipped local armor non-skin pieces and local helmet pieces. Cape equipment, skin, Armory previews and weapons are excluded. Every referenced texture slot is inspected for bounded float lookups; material, pattern and other discovered tables have separate identities and exact rows. Non-LUT/unsupported resources are retained and reported. Sharing with other player units is not comprehensively established.

## Export and import

Use each target's **Export preset / Import preset** for full-float v2 `.dbflut` interchange. Target kind/kit, body, resource hashes, dimensions, complete cells and activation flags are validated before one settings commit. Legacy armor RGB v1 imports remain supported. Helmet presets cannot silently apply to armor. Files are data, never executed. [Preset format](docs/PRESETS.md).

For pre-made files/packages, use **Files / hotload > Open file / archive picker**, or `start_editor.ps1`. Choose/drop DDS, EXR, ZIP or RAR. Packages are extracted automatically in a private cache; documents/code are never executed and mod patches are not installed. An exact unambiguous resource/dimension match may publish to its equipped target; otherwise choose a target explicitly. [File/archive workflow and supported formats](docs/FILES.md).

The local companion includes semantic fields, pixel grid, rectangular clipboard, undo/redo, Ctrl+S, row presets, scratch RGB, camo and debug rows, and DDS/EXR bulk conversion. Set up codecs once using `setup_companion.ps1`. EXR conversion runs outside the game and publishes float DDS for hotloading. No third-party palette assets are included in this repository.

## Build and validation

`build.ps1 -Verify` produces `dist/Epic-LUT-R2.zip` using a non-Store Python interpreter. `-Python <path>` selects another non-Store runtime. Microsoft Store/WindowsApps Python is rejected before filesystem work. For the first reviewed installation, install the ZIP's `armor_lut_editor` folder including `presets`; keep the stable folder name to preserve settings.

For subsequent authorized updates, use **`deploy.ps1`**. It validates the real absolute LLL destination and opened-handle path, rejects LocalCache/virtualized paths, preserves a hash-verified rollback, and checks the actual installed SHA-256 immediately and after reload. It stops on mismatches or unconfirmed reload instead of blindly retrying. Backups/receipts stay under ignored `dist/deployment-backups`. Run `tests/deploy_guards.ps1` for rejection checks. These protections cover the supported entrypoints; external copies can bypass them.

`python verify.py` runs LuaJIT syntax and meaningful contracts. Set `LUA51_DLL` to the LuaJIT Lua 5.1 library and `MCM_SOURCE_DIR` to the DBF-MCM checkout if they differ from the defaults (Windows Steam library, sibling DBF-MCM). Tests cover non-color preservation, stale/foreign binding handling, partial failures, actual MCM picker commit/cancel, automatic activation, equipment lifecycle, complete preset round trip, malformed rejection and atomic-save failure.

MCM batch integration is a narrowly scoped setter addition, not a replacement framework build. [Integration instructions](docs/MCM-BATCH.md) explain how to add it without overwriting other MCM changes.

## Runtime limits and evidence

Textures are immutable per edit and retained in shared Lua storage until process exit. No elapsed-frame resource reuse/destruction assumption is imported. Pixel budget: 8 MiB; allocation-record budget: 2,048. Exhaustion restores originals and pauses. Unlimited sessions and GPU reclamation are outside R2.

Live armor color editing has been verified in game without a restart. MCM picker visibility, immediate controls, and restoration/readback through hot reload were also verified. Equipped helmet material/pattern discovery, provider submenu synchronization and the RGB-only Live Wire glow check have also been verified. Comprehensive mission transitions, peer visibility and long-session validation remain open. Offline tests do not prove native rendering.
