# Epic LUT R5.5.2 — MDL / LLL package

Same Python-free editor as the BSL release, packaged as an API-2 folder mod. This ZIP contains no BSL startup archive and does not require BSL for activation.

## Live Lua Loader

1. Close the game before replacing an existing Epic LUT package.
2. Extract the complete `armor_lut_editor` folder into `%LOCALAPPDATA%/LLL/Helldivers2/Mods`.
3. Confirm `Mods/armor_lut_editor/mod.lua`, `manifest.json`, `library.txt` and the included input DLL are together.
4. Start the game, refresh LLL's mod list if needed, then enable Epic LUT. Press F10 for the editor.

LLL R18 and newer support the MDL-style API-2 lifecycle used here. Use the complete folder: copying only `mod.lua` omits the native input companion.

## MDL

Place the complete `armor_lut_editor` folder in your compatible MDL loader's configured mod directory, then enable it through that loader. The loader must support `on_enable(context)`, `on_update(context, dt)`, `on_disable(context)` and an API-2 context with an absolute `dir`, `log` and `on_cleanup`.

MDL directory locations vary by installation. Use the directory configured by your loader rather than copying files into the game data directory.

## Requirements and duplicate copies

No Python installation, pip, browser or MCM integration is required. Windows PowerShell/.NET supplies the picker and temporary readers. RAR import requires installed 7-Zip. Turn Match Your Colors matching Off before editing the same gear.

Enable exactly one Epic LUT entrypoint. Disable the older epic_player_preview test sidecar; R5 includes Player Preview. Disable the BSL Epic LUT archive if switching to this folder package. LLL also scans some legacy MDL locations, so do not leave the same folder enabled in multiple roots.

The folder model and native DLL match the BSL package. See README.md for controls, compatibility and credits.
