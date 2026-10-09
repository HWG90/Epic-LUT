# Pattern LUTs

Open **LUT Editor > Pattern LUT Editor**, then **Load Current Patterns**. Armor and Helmet stay gray until current or imported pattern data is available. Choose either gear and a table. The popup refreshes loaded values when equipment changes; use the gold Load button to retry a missing snapshot. The optional automatic-population setting also enables loading on first open.

Pattern LUTs contain **3 columns and 1 row**, bound through a separate pattern texture slot. They do not replace the 23-column material table. A garment can bind a pattern table without visibly using it; **Flash Pattern** identifies where the selected accent appears. **Stop Flash** restores its previous binding.

- **Column 1 RGB:** accent color. Alpha is unknown.
- **Column 2 RGB:** metallic controls, normally edited between 0 and 1. Alpha is pattern opacity. These mappings are provisional; their effect depends on the material.
- **Column 3 RGBA:** unknown. Values stay intact until explicitly edited.

Click a swatch to select its controls. Double-click to open the color picker. Color and alpha preview live; **Use Color** keeps the edit and **Cancel** restores the values from when the picker opened. For exact numbers, use the channel fields. **Advanced** exposes the unknown channels without assigning them invented meanings.

**Undo** and **Redo** apply to the selected table. History follows that table when switching Armor and Helmet. **Restore All Patterns** restores the original bindings for every pattern table edited in this session.

**Show Alpha** is shared with the LUT Editor. It draws a checkerboard as alpha approaches zero. Display values are clamped to 0-1; stored floats are preserved. Shader alpha is not always transparency.

To import a pattern, choose **Import** and select a 3x1 DDS. Preview its three swatches, choose a loaded destination, then **Apply Imported DDS to Selected Pattern LUT**. Importing a file alone does not change the model. An unavailable destination must finish loading before an import can be applied.

Name the export, then choose **Export DDS** for the selected table or **Export Patch ZIP** for its game texture replacement. **Export Entire Palette** in the main editor also includes edited pattern tables. Exports append a timestamp in `files/exports`; **Open Export Location** opens that folder. All twelve floats, including unknown values, remain intact.

Edited patterns are included in compatible Epic LUT appearance sharing. Pattern rendering and multiplayer appearance still require confirmation in the game; an unused pattern may produce no visible change.
