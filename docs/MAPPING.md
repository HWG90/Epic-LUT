# Mapping reference

Navigation: **Epic LUT → Armor → Semantics / grid cell** for armor; **Helmet → Semantics / grid cell** for the helmet. Each editor selects **actual LUT resource → numbered row → semantic field → channel**. LUT count, row count and mesh/material binding count are different quantities. All eight material rows are available when a LUT is 23×8; they are not eight additional LUT resources.

Material field numbering follows research on 23-column LUTs. Base Color is column 1 (zero-based pixel column 0). RGB recolors; alpha carries shader behavior. Camo colors are columns 17–20; camo fade is column 21 alpha; column 22 contains selector/scale/pattern controls. Unknown fields remain unknown. Semantic names describe parameters, not named armor surfaces.

## Emission

The current research mapping describes column 14 R as emission strength (small values around 0.001–0.06); other channels and dependencies are uncertain. It is **not a confirmed RGB emission-color picker**. Effect protection makes it read-only and disables the irrelevant color picker. Deliberately unlock material effects to experiment with raw strength; this does not establish that every shader consumes it the same way.

Glow color can follow Base Color. The examined helmet's eye tint changed through material LUT 1, row 8, Base Color. This is an observed per-item row mapping, not a universal row-8 rule. On Live Wire, LUT `800b5d4ab3fdd044`, row 2 has red base RGB and can influence indicator tint. Preserving emission/mode floats does not guarantee unchanged emitted hue.

## File values and overrides

The working document holds Float32 RGBA values, including HDR/negative values. RGB swatches clip for preview and color-picker representation only. Disabled rows render their originals; committed edits activate their row. The full document is authoritative; old RGB settings are compatibility metadata and do not form another render layer.

Restore original colors disables application while retaining the document. Reset Custom LUT Rows resets every original/current row value and clears overrides. Full-float v2 presets retain target identity and all cells; legacy armor v1 imports are supported. Helmet presets cannot silently apply to armor.

Research references: [Paydex material mapping](https://github.com/paytonrog/paydex-lut-editor/blob/main/mappings/mappings_8x23.json), [pattern mapping](https://github.com/paytonrog/paydex-lut-editor/blob/main/mappings/mappings_1x3.json), [cape mapping](https://github.com/paytonrog/paydex-lut-editor/blob/main/mappings/mappings_5x16.json). Equivalent code/descriptions are independently authored; no unlicensed Paydex implementation is vendored.

Quick Load's remapper uses the original target-sized buffer, then maps only named fields. Unknown material columns 9, 12 and 16 and emission GBA always retain the target originals. Same-layout rows are nearest proportional, aligning first/last source and target rows; one-row sources repeat. Material preservation retains non-color values and color alpha/mode; emission preservation independently retains column 14 R as well. Across different recognized layouts, only shared Base Color RGB is mapped. Source choice is exact resource first, then same layout, nearest row count and stable resource/name order. These rules are a bounded remapping recipe, not a claim that material regions correspond between items.
