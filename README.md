# Epic LUT R5.2

**STYLISH FREEDOM. Defend Freedom in Style.**

Paint your Helldiver in-game. Match your helmet to your armor, build a color scheme from scratch, or get into the full material table. R5.2 brings live character preview, named gear presets and fast per-LUT editing into one package.

**Still extremely alpha and work in progress.** [Download R5.2](https://github.com/HWG90/Epic-LUT/releases/tag/R5.2) | [Report bugs](https://github.com/HWG90/Epic-LUT/issues)

## Install

Choose one package:

- **BSL:** import `Epic-LUT-R5.2-BSL.zip` through Arsenal/HD2MM and enable the startup option with **Bingus Shared Loader v15+**.
- **LLL / compatible MDL:** extract the complete `armor_lut_editor` folder from `Epic-LUT-R5.2-LLL.zip` into your loader's Mods directory. LLL uses `%LOCALAPPDATA%/LLL/Helldivers2/Mods`. Enable Epic LUT. [Installation details](docs/MDL-LLL.md).

Enable one Epic LUT entrypoint. Disable the separate **epic_player_preview** test addon before enabling R5.2: preview is now included.

No Python or MCM installation required. Windows PowerShell/.NET handles file picking and archive reads. **RAR requires installed 7-Zip.** Turn **Match Your Colors matching Off** before editing the same gear.

## Start with Basic

Press **F9**. Your worn Armor and Helmet colors load into separate columns. Choose the LUT above a palette, then click a region color to edit it. Colors apply live to that table; alpha and material values remain intact.

- Click a **Region** label to flash it magenta on your character. **Stop Highlight** ends it immediately.
- **Copy Helmet / Copy Armor** transfers the selected table to the opposite gear. **Copy Helmet to All** transfers it to every worn Armor LUT.
- **Advanced Mode** in the header opens the full editor; **Basic Mode** brings you back.
- Hover for guidance. Extra import controls appear only after loading a file.

## Import and apply

1. Choose **Import DDS / ZIP / RAR**. Expand archive folders and choose a gold variant folder containing LUTs. Import loads colors without installing archive content.
2. Choose the imported table: `lut001.dds` is LUT 1. Its swatch strip previews the primary colors.
3. Use **Single LUT Import** beneath either Basic column for one destination. Its button shows the source file, destination LUT and bracketed texture ID.
4. Use **Apply LUT N to All Armor / Helmet LUTs** to apply the selected source across that gear.
5. **Apply Matching LUTs** maps patch tables by resource ID to your worn gear. Unmatched, unidentified and duplicate-ID entries stay untouched.

Press **F10**, then **Import / Apply** for full table previews. Each gear has its own LUT selector. **Send to LUT Editor** copies the selected imported table into the editor.

Matching uses texture IDs, not armor names or table order. Archives can contain gear you are not wearing; use manual targeting when no IDs match.

## Pick, paint, copy

On Import / Apply swatch previews:

- **Left-click:** select.
- **Double-click:** edit color.
- **Right-click:** paint the held Quick Scratch color into that cell.
- **Middle-click:** copy into Quick Scratch.

Painting targets the clicked gear table. **Undo Last Action / Redo Last Action** includes imports and gear applications. The LUT Editor also provides pixel-edit undo/redo and copy/paste.

**Quick Scratch** opens a movable color panel with ten session swatch slots. Pick a color once and paint it where you need it.

## LUT Editor

Select **Armor LUT** or **Helmet LUT**, then a table. Populating reads current worn colors, including stock-game LUTs.

The labeled grid covers all **23 columns**, with a collapsible row value editor. Edit RGB, type floats, use material/camo selectors, or unlock advanced channels. Shift-click selects a rectangle; grid tools support drawing, copy/paste and moving pixels. Double-click color cells opens the picker; middle-click also copies the full pixel.

Typed values can exceed recommended slider ranges. Swatches clamp RGB for viewing; stored floats remain intact. Export edited DDS files to `%LOCALAPPDATA%/Epic LUT/files` to share them.

## Player Preview

Use **Player Preview** or **F6** to see your worn character while editing. It docks beside the LUT Editor and can pop out on other pages. Armor and Helmet edits update the copied model live.

- Left-drag pans; right-drag rotates; mouse wheel zooms.
- Drag the title to move a floating panel; drag its corner to resize.
- **Pop Out / Dock** changes placement.

Close the preview or editor before switching game screens. Player Preview is experimental; broader equipment and screen transitions still need testing.

## The Armory

**Save to Armory / Save Current Gear Preset** asks for **Armor Only, Helmet Only, or Both**, then a name.

Select a preset to preview it. Name-selector swatches give a quick glance; the full preview shows every saved LUT. Apply either half separately to mix and match. Type labels show included gear. **Rename Preset** changes its name; **Delete Preset** asks before removing it from the library.

Presets live in `%LOCALAPPDATA%/Epic LUT/presets`. Library changes leave worn colors unchanged.

## Restore and configure

**Restore Arrowhead LUT (Original)** restores original bindings and refreshes displayed colors. **Restore Imported** resets editor values to the imported file.

**Preserve Original Emissives** defaults Off. It preserves original emissive RGBA and primary shader mode, including zeros. Missing snapshots or insufficient source rows produce an error instead of guessed values.

**Configuration** lets you rebind Basic, Advanced and Player Preview shortcuts; adjust UI scale, fonts and window size; and display LUT IDs in hex or decimal. Keys have readable names such as **Insert** and **F9**.

**Check for Updates** checks the public GitHub release. Automatic checks are opt-in, once per launch, and never install anything.

## Compatibility

Supports 23-column 2D RGBA16F/RGBA32F DDS, valid mip chains, and ZIP/RAR containing DDS or supported patch resources with GPU/stream sidecars. Mesh-only archives contain no palettes to import.

Native adapters target Steam build **25480438**; game updates may require changes. This alpha does not certify every loader, screen transition, multiplayer scenario or long session. Packages contain no user settings, presets, logs, snapshots or game textures.

## Credits

Made by **Goose**. Thanks to everyone testing this extremely alpha paint job.

Native adapters and foundational LUT research: [CowboyBingus / Match Your Colors](https://github.com/CowboyBingus/MatchYourColors), under the included Zero-Clause BSD license.

[Paydex LUT Editor](https://github.com/paytonrog/paydex-lut-editor) inspired the semantic controls and layout. Epic LUT's implementation is independently authored.

Thank you to **Shikami** for the **Region Indicator** idea.
