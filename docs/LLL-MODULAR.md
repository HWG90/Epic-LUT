# Modular LLL review package

Build with `py -3 tools/build_lll.py`. Output is `dist/releases/modular-20261010`; LLL R30 or later is required. The package uses `main.lua`, separate modules and `config/defaults.cfg`. Existing archive builders and installed mods are unchanged.

Epic LUT presets, exports and preferences retain their established Local AppData/Epic LUT locations. Shipped preference defaults are editable CFG data. The epiclut.preferences command surface uses the existing preferences handle. Preview animation remains disabled in this ordinary modular candidate.

Active development uses `python tools/manage_dev.py --build --install`, which pairs the unchanged BSL builder with this modular LLL builder and enables authored preview animation in the development variant. Direct modular animation builds require `--preview-animation --output Epic-LUT-Dev-Animation-LLL.zip`; both the preview metadata and private `mod.scope` gate are set together. The standard modular package remains static.

Modules compile and constructors are checked in an isolated LuaJIT process. Activation, input, visuals and resource lifetime still need game validation. This work does not deploy the package.
