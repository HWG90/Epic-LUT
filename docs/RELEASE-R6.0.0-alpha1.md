# Epic LUT R6.0.0 Alpha 1 development candidate

Weapon LUT editing is under development on `r6/weapon-lut-editing`. R5 maintenance remains on `main`. This candidate is not a published release.

- Primary, Secondary and Support have independent weapon and LUT selectors. Material tables reuse the full LUT table and Value Editor; compatible quick color/camo controls preserve exact float values. Pattern controls include color, material/opacity and roughness Alpha.
- Weapon import mapping supports individual destinations, ordered Auto-map and rollover. Certified Pattern companions follow their exact material destinations.
- Armory schema 4 records weapon configuration IDs, slots and every LOD assignment. Shared palette data is deduplicated while each destination remains explicit. Older garment presets remain readable.
- EL6 Shared LUT packets retain exact weapon identities and full float32 palettes. Receiving requires a matching peer weapon, active sharing consent and proven live ownership.
- Restoration and history retain original bindings, refuse stale or foreign targets, and roll back partial writes. Weapon patches use precise Unit/material assignments; an independently verified patch destination is required.
- Save applied setup includes weapon palettes with exact named assignment proofs. Startup restores only matching configurations and effective sources; unresolved snapshots survive cache waits, mismatches and temporary unavailability.
- Material quick Pattern selectors preserve independent sibling assignments when those materials share a stock Pattern texture. Apply, Restore and mapping participate in global Undo/Redo, and workflow services survive addon activation.
- Shared LUT normalizes only its own live uploaded textures to their captured source identity, retaining foreign-writer detection and safe cleanup quarantine.

The live probes verified Adjudicator and Bolt Pistol assignments. The authorized Adjudicator body pilot changed all five LODs to magenta and restored their original pointers; the user confirmed the visible change and restoration. Integrated UI/startup acceptance, Pattern and secondary/support rendering, switch/drop/respawn recovery, remote sharing and installed weapon-patch rendering remain open. The earlier native crash trigger is unproven. Offline fixtures and matching packages do not establish those results.
