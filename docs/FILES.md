# Files and pre-made palettes

Use **Files / hotload → Import LUT / mod archive** in MCM. Its Windows picker runs on a helper thread outside the game/render thread, owned by the invoking game window. Cancel is inert; the selected file is imported privately, then its target and Apply are presented in MCM. The browser Advanced editor is optional. The file service starts automatically when needed. The release includes its own Python runtime and codecs; no setup script is required. Everything runs locally; the service has no game-memory access.

The local file service accepts DDS, EXR, ZIP and RAR through **Open / drop file**. ZIP extraction uses a bounded data parser; RAR requires the installed 7-Zip executable. Raw float files and standard direct Stingray patch resources are supported. Encrypted, traversal/absolute-path/link, oversize and malformed packages are rejected. Package documents/scripts are not executed; the mod patch is not installed. Compressed/nonstandard resource archives are not claimed supported.

An exact resource-ID/dimension match is selected automatically; click Apply to use it. Import alone is preview-only. Choose All compatible armor LUTs for a deliberate group remap; incompatible pattern tables are skipped. Unmatched or multiple matches stay preview-only until a target is chosen. Palette reuse by dimensions is an explicit remap: matching 23×8 dimensions do not establish matching surface regions. Effect preservation defaults Off: full LUT imports can change emission/modes. Turn it On to preserve those original controls. RGB-only edits keep other channels intact.


## Editor operations

- Semantic fields and pixel grid; unknown channels remain labeled unknown.
- Rectangular/individual selections, checked-channel edits and cell copy/paste.
- Ctrl+S quick save, Save As, Ctrl+Z/Ctrl+Shift+Z or Ctrl+Y undo/redo.
- Row presets across compatible widths, scratch RGB and debug row colors.
- Camo selector, color and scale fields; no invented pattern names.
- DDS/EXR bulk conversion; existing conversion destinations are skipped.

DDS input accepts uncompressed RGBA16F/RGBA32F, 2D LUTs, including valid mip chains (the full-resolution level is imported). DDS saves use RGBA32F. EXR requires one non-deep bounded RGBA part and saves Float32 channels. Neither codec applies gamma, normalizes HDR or clamps signed values. Unsupported formats fail before changing the document.

The local file service writes validated float DDS files. MCM watches current target-qualified working files and binds immutable uploaded textures. EXR bridge conversion runs outside the game. Malformed hotload files leave the previous rendered texture in place. Native resources remain retained under the documented budget; immutable repeats/undo reuse cached resources rather than mutate them unsafely.

Quick Load appears first, followed by Armor, Helmet and CowboyBingus's original submenu. Quick Load has independent material-property and emission preservation switches, both Off by default, and separate whole-target Armor/Helmet Apply buttons. Cross-item and different-row-count remaps use known semantic fields and nearest proportional rows; mismatched recognized layouts map Base Color RGB only. Original unknown fields stay intact. Unclassified layouts are attempted but reported as skipped because no semantic meaning is established. See README for the deterministic source selection and private mapping report.

The native picker initializes an STA worker and uses a helper-owned window when an elevated game window rejects modal creation (`0xFFFF`). Foreground permission is granted only to the running helper on explicit picker invocation. Focus returns after success/cancel without input injection, game restart or an input DLL replacement. Dialog diagnostics stay in the private working folder. Controller and full focus-cycle compatibility require validation on the matching game build.

All new durable editor files use `%LOCALAPPDATA%/Epic LUT`: `settings` for values/menu key, `files` for private float documents and native import IPC, and `presets` for exported presets. Runtime/cache data is kept separate from settings. No migration from old loader folders is performed. Imported source-row swatches are display-only; clipped RGB is used solely for preview. Extras is collapsed below Apply, and shared master aliases restore/re-enable each target without a second stored flag.
