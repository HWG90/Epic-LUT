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
in game, and does not establish a fix for the GPU device-hung crash. R5 retains its garment-only startup restore contract; R6 weapon intent and weapon UI remain separate.

Automatic garment recovery coalesces native mesh commits within each existing
replay stage, matching the user-action path. Recovery keeps immutable cached
textures and does not refill textures still reachable by history or previews.
The large recovery fixture verifies 256 material writes across four meshes
produce four commits, with fresh ownership checks and no new texture allocation.

## R5.9.3 maintenance backport

Backported the shared R6 recovery/controller separation, supported lifecycle
observer, validated prepared-apply pipeline and bounded Unit ownership cache.
The old half-second appearance detector is removed. Unchanged recovery performs
no native reads, allocations or scans. Existing R5 export naming and chooser
controls remain intact. No weapon feature is added.

The current-player R6 recovery was observed restoring NEW DESERT when switching
away from and back to the same armor. R5 has offline validation only; this task
does not replace the installed R6 runtime or publish a release.

All targeted recovery and controller fixtures pass. The full suite retains a
pre-existing legacy full_editor emission-control failure, reproduced with the
unchanged HEAD fixture and unchanged legacy controller/semantics sources.
Consequently the complete managed-build verification is not green.
