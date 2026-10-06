# Epic LUT

Live armor color editing in Helldivers 2 through MCM.

**Discovery and implementation credit: [CowboyBingus](https://github.com/CowboyBingus/MatchYourColors).** Epic LUT builds on the float-LUT discovery, resource binding, armor discovery and file-decoding work in Match Your Colors. The measured native adapters are reused under its Zero-Clause BSD license, preserved in `vendor/LICENSE`. The numbered-row editor, MCM integration, immutable lifetime policy and preset interchange are additions; we do not claim the original LUT discovery.

## Use

Requires Live Lua Loader (or compatible MDL API 2 lifecycle), DBF-MCM with RGB color controls, and the batch setter supplied in `tools/mcm-set-many.lua` for preset imports. Supported native contract: Steam build 25480438, verified by executable/game SHA-256 and function-table addresses.

Open MCM > Epic LUT. Choose a numbered LUT row's **primary RGB** color. **USE COLOR** automatically activates that row and live application. Opening or canceling the picker changes nothing. Edits apply on the next update after commit. Row toggles and the master switch remain available to disable edits. **Restore original armor colors** restores original texture objects.

**Reset Custom LUT Rows** also resets persisted/displayed colors from each preserved original LUT row, clears overrides and disables application in one batch. Restore keeps custom colors for later reapplication/export. Original colors are shown at the RGB picker's 8-bit precision (clamped/rounded); original texture restoration preserves the full original float values. Multiple LUTs retain separate originals, with no invented uniform color.

Targets the currently equipped local armor's body-compatible non-skin pieces, slots 2-9. Helmet, cape, skin, Armory previews and weapons are excluded. Row meanings are deliberately numbered until mapped visually. Only primary-color RGB in column zero changes; alpha and every other LUT value are copied unchanged. Lighting, material detail and camouflage affect perceived color.

Settings persist separately per armor kit/body/LUT/row. Equipment changes restore prior bindings and rediscover targets. Competing ownership pauses editing. Match Your Colors can remain in Helmet Matches Armor mode only with disjoint materials; Armor Matches Helmet must be disabled for armor editing. Shared pointers with excluded local pieces are rejected. Sharing with other player units is not comprehensively established.

## Export and import

**Export armor preset** writes a new `.dbflut` file without overwriting earlier exports and selects its filename for re-import. Files are in the installed mod's `presets` folder: on a normal Windows LLL install, `%LOCALAPPDATA%\LLL\Helldivers2\Mods\armor_lut_editor\presets`.

To share/reapply, copy a `.dbflut` file there and enter its filename **without the extension** in MCM, then select **Import armor preset**. The full version, armor kit ID, body, LUT hashes, dimensions, row coverage, activation flags and colors must match. Imported enabled/disabled flags are preserved. The file is data, never executed. Invalid files and failed persistence leave values unchanged. See [preset format](docs/PRESETS.md).

This is editor preset interchange, not a game archive patch. Producing a distributable archive patch needs an independently verified asset packaging path and is outside R1.

## Build and validation

`build.ps1 -Verify` produces `dist/Epic-LUT-R1.zip` using a non-Store Python interpreter. `-Python <path>` selects another non-Store runtime. Microsoft Store/WindowsApps Python is rejected before filesystem work. For the first reviewed installation, install the ZIP's `armor_lut_editor` folder including `presets`; keep the stable folder name to preserve settings.

For subsequent authorized updates, use **`deploy.ps1`**. It validates the real absolute LLL destination and opened-handle path, rejects LocalCache/virtualized paths, preserves a hash-verified rollback, and checks the actual installed SHA-256 immediately and after reload. It stops on mismatches or unconfirmed reload instead of blindly retrying. Backups/receipts stay under ignored `dist/deployment-backups`. Run `tests/deploy_guards.ps1` for rejection checks. These protections cover the supported entrypoints; external copies can bypass them.

`python verify.py` runs LuaJIT syntax and meaningful contracts. Set `LUA51_DLL` to the LuaJIT Lua 5.1 library and `MCM_SOURCE_DIR` to the DBF-MCM checkout if they differ from the defaults (Windows Steam library, sibling DBF-MCM). Tests cover non-color preservation, stale/foreign binding handling, partial failures, actual MCM picker commit/cancel, automatic activation, equipment lifecycle, complete preset round trip, malformed rejection and atomic-save failure.

MCM batch integration is a narrowly scoped setter addition, not a replacement framework build. [Integration instructions](docs/MCM-BATCH.md) explain how to add it without overwriting other MCM changes.

## Runtime limits and evidence

Textures are immutable per edit and retained in shared Lua storage until process exit. No elapsed-frame resource reuse/destruction assumption is imported. Pixel budget: 8 MiB; allocation-record budget: 2,048. Exhaustion restores originals and pauses. Unlimited sessions and GPU reclamation are outside R1.

Live armor color editing has been verified in game without a restart. MCM picker visibility, immediate controls, and restoration/readback through hot reload were also verified. Comprehensive live equipment-change, peer visibility and long-session validation remain open. Offline tests do not prove native rendering.
