# Weapon LUT ownership

R6 keeps edited textures authoritative at the private weapon appearance source.
On the supported game build, ammunition reload restores named material textures
from ten appearance records in the weapon's private configuration. A zero texture
override means restore the stock texture; it does not mean leave the texture alone.

`weapon_source_lease.lua` temporarily clears only the material selector for roles
owned by Epic LUT. It validates the executable build, local or consented peer
identity, private configuration map, exclusive configuration index, mesh role,
exact record contents, writable private data and write readback. Existing LUT
overrides are accepted only for slots explicitly replaced by the assignment plan;
their source bytes are retained exactly for restoration. Unselected texture
overrides, unknown padding and ambiguous/shared sources are refused. No executable code
is patched and no shared weapon configuration is changed.

Source ownership is acquired before native texture assignment. Failed assignments
retain the previous source ownership, or release a newly acquired source after
rollback. Partial restores retain a role while any of its LUT bindings remain
assigned. Restore and shutdown release selectors only against the same owner and
exact expected bytes. Foreign changes are preserved and unresolved cleanup blocks
retirement. Dead or reused owners never receive old selectors.

The editor no longer calls its per-frame assignment gate or recurring material
catalog scan. With HD2Runtime available, weapon equip, unequip and change events
schedule one validation per inventory slot over three frames. Event subscriptions
are removed on close. HD2Runtime remains optional: without its event service,
Load Current Gear and explicit editing actions perform fresh validation, but
automatic equipment-change recovery is unavailable. Ammo reload retention itself
does not depend on this event service.

The native event adapter also supports recovery without HD2Runtime. It schedules
one validation after a nonempty native unit lifecycle notification, compares the
three equipped slots, and disables its deferred callback immediately afterward.
Unchanged frames do not inspect weapon identity or reapply assignments. Restore
Arrowhead clears assignments without removing these subscriptions; addon teardown
removes them. Automatic recovery uses the shared validated mutation path without
capturing the entire outfit's user Undo history.

Focused offline contracts are in `tests/weapon_source_lease.lua`,
`tests/weapon_source_transaction.lua`, `tests/weapon_idle_poll.lua` and the existing
weapon runtime/bridge/integration fixtures. Package checks and live reload/performance
observations are separate verification steps.

Private configuration storage can move or compact when equipment changes. Each
source journal resolves its exact owner again before assignment or restoration,
then follows that owner's current configuration address. Journals for retired
owners are discarded without writing into a replacement weapon's storage.
Materials absent from the configuration's reset selectors need no suppression;
they use the ordinary validated binding path. This includes secondary weapons
whose reset selector table is entirely empty.


## Restart intent

Applied weapon colors are persisted as slot-bound palettes, with canonical keys
and bounded DDS payloads, in setup-v4. Current owned bindings and immutable bytes
are checked before and after capture. Export proof and original source pixels
are not prerequisites for remembering a live assignment. Export continues to
require exact source/assignment provenance.

Startup uses the same slot mapper as manual preset application, including for a
different equipped weapon. A failed slot retains intent and waits for an actor
or equipment lifecycle notification. There is no clock-based retry or idle
native scan. Manual mutation and Restore cancel startup through the existing
shared cancellation contract. Existing setup-v3 snapshots remain readable.
