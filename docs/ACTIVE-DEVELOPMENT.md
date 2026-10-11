# Managed Epic LUT development

Maintain three package targets: BSL, modular LLL and standalone API-2 MDL. Modular LLL is the default local build and installation target, with the default idle preview. Animation testing is preserved separately and remains disabled in the active copy until explicitly selected. Every shared fix is included in Static and Animation packages for all three targets. They use the same source; only animation metadata and the animation gate may differ. Published release ZIPs remain immutable.

Build and check all six archives, then update the installed static LLL development copy:

```powershell
python tools/manage_dev.py --build --install
```

The first installation or explicit adoption after the modular migration requires `--expect-installed` with the current installed entrypoint SHA-256 (`main.lua` for LLL R30 projects). Later installations check the recorded hashes in `dist/deployment/active.json` and refuse to overwrite untracked changes. Running without `--install` leaves installed files alone.

The workflow builds matching Static and Animation packages for all three loaders, checks their shared code, DLL and helper payloads, and saves receipts under `dist/deployment`. LLL uses `tools/build_lll.py`, `main.lua` and separate modules. BSL and MDL use `build.py --loader bsl` and `build.py --loader mdl`; their bundled `mod.lua` bytes are identical for each preview variant. BSL includes its startup archive; MDL is a standalone API 2 bundle without an archive provider.

The local selection defaults to Static LLL. `--static` remains an explicit equivalent; `--animation` selects the separate animation candidate only when requested. Building packages does not change the local provider to BSL or MDL. LLL also supports the legacy MDL package; MDL cannot use LLL's modular entrypoint.

BSL and MDL archives are written to `dist/Epic-LUT-Dev-{Static|Animation}-{BSL|MDL}.zip`. Modular LLL archives are written to `dist/releases/modular-20261010/Epic-LUT-Dev-{Static|Animation}-LLL.zip`. The MDL ZIP is copied and enabled independently in MDL; this helper never installs or activates it. Enable one Epic LUT provider at a time.

Modular deployment validates the installed checksum inventory, backs up source and metadata files, and publishes `main.lua` last. It preserves the native DLL, loader settings, existing shipped defaults and saved presets. Authorized defaults migrations may add `preferences.include_patterns_in_exports=true` and `preferences.tools_docked=true`; every preexisting key, value and type must remain unchanged. `config/settings.cfg` and saved user preferences are never replaced. Partial replacement failures restore files only while they still match this deployment's writes.

All six archives get one shared development ID, printed in the preview startup log. This also lets another managed build retrigger LLL's normal auto-reload after deferred cleanup finishes. A pending cleanup must finish before retrying; the helper never bypasses it.

Switch to the current static build while retaining all shared development fixes:

```powershell
python tools/manage_dev.py --static --install
```

The preserved R5.5.4 release uses the legacy `mod.lua` layout. Its rollback command is available for legacy installations:

```powershell
python tools/manage_dev.py --rollback --install
```

The R5.5.4 BSL and LLL archives are preserved in `dist/deployment/baselines/R5.5.4`. Each deployment also records a separate backup of the actual previously installed files, even if their metadata was old.

Use `--static --install` for a modular rollback. The helper refuses to mix the legacy entrypoint into a modular installation.

Enable one Epic LUT copy. With LLL auto-reload enabled, file updates use its normal cleanup and reload path; otherwise load them through the loader or next game launch. The helper does not force native cleanup, enable another copy or restart the game. A build pass, installed bytes, loader acknowledgment and observed preview animation are separate checkpoints. Future authorized development changes follow this managed path; publication remains a separate action.
