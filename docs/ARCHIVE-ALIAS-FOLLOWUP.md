# Archive alias follow-up (released in R5.7.4)

A different archive family was previously refused before comparing palette content. Resolve the highest numeric layer in each family, validate equal-index duplicates, then compare exact native metadata, pixel bytes and flags. Identical winners may load colors without inventing a single archive provenance; preserve their source labels separately. Differing winners still refuse and identify the competing archives. Cache schema v6 prevents reuse of previous results.

Color-only snapshots with multiple archive aliases have no `.patch-source`; patch export must retain the separate binding/source proof requirement. No selected archive is fabricated from alphabetical order or the largest patch number across unrelated families.

A missing binding-cache part now identifies its resource filename and I/O reason, invalidates the cache and gives Load Current Gear as a recovery action. Offline validation of the reported local cache opened all 29 captured resources and matched their hashes. The exact live cause remains unproven.

These changes are carried through R5 and R6. Published R5.7.3 / R6 Alpha 2 assets remain unchanged. The user confirmed the creator-side test build resolves the reported failure; R5.7.4 now publishes the fix.
