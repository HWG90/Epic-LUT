# Epic LUT R5.3 — Sharing and Patterns

- Share full Armor, Helmet and Pattern LUT appearances with compatible Epic LUT squadmates. Enable sharing in Configuration on both players.
- Open the movable Pattern LUT Editor from LUT Editor for accent colors, material values, opacity, flash identification, undo/redo and DDS import/export.
- Show Alpha adds checkerboard transparency previews to both LUT grids. Color pickers and Scratch Pixel include alpha controls.
- Preview color-picker changes on your character before accepting them. Sliders display changes while dragging.
- Export named DDS files or a destination-specific patch ZIP from LUT Editor. Exports are saved in `files/exports`.
- Improved Armory preset targeting and local Armory appearance mirroring.
- Added a Preview Meshes checklist for identifying unwanted preview geometry.
- Value Editor descriptions wrap using the selected font size.
- Completed original LUT caches can load while the resource index rebuilds, recovering from a missing index marker.
- Clearer highlighted Pattern Editor, Save, Export and mode-switch controls; removed the redundant Material / camo page.

## Known issues

- Player Preview remains experimental. Limb caps or damage overlays can remain visible; close Preview before switching game screens.
- Full appearance sharing still needs confirmation with two players. Oversized appearances remain local.
- Patch export requires a matched original destination and its archive metadata. Exported patches still need in-game validation.
- Pattern channel meanings beyond accent color and material/opacity remain uncertain.

Choose **Epic-LUT-R5.3-LLL.zip** for Live Lua Loader / compatible MDL, or **Epic-LUT-R5.3-BSL.zip** for Arsenal/HD2MM with Bingus Shared Loader v15+. Enable one Epic LUT entrypoint. Turn Match Your Colors matching Off before editing the same gear.

Native adapters and upstream appearance-sharing groundwork by CowboyBingus.
