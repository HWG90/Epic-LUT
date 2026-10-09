# Epic LUT R5.4 - Patch Target Fix

- Exported LUT patches now target the shared base archive, instead of an unrelated archive containing another copy of the texture. The replacement texture remains the selected worn LUT.
- Open Export Location now opens Explorer directly and reports failures.
- Preview Meshes / Masks includes leg-material texture probes and page-wide Black, White and Original controls to identify unwanted preview overlays.
- Pattern editor numeric inputs preview changes while editing.
- Added Scarpheon to the credits for his inexhaustible help testing Epic LUT and tracking down bugs.

## Known issues

- Exported patch loading still needs in-game confirmation. Re-export older patches to use the corrected archive target.
- Player Preview remains experimental; limb caps or damage overlays may remain visible. Mask probes affect only the preview copy.
- Full appearance sharing still needs confirmation with two players. Oversized appearances remain local.

Choose **Epic-LUT-R5.4-LLL.zip** for Live Lua Loader / compatible MDL, or **Epic-LUT-R5.4-BSL.zip** for Arsenal/HD2MM with Bingus Shared Loader v15+. Enable one Epic LUT entrypoint.
