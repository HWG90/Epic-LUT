# Changelog

## Unreleased

- Select held Idle, Salute, Wave, Taunt and High Five poses in Player Preview; keep Idle as the default and load real game emote tracks only when selected.
- Replace Tools' Dock/Undock text controls with opposing window icons beside Close; preserve tooltips and a separate draggable title area.
- Begin controller refactoring by separating file-picker requests, retries, progress and worker polling into `import_picker`; preserve result acceptance and native ownership in the editor.
- Resize docked Tools vertically with a draggable divider; retain the split across window resizing and redocking without changing LUT data.
- Keep partially visible Value Editor text rendering at both scroll edges, with clipped controls and fixed chrome above the scrolling content.
- Align Value Editor labels and numeric fields to measured font bounds; add thumb/track dragging and finer scrolling without clipping beneath its header.
- Recover workspace height above the status divider, move the docked Tools title into the footer, and place Paydex JSON import last below Reset Row.
- Flash camo color contributions as well as Base during region identification, preserving original data and restoring only owned live bindings.
- Fill the available grid space with docked Tools and show its tabs only inside the docked or floating panel.
- Apply row presets to every selected row whose selection includes column 1, as one undoable full-RGBA edit.
- Add removal X buttons to saved-row, palette and Armory preset choosers, with recoverable backups and preserved applied colors.
- Import Paydex JSON row libraries directly from Tools > Rows, preserving complete float RGBA values, existing presets and the current editor/gear state.
- Dock or undock Tools beneath the LUT grid, with independent scrolling and shared Import, Rows, Export and Options controls.
- Thank Arkturus425 and Scarpheon for helping test the Shared LUT update.
- Size editable preset-name hit areas to their text, preserve a large dropdown opening area, and enlarge dropdown/step controls; keep the caret inside its own field.
- Clear the previous row-preset name when choosing New preset and reject blank saves before modifying a saved row.
- Add an explicit Apply Cape action for imported palettes; isolate Cape material bindings from Armor, Helmet and the separate tint slot.
- Preserve complete RGBA, material and camo controls when pasting swatches or rows without Advanced mode; keep typed advanced edits protected.
- Apply paired Pattern DDS files through Apply Matching LUTs when their exact resource IDs match the worn gear.
- Add a lossless shared-value dictionary format to fit larger combined material and Pattern appearances within the existing lobby budget.
- Compare lossless Windows XPRESS compression with the existing sharing compressor and send the smaller packet; preserve exact LUT bytes, all bindings and earlier packet decoding.
- Remove the old 128-destination sharing cap with a compact extended packet format supporting up to 4,096 bindings; retain the lobby byte budget and exact LUT values.
- Keep receiving Shared Lobby LUTs when the local appearance cannot be encoded; retain the last shareable appearance only for the same equipped kits and keep the failure visible.
- End quick swatch picker sessions when closed so double-click editing works after changing LUTs; keep live edits on the selected material through discovery refreshes and reject changed gear or slots.
- Use the game's loaded HUD font with measured caret alignment and a guarded debug-font fallback.
- Balance the HUD font's visible vertical padding across buttons, selectors and row headers.
- Restore dropdowns and floating overlays to the previously working native drawing-layer range while preserving their integer ordering.
- Give Epic LUT a distinct near-black skin, outlined secondary actions, gold navigation indicators and quieter row/inspector headers.
- Use integer native drawing layers and narrow border strips so retained swatches, labels and dark selected-card fills stay visible after partial updates.
- Keep Import preview/highlight actions inside a reserved footer; scroll its lower actions when the window cannot fit them.
- Give the editor distinct title, heading, label and hint styles; keep body and editable text at regular weight with optional bold headings.
- Scale button padding and header geometry with the configured font size; keep secondary navigation quiet and primary Load/Apply/Export actions clear.
- Reuse named preview function types across reloads; keep the editor available when the optional preview binding reaches capacity, with bounded single-line loader diagnostics.
- Add a separately named preview animation test using procedural standing/salute poses, cape sway and Pause/Play on existing garment copies.
- Resolve salute joints across segmented garments; handle missing update deltas and keep diagnostic single-frame mode from leaking into normal preview openings.
- Use the actual Helldiver standing and salute clip tracks, including fingers, from a bounded local game cache; keep cape sway separate and ship no animation assets.

## R5.5.6 - 2026-10-10

- Restore dedicated Pattern LUT export names, DDS and Patch ZIP buttons in the floating Pattern window.
- Include exact matching Pattern LUTs in live and saved-preset exports; DDS exports write companion files, and bulk custom exports retain unchanged associated Patterns.
- Add Include Pattern LUTs in Exports under Configuration > Exports, default On, with synchronized MCM settings.
- Add a separate bundled API-2 MDL package alongside modular LLL R30+; maintain BSL, LLL and MDL parity from one source snapshot.
- Keep the default idle Player Preview in standard builds.
- Shared Lobby LUT is in testing.

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
