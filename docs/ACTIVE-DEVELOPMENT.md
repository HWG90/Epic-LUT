# Managed Epic LUT development

The active development deployment uses the integrated LLL editor with the default idle preview. Animation testing is preserved separately and remains disabled in the active copy until requested. Shared fixes must have parity with both builds. They use the same source; only animation metadata and the animation gate may differ. Published release ZIPs remain immutable.

Build, check both variants and update the installed development copy:

```powershell
python tools/manage_dev.py --build --static --install
```

The first installation or explicit adoption after the modular migration requires `--expect-installed` with the current installed entrypoint SHA-256 (`main.lua` for LLL R30 projects). Later installations check the recorded hashes in `dist/deployment/active.json` and refuse to overwrite untracked changes. Running without `--install` leaves installed files alone.

The workflow builds matching Static and Animation BSL/modular LLL packages, checks their shared code and payloads, and saves receipts under `dist/deployment`. LLL uses `tools/build_lll.py`, `main.lua` and separate modules; BSL retains its archive builder. Modular deployment validates the installed checksum inventory, backs up changed source and metadata files, and publishes `main.lua` last. It preserves the native DLL, loader settings, shipped defaults and saved presets. Partial replacement failures restore files only while they still match this deployment's writes.

Each paired build gets one shared development ID, printed in the preview startup log. This also lets another managed build retrigger LLL's normal auto-reload after deferred cleanup finishes. A pending cleanup must finish before retrying; the helper never bypasses it.

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
