# Modular LLL package

Build with `python tools/build_lll.py`. Output is `dist/releases/modular-20261010`; **LLL R30 or later is required**. This package uses `main.lua`, separate modules, private `mod.scope` and `config/defaults.cfg`. The modular package cannot run in MDL.

For MDL, use `python build.py --loader mdl` and its standalone API-2 `mod.lua` folder package. That bundled MDL package can also load through LLL's legacy compatibility route. The compatibility is one-way: LLL's modular package depends on LLL's module and configuration APIs. Installation details are in [MDL-LLL.md](MDL-LLL.md).

Epic LUT presets, exports and preferences retain their established Local AppData/Epic LUT locations. Shipped LLL preference defaults are editable CFG data. The `epiclut.preferences` command surface uses the existing preferences handle. The ordinary modular package keeps the default idle preview with authored animation disabled.

Active development uses `python tools/manage_dev.py --build --install` to build matching static and animation variants for BSL, MDL and modular LLL while defaulting local installation to static LLL with the idle preview. `--animation` explicitly selects the animation candidate. Shared source and payloads retain parity. Direct modular animation builds require `--preview-animation --output Epic-LUT-Dev-Animation-LLL.zip`; preview metadata and the private animation gate are set together.

Modules compile and constructors are checked in an isolated LuaJIT process. Build checks, installed bytes, loader activation and observed game behavior are separate checkpoints. Running the modular builder alone does not deploy the package.
