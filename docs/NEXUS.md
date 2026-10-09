# Epic LUT

**Author: Goose**

**Alpha preview — features, layout, and behavior may change.**

Edit equipped armor and helmet LUTs in game: semantic fields, float channels, colors, camos, undo/redo, presets and file hotloading.

## Requirements

Python and the DDS/EXR codecs are included in the release. There is no separate Python installation or setup step: file actions unpack and start the private runtime automatically. A browser is optional.

Choose one loader path:

- Bingus Shared Loader v15+ using the package's startup option.
- LLL or a compatible MDL API-2 loader using the loose `armor_lut_editor` folder.

MCM is optional. Compatible MCM is used automatically; without MCM, Epic LUT provides its own in-game menu. An older MCM without the required storage/presentation APIs needs updating or disabling. Activate only one Epic LUT entrypoint. The native adapters target Steam build 25480438.

Multi-mip DDS imports are supported for bounded 2D uncompressed RGBA16F/RGBA32F LUTs. The importer reads the full-resolution level and validates the declared mip chain. Cube, volume, array, and unsupported/compressed formats remain unsupported. Seven five-mip Cadian Guardsman palettes pass exact-value offline extraction; live import verification is pending.

RAR extraction requires installed 7-Zip. DDS, EXR and ZIP imports use the bundled codecs without an external Python installation.

## Controls and usage

**F10** opens and closes the standalone menu. Quick Load is the opening page. General Settings contains the menu-key preference. The current alpha testing path uses the menu's direct keyboard handler; the separate Bingus binding adapter is withheld while startup compatibility is investigated.

**Quick Load** opens a Windows picker for ZIP, RAR, DDS or EXR. Review the filename and source-row color swatches, then choose **Apply to Armor** or **Apply to Helmet**. Each target has an independent override toggle: disable to restore originals, re-enable to restore its retained mapping. **Reset Custom LUT Rows** clears custom edits separately.

**Reset Armor and Helmet** restores both targets and disables their overrides while retaining custom colors. **Base Color / regions** lists all supported color fields and numbered rows for the selected LUT, with clickable current-color squares beside original-color references. Surface meanings remain unconfirmed; the advanced float grid is available separately.

Collapsed **Extras** contains independent **Preserve material properties / semantics** and **Preserve emission** switches, both Off by default. Unknown fields retain their originals. Base Color can still tint glow when emission controls are preserved.

Quick Load prefers exact resource matches and can attempt cross-item semantic remaps. Rows use nearest proportional mapping; different recognized layouts map shared Base Color RGB only. Applied/skipped counts are reported. Unsupported layouts are retained. Visual results depend on the material and surface mapping.

Armor and Helmet contain equipped-target controls, **Base Color / regions**, **Advanced / float grid**, and **Files / hotload**. An optional browser editor provides a full grid, clipboard and bulk conversion. The standalone menu supports keyboard and mouse navigation.

## Storage and compatibility

Data is stored under **`%LOCALAPPDATA%\Epic LUT`** in `settings`, `files`, `presets` and `cache`. Legacy loader folders are not migrated or deleted. Imported archive scripts are not executed and mod patches are not installed. A live 3D armor preview is not included.

The direct-keyboard functional candidate has passed repeated user-reported launches and Armor/Helmet editing, restoration, and movement tests. Earlier candidates experienced startup crashes; the exact cause remains unproven. This is an alpha, and the latest UI changes still require live validation before publication.

Quick Load remembers the imported filename and cached extracted palette. It does not extract the original archive or run Quick Apply automatically each launch. Previously saved enabled target edits can be restored and applied at startup.

## Credits

Thank you to **Scarpheon** for his inexhaustible effort helping me test Epic LUT, track down bugs, and make it better.

LUT discovery and native adapters: CowboyBingus / Match Your Colors, under the included Zero-Clause BSD license. Semantic research references: Paydex LUT Editor. Editor and mapping code are independently authored; third-party palettes are not included.

A successful import switches the original Match Your Colors setting Off through its own provider. Cancel and invalid files leave that setting unchanged. The game-launched file service exits when the game closes or crashes. Manual browser-editor startup remains independent of game lifetime.
