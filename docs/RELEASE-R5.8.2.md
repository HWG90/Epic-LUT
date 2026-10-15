# Epic LUT R5.8.2 — Shared LUT Compression

- Shared LUT automatically compares full tables, sparse deltas, XOR, native LZNT1/XPRESS and dictionary layouts. New dictionary orderings and exact destination masks reduce packet size without quantization or lost assignments. Both players need R5.8.2 or R6 Alpha 3 for the new EL7 packets; older supported packets remain readable.
- Deterministic stress fixture: 32 distinct LUTs and 4,096 shuffled assignments shrink from 17,081 to 1,113 characters, with every F32 bit and assignment verified. Supplied Desert preset: 3,437 to 2,889 characters across all 176 assignments. Truly random oversized data remains local rather than being truncated. The reported 4,953-character sender payload has not been reproduced exactly.
- Shared LUT recovery handles late material readiness, game-reset bindings and failed applies while preserving independent armor/helmet Pattern palettes. Stable-lobby and ownership checks remain.
- Preset-list X buttons now confirm deletion. Existing row/Armory overwrite warnings can be suppressed after saving and restored in Configuration.
- Import loose .patch_NUMBER archives with adjacent .gpu_resources/.stream sidecars. Existing ZIP/RAR extraction and Apply Matching LUTs retain resource IDs; importing alone does not recolor gear.
- LUT Editor Tools > Rows offers Arrowhead restore for this LUT, row or selected cells, with Undo/Redo. Loaded mod colors and bundled Arrowhead snapshots stay distinct; unknown or mismatched originals are refused.
- Hardware cursor selection supports Helldivers and Windows modes through the reviewed helper. Helldivers artwork appearance still needs visual confirmation.

Install exactly one package: BSL through your mod manager with Bingus Shared Loader v15+, modular LLL R30+ in its Mods folder, or MDL API 2 with bundled mod.lua. Standard static Idle preview is included. Retain your settings/presets and disable any duplicate Epic LUT installation. Restart normally if upgrading an older native input helper.

Validation: focused codec/recovery/ownership tests and exact stress-preset roundtrips passed. All three loader packages are built from the tagged source. Real two-player testing of this compression build remains pending. Nexus publication is on hold.
