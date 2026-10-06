# Preset format v1

UTF-8/ASCII data with tab-separated fields, newline-terminated, at most 128 KiB. Strict order: header, armor, body, enabled, then LUT declarations and complete row records. Example (truncated for illustration; a real file must include every row and LUT):

```text
DBF-ARMOR-LUT	1
armor	12345678
body	0
enabled	1
lut	0123456789abcdef	23	8
row	0123456789abcdef	1	1	#FF8000
```

Armor is the applied 32-bit kit identity, body is its current body type, LUT IDs are stable 64-bit archive resource hashes, dimensions must match the current originals. A row is 1-based, with an override flag and canonical RGB color. All rows, including disabled rows, are present. Non-color values are preserved from current originals, not serialized. No runtime addresses, player IDs, paths or game asset pixels occur in this format.

Compatibility is exact kit/body/LUT-layout matching. A Transmog custom kit may have a different kit identity even when appearances match; it is rejected rather than silently adapted. Presets are local renderer changes and do not imply replication to peers.

Imports decode and validate completely before one authoritative MCM batch save. Callbacks run after persistence and do not auto-enable rows during import, so saved disable flags remain meaningful. Malformed files do not stage, persist or apply partial settings. File paths are restricted to a simple local filename. Export names include armor ID, timestamp and collision suffix; existing names are skipped.
