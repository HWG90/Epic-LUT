# Internal direct patch export candidate

Epic LUT can write the selected edited material LUT straight to a Helldivers 2 patch triplet. The exporter runs in Lua; it requires no Python, Blender, DDS converter, SDK installation, or extra executable. The existing Windows PowerShell/C# original-snapshot worker supplies the base-game metadata in the background.

Load the worn Armor or Helmet LUT, edit it, enter an **Export Name**, and choose **Export Patch ZIP** in Basic or LUT Editor Options. The triplet is zipped immediately in Lua, using that name for the ZIP. Output is a new folder:

```text
%LOCALAPPDATA%/Epic LUT/files/exports/<name>/
    <name>.zip
    9ba626afa44a3aa3.patch_0
    9ba626afa44a3aa3.patch_0.gpu_resources
    9ba626afa44a3aa3.patch_0.stream
```

The texture ID and native texture metadata come from the selected live destination's original snapshot. The patch always targets the shared base archive `9ba626afa44a3aa3`, matching the SDK's default. A texture can appear in multiple helmet, tutorial and prop archives; the first archive encountered during extraction does not identify the equipped gear's loaded package. Imported DDS names and resource IDs do not select the replacement target. **Export LUT Patch** replaces the selected material LUT resource, including every material sharing that resource. **Export Entire Palette** gathers all currently worn Armor, Helmet and Pattern LUTs, using their applied values and original values for untouched tables, and writes them as separate texture entries in one patch ZIP. Shared texture IDs are deduplicated; conflicting values or a missing snapshot stop the export before any files are published. It does not bundle all Armor/Helmet tables, materials, meshes, or runtime scripts. Existing export folders are refused; choose another name. Exporting does not install the patch or change saved application settings.

The texture writer retains the original native texture `UnkID`, clears streaming/mip descriptors, and writes one RGBA32F DDS header with all edited float channels in GPU storage. The stream sidecar is empty. Material LUTs retain their saved shape: 23 columns and 1–64 rows, including row counts different from the original. Original metadata must still agree with its native header. Pattern LUTs require exactly 3×1. No mip filtering or half-float quantization changes discrete row parameters. Nonfinite values, unsupported layouts, missing metadata, and stale gear selections are rejected. The complete triplet is staged in a sibling `.pending` directory and published by directory rename.

A texture record provides one payload per resource ID. The binding-aware serializer can preserve different assignments by creating distinct texture resources, patching verified material texture slots, and redirecting the exact unit material section when a material fork is needed. It preserves original unrelated main bytes, GPU/stream payloads and TOC fields. Resource IDs are checked against a complete collision catalog. Missing source records, ambiguous sections and unsupported kit overrides stop export before files are published.

Runtime binding-provenance capture is currently disabled after a native failure during export. The serializer has offline validation, but its live identity provider remains unverified. Ordinary texture-only patches still export. Presets with conflicting palettes for a shared resource refuse patch export before entering the new native lookup path; **Shareable Preset ZIP** retains every saved assignment and palette.

New presets can retain metadata-only v3 assignment references. The source records stay in the local cache. Legacy presets require a complete match to current binding keys, original texture IDs and original dimensions before their material identities can be resolved. Their conflicting palettes must also match the values currently assigned to that gear; apply the saved preset first. This leaves the saved preset unchanged. Shareable Preset ZIP and Raw DDS exports retain variants even when binding-aware patch verification is unavailable.

Original capture now saves a private `.patch-source` record alongside each cached original DDS: 16 ASCII archive-ID characters, newline, and the 340-byte native texture/DDS header. The cache schema marker is `patch-source-v2.txt`; older caches are reindexed and equipped LUTs recaptured. These records are user-local game data and are excluded from the release package.

Format references reviewed: [HD2SDK Community Edition archive serializer](https://github.com/Boxofbiscuits97/HD2SDK-CommunityEdition/blob/main/__init__.py) (`StreamToc`, `TocEntry`, `TocFileType`) and [texture serializer](https://github.com/Boxofbiscuits97/HD2SDK-CommunityEdition/blob/main/stingray/texture.py) (`StingrayTexture.Serialize`). The implementation is a narrow original Lua writer, with no imported SDK code or dependency. CowboyBingus attribution and the existing vendor license remain intact.

Validation: synthetic float/ID round trip, filesystem transaction and rollback, UI callback destination identity, stale gear refusal, existing editor contracts, and read-only extraction/export of real base-game 23x8, 23x5 and 3x1 LUTs. A saved Cape replacement with eight rows over an original five-row texture also round-trips exactly. The Pattern workspace offers DDS and Patch ZIP export. A separate binary check validates emitted archive records, sidecars, dimensions and edited floats.

Archive validation and live patch rendering are separate checks. Managed development packages include the editor and preview; installing the editor does not install its exported patches. Source build tools use Python, while users do not need it to export.
