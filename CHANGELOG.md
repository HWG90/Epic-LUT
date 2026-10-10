# Changelog

## Unreleased

- Add a separately named preview animation test using procedural standing/salute poses, cape sway and Pause/Play on existing garment copies.
- Resolve salute joints across segmented garments; handle missing update deltas and keep diagnostic single-frame mode from leaking into normal preview openings.
- Use the actual Helldiver standing and salute clip tracks, including fingers, from a bounded local game cache; keep cape sway separate and ship no animation assets.

## R5.5.5 - 2026-10-10

- Synchronize the live LUT selector when loading current gear; region highlights use the exact selected Armor, Helmet or Cape LUT.
- Keep live edits attached to the selected LUT through list reordering and reject stale targets.
- Keep the default idle Player Preview in standard builds; animation testing remains separate.
- Shared Lobby LUT is in testing.

## R5.5.4 - 2026-10-10

- Dismiss the editor and release its cursor while preview or import cleanup is pending; keep native retirement retryable without trapping the menu on screen.
- Fix empty-editor guidance overlapping Load Current Armor/Helmet; keep actions compact, wrap help text and scale spacing beneath the actual header.
- Replace the 128-binding preset cap with 4,096 destinations across save, import, export and appearance recovery.
- Store identical LUTs and patch metadata once while preserving every Transmog target and distinct custom value.
- Remove the extra avatar/simulation-world animation path implicated in the first-run native crash; standard packages keep the static preview.

## R5.5.3 - 2026-10-09

- Fixed drawing order across independent Pattern, Tools and Scratch windows, dropdowns, pickers and tooltips.
- Keep swatches, selection outlines, picker markers, slider handles and text carets visible during partial redraws.
- Give empty preset saves and the 128-binding limit distinct errors, with the actual binding count for oversized saves.
- Identify unavailable Armor or Helmet LUTs before saving and log the collected binding counts.
- Keep saved-preset swatches visible when the dropdown hover background updates.
- Moved Cape LUTs into the Armor dropdown, labeled Cape, using the regular editor controls.
- Removed the separate Cape panel to keep the editor compact.
- Added Include Capes in Armor Exports in Export tools, Configuration and MCM settings.
- Added persistent custom LUT names by texture ID; click the displayed hash or name to rename it.

## R5.5.2 - 2026-10-09

- Corrected text caret, selection and mouse-position drift in long fields.
- Fixed region-identification magenta being copied into editor tables when switching tabs.
- Restored cape material LUT editing through an explicit Cape target, separate from Armor-wide application.
- Paused menu and Player Preview native rendering during Alt-Tab and minimization; resume waits for valid dimensions.

## R5.5.1 - 2026-10-09

- Raised material LUT support to 64 rows across import, editing, copying and export.
- Fixed the clipped Brush label at larger font sizes.
- Corrected the thumbnail credit to [Lytatroan](https://www.nexusmods.com/profile/Lytatroan).
- Shared Lobby LUT is in testing.

## R5.5 - 2026-10-09

- Fixed custom Armor, Helmet and Pattern colors reverting across hellpod, mission and ship transitions.
- Expanded the editor with independent Tools, Scratch and Pattern windows, clearer dropdowns and font-scaled padding.
- Added multi-row copy/paste with outlines that preserve swatch colors.
- Improved text selection, clipboard shortcuts, key repeat, HEX cursors and hover tooltips.
- Added bulk DDS export, shareable Armory presets and LUT/Palette patch export.
- Named all 26 bump maps using Scarpheon's R0-R25 mapping.
- Improved Player Preview and settings, with optional MCM integration.
- Added Plain Furniture's Debug LUT.
- Shared Lobby LUT is in testing.

**A massive thank you to Scarpheon** for mapping the bump maps and for his vital testing and assistance with Export to Patch. Native adapters and foundational LUT research by **CowboyBingus**; Debug LUT by **Plain Furniture**.

Earlier changes: [release history](docs/NEXUS-CHANGELOG.txt).
