# Epic LUT R3 Alpha — System Python package

This variant includes no Python interpreter, codecs, runtime ZIP, or nested archives. Python source for the file service is included. The existing native input DLL remains included.

## Required setup before launching the game

1. Install 64-bit Python from https://www.python.org/downloads/windows/. Python 3.13 is the tested version. Windows Store aliases are not supported by this launcher.
2. Extract the complete Epic LUT download to a folder.
3. Open PowerShell in that folder and run:

```powershell
.\setup_companion.ps1 -Python "C:\Path\To\python.exe"
```

The script installs NumPy and OpenEXR into Epic LUT's private dependency folder and records your interpreter path. This requires internet access once. It does not install an embedded interpreter or change game files. If Python can already be found through PATH or the registry, the `-Python` argument can be omitted.

4. Install exactly one mod entrypoint: the BSL data option through Arsenal/HD2MM (BSL v15+), or the complete `armor_lut_editor` folder through LLL/compatible MDL API 2.
5. Launch the game. The local service starts automatically for discovery and file actions. F10 opens the standalone menu after discovery; compatible MCM is optional.

Python and codec setup are mandatory for discovery as well as file import. No browser is required. RAR import also requires installed 7-Zip. The game-owned helper exits on normal game exit or crash. A manually started browser helper is independent.

## Features and limits

Grouped editable color palettes, advanced float editing, camos, presets, undo/redo, hotloading, quick save, Armor/Helmet application, combined restoration, and multi-mip 2D RGBA16F/RGBA32F DDS support remain present. Unknown shader semantics and unsupported texture types are not fabricated or accepted.

This remains an alpha targeting the verified native game build. The direct-keyboard release path retains its previous testing evidence; this package's service/setup checks are offline evidence, not a claim of exhaustive live compatibility. Nexus may still review the remaining input DLL.
