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

The texture ID and native texture metadata come from the selected live destination's original snapshot. The patch always targets the shared base archive `9ba626afa44a3aa3`, matching the SDK's default. A texture can appear in multiple helmet, tutorial and prop archives; the first archive encountered during extraction does not identify the equipped gear's loaded package. Imported DDS names and resource IDs do not select the replacement target. One export replaces one selected material LUT resource, including every material sharing that resource. It does not bundle all Armor/Helmet tables, materials, meshes, or runtime scripts. Existing export folders are refused; choose another name. Exporting does not install the patch or change saved application settings.

The texture writer retains the original native texture `UnkID`, clears streaming/mip descriptors, and writes one RGBA32F DDS header with all edited float channels in GPU storage. The stream sidecar is empty. LUT dimensions must exactly match the destination. No mip filtering or half-float quantization changes discrete row parameters. Nonfinite values, unsupported layouts, missing metadata, and stale gear selections are rejected. The complete triplet is staged in a sibling `.pending` directory and published by directory rename.

Original capture now saves a private `.patch-source` record alongside each cached original DDS: 16 ASCII archive-ID characters, newline, and the 340-byte native texture/DDS header. The cache schema marker is `patch-source-v2.txt`; older caches are reindexed and equipped LUTs recaptured. These records are user-local game data and are excluded from the release package.

Format references reviewed: [HD2SDK Community Edition archive serializer](https://github.com/Boxofbiscuits97/HD2SDK-CommunityEdition/blob/main/__init__.py) (`StreamToc`, `TocEntry`, `TocFileType`) and [texture serializer](https://github.com/Boxofbiscuits97/HD2SDK-CommunityEdition/blob/main/stingray/texture.py) (`StingrayTexture.Serialize`). The implementation is a narrow original Lua writer, with no imported SDK code or dependency. CowboyBingus attribution and the existing vendor license remain intact.

Validation: synthetic float/ID round trip, filesystem transaction and rollback, UI callback destination identity, stale gear refusal, existing editor contracts, and read-only extraction/export of real base-game 23x8, 23x5 and 3x1 LUTs. The 3x1 binary writer path is tested internally; the Pattern popup still offers DDS export only. A separate PowerShell binary check validates real emitted archive records, sidecars, dimensions and edited floats.

This is an internal candidate. No game files were installed, no runtime was activated, and patch loading/rendering in-game remains unverified. The build uses `--no-player-preview` to keep this review scoped to the editor/export path. Source build tools still use Python as before; users do not need it to export.
