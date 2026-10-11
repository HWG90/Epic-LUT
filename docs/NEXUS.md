# Epic LUT R5.7.1

**STYLISH FREEDOM. Defend Freedom in Style.**

Edit worn Armor, Helmet, Cape and Pattern LUTs in-game. Use Basic for region colors and checked-region camo, or Advanced for the full material grid. Save looks in The Armory, map imported palettes to gear, and export DDS, shareable presets or verified game patches.

The current Nexus description source is [NEXUS-BBCODE.txt](NEXUS-BBCODE.txt); version history is [NEXUS-CHANGELOG.txt](NEXUS-CHANGELOG.txt). [R5.7.1 changes](RELEASE-R5.7.1.md) cover the compact editor, mapping, embedded Pattern workspace and gear-assignment export fixes.

## Choose one package

| Nexus category | Package | Loader and entrypoint |
| --- | --- | --- |
| Main File | `Epic-LUT-R5.7.1-BSL.zip` | Arsenal/HD2MM with Bingus Shared Loader v15+; enable its startup option |
| Optional File | `Epic-LUT-R5.7.1-LLL.zip` | Live Lua Loader R30+; modular `armor_lut_editor/main.lua` |
| Optional File | `Epic-LUT-R5.7.1-MDL.zip` | Compatible MDL API-2 loader; bundled `armor_lut_editor/mod.lua` |

For LLL, extract the complete folder into `%LOCALAPPDATA%/LLL/Helldivers2/Mods`. For MDL, use the loader's configured Mods directory. Keep the package's native DLL and scripts together. Enable one Epic LUT entrypoint and disable the separate old `epic_player_preview` test addon; preview is included. MDL cannot load the modular LLL package. See [README](../README.md), [LLL installation](LLL-MODULAR.md) and [MDL installation](MDL-LLL.md).

No Python or MCM installation is required. Windows PowerShell/.NET handles file actions. RAR import requires installed 7-Zip. Turn Match Your Colors matching Off before editing the same gear. Native adapters target Steam build 25480438; game updates may require changes.

## Use it

**F9** opens Basic; **F10** opens Advanced. Press **Load Current Gear**, choose a LUT and edit its colors. Camo boxes start unchecked: only checked regions receive camo changes. The two quick Pattern swatches sit below the LUT table; the full Pattern editor opens in the same workspace. Docked Tools starts open and provides Import, Rows, Export and Options. **F6** opens Player Preview with the default Idle pose.

Use **Map LUTs to Gear** for manual assignment or numbered Auto-map across checked Armor, Helmet and Cape columns. Use The Armory's gear checkboxes to save and apply selected parts with their associated Patterns.

Patch export retains verified material and mesh assignments, including different material-bound palettes sharing a texture ID. Kit-fixed IDs keep their required original resource. Unproved or incompatible fixed assignments report an error before publishing files. For an older preset, load and apply its matching gear before binding-aware export. DDS and shareable presets remain available. Exports do not install game patches.

Data stays under `%LOCALAPPDATA%/Epic LUT`. Releases exclude settings, saved presets, logs, cache, game textures and animation assets. **Shared Lobby LUT remains in testing**; both players need a compatible version and sharing enabled. Oversized appearances remain local.

## Links and credits

[Nexus files](https://www.nexusmods.com/helldivers2/mods/17039?tab=files) | [GitHub downloads](https://github.com/HWG90/Epic-LUT/releases/tag/R5.7.1) | [Report bugs on GitHub](https://github.com/HWG90/Epic-LUT/issues)

Made by **Goose**. A massive thank you to **Scarpheon** for his continued testing, help with Export to Patch and mapping all 26 bump maps. Thanks to **Arkturus425** for Shared LUT testing, **CowboyBingus / Match Your Colors** for LUT discovery and the native adapters under the included Zero-Clause BSD license, **Plain Furniture** for the Debug LUT, **Shikami** for the Region Indicator idea, **Kaiser & Amiba** and the modding community for shared knowledge, **Paydex LUT Editor** for inspiration, and **[Lytatroan](https://www.nexusmods.com/profile/Lytatroan)** for the human-made thumbnail.