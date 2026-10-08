# Pattern LUTs

Open **LUT Editor**, then **Pattern LUT Editor** to open the movable popup. Select the Armor or Helmet tab. Choose **Load Current Pattern LUTs** and select the bound Armor or Helmet pattern table. Original snapshots may take a moment to finish loading.

Pattern LUTs are **3 columns by 1 row**, bound through the separate pattern texture slot. They do not replace the 23-column gear LUT.

- Column 1 RGB: accent color. Alpha remains unknown.
- Column 2 RGB: metallic controls, with a useful range of 0 to 1. Alpha: pattern opacity. These are provisional mappings from the supplied pattern reference.
- Column 3 RGBA: unknown, preserved unless explicitly edited under raw values.

Edits apply to the selected pattern table's live bindings. Use **Undo Pattern Edit**, **Redo Pattern Edit**, or **Restore Original Pattern LUTs**. Enter a name and **Export Pattern DDS** to save all 12 floats in `files/exports`. Import a 3x1 DDS using the normal file chooser; then choose the destination and explicitly apply it in this section.

Edited pattern tables are included in the compatible Epic LUT full-appearance sharing packet. Their live mapping still needs in-game confirmation.

**Show Alpha** is shared with the LUT Editor grid. It displays each swatch over a checkerboard as alpha approaches zero; values outside 0 to 1 are clamped only for display. Alpha can be a shader control instead of opacity, so this display does not change the actual material behavior.
