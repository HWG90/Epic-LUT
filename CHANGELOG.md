# Changelog

## Unreleased

## R5.7.5 - 2026-10-14

- Save updates the selected Armory preset after a confirmation naming the overwrite target. Capture and storage failures leave the existing preset intact.
- Select **Save a New Preset** at the top of the preset dropdown when a LUT is loaded to create a separate preset through the existing Save workflow. No extra button is required.
- Add cooperative input handoff support for updated War Journalist Photo Mode builds. Photo retains the camera while Epic LUT borrows input; closing Epic LUT returns the lease. Older Photo Mode builds do not provide this bridge, and its installed camera hooks require a normal game restart after updating.
- Carry the shared changes into R6 without removing weapon-specific save scopes.

## R5.7.4 - 2026-10-14

- Fix false Pattern/LUT conflicts across mod archives: compare the effective highest numeric layer in each family before refusing. Byte-identical native metadata, pixels and flags can load normally. Differing palettes and conflicting equal-index records remain refused, with the competing filenames reported.
- Keep color agreement separate from archive provenance. Do not invent a single archive source for patch export; retain the alias list and refresh older caches with schema v6.
- Identify the exact missing binding-cache part and I/O reason, invalidate the failed cache, and provide Load Current Gear as a recovery action.
- User confirmed the archive-alias test build resolves the reported custom-model loading failure. The maintenance fix is also carried into R6.

## R5.7.3 - 2026-10-14

- Resolve installed custom LUT layers by numeric patch precedence within their exact archive family. Higher layers replace lower layers for the same texture; equal-layer conflicts and competing archive families remain explicit errors. Invalidate older source caches.

## R5.7.2 - 2026-10-14

- Right-click a LUT ID or its local name to copy the underlying texture ID using the configured hexadecimal or exact unsigned decimal format. Keep left-click naming and LUT values unchanged.
- Load current LUT pixels from installed custom texture patches instead of reusing stock pixels under the same resource ID. Validate the patch-sensitive snapshot scope before exposing cached colors and recheck it on Load Current Gear; highlighting retains the custom model's other rows and original bindings.
- Match Basic Apply Preset to Armory's live assignments: apply valid material LUTs when a mesh has no matching Pattern, include every resolved companion, and offer Pattern-only destinations without inventing assignments. Preserve checked targets, stale-state checks, rollback and one-action Undo.
- Extend Player Preview gore filtering to cataloged numbered gib sections and separate named gore/LOD meshes. Preserve copied clothing and live LUT sync when material replacement recreates handles; reject replacements that alias equipped source materials.
- Identify Pattern LUT column 3 Alpha as roughness. Restore the third quick swatch with Color, Mat/Opac and Roughness labels above the selectors, retaining compact grid-sized cells and abbreviated labels when needed.
- Expose Roughness A without Advanced. Ordinary roughness picker edits preserve every other channel exactly, including unmapped RGB, with live preview, Cancel and Undo/Redo.
- Fix Armory's Apply Preset caption clipping at larger fonts by reserving both scaled padding margins. Wrap gear checkboxes and place Apply on another row when their complete labels cannot fit together.

## R5.7.1 - 2026-10-11

