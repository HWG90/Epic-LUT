# Epic LUT R3 Alpha

Final alpha package for manual installation: Epic-LUT-R3.zip.

- In-game Armor and Helmet editing, grouped clickable color palettes, advanced float grid, camo controls, undo/redo, presets, hotloading and quick save.
- Quick Load is the opening page. Combined Armor and Helmet reset restores originals while retaining custom colors.
- Bundled Windows x64 Python/NumPy/OpenEXR runtime; no separate Python installation or setup. Native Windows picker, optional browser; RAR requires installed 7-Zip.
- Automatic game-owned helper shutdown on normal exit or crash. Atomic IPC and guarded import ownership handoff.
- Multi-mip bounded 2D RGBA16F/RGBA32F DDS support. Import uses full-resolution values; unsupported cube, volume, array and compressed textures are rejected.
- Ordinary builds use the tested direct saved-key handler. The separate Bingus binding adapter is withheld while compatibility is investigated.

Validation: repeated user-reported stable direct-keyboard launches, Armor/Helmet editing and restoration, native picker use, movement return, and helper shutdown. Offline regressions cover grouped swatches, combined reset, DDS bounds/mips, IPC, loader lifecycle and both service installation paths. The real Cadian Guardsman archive extracts all seven five-mip LUTs with exact full-resolution float values.

Limits: the exact cause of earlier startup hangs is not proven. The Cadian-specific fix has offline proof; item-specific live behavior, exhaustive equipment/mission transitions, multiplayer visibility and long-session reliability are not guaranteed. This remains an alpha. No game assets, third-party palettes, user settings, logs or diagnostic dumps are included.

Install exactly one entrypoint: BSL v15+ startup option via Arsenal/HD2MM, or the complete armor_lut_editor folder through LLL/compatible MDL API 2. Compatible MCM is optional. Target native adapters: Steam build 25480438.

Nexus upload text: docs/NEXUS-BBCODE.txt preserves the author's original banner, wording, humor and credits. No live Nexus page or GitHub Release is created by the source push.
