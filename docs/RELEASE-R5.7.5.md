# Epic LUT R5.7.5 — Shared LUT, Camo & Compact Editing

R5.7.5 adds confirmed saves to the selected preset and a seamless new-preset dropdown option. It includes expanded **Shared LUT** appearances, checked-region camo, one-click gear mapping, the embedded Pattern editor and compact layouts. Patch exports now preserve verified assignments when gear uses different palettes on shared resources.

## Selected preset saves and Photo Mode handoff

- Save updates the selected Armory preset after a confirmation naming the overwrite target. Capture and storage failures leave the existing preset intact.
- Select **Save a New Preset** at the top of the preset dropdown when a LUT is loaded to create a separate preset through the existing Save workflow. No extra button is required.
- Add cooperative input handoff support for updated War Journalist Photo Mode builds. Photo retains the camera while Epic LUT borrows input; closing Epic LUT returns the lease. Older Photo Mode builds do not provide this bridge, and its installed camera hooks require a normal game restart after updating.
- Carry the shared changes into R6 without removing weapon-specific save scopes.

The Photo Mode bridge requires an updated companion build; it is not supplied by this Epic LUT package. Offline save, input lifecycle and package tests passed. David confirmed that Epic LUT and Photo Mode both stay open after a normal restart with the updated companion.

## Maintenance fixes in this release

- Read installed custom-model LUT patches instead of stock pixels under reused texture IDs. Recheck patch-sensitive caches on Load Current Gear; highlighting retains the custom palette's other rows.
- Basic Apply Preset uses the same live assignments as The Armory. Valid material LUTs remain applicable without a matching Pattern; actual companions and Pattern-only destinations remain explicit.
- Filter numbered gore caps and named gore/LOD meshes from Player Preview while preserving clothing and live LUT synchronization.
- Restore the third quick Pattern swatch as Roughness, with Color and Mat/Opac labels. Roughness edits change Alpha and preserve all other channels; Cancel and Undo/Redo remain available.
- Prevent Armory Apply Preset clipping at larger font sizes, wrapping controls when needed.
- Right-click the LUT ID or renamed label to copy its underlying texture ID in the configured hexadecimal or exact unsigned decimal format.
- Split the large direct editor into focused workflow modules without changing its public editing behavior.

## Shared LUT — your look, visible to your squad

**Shared Lobby LUT** lets compatible Epic LUT squadmates see your currently applied Armor, Helmet and associated Pattern edits. Apply a saved Armory preset to share that look, or share the colors you are editing now. It transfers complete supported tables, including color alpha, material, camo and emissive channels, with exact float values rather than reducing the appearance to a few RGB swatches.

- Both players need R5.7.5 and **Configuration > Share full LUT appearance with Epic LUT users** enabled. The current default is On; that one setting controls both sending and receiving. Turn it Off to stop advertising your appearance and restore received looks owned by Epic LUT.
- Updates wait for a stable squad lobby and settled edits. They apply to the sender's matching body, Armor and Helmet kits on the receiving client; the receiver can wear a different outfit.
- Larger appearances use deduplicated tables, exact-value dictionaries and improved lossless compression. Up to 4,096 bindings can be represented, subject to the lobby budget. An oversized look stays local with an explanatory status, and receiving remains available.
- Cape material LUTs are excluded from lobby sharing in this build. Unmodified games and Match Your Colors-only clients do not interpret Epic LUT appearance packets.
- **Shared Lobby LUT remains in testing.** Codec and ownership checks pass offline; two-player visual confirmation is still required for this build.

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

- Three **Quick Editor: Pattern LUT** swatches sit directly below the material table, align with its grid and initialize without opening the full Pattern editor. Labels identify Color, Mat/Opac and Roughness. Column 3 Alpha controls roughness; ordinary edits preserve its other channels.
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

## Downloads

All three packages use the same source snapshot and include Player Preview:

- **BSL — Nexus Main File:** `Epic-LUT-R5.7.5-BSL.zip`, for Arsenal/HD2MM with Bingus Shared Loader v15+.
- **LLL — GitHub only:** `Epic-LUT-R5.7.5-LLL.zip`, modular `main.lua`, for Live Lua Loader R30+.
- **MDL — Nexus Optional File:** `Epic-LUT-R5.7.5-MDL.zip`, bundled API-2 `mod.lua`, for compatible MDL loaders.

Enable one Epic LUT entrypoint. No Python or MCM installation is required. RAR import requires installed 7-Zip. Turn Match Your Colors matching Off before editing the same gear.

[GitHub release](https://github.com/HWG90/Epic-LUT/releases/tag/R5.7.5) | [Nexus files](https://www.nexusmods.com/helldivers2/mods/17039?tab=files) | [Bug reports](https://github.com/HWG90/Epic-LUT/issues)

A massive thank you to **Scarpheon** for mapping all 26 bump maps and for his continued testing and vital help with Export to Patch. Thanks to **Arkturus425** for Shared LUT testing, **CowboyBingus** for the native adapters and LUT foundation, **Plain Furniture** for the Debug LUT, and **[Lytatroan](https://www.nexusmods.com/profile/Lytatroan)** for the human-made thumbnail.
