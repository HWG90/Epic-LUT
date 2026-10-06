# MCM atomic batch setter

`tools/mcm-set-many.lua` adds `handle.set_many(values)` inside DBF-MCM's per-mod registration scope, immediately before `handle.reset`. It uses the same `normalize`, validation, persistence, values and callbacks as `handle.set`. Validate the entire batch, save once, publish values, then notify callbacks. A failed validation/save invokes no callbacks and leaves values unchanged. Callback failures follow existing MCM semantics; they do not undo a saved commit.

Apply only this scoped addition to your owning MCM source, preserving other changes. Build through its normal workflow. An existing running MCM bundle can be patched at the same unique `handle.reset` anchor and reloaded through its supported lifecycle after preserving the exact prior bundle; do not install a replacement framework from unrelated work. Epic LUT refuses imports when this method is missing. No native input changes are part of this integration.

On Windows, use PowerShell or a non-Store Python runtime for installed AppData paths. Microsoft Store Python can redirect those paths into its package LocalCache, causing a stale framework copy to be staged or verified. Verify the real installed file through PowerShell or its final opened-handle path, and preserve existing resize and legacy-registration code along with the batch addition.
