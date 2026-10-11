# Epic LUT R5.7.1 — Compact Editor & Gear Export Fix

R5.7.1 makes more of the editor visible, brings camo and Pattern edits into the main workflow, and fixes exported patches losing distinct palettes on shared gear resources.

## Basic, mapping and presets

- **Load Current Gear** loads Armor, Helmet and Cape. The Basic layout prioritizes all eight regions together.
- Each region has an initially unchecked **Camo** box. Pattern, colorway and tint changes apply only to checked regions, with the four tint swatches above the selectors.
- Dormant camo receives the complete Match Your Colors recipe instead of remaining invisible. Jungle, Desert, Urban and Arctic colorways provide working starting colors; editing a tint changes the label to **Current / custom** and keeps the menu open.
- Imported-texture Apply buttons sit below each destination LUT selector. Their dropdown arrows select the source without applying it.
- One **Map LUTs to Gear** dialog works in Basic and Advanced. Imported LUTs and Armor, Helmet and Cape destinations appear in columns for one-click assignment.
- **Auto-map** follows numbered imports: `lut000` → slot 1, `lut001` → slot 2, repeating the imports when slots outnumber them. Each checked gear column starts at the first import. Verified matching Patterns accompany material assignments.
- Save Armor, Helmet and Cape independently using checkboxes. The Armory applies checked gear with one button; Basic's **Apply Preset...** chooser provides individual LUT checkboxes and **Select All**, including associated Patterns.
- Armory previews use compact Armor, Helmet, Cape and Pattern lanes with independent scrollbars. Repeated identical tables share a preview with a count while retaining every saved assignment.
- Preset naming offers **Tab** completion for existing names. **Cancel** works with an empty name. Removing row, palette and outfit presets preserves recoverable files and applied colors.

## LUT and Pattern editing

- Two **Quick Editor: Pattern LUT** swatches sit directly below the material table, align with its grid and initialize without opening the full Pattern editor. The unknown third column stays intact and remains available in advanced controls.
- **Pattern LUT Editor** replaces the material table with the full workspace. Editing, raw channels, undo/redo, flash, import, DDS export and Pattern Patch ZIP export remain available. Returning to Armor or Helmet preserves Pattern edits.
- Clamp table cells, swatches and controls against the available height and width. Showing or hiding Values and Preview prioritizes visible rows instead of oversized controls. Tools and longer content scroll independently.
- Docked Tools starts open on **Import**; saved undocked Tools starts closed. Resize its docked area with the divider, or use the Dock/Undock icons beside Close.
- Typed Value Editor numbers apply when clicking away. Invalid entries stay available for correction. **Delete** resets selected cells or rows to loaded original values as one undoable edit.
- Row tools show the saved row preview beside the controls. Import Paydex JSON row libraries and apply a preset to all selected rows.
- Improved font metrics, caret alignment, text clipping, dropdown hit areas, retained drawing layers and import-progress spacing. Preview and Stop Highlight remain accessible in their reserved footer.
- Player Preview keeps **Idle** by default, with selectable held Salute, Wave, Taunt and High Five poses read from the local game. Continuous animation remains a separate development build.

## Patch exports and reliability

- Preserve verified material and mesh assignments when different palettes share one texture ID. Material-bound variants receive separate resources; kit-fixed replacements keep their required original IDs. Unselected mesh and LOD slots retain their original values.
- Accept valid empty stock texture tables, missing stock roles on certified fixed assignments, and opaque unselected material slots without inventing bindings. Unsupported or conflicting fixed assignments stop before files are published.
- Fixed the export crash by removing the unverified native provenance route and using checked Lua handles, exact named slots and background archive reads.
- Large loose GPU patches are fingerprinted in bounded chunks, including files over 512 MiB. Cache failures report their actual reason; **Load Current Gear** explicitly retries instead of silently restarting a failed read.
- MASTER OF CEREMONY and MASTER-CRAFTED-ARMOR exported successfully in-game. Their actual patch contents passed separate archive, pixel and assignment checks; the installed exported patch was confirmed working in-game. This verifies those tested gear assignments, not every possible game resource.
- Material and Pattern actions preflight and restore together through Undo/Redo. Cleanup finishes before render services close; eligible owned textures retire only after binding checks and render fences. Continuous edits coalesce live uploads while the final value applies immediately.
- Shared Lobby LUT packets use exact-value dictionaries and the smaller successful XPRESS/legacy encoding, retaining up to 4,096 bindings within the existing lobby size limit. **Shared Lobby LUT remains in testing.**

## Downloads

All three packages use the same source snapshot and include Player Preview:

- **BSL — Nexus Main File:** `Epic-LUT-R5.7.1-BSL.zip`, for Arsenal/HD2MM with Bingus Shared Loader v15+.
- **LLL — Nexus Optional File:** `Epic-LUT-R5.7.1-LLL.zip`, modular `main.lua`, for Live Lua Loader R30+.
- **MDL — Nexus Optional File:** `Epic-LUT-R5.7.1-MDL.zip`, bundled API-2 `mod.lua`, for compatible MDL loaders.

Enable one Epic LUT entrypoint. No Python or MCM installation is required. RAR import requires installed 7-Zip. Turn Match Your Colors matching Off before editing the same gear.

[GitHub release](https://github.com/HWG90/Epic-LUT/releases/tag/R5.7.1) | [Nexus files](https://www.nexusmods.com/helldivers2/mods/17039?tab=files) | [Bug reports](https://github.com/HWG90/Epic-LUT/issues)

A massive thank you to **Scarpheon** for mapping all 26 bump maps and for his continued testing and vital help with Export to Patch. Thanks to **Arkturus425** for Shared LUT testing, **CowboyBingus** for the native adapters and LUT foundation, **Plain Furniture** for the Debug LUT, and **[Lytatroan](https://www.nexusmods.com/profile/Lytatroan)** for the human-made thumbnail.
