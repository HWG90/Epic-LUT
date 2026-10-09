# Epic LUT R5.5.2

**STYLISH FREEDOM. Defend Freedom in Style.**

Paint your Helldiver in-game. Match your helmet to your armor, build a color scheme from scratch, or get into the full material table. R5.5.2 brings a roomier editor, clipboard shortcuts, named gear presets and bulk DDS export into one package.

[Download R5.5.2](https://github.com/HWG90/Epic-LUT/releases/tag/R5.5.2) | [Report bugs](https://github.com/HWG90/Epic-LUT/issues)

## Install

Choose one package:

- **BSL:** import `Epic-LUT-R5.5.2-BSL.zip` through Arsenal/HD2MM and enable the startup option with **Bingus Shared Loader v15+**.
- **LLL / compatible MDL:** extract the complete `armor_lut_editor` folder from `Epic-LUT-R5.5.2-LLL.zip` into your loader's Mods directory. LLL uses `%LOCALAPPDATA%/LLL/Helldivers2/Mods`. Enable Epic LUT. [Installation details](docs/MDL-LLL.md).

Enable one Epic LUT entrypoint. Disable the separate **epic_player_preview** test addon before enabling R5.5.2: preview is now included.

No Python or MCM installation required. Windows PowerShell/.NET handles file picking and archive reads. **RAR requires installed 7-Zip.** Turn **Match Your Colors matching Off** before editing the same gear.

## Sharing and Pattern LUTs

**Shared Lobby LUT is in testing.** Share Armor, Helmet and Pattern LUTs with compatible Epic LUT users. Both players need this version, with **Share full LUT appearance with Epic LUT users** enabled in Configuration. Updates wait for a stable squad lobby and settled edits. Appearances that exceed the lobby packet limit remain local. [Sharing details](docs/UPSTREAM-MYC-INTEGRATION.md).

**LUT Editor** now opens a separate movable **Pattern LUT Editor** popup for 3x1 pattern tables: color, metallic RGB, opacity, raw unknown values, undo/redo, DDS export and Pattern Patch ZIP export. Import a 3x1 DDS through the normal chooser, then apply it explicitly to the selected Pattern LUT. **Show Alpha** is shared between the main grid and popup. [Pattern controls](docs/PATTERN-LUTS.md).

## Roomier LUT Editor

The Pixel Grid uses the full height above a compact action bar. **Hide Values** gives it the inspector's width; **Show Values** restores the numeric editor. The setting is remembered.

Use the gold **Tools** button to open the movable toolbox and reveal **Import**, **Rows**, **Export**, and **Options** beside it. They switch the same toolbox. **Scratch** opens a separate brush palette with color and alpha controls; it can stay open alongside the toolbox. Export keeps the shared format selector and timestamped filenames.

**Tools > Options > Load Debug LUT** loads the bundled 23x8 Debug table by **Plain Furniture** into the editor. Each load starts with a fresh copy; use the Apply controls to send it to gear.

For one-click DDS export of every custom LUT currently applied to your Armor and Helmet, choose **Tools > Export > All Custom LUTs (DDS)**. Pick **LUT# + HEX**, **LUT# + Decimal**, **LUT#**, **HEX**, or **Decimal** naming, then press **Export**. The export name prefixes every file, for example `HONK LUT3-d3ce605892d5331b.dds`. Each batch gets a new timestamped folder under the export location. Pattern LUTs are included as `PatternLUT#`; unknown IDs use the LUT number.

To export a saved Armory collection without equipping it, select the preset and choose **Raw DDS (entire preset)**. **Save Current Gear Preset** keeps the currently applied Armor and/or Helmet LUTs in the app for later reuse.

Closing or popping out Player Preview returns its reserved grid width. Tools, Scratch and Pattern Editor can stay open independently.

The active tools shortcut stays highlighted. Clicking it again keeps its window open; use that window's close button to close it. The LUT dropdown sits indented below Helmet/Armor, with Pattern Editor beside those gear buttons. Settings and the footer share one UI scale. Windows and popouts have visible borders.

## Larger tables and custom rows

Material LUTs with up to **64 rows** remain editable. Scroll over the Pixel Grid or use its row-page buttons; choosing a row brings it into view. Basic's region list and the Value Editor scroll separately. Region labels flash the actual selected row on the model when that material uses it.

Tables above eight rows retain their added rows when Preserve Original Emissives is enabled. Original values are preserved for the rows present in the game snapshot; extra rows keep the imported values. DDS and patch export retain the custom row count. The model must reference those rows for them to be visible.

## Start with Basic

Press **F9**, then **Load Current Armor & Helmet**. Choose the LUT above either column, then click a region color to edit it. Colors apply live to that table; alpha and material values remain intact. Gear selectors stay gray until current or imported LUTs are ready. Gold Load buttons pulse until their first use.

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

Press **F10**, then **Import / Apply** for full table previews. Every loaded Armor and Helmet LUT appears in its own scrollable column. Click a table's title or texture hash to select it; selecting a title leaves its colors unchanged. **Send to LUT Editor** copies the selected imported table into the editor.

Matching uses texture IDs, not armor names or table order. Archives can contain gear you are not wearing; use manual targeting when no IDs match.

Applied Armor, Helmet and Cape material LUTs, plus Pattern LUTs, are retained during loading gaps and automatically restored to matching worn gear when the game recreates its materials. Recovery reuses the applied texture without changing its values. Different gear and bindings owned by another writer are left untouched; Restore clears the retained appearance.

## Pick, paint, copy

On Import / Apply swatch previews:

- **Left-click:** select.
- **Double-click:** edit color.
- **Right-click:** paint the held Quick Scratch color into that cell.
- **Middle-click:** copy into Quick Scratch.

Painting targets the clicked gear table. **Undo Last Action / Redo Last Action** includes imports and gear applications. The LUT Editor also provides pixel-edit undo/redo and copy/paste.

**Quick Scratch** opens a movable color panel with ten session swatch slots. Pick a color once and paint it where you need it. Scratch Copy/Paste uses system clipboard hex colors; the color picker HEX field also supports Ctrl+C/V.

## LUT Editor

Choose **Load Current Gear**, then **Armor LUT** or **Helmet LUT** and a table. Loading reads every current worn LUT, including stock-game values. The Import toolbox includes Apply to All Armor LUTs or Apply to All Helmet LUTs beneath its selected-table action; it applies the current editor table.

The labeled grid covers all **23 columns**, with a collapsible row value editor. Edit RGB, type floats, use material/camo selectors, or unlock advanced channels. Bump-map choices show R0-R25 alongside their material names, in actual column-2 R-value order. Drag in Select mode to select a rectangle; Shift-click also extends it. Ctrl+C/V copy and paste the grid selection, Ctrl+Z undoes an edit, and Ctrl+Shift+Z (or Ctrl+Y) redoes it. Click or drag row labels in Select mode to select whole rows; Shift-click extends the row range. Copy, select the destination rows, and paste from their top-left row. Full-row paste includes every RGBA channel and requires Advanced editing. Selected swatches keep their colors inside an outline. Grid tools also support drawing and moving pixels. Double-click color cells opens the picker; middle-click also copies the full pixel.

Open the collapsible **Cape Material** section beneath the main LUT table to load and edit the worn cape's 23-column material table. Its selector, edits, history and Load/Apply/Restore controls stay separate from Armor and Helmet.

The Pattern LUT Editor is an independent window and can stay open alongside Tools and Scratch.

Select a Value Editor channel, then use Copy Value/Paste Value to transfer its raw number. Clipboard paste respects the advanced editing lock. Text fields support click/drag selection, Shift+arrow selection, Home/End, and Ctrl+A/C/X/V while typing. Held letters, Backspace/Delete and navigation keys repeat after a short delay.

Typed values can exceed recommended slider ranges. Swatches clamp RGB for viewing; stored floats remain intact. Export edited DDS files to `%LOCALAPPDATA%/Epic LUT/files/exports` to share them.

## Player Preview

Use **Player Preview** or **F6** to see your worn character while editing. It docks beside the LUT Editor and can pop out on other pages. Armor and Helmet edits update the copied model live.

- Left-drag pans; right-drag rotates; mouse wheel zooms.
- Drag the title to move a floating panel; drag its corner to resize.
- **Pop Out / Dock** changes placement.

Menu and Player Preview native rendering pause when the game loses focus or its display dimensions are invalid, and resume when foreground rendering is ready. Close the preview or editor before switching game screens.

SDK names come from a compact, pinned Community Edition catalog. Unknown resources and shader parents remain unknown. [SDK integration details](docs/SDK-INTEGRATION.md).

Preview uses the game's lighter **Game Default UI pipeline**, with an independently owned model and portrait target. [Full Render vs Game Default](docs/PREVIEW-RENDER-PATH.md).

## The Armory

**Save to Armory / Save Current Gear Preset** asks for **Armor Only, Helmet Only, or Both**, then a name.

Select a preset to preview it. Name-selector swatches give a quick glance; the full preview shows every saved LUT. Apply either half separately to mix and match. Type labels show included gear. **Rename Preset** changes its name; **Delete Preset** asks before removing it from the library.

Presets live in `%LOCALAPPDATA%/Epic LUT/presets`. Library changes leave worn colors unchanged.

To share a saved look, select it in **The Armory**, enter an export name and choose a format:

- **Shareable Preset ZIP:** includes every saved Armor, Helmet and Pattern LUT. Use **Import Shared Preset** in The Armory to add it to another library.
- **Selected LUT Patch ZIP:** packages the selected saved table for a mod manager.
- **Entire Preset Patch ZIP:** packages all tables in that preset together.
- **Raw DDS:** exports the selected saved table for another editor.

Exports use the saved preset, including its original texture destinations. Older presets still load; resave them to capture destination metadata before patch export. Filenames receive a timestamp and export folders open through **Open Export Location**.

## Restore and configure

**Restore Arrowhead LUT (Original)** restores original bindings and refreshes displayed colors. **Restore Imported** resets editor values to the imported file.

**Preserve Original Emissives** defaults Off. It preserves original emissive RGBA and primary shader mode, including zeros. Missing snapshots or insufficient source rows produce an error instead of guessed values.

**Configuration** lets you rebind Basic, Advanced and Player Preview shortcuts; adjust UI scale, fonts and window size; and display LUT IDs in hex or decimal. Keys have readable names such as **Insert** and **F9**.

Settings are grouped in two scrollable columns. **Always populate all LUT slots from current gear** loads Armor and Helmet tables after equipment changes. **Turn off Player Preview** remembers your choice and disables its shortcut and automatic dock until you enable it again.

When DBF-MCM is available, **Epic LUT Settings** appears there too. Both menus use the same saved values; its editor shortcuts open Basic or the LUT Editor directly.

**Check for Updates** checks the public GitHub release. Automatic checks are opt-in, once per launch, and never install anything.

## Compatibility

Supports 23-column 2D RGBA16F/RGBA32F DDS, valid mip chains, and ZIP/RAR containing DDS or supported patch resources with GPU/stream sidecars. Mesh-only archives contain no palettes to import.

Native adapters target Steam build **25480438**; game updates may require changes. Packages contain no user settings, presets, logs, snapshots or game textures.

## Credits

### A huge thank you to Scarpheon

A huge thank you to **Scarpheon** for all the time he has dedicated to helping me build a better tool for people.

His testing, bug reports, and continued assistance were vital to getting **Export to Patch** implemented correctly and working reliably. He kept trying builds, checking the results in-game, and helping me work through the problems until we got it right.

And a **massive additional thank you to Scarpheon for mapping every bump map**. He worked through all 26 entries, matched their actual column-2 R values, and gave us useful names instead of a list of mystery numbers. Flat grime, suede, denim, wool, leather, metal, circuitboard: those readable choices are here because he put in the time to identify them.

That mapping makes material editing easier for everyone using this tool. Alongside his repeated testing and Export to Patch work, it is a substantial contribution to what Epic LUT has become. **Scarpheon, thank you for the patience, the detail, and the continued help. You have made this a much better tool for people.**

That work deserves more than a name in a credits list. Epic LUT is a better tool because of the time and care he has put into it. **Thank you, Scarpheon. Your help made this possible.**

**Plain Furniture** created the bundled **Debug LUT**.

Made by **Goose**. Thanks to everyone helping make Epic LUT better.

Native adapters and foundational LUT research: [CowboyBingus / Match Your Colors](https://github.com/CowboyBingus/MatchYourColors), under the included Zero-Clause BSD license.

[Paydex LUT Editor](https://github.com/paytonrog/paydex-lut-editor) inspired the semantic controls and layout. Epic LUT's implementation is independently authored.

Thank you to **Shikami** for the **Region Indicator** idea, and [**Lytatroan**](https://www.nexusmods.com/profile/Lytatroan) for the human-made thumbnail.
