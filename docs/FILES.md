# Files and pre-made palettes

Use **Files / hotload → Open file / archive picker** in MCM, or run `start_editor.ps1` and open its local URL. Set up codec dependencies once with `setup_companion.ps1`. Everything runs locally; the service has no game-memory access.

The companion accepts DDS, EXR, ZIP and RAR through **Open / drop file**. ZIP extraction uses a bounded data parser; RAR requires the installed 7-Zip executable. Raw float files and standard direct Stingray patch resources are supported. Encrypted, traversal/absolute-path/link, oversize and malformed packages are rejected. Package documents/scripts are not executed; the mod patch is not installed. Compressed/nonstandard resource archives are not claimed supported.

An exact unambiguous resource-ID/dimension match can publish to its equipped armor/helmet lookup. Unmatched or multiple matches stay preview-only until a target is chosen. Palette reuse by dimensions is an explicit remap: matching 23×8 dimensions do not establish matching surface regions. Default game-side effect protection preserves non-color/emission controls; deliberate unlock is needed for full material changes.

The checked Trailblazer example contained one texture patch resource, `028cfcfea3304e83`, 23×8 RGBA32F. Extraction produces a regular float DDS. The package filename alone does not prove which equipped item owns that resource. The sample was inspected/previewed, not applied or redistributed.

## Editor operations

- Semantic fields and pixel grid; unknown channels remain labeled unknown.
- Rectangular/individual selections, checked-channel edits and cell copy/paste.
- Ctrl+S quick save, Save As, Ctrl+Z/Ctrl+Shift+Z or Ctrl+Y undo/redo.
- Row presets across compatible widths, scratch RGB and debug row colors.
- Camo selector, color and scale fields; no invented pattern names.
- DDS/EXR bulk conversion; existing conversion destinations are skipped.

DDS input accepts uncompressed RGBA16F/RGBA32F, single-mip 2D LUTs. DDS saves use RGBA32F. EXR requires one non-deep bounded RGBA part and saves Float32 channels. Neither codec applies gamma, normalizes HDR or clamps signed values. Unsupported formats fail before changing the document.

The companion writes validated float DDS files. MCM watches current target-qualified working files and binds immutable uploaded textures. EXR bridge conversion runs outside the game. Malformed hotload files leave the previous rendered texture in place. Native resources remain retained under the documented budget; immutable repeats/undo reuse cached resources rather than mutate them unsafely.
