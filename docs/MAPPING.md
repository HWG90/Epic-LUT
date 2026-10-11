# Mapping reference

Navigation: **Epic LUT → Armor → Semantics / grid cell** for armor; **Helmet → Semantics / grid cell** for the helmet. Each editor selects **actual LUT resource → numbered row → semantic field → channel**. LUT count, row count and mesh/material binding count are different quantities. All eight material rows are available when a LUT is 23×8; they are not eight additional LUT resources.

Material field numbering follows research on 23-column LUTs. Base Color is column 1 (zero-based pixel column 0). RGB recolors; alpha carries shader behavior. Camo colors are columns 17–20; camo fade is column 21 alpha; column 22 contains selector/scale/pattern controls. Unknown fields remain unknown. Semantic names describe parameters, not named armor surfaces.

## Basic camo masks

Basic's selectors change column 22 A (-1 off, 0–5 pattern) across the selected 23-column LUT. Armor affects every row; Helmet excludes Region 8, forcing that row's pattern Off when selecting a mask and retaining its bytes during color edits. Off retains all other fields. A mask with finite, nonzero column 22 R/B and nonblack camo colors keeps its authored settings. Otherwise the pattern action seeds a complete Jungle camo recipe, keeping nonblack colors and supplying the generated Jungle palette only when all twelve camo RGB channels are zero. Dormant controls or all-black colors display Current / mixed so reselecting a mask can initialize them.

The current game's ArmorTemplate binds `CustomizationCamoTilerArray` (slot `0f5ff78d`) to texture `eecf271273d7090c`, a 256×256 RGBA8 array with six slices and nine mips. The preview worker reads mip 4: 16×16, 1,024 bytes per slice, at offset 348,160 within each 349,524-byte slice. The six neutral mask thumbnails are not a full shader render; the source RGB channels contain packed masks and its alpha is zero. Slice 5 duplicates slice 0 in this atlas.

SDK inspection at commit `5a886256e54db52b5d228335eae20ce796f87fc0` finds weapon `PaintSchemeArctic`, `PaintSchemeArcticCamo`, `PaintSchemeDesert`, `PaintSchemeDesertCamo`, `PaintSchemeForest`, `PaintSchemeForestCamo`, `PaintSchemeUrban` and `PaintSchemeUrbanCamo` shader variables. Numeric pattern names remain because each named colorway combines colors and scalar controls, rather than uniquely naming a mask.

Basic's Jungle, Desert, Urban and Arctic RGB palettes are generated, not extracted game colors. Their supporting controls were verified against the corresponding weapon LUTs. Like [Match Your Colors' camo copy](https://github.com/CowboyBingus/MatchYourColors/blob/5a7c4298d1046923c49406f50c7ab2e953aebf49/src/recolor.lua#L48), a colorway supplies columns 17–20 RGBA, column 21 A, column 22 RGBA and column 23 A. It retains the prior mask only when its index is valid and its R/B controls are nonzero; otherwise it uses the profile's mask. Base/detail colors, Base alpha/shader mode, emission, column 21 RGB and column 23 RGB remain byte-exact.

Column 22 R controls mask sharpness, G its bias, B camo UV scale, and A its array layer. Column 23 A controls camo roughness blending; it is not spatial scale and zero is valid. Column 23 R scales detail UVs. These meanings follow the [pinned Filediver shader](https://github.com/xypwn/filediver/blob/9f92623133cde32b1167e13f05ce6c4825805ccf/cmd/filediver-gui/widgets/previews/shaders/lut.frag#L219).

| Colorway | C22 R | C22 G | C22 B | Default C22 A | C23 A |
| --- | --- | --- | --- | --- | --- |
| Jungle | 216.625 | -0.98974609375 | 2 | 3 | 0.82958984375 |
| Desert | 216.625 | -0.98974609375 | 3.5 | 1 | 0 |
| Urban | 216.625 | -1 | 1.19921875 | 1 | 0.82958984375 |
| Arctic | 216.625 | -0.98974609375 | 5 | 3 | 0.82958984375 |

All profiles use camo color alpha values `0.52978515625, 2, -1, 4` and column 21 A `0.8896484375`. Individual swatches change only one camo RGB column across the eligible rows; a mixed table displays the first row's color until it is applied. Picker changes commit once when Apply is pressed, rather than uploading a texture for every drag frame.

## Emission

The current research mapping describes column 14 R as emission strength (small values around 0.001–0.06); other channels and dependencies are uncertain. It is **not a confirmed RGB emission-color picker**. Effect protection makes it read-only and disables the irrelevant color picker. Deliberately unlock material effects to experiment with raw strength; this does not establish that every shader consumes it the same way.

Glow color can follow Base Color. The examined helmet's eye tint changed through material LUT 1, row 8, Base Color. This is an observed per-item row mapping, not a universal row-8 rule. On Live Wire, LUT `800b5d4ab3fdd044`, row 2 has red base RGB and can influence indicator tint. Preserving emission/mode floats does not guarantee unchanged emitted hue.

## File values and overrides

The working document holds Float32 RGBA values, including HDR/negative values. RGB swatches clip for preview and color-picker representation only. Disabled rows render their originals; committed edits activate their row. The full document is authoritative; old RGB settings are compatibility metadata and do not form another render layer.

Restore original colors disables application while retaining the document. Reset Custom LUT Rows resets every original/current row value and clears overrides. Full-float v2 presets retain target identity and all cells; legacy armor v1 imports are supported. Helmet presets cannot silently apply to armor.

Research references: [Paydex material mapping](https://github.com/paytonrog/paydex-lut-editor/blob/main/mappings/mappings_8x23.json), [pattern mapping](https://github.com/paytonrog/paydex-lut-editor/blob/main/mappings/mappings_1x3.json), [cape mapping](https://github.com/paytonrog/paydex-lut-editor/blob/main/mappings/mappings_5x16.json). Equivalent code/descriptions are independently authored; no unlicensed Paydex implementation is vendored.

Quick Load's remapper uses the original target-sized buffer, then maps only named fields. Unknown material columns 9, 12 and 16 and emission GBA always retain the target originals. Same-layout rows are nearest proportional, aligning first/last source and target rows; one-row sources repeat. Material preservation retains non-color values and color alpha/mode; emission preservation independently retains column 14 R as well. Across different recognized layouts, only shared Base Color RGB is mapped. Source choice is exact resource first, then same layout, nearest row count and stable resource/name order. These rules are a bounded remapping recipe, not a claim that material regions correspond between items.
