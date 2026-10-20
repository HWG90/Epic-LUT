# R5 maintenance carried forward from R6

Reviewed the Epic LUT 6 development chat on 2026-10-18, including the work
following the R5.8.7 / R6 Alpha 4 releases. This is a maintenance checklist,
not a claim that every candidate has been verified in a running game.

## R5.9.0 candidate: already backported

- Armor, Helmet and Cape recovery wakes on lifecycle events and explicit gear
  loads. Older loaders use a bounded read-only change detector instead of full
  repeated material discovery. Ownership validation remains required for writes.
- Shared LUT publication caches unchanged appearances, builds changed packets
  cooperatively and cancels stale generations. One read-only observation scope
  replaces repeated material validation within the same publication operation.
- Exact appearance values and the existing multiplayer wire format are retained.
- These shared changes are in R5 `5a9c37e` and R6 `ffbb72f`. The R6 chat records
  deployed performance measurements; source/package checks are separate evidence.

## Slider regression: shared maintenance fix

- The earlier Undo change delayed the actual edit until mouse release, so sliders
  moved without updating the appearance while held.
- Material and Pattern sliders now preview changed pixels while dragging, at
  most 15 times per second. Release flushes the exact final value immediately.
- Only the starting and final pixels enter Undo history. Intermediate previews
  do not commit settings, record history or emit edit notices.
- Closing, losing input focus or abandoning the owning window cancels the
  unfinished drag. Changed/stale targets do not authorize native writes.
- Implemented in both branches. Offline tests cover live pixels/native Pattern
  binding, exact Undo/Redo, no-op drags, cancellation and bounded preview work.
  Deployed timing and visual confirmation are still pending.

## Existing shared baseline

The earlier R6 work on long source-cache paths, cooperative export verification,
cache publication races, closed-menu polling and slider endpoint Undo predates
the current candidate. Retain those fixes; do not replace them with weapon-only
implementations or remove provenance checks to improve responsiveness.

## Snapshot resolver reentry fix

- Backported the snapshot advancement guard and the exact Cape metadata reentry
  regression to R5. A snapshot lookup during gear matching stays pending instead
  of recursively advancing or replacing the active snapshot job. No new polling.
- The regression passes in both branches. The R6 installed candidate completed
  two live NEW DESERT Apply -> Restore Arrowhead -> Load Current Gear sequences;
  snapshots reached 100% with no active worker/job afterward. R5 runtime and rebuilt
  release packages still require their own validation before publication.

## Open issue: release hold

- A reported Apply Preset -> Restore Arrowhead LUTs -> Load Current Gear crash
  remains unproven at the native/runtime level. Repeated offline sequence tests
  were added in both branches and pass; they do not establish that the reported
  game crash is fixed.
- Keep R5.9.0 unpublished until the crash report is resolved or explicitly
  reassessed. Do not interrupt another live-game test to reproduce it.
- Prepared BSL/LLL packages predate the slider fix and must be rebuilt before
  distribution. Publication and deployment require their own verification.

## R6 work to review, rather than blindly backport

- The in-progress weapon menu reuses the common Apply Preset chooser and shared
  Armory application logic. Review changes to shared chooser/application code for
  R5 relevance once that work is complete; exclude weapon slots from R5.
- Shared menu differences to review for R5 include retaining the save dialog when
  its callback explicitly returns false, and bounding the main title text. Weapon
  tabs and weapon-specific preset columns are excluded from that review.
- Weapon-only private configuration ownership, ammo-reload retention, equip
  handling, startup restoration and weapon-specific save selection stay in R6.
  Their shared infrastructure or correctness fixes still need R5 review.

Carry subsequent shared fixes into both branches in the same task. Preserve
weapon-specific R6 code and keep source, package, installation, runtime and
publication status distinct.
