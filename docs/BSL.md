# Bingus Shared Loader alone

The R3 ZIP has two entrypoints for the same editor. Choose one:

- Import the ZIP in Arsenal/HD2MM and select its **Bingus Shared Loader startup** option. Bingus Shared Loader v15+ is required; current v19 is recommended. MCM, LLL and MDL are optional. The plaintext addon `mods/goose/epic_lut/startup` creates an API-2 context adapter, starts the same descriptor, and preserves the previous update/shutdown callbacks and every return value. It ships no Wwise or boot replacement. Install/deploy/restart manually for this archive path; startup compatibility is awaiting live validation.
- Extract the `armor_lut_editor` folder for LLL/MDL's supported API-2 lifecycle. Do not activate this loose copy alongside the startup archive. Owner guards reject duplicate initialization.

The package auto-detects compatible MCM; otherwise its own in-game menu is used. An older incompatible MCM must be updated or disabled to avoid competing input ownership. The pinned input DLL is embedded in the BSL entry and extracted into `%LOCALAPPDATA%/Epic LUT/cache` only when absent; an existing different library is refused. Both loader paths use `%LOCALAPPDATA%/Epic LUT/settings`, `files` and `presets`. No loader-specific settings or palettes are migrated or deleted.

The package includes the official Windows x64 embeddable Python runtime, NumPy and OpenEXR. File actions automatically unpack the runtime into the private cache and start the service. Keep the package stream file installed: it carries the BSL runtime bundle. The loose entrypoint carries the same bundle in `armor_lut_editor/runtime.zip`. Neither path requires an installed Python interpreter, pip, a setup script or a browser. RAR extraction requires installed 7-Zip.

Set **Extras → Epic LUT menu key** in either frontend, or use **Reset menu key to F10**. The shared preference lives in `settings/epic_lut_preferences.ini`. With MCM present, F10 remains MCM's global open/close key; Epic LUT does not change it or toggle it twice. A custom shortcut opens/focuses Quick Load. In the own menu, the configured shortcut toggles it.

Optional Mod Bindings Menu v2+ registers **Epic LUT → Open Epic LUT** with an automatically assigned action. Assign its keyboard/mouse/controller binding on the game's MODS binding tab. That action's mappings remain owned and saved by Bingus; its API has no mapping setter or unregister method, so Epic LUT never overwrites assignments and stops polling on disable. The shared Epic LUT keyboard preference remains a fallback/additional shortcut, not a claim that a virtual-key setting represents native controller/activation mappings. Foreground, editor typing/rebinding and native cursor-UI guards suppress inappropriate activation. Own-menu navigation is keyboard/mouse; native binding activation is supported as exposed by Bingus, with live controller validation still pending.

Protocol references: [BSL addon authoring](https://github.com/CowboyBingus/BingusSharedLoader/blob/main/docs/AUTHORING.md), [Mod Bindings Menu API](https://github.com/CowboyBingus/ModBindingsMenu#for-mod-authors). Packaging is independently authored using the existing owned archive reader/writer; third-party loader implementation is not included.

A successful import switches the original Match Your Colors setting Off through its own provider. Cancel and invalid files leave that setting unchanged. The game-launched file service exits when the game closes or crashes. Manual browser-editor startup remains independent of game lifetime.
