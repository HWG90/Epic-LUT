# Epic LUT R5.7.1 - MDL API-2 package

The MDL ZIP contains the same Python-free editor as BSL, packaged as a standalone API-2 folder mod. Its entrypoint is `armor_lut_editor/mod.lua`. It contains no BSL startup archive and does not require Live Lua Loader to activate.

## MDL installation

1. Close the game before replacing an existing Epic LUT package.
2. Extract the complete `armor_lut_editor` folder into your compatible MDL loader's configured mod directory.
3. Keep `mod.lua`, `manifest.json`, `library.txt` and the included input DLL together.
4. Enable Epic LUT through MDL, start the game and press F10 for the editor.

The loader must support `on_enable(context)`, `on_update(context, dt)`, `on_disable(context)` and an API-2 context with an absolute `dir`, `log` and `on_cleanup`. Directory locations vary by MDL installation; use your loader's configured location rather than the game's data directory.

The bundled MDL entrypoint does not use LLL's `main.lua`, `mod.require`, private module scope or `config/defaults.cfg`. Its preferences, presets and exports retain the established `%LOCALAPPDATA%/Epic LUT` locations. The ordinary package keeps the default idle preview; authored animation requires a separately named development build.

## LLL compatibility

The MDL folder can also load through LLL's legacy API-2 compatibility route. Extract the complete folder into `%LOCALAPPDATA%/LLL/Helldivers2/Mods`, then enable it through LLL. LLL R18 and newer support this lifecycle.

The separate **LLL R30 modular package** uses `main.lua`, separate source files and CFG defaults. It requires LLL and cannot be used as an MDL package. Choose the ZIP matching your loader; do not copy one entrypoint into the other package.

## Requirements and duplicate copies

No Python installation, pip, browser or MCM integration is required in-game. Windows PowerShell/.NET supplies the picker and temporary readers. RAR import requires installed 7-Zip. Turn Match Your Colors matching Off before editing the same gear.

Enable exactly one Epic LUT entrypoint. Disable the older `epic_player_preview` test sidecar; R5 includes Player Preview. Disable the BSL Epic LUT archive when switching to this folder package. LLL also scans some legacy MDL locations, so do not leave the same folder enabled in multiple roots.

The bundled model and native DLL match BSL when built with the same preview mode and development stamp. Scripts and CowboyBingus attribution remain included. See README.md for controls, compatibility and credits.

## Building the MDL package

From the canonical Epic-LUT checkout:

```powershell
python build.py --loader mdl
```

Output: `dist/Epic-LUT-R5.7.1-MDL.zip`. The former `--loader loose` option remains an alias for MDL and now uses the MDL filename by default. To build LLL R30's modular package, use `tools/build_lll.py` instead. MDL is an **Optional File** on Nexus, alongside the optional LLL package; BSL is the Main File.
