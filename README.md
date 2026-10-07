# Epic LUT

**Author: Goose.** Armor and helmet LUT editing with native archive import, semantic controls and an optional advanced editor.

**Alpha preview — features, layout, and behavior may change.**

## Requirements and installation

Choose one entrypoint from `Epic-LUT-R3.zip`:

- **Bingus Shared Loader:** import the ZIP through Arsenal/HD2MM and enable its startup option alongside Bingus Shared Loader v15+. MCM, LLL and MDL are optional.
- **LLL / MDL:** install the complete `armor_lut_editor` folder through a compatible API-2 loader.

Compatible MCM is used when present; otherwise Epic LUT provides its own in-game menu. Older MCM versions without per-mod storage and presentation support need updating or disabling. Activate only one Epic LUT entrypoint. The native adapters target Steam build 25480438.

Python, NumPy and OpenEXR are bundled for Windows x64. Equipped-target discovery and file actions unpack and start the private runtime automatically; no Python installation, pip command, setup script or browser is required. RAR extraction still requires installed 7-Zip. The optional browser editor can be started with `start_editor.ps1`. [Installation and bindings](docs/BSL.md).

## Controls

F10 is the initial standalone menu key. General Settings and Quick Load → Extras expose the same saved key preference. Quick Load opens by default. The current alpha uses the direct menu keyboard path; the separate Bingus binding adapter is withheld while startup compatibility is investigated.

**Quick Load** opens a Windows picker for ZIP, RAR, DDS or EXR. It shows the imported filename and source-row color swatches, then separate **Apply to Armor** and **Apply to Helmet** buttons. **Extras** contains independent material/emission preservation switches, both Off by default. Unknown fields retain their originals. Source swatches clip RGB for display only.

Quick Load prefers exact resource matches, then maps known semantic fields deterministically. Rows use nearest proportional mapping with aligned endpoints. Different recognized layouts map shared Base Color RGB only; unsupported layouts are skipped and reported. Matching dimensions do not establish matching surfaces. [Mapping reference](docs/MAPPING.md).

Armor and Helmet provide independent **Equipped**, **Semantics / grid cell**, and **Files / hotload** pages. Features include float-channel editing, RGB colors, camos, undo/redo, row copy/paste, full-float presets, file hotloading and quick save. The optional browser editor adds a pixel grid, rectangular clipboard, row presets and bulk DDS/EXR conversion.

Disable either override to restore original bindings while retaining its mapped document. Re-enable it to restore the retained mapping for that item. **Reset Custom LUT Rows** clears custom edits separately. Full imports may alter emission/modes while preservation is Off; Base Color can tint glow even when emission controls are preserved.

The original CowboyBingus Match Your Colors options retain their provider's settings and callbacks. Conflicting modes pause the affected target editor.

## Storage and limits

Data uses `%LOCALAPPDATA%/Epic LUT`: `settings`, `files`, `presets` and `cache`. Legacy loader folders are neither migrated nor deleted. Files/packages are parsed as data; archive scripts are not executed and imported mod patches are not installed. [File formats](docs/FILES.md), [preset format](docs/PRESETS.md).

Targets are the local equipped armor and helmet. Cape equipment, skin, Armory previews and weapons are excluded. Immutable texture storage is limited to 8 MiB / 2,048 records; exhaustion restores originals and pauses editing. The own menu supports keyboard/mouse navigation. A live 3D armor panel is not included.

The direct-keyboard functional candidate has passed repeated user-reported launches and Armor/Helmet application, restoration, movement, and helper-shutdown checks. Earlier candidates crashed; the exact cause remains unproven. The latest alpha UI still requires live visual and interaction confirmation. Controller activation through the withheld binding adapter is not claimed.

## Building

`build.ps1 -Verify` creates the package and checks LuaJIT contracts. Set `LUA51_DLL` or `HD2_GAME_DIR` for the matching game library. The build uses the pinned input DLL from the sibling DBF-MCM checkout or `EPIC_LUT_INPUT_LIBRARY`. Deployment guards validate the physical destination, create a rollback and require a reload marker. No native input DLL is replaced by the Lua deployment script.

## Credits

LUT discovery and native adapters: [CowboyBingus / Match Your Colors](https://github.com/CowboyBingus/MatchYourColors), under the included Zero-Clause BSD license. Semantic research references: [Paydex LUT Editor](https://github.com/paytonrog/paydex-lut-editor). Equivalent mapping/editor code is independently authored; no unlicensed Paydex implementation or third-party palette assets are included.

A successful import switches the original Match Your Colors setting Off through its own provider. Cancel and invalid files leave that setting unchanged. The game-launched file service exits when the game closes or crashes. Manual browser-editor startup remains independent of game lifetime.