- Expand Shared Lobby LUT with complete exact-value Armor, Helmet and Pattern appearances, including applied Armory looks. Deduplicated tables, shared float dictionaries and improved lossless compression support up to 4,096 destinations within the existing lobby budget. One Configuration toggle controls send/receive and currently defaults On; remote application requires matching sender kits. Cape materials remain excluded, oversized looks remain local, and two-player visual confirmation is still pending for this build.
- Initialize the two quick Pattern swatches from current gear without opening the full Pattern workspace; preserve existing edits and history while refreshing their source.
- Replace separate imported-target actions with one Map LUTs to Gear dialog in Basic and Advanced. Map imported tables to Armor, Helmet and Cape columns; Auto-map uses numeric source order, restarts for each checked gear family and cycles when destinations outnumber imports.
- Preserve distinct palettes sharing one texture ID through verified Texture, Material and Unit mesh-slot replacements. Retain kit-fixed original IDs, original unselected mesh/LOD palettes and authentic raw resource bytes; refuse incompatible fixed assignments before staging.
- Remove the unverified native provenance path after the export crash. Resolve bindings through genuine Lua Unit handles, hash-verified named mesh/material queries and rechecked exact source receipts; no ResourceManager material lookup or inferred multi-slot ordering.
- Support valid empty Material texture tables, missing stock LUT roles for certified fixed assignments and opaque unselected mesh slots. Missing roles cannot authorize a material fork; unrelated unnamed sections do not invalidate an exact proved target.
- Preserve legacy Armory assignment metadata and validate matching worn gear and applied preset values before binding-aware patch export. Keep saved presets unchanged while resolving their export references.
- Fix fingerprint validation for loose GPU sidecars larger than 512 MiB using bounded streaming and exact measured lengths. Report real worker/cache errors without implicit restart; Load Current Gear explicitly retries failed or changed binding sources.
- Independently audit the actual MASTER OF CEREMONY and MASTER-CRAFTED-ARMOR exports for exact pixels, resource chains and retained geometry. Both exports and the installed exported patch were confirmed working in-game for those tested assignments.
- Keep Basic's Load Current Gear label consistent and include Cape loading.
- Switch edited Basic camo colorways to Current / custom; keep the menu open and preserve unrelated channels when using the RGB picker.
- Clamp expandable controls on both axes, keep quick Pattern swatches aligned with the grid, reserve a gap beside Player Preview and avoid dividers or progress indicators colliding with import text.
- Present Armory previews in compact Armor, Helmet, Cape and Pattern lanes with independent scrollbars; group identical previews within a gear family while retaining every saved binding.
- Add Tab completion for existing Armory preset names and a selected saved-row preview beside Rows controls.
- Reset selected cells or rows to loaded original values with Delete as one undoable edit; keep text-field Delete behavior separate.
- Replace Basic's separate preset apply buttons with a two-column LUT checkbox chooser and Select All. Apply selected Armor, Cape and Helmet LUTs with their associated Patterns as one checked transaction.
- Commit typed Value Editor numbers when clicking away; retain invalid edits for correction. Canceling an Armory name skips validation and never saves, including when the name is empty.
- Add a two-swatch Pattern quick editor below the material LUT table and place the complete Pattern editor in that workspace instead of a separate window. Keep the unknown third column intact and available through advanced controls. Preserve independent scrolling, editing, import/export and non-restoring navigation back to the material table.
- Select Armor, Helmet and Cape independently with checkboxes when saving an Armory preset. Replace The Armory's stacked apply actions with the same three targets and one Apply Preset button, with grouped preflight, rollback and Undo.
- Clamp Advanced LUT cell growth against the final space above docked Tools. Hiding Values or Preview keeps eight readable rows visible whenever they fit; cap oversized cells and retain scrolling for larger tables or tighter divider positions.
- Give Basic mode enough minimum window height to show all eight regions together, expanding those rows to fill the available space. Remove its repeated title/help above the LUTs and measure the compact Load, gear and import headers. Retain scrolling for larger tables.
- Add a Camo checkbox column beside Basic's regions, with square boxes and drawn check marks, every box initially unchecked. Patterns, colorways and camo tints affect only checked rows; keep unchecked bytes intact, retain selections through Undo/Redo and use the first checked row for color swatches.
- Place Basic's Apply Imported Texture controls directly below each destination LUT selector, with source selection on the dropdown arrow and Apply [filename] on the main button. Keep both source labels synchronized and move camo swatches above the pattern/colorway selectors.
- Initialize dormant Basic camo using the complete recipe copied by Match Your Colors: color alpha, fade, mask sharpness/bias/UV scale and roughness blending. Generated colorways now activate camo; keep authored working patterns and independent tint edits.
- Reserve a measured Basic action footer so scrolling content and clip masks cannot cover Player Preview or Stop Highlight.
- Keep Armor and Cape preset application separate. Adapt unmatched LOD meshes only when the saved piece/material family has identical palettes and an exact live match proves the current resource and dimensions; log successful preset binds after readback.
- Finish texture retirement before closing the frontend's render-readiness service, preventing a cleanup deadlock that blocked LLL reloads.
- Reclaim eligible owned LUT textures after complete addon cleanup using binding readback and two render fences; retain uncertain or legacy allocations. Give editing a bounded 64 MiB / 16,384-record budget and coalesce continuous material edits to 15 live uploads per second, flushing the final value when editing ends.
- Restore owned material and Pattern LUTs together through action Undo/Redo, preflight both slots and roll back partial failures without overwriting another mod's bindings.
- Add independent Apply Cape in The Armory, matching saved Cape material and Pattern entries to current Cape destinations, with support for older Armor-labelled Cape entries.
- Add separate Armor and Helmet camo pattern selectors beneath Basic Mode's regions and provide thumbnails decoded from the game's actual mask atlas.
- Select held Idle, Salute, Wave, Taunt and High Five poses in Player Preview; keep Idle as the default and load real game emote tracks only when selected.
- Replace Tools' Dock/Undock text controls with opposing window icons beside Close; preserve tooltips and a separate draggable title area.
- Begin controller refactoring by separating file-picker requests, retries, progress and worker polling into `import_picker`; preserve result acceptance and native ownership in the editor.
- Start Tools open on Import when docked; saved undocked Tools start closed. Remember the last Dock/Undock choice across reloads and preserve manual visibility within the loaded editor.
- Add generated Jungle, Desert, Urban and Arctic colorways and four editable camo colors to Basic Mode.
- Place Basic's modified-color notice inside the scrolling action pane and measure wrapped content to prevent overlapping export controls.
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
