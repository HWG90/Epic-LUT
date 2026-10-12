# Epic LUT R6.0.0 Alpha 1 development candidate

Weapon LUT editing is under development on `r6/weapon-lut-editing`. R5 maintenance remains on `main`. This candidate is not a published release.

- Primary, Secondary and Support have independent weapon and LUT selectors. Material tables reuse the full LUT table and Value Editor; compatible quick color/camo controls preserve exact float values. Pattern controls include color, material/opacity and roughness Alpha.
- Weapon import mapping supports individual destinations, ordered Auto-map and rollover. Certified Pattern companions follow their exact material destinations.
- Armory schema 4 records weapon configuration IDs, slots and every LOD assignment. Shared palette data is deduplicated while each destination remains explicit. Older garment presets remain readable.
- EL6 Shared LUT packets retain exact weapon identities and full float32 palettes. Receiving requires a matching peer weapon, active sharing consent and proven live ownership.
- Restoration and history retain original bindings, refuse stale or foreign targets, and roll back partial writes. Weapon patches use precise Unit/material assignments; an independently verified patch destination is required.

The live read-only Adjudicator probe verified its body, rail and Pattern tables. Native editing, switch/drop/respawn recovery, remote sharing and exported weapon rendering still require live verification. Offline fixtures and matching packages do not establish those results.
