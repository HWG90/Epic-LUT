# Pattern LUTs

Open **LUT Editor > Pattern LUT Editor** to replace the material table with the full Pattern workspace, then use **Load Current Patterns** if values are not ready. Armor and Helmet stay gray until current or imported pattern data is available. Choose either gear and a table. The workspace refreshes loaded values when equipment changes; use the gold Load button to retry a missing snapshot. The optional automatic-population setting also enables loading on first open.

Below the ordinary material table, **Quick Editor: Pattern LUT** provides three swatches. An explicit **Load Current Gear** also loads their current Pattern values without opening the workspace or resetting its edited values and history. Click a quick swatch to edit it; the full editor retains the advanced gates for unknown channels. Selecting Armor or Helmet closes the full Pattern workspace without restoring its edited bindings. Quick editing is disabled while a Cape material LUT is selected.

The quick swatches align with the material grid and use its cell size, capped at 40 logical pixels. The layout reserves space for them together with the material rows and keeps a gap before Player Preview. Wider windows keep controls compact; the full Pattern workspace packs channel fields into two columns when space permits.

Pattern LUTs contain **3 columns and 1 row**, bound through a separate pattern texture slot. They do not replace the 23-column material table. A garment can bind a pattern table without visibly using it; **Flash Pattern** identifies where the selected accent appears. **Stop Flash** restores its previous binding.

- **Column 1 RGB:** accent color. Alpha is unknown.
- **Column 2 RGB:** metallic controls, normally edited between 0 and 1. Alpha is pattern opacity. These mappings are provisional; their effect depends on the material.
- **Column 3 RGBA:** unknown. Values stay intact until explicitly edited.

Click a swatch to select its controls. Double-click to open the color picker. Color and alpha preview live; **Use Color** keeps the edit and **Cancel** restores the values from when the picker opened. For exact numbers, use the channel fields. **Advanced** exposes the unknown channels without assigning them invented meanings.

**Undo** and **Redo** apply to the selected table. History follows that table when switching Armor and Helmet. **Restore All Patterns** restores the original bindings for every pattern table edited in this session.

**Show Alpha** is shared with the LUT Editor. It draws a checkerboard as alpha approaches zero. Display values are clamped to 0-1; stored floats are preserved. Shader alpha is not always transparency.

To import a pattern, choose **Import** and select a 3x1 DDS. Preview its three swatches, choose a loaded destination, then **Apply Imported DDS to Selected Pattern LUT**. Importing a file alone does not change the model. An unavailable destination must finish loading before an import can be applied.

For paired material and Pattern DDS imports, **Import / Apply > Apply Matching LUTs** includes Patterns whose exact resource IDs match the worn gear. Material and Pattern targets are checked before applying either. Files without matching resource IDs still use the explicit destination action in the Pattern workspace.

Name the export, then choose **Export DDS** for the selected table or **Export Patch ZIP** for its game texture replacement. **Export Entire Palette** in the main editor also includes edited pattern tables. Exports append a timestamp in `files/exports`; **Open Export Location** opens that folder. All twelve floats, including unknown values, remain intact.

**Configuration > Exports > Include Pattern LUTs in Exports** defaults to On, directly beneath the Cape option. When enabled, exporting a loaded Armor, Helmet or Cape material LUT includes Patterns bound to those exact material destinations. Selected Patch exports bundle them into the same ZIP. Selected DDS exports put the material and companion Pattern DDS files in one named folder; bulk custom DDS exports include unchanged matching Patterns too. A saved-preset selection uses its stored matching Pattern, never the currently worn gear. Turning the option off omits Patterns from appearance exports without removing saved data. Standalone Pattern exports remain available. Unattached imported tables and older presets without stored Pattern data export their selected table alone.

Edited patterns are included in compatible Epic LUT appearance sharing. Pattern rendering and multiplayer appearance still require confirmation in the game; an unused pattern may produce no visible change.
