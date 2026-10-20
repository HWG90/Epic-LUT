# Direct Editor separation

Direct Editor remains the session coordinator. It must not grow another apply,
recovery, or persistence path for a particular page.

## Implemented boundaries

- `editor_registration`: page registration, action adapters, and view composition.
  Explicit ports read current session state when callbacks run, including after
  same-instance reactivation. This module never performs a native binding write.
- `appearance_recovery`: staged recovery requested by lifecycle invalidation.
  Material discovery, material replay, Pattern discovery, and Pattern replay run
  in separate stages. Idle entry returns before constructing a context or reading
  native memory. Existing current-owner checks remain in the binding sessions.
- `setup_restore`: bounded startup restore orchestration with explicit job and
  cancellation state shared with manual actions and teardown.
- `weapon_services` (R6): lazy construction of workflow, startup, provenance, and
  sharing services. Constructors do not discover gear or start recurring work.
  The existing shared workflow continues to map manual and automatic slot replay.

The two non-weapon modules are identical in R5 and R6 and are included by the
common package inventory. R5 does not load weapon services.

## Remaining work

This is the first structural pass, not a complete rewrite. `direct_editor.lua`
still owns import coordination, session snapshots, and too
much initialization/update orchestration. Move those behind explicit controllers
before changing their behavior. Do not move the entire monolith into a renamed
session file, use proxy environments, or introduce separate page-owned apply loops.

The target apply contract is shared across all pages: resolve current owned
binding receipts; prepare immutable texture data; revalidate and commit; record
intent and history once. Recovery consumes that same intent only on lifecycle
invalidation. Export provenance remains independent of live application.

## Validation boundary

Offline controller and integration fixtures cover registration, repeated
activation, current-owner rejection, import mapping, export routing, history,
respawn recovery, coalesced stages, and idle native-read suppression. All owned
Lua modules are syntax checked. This refactor has not been installed or tested
in game, and does not establish a fix for the GPU device-hung crash. Weapon startup now saves version4 slot intent separately from patch export
proof. Legacy version3 manifests remain readable. Live restart acceptance must
be checked independently of offline round trips.

Automatic garment recovery coalesces native mesh commits within each existing
replay stage, matching the user-action path. Recovery keeps immutable cached
textures and does not refill textures still reachable by history or previews.
The large recovery fixture verifies 256 material writes across four meshes
produce four commits, with fresh ownership checks and no new texture allocation.
