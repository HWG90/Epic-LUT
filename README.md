<img width="1672" height="941" alt="exec-3dcb130a-9516-4897-a50b-865c034d3e20" src="https://github.com/user-attachments/assets/a09c0db9-e4d2-4543-9837-7603ddb908a5" />


# Epic LUT R4 RC1

**Legendary looks. Defend Freedom in Style.**

Goose's Python-free, in-game LUT editor for Helldivers 2 armor and helmets. **Release candidate: still extremely alpha and work in progress.**

[Downloads](https://github.com/HWG90/Epic-LUT/releases) · [Report bugs](https://github.com/HWG90/Epic-LUT/issues)

Source and local test candidates may be newer than published releases.

## Install

Import the complete ZIP through Arsenal/HD2MM. Enable its Bingus Shared Loader startup option alongside **BSL v15 or newer**, with only one Epic LUT entry. The included `armor_lut_editor` folder also supports a compatible API-2 loose loader.

For **MDL / Live Lua Loader**, use the separate `Epic-LUT-R4-RC1-MDL-LLL.zip` asset. Extract the complete folder into your loader's mod directory; LLL uses `%LOCALAPPDATA%/LLL/Helldivers2/Mods`. See [MDL/LLL installation](docs/MDL-LLL.md). Activate only one Epic LUT entrypoint.

- **No Python installation or embedded Python runtime.**
- Windows PowerShell/.NET provides the native file picker and temporary background readers.
- **RAR requires installed 7-Zip.** DDS and ZIP do not.
- **F10** opens the standalone editor. No MCM integration or separate binding adapter is required.
- Turn Match Your Colors matching **Off** before editing the same gear.

## Import, edit, apply

1. **Choose file** on Import / Apply. Open DDS, ZIP or RAR; import refreshes live LUTs automatically.
2. Select an **Imported LUT** when a file contains multiple tables.
3. **Apply LUT** sends the selected file LUT to checked **Armor / Helmet** targets.
4. **Save LUT to Palette** overwrites the editor table. It does not apply to gear or export a file.
5. Editor changes preview immediately while Armor and/or Helmet are checked. With both unchecked, edits stay in the editor.

Applications are cumulative: selecting another source does not remove earlier assignments. **Live LUT #** is under Advanced; normal application uses the target checkboxes.

### Quick Scratch

Toggle the movable **Quick Scratch** window. **Left-click selects a palette cell; right-click paints the held color.** Edits update the corresponding LUT Editor row/column, preserve alpha and support Undo/Redo. Ten saved swatch slots start empty each fresh run.

Imported, Armor and Helmet tables retain separate previews. Identical tables within each section are grouped; **Show All LUTs** reveals them individually.

### LUT Editor

- Clickable pixel grid and scrolling **23-column** value editor grouped by rows.
- RGB colors, typed floats, sliders and dropdowns. Advanced material/camo edits require unlocking.
- Selection, drawing, channels, Shift-click rectangles, copy/paste and moving selected pixels.
- Editable row-preset names with a saved-preset dropdown.
- **Preview Palette / Preview Live LUT** open separate read-only swatch/RGBA windows.
- A blank editor offers **Populate editor with current applied palette** from the selected Live LUT's Epic LUT assignment.
- Last tab and chosen window size are retained. Initial opening uses the minimum size. **UI Scale (70–130%)** sits below Epic LUT / Goose in the footer and is limited to fit the display.

## Restore, save and share

**Restore Original** restores original game bindings and clears saved automatic application while retaining the editor document. **Restore Imported / Reset Custom LUT** resets edits to their imported starting values. **Remove LUT** also unloads the document.

**Save applied setup** retains assignments for later launches. **Save / History → Export DDS preset to share** exports full finite float values to `%LOCALAPPDATA%/Epic LUT/files/<name>.dds`. Share that DDS for another user to import. Applying, populating the editor and exporting are separate actions.

## Original-game snapshots

A temporary background reader indexes base-game LUT metadata, matches it to the local equipped Armor/Helmet's original texture objects, and decodes only matching tables. No equipment names or kit IDs are required. Archive decoding runs outside the game thread.

**Preserve Original Emissives** defaults **Off**. It preserves original emissive RGBA and primary shader mode, including zeros. Shorter original tables retain their native row count with corresponding imported color rows. Missing data or insufficient imported rows produces an error instead of guessed values.

Snapshot stages show progress. Worker failures are contained; an expiring editor heartbeat controls reader lifetime. Private caches are separated by game-index fingerprint. No game textures are distributed.

## Formats and limits

Supports **23-column 2D RGBA16F/RGBA32F DDS**, including valid mip chains, and ZIP/RAR containing DDS or standard patch resources with matching GPU/stream sidecars. Archive contents are data, never installed or executed. EXR, bulk conversion and pattern/cape layouts are outside this version.

Other players' units are excluded. Restoration checks ownership and avoids overwriting another mod's changes. Immutable runtime texture buffers remain retained until process exit, bounded to **8 MiB / 2,048 textures**.

Data lives under `%LOCALAPPDATA%/Epic LUT`: `files`, `presets`, `settings`, `cache`, `originals`.

## Testing status

Direct ZIP import and palette application have been confirmed in game during development. Offline checks cover editor interactions, RGB/alpha isolation, history, presets, cumulative assignments, import recovery, floating panels and package integrity.

The reader indexed 2,312 material LUTs; 23 earlier snapshots matched exactly. Narrowed capture saved only requested tables with matching float values. Heartbeat-enabled indexing and heartbeat-expiry shutdown passed offline. **These checks do not certify live startup, snapshot matching, emissive behavior, restart persistence or final UI acceptance.**

Native adapters target Steam build 25480438; game updates may require changes. A floating 3D Player Preview is under investigation, **not included**.

## Build

Python is a **developer build tool only**; users do not need it.

```powershell
python build.py
python tests/test_direct_zip.py
python verify.py
python tests/test_release.py dist/Epic-LUT-R4-RC1.zip
```

The input DLL is pinned from sibling DBF-MCM or `EPIC_LUT_INPUT_LIBRARY`. Snapshot-reader C# and PowerShell source is included; Windows .NET prepares the reader at runtime. No user presets, logs, snapshots or game textures are packaged.

## Credits

Native adapters and foundational LUT research: [CowboyBingus / Match Your Colors](https://github.com/CowboyBingus/MatchYourColors), under the included Zero-Clause BSD license.

[Paydex LUT Editor](https://github.com/paytonrog/paydex-lut-editor) inspired the semantic controls and layout. Epic LUT's editor implementation is independently authored.

Made by **Goose**. Thank you to everyone testing this extremely alpha paint job.
