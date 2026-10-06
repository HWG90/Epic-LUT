# Preset formats

v2 is tab-separated data, at most 4 MiB, newline-terminated. It records `EPIC-LUT\t2`, `target\tarmor|helmet\t<kit-id>`, body type, master enabled state and effect-preservation flag. Every declared LUT has its exact resource hash/width/height, every row has its override flag and RGB preview metadata, and every cell has four Float32 values formatted for round-trip precision. No pointers, player IDs or arbitrary code are serialized.

Example (incomplete for illustration):

```text
EPIC-LUT	2
target	helmet	41dd184d
body	0
enabled	1
effects	1
lut	0d8c20ce272a7a1d	23	8
row	0d8c20ce272a7a1d	1	1	#FF8000
float	0d8c20ce272a7a1d	1	1	1	0.5	0	0
```

The target kind is `helmet` or `armor`. Full coverage is mandatory. Duplicate, missing, nonfinite/overflowing, wrong-target or incompatible records fail before mutation. Settings save atomically; document publication follows validation. HDR and negative non-color cells remain Float32 values.

Legacy `DBF-ARMOR-LUT\t1` contains armor RGB/row flags and imports only to matching armor; remaining material values are seeded from originals. v2 exports preserve the full document. A custom Transmog kit may have a different identity even when appearance matches, so compatibility is exact.

Exports skip existing filenames. Filename selection is simple/local and imports are never executed. Raw DDS/EXR palette imports are explicit resource/dimension workflows rather than target-specific preset imports.
