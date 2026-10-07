<img width="1774" height="887" alt="image" src="https://github.com/user-attachments/assets/5fe0be6e-66ca-45bc-879e-d0cd8192c648" />


# Epic LUT R4 Alpha

**Goose's Python-free in-game LUT editor. Alpha / work in progress.**

## Install

Import the complete ZIP through Arsenal/HD2MM and enable its Bingus Shared Loader startup option alongside BSL v15+. Enable only one Epic LUT entry. The complete `armor_lut_editor` folder also supports a compatible API-2 loose loader.

No Python interpreter, codec installation, pip, embedded runtime or persistent service is required. Windows PowerShell/.NET supplies the standard file picker and short-lived archive extraction worker. The reviewed native input DLL remains included.

## Use

Press F10. **Import / Apply** opens first: choose a DDS, ZIP or RAR with the Windows picker, select an imported LUT on the left, use Save LUT to Palette to put it in the editor, then check Helmet/Armor and Apply LUT. Importing does not automatically apply a texture. If Match Your Colors is installed, turn its matching Off before applying. This standalone build does not change its settings.

**LUT Editor** uses top tabs and a clickable pixel grid. Its independently scrolling value pane expands each row into all 23 named fields, sliders, typed values and selectors. Body and value text use size 10, with slightly larger headers. File actions, history, row presets and scratch color sit below the grid. Color edits preserve alpha; advanced material/camo values require explicit unlocking. Apply sends your edited palette to the selected live LUT. **Apply Armor** updates all local armor LUTs; **Apply Helmet** updates helmet LUTs without removing armor changes. Per-LUT applications are cumulative too. **Save applied setup** snapshots all active palettes and resumes them on later launches. **Restore Original** restores the original bindings and clears saved automatic application while retaining the imported document. **Remove LUT** also unloads that document. **Reset Custom LUT** resets edits to the imported palette and can be undone. Restore before changing equipment. This is a standalone editor: MCM detection, compatibility registration and the binding adapter are excluded.

Undo/Redo, row copy/paste, saved row presets and DDS export are available. Grid tools support channel selection, drawing, Shift-click rectangular selection, copy/paste and moving a selection. Dropdown/stepper combos select palettes, LUTs, rows, fields and modes. A saved setup uses local piece/mesh/material slot keys and all-armor/helmet defaults, never process addresses or guessed gear names. RGB is clamped only for display. Full finite float data is retained on disk.

## Formats and limits

DDS: bounded 23-column 2D RGBA16F/RGBA32F material LUTs, including valid mip chains. ZIP/RAR: DDS files or standard game patch resources with GPU/stream sidecars. Imported archive contents are never installed or executed. EXR, bulk conversion and pattern/cape layouts are not part of this simplified runtime.

No armor names, kit IDs, installed game archives or original pixel data are needed. The editor groups local live material LUT bindings; shared Armor/Helmet bindings are labeled accordingly. Original dimensions and surface meanings are unknown, so use a palette appropriate for the selected target. Other players' units are excluded.

Data lives in `%LOCALAPPDATA%/Epic LUT` (`files`, `presets`, `settings`, `cache`). GPU buffers are immutable and retained until process exit, bounded to 8 MiB / 2,048 textures. Restoration checks live membership and ownership and does not overwrite a different writer.

## Validation

The user confirmed direct ZIP importing works in game. The redesigned standalone tabs, picker, 23-column value pane and multi-target saving pass offline checks but still need live interaction/visual and restart confirmation. Native adapters target Steam build 25480438. Later game updates may require changes.

## Build

Python is used only by developers to assemble and test the package: `python build.py`, then `python tests/test_direct_zip.py`, `python verify.py`, and `python tests/test_release.py dist/Epic-LUT-R4-Alpha.zip`. No build tools are shipped to users. The input DLL is pinned from sibling DBF-MCM or `EPIC_LUT_INPUT_LIBRARY`.

## Credits

Native adapters and the original LUT research: [CowboyBingus / Match Your Colors](https://github.com/CowboyBingus/MatchYourColors), under the included Zero-Clause BSD license. [Paydex LUT Editor](https://github.com/paytonrog/paydex-lut-editor) is a semantic and layout reference; Epic LUT's editor implementation is independently authored. No third-party palettes or game assets are included.

RAR requires installed 7-Zip. Import / Apply uses grouped Armor/Helmet row previews and a loader throbber with cancel/retry recovery. Save LUT to Palette changes only the editor; Export DDS preset to share writes a portable full-float DDS.
