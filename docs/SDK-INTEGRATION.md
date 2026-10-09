# SDK reference catalog

Epic LUT uses a compact local catalog derived from [HD2SDK Community Edition](https://github.com/Boxofbiscuits97/HD2SDK-CommunityEdition/tree/5a886256e54db52b5d228335eae20ce796f87fc0). It supplies recognizable names for known resources, gear archives, material texture bindings and cosmetic shader parameters. It also records the UI rendering support explicitly described for the SDK's material templates.

The SDK is a development reference, not a runtime dependency. The generated Lua module is about 54 KB. It makes no network requests, scans no game files and does not load the SDK or Blender. Lookup tables are created once when the module loads.

## What the catalog knows

| Catalog | Entries | Meaning |
| --- | ---: | --- |
| Gear resources | 127 | Exact friendly resource IDs identified as helmets or capes in the SDK. The pinned friendly-name list supplies no named armor resources. |
| Gear archives | 337 | Armor, Helmet and Cape archive IDs and labels from the SDK's grouped archive list. |
| Texture bindings | 482 | The SDK's texture-slot names, including `MaterialLut`, `PatternLut`, `BloodSplatterTiler`, `TearNormalsGrayscale` and `MudNormalsGrayscale`. |
| Cosmetic parameters | 81 | Selected blood, mud, tear, dirt, pattern, wound and opacity variable IDs. Unrelated bones and other shader catalog entries are excluded. |
| Template parents | 10 | Genuine parent material IDs read from the ten current SDK template files. |

Resource IDs, archive IDs, material parents, texture slots and shader variables are separate namespaces. A helmet archive name is not evidence that a texture inside that archive belongs exclusively to that helmet. Shared resources retain the SDK's combined names. Unknown IDs stay unknown; the editor should continue displaying their exact raw IDs.

All 64-bit IDs remain hexadecimal strings. Converting these IDs to ordinary Lua numbers can discard their low bits. The catalog rejects numeric 64-bit lookups. It accepts numeric 32-bit slots and variables, including signed 32-bit representations.

## Use in Epic LUT

The Import / Apply workspace shows all loaded Armor and Helmet LUTs in separate scrollable columns. Select a table by its title or resource hash. Titles use known SDK unit names when there is an exact match; archive labels are kept separate from unit and texture identities.

## Game Default preview compatibility

The [SDK template descriptions](https://github.com/Boxofbiscuits97/HD2SDK-CommunityEdition/blob/5a886256e54db52b5d228335eae20ce796f87fc0/__init__.py#L215-L225) explicitly identify **Advanced** and **Basic+** as rendering in the game UI, and **Alpha Clip** and **Alpha Clip+** as not rendering there. The remaining template descriptions do not establish UI compatibility, so their status is **unknown**.

The parent ID comes from bytes 24–31 of a serialized material, as defined by [the SDK material reader](https://github.com/Boxofbiscuits97/HD2SDK-CommunityEdition/blob/5a886256e54db52b5d228335eae20ce796f87fc0/stingray/material.py#L24-L30). A runtime material pointer is not a parent ID. Use this compatibility information only when the actual parent is available from reliable metadata; never guess it from a pointer or texture binding.

These descriptions help explain a missing surface in the Game Default UI pipeline. They do not prove every stock material is compatible, and they do not replace in-game verification. The catalog does not alter materials, substitute templates or switch to Full Render automatically. See [the preview render-path comparison](PREVIEW-RENDER-PATH.md).

## Runtime API

`src/gear/sdk_catalog.lua` exports:

```lua
catalog.resource_name('d5f99488a6f12896') -- Helmet A-9 Helljumper
catalog.resource_kind('d5f99488a6f12896') -- Helmet
catalog.archive_name('1d6dc4216e7ce52d')  -- A-9 Helljumper
catalog.archive_kind('1d6dc4216e7ce52d')  -- Armor
catalog.texture_name(0x81d4c49d)         -- PatternLut
catalog.variable_name(0x0955ef2e)        -- BloodWeightsPositive
local label, status = catalog.compatibility('d84d04634a1e2f60')
-- Alpha Clip, unsupported_ui
```

The compatibility statuses are `supports_ui`, `unsupported_ui` and `unknown_ui`. Unrecognized parents return `nil`. String lookups accept uppercase hexadecimal and an optional `0x` prefix; a 64-bit string must contain exactly 16 hexadecimal digits. The module also exposes `revision`, `source`, `fingerprint` and `counts` for diagnostics.

Slot and parameter names are preserved exactly as cataloged upstream. They identify a binding or field, not every detail of its semantics. In particular, the SDK does not establish the meaning of every channel in the Pattern LUT's three pixels. A named blood parameter does not prove that changing it is sufficient to trigger blood coverage, or that a live player has an owned, reversible material copy.

## Reproduce and refresh

Pinned revision: **`5a886256e54db52b5d228335eae20ce796f87fc0`**.

`tools/generate_sdk_catalog.py` records the SHA-256 of every input file. Reference files live in the ignored `dist/sdk-reference/<revision>/` cache. Template `.material` bytes and SDK Python source are not included in Epic LUT packages.

Run from the repository root using the project's Python runtime:

```text
python tools/generate_sdk_catalog.py --refresh
python tools/generate_sdk_catalog.py --check
python tests/test_sdk_catalog.py
```

`--refresh` downloads only the fixed input list from the recorded revision, verifies every hash and size, then regenerates the catalog. It does not follow the upstream default branch. `--check` compares the generated catalog with the checked-in file without modifying it. Fixture tests need neither the reference cache nor network access. Lua API tests are in `tests/sdk_catalog.lua`.

To adopt a newer SDK revision, review the upstream catalog and template changes first, then update the revision and reviewed input hashes. The generator fails on malformed entries, conflicting relevant names, missing curated variables, oversized inputs or catalogs beyond the reviewed entry/byte bounds. It parses the literal template descriptions with Python's AST and never executes the addon. SDK catalogs may lag behind a game update; unmapped data must remain usable through existing raw-ID behavior.

## Attribution and license boundary

The underlying discoveries and names come from **Boxofbiscuits97 and HD2SDK Community Edition contributors**. Preserve that attribution when presenting these mappings. The pinned repository tree contains no repository-wide `LICENSE` or `COPYING` file; the bundled LZ4 dependencies have their own licenses. This integration distributes selected factual ID/name mappings, not SDK addon code, material files, textures or game assets. Any future SDK code port needs a separate license review rather than assuming the LZ4 license applies to the addon.
