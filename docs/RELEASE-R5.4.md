# Epic LUT R5.4 - Patch Target Fix

- Exported LUT patches now target the shared base archive, instead of an unrelated archive containing another copy of the texture. The replacement texture remains the selected worn LUT.
- Open Export Location now opens Explorer directly and reports failures.
- Removed the temporary preview mesh/material inspector and its debugging probes.
- Added Load Debug LUT under Tools > Options, with the Debug LUT by Plain Furniture.
- Added one-click bulk DDS export for custom gear LUTs and complete saved Armory presets, with five naming formats, export-name prefixes and timestamped folders.
- Pattern editor numeric inputs preview changes while editing.
- Expanded the thank-you to Scarpheon for his dedicated testing and vital help implementing Export to Patch.

## Known issues

- Exported patch loading still needs in-game confirmation. Re-export older patches to use the corrected archive target.
- Player Preview remains experimental; limb caps or damage overlays may remain visible.
- Full appearance sharing still needs confirmation with two players. Oversized appearances remain local.

Choose **Epic-LUT-R5.4-LLL.zip** for Live Lua Loader / compatible MDL, or **Epic-LUT-R5.4-BSL.zip** for Arsenal/HD2MM with Bingus Shared Loader v15+. Enable one Epic LUT entrypoint.
