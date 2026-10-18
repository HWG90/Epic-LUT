# R5.9.0

Performance update for Armor, Helmet and Cape LUT editing and Shared LUT multiplayer appearances.

- Appearance recovery now wakes on player lifecycle events and explicit gear loads instead of repeatedly rediscovering unchanged materials.
- Shared LUT reuses unchanged appearance packets and builds changed packets cooperatively, reducing background work and spikes.
- Publication validates materials once per operation and discards work invalidated by a newer edit or lifecycle event. Native write ownership checks remain in place.
- Older loaders without lifecycle notifications use a bounded, read-only change detector; full recovery runs only when the signature changes.

Retains Shared LUT multiplayer sharing, Pattern editing, checked-region camo, gear mapping, Armory presets and assignment-aware patch exports. Weapon LUT editing remains on the separate R6 development branch.

Prepared packages: BSL and modular LLL R30+. Keep your presets and settings; install only one package. LLL remains GitHub-only.

