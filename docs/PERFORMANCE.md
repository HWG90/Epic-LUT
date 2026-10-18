# Runtime performance

Prefer lifecycle notifications and explicit invalidation. Unchanged assignments
must not trigger native material scans, texture repairs, or packet reconstruction.

Appearance recovery wakes on player spawn/death, mission start/end, or Load Current
Gear. Missing source metadata/avatar readiness retries are bounded to 40 attempts;
new lifecycle events reset that budget. The optional HD2Runtime event service is
used for automatic gameplay lifecycle notifications. Without it, a bounded
half-second read-only avatar/binding signature detects changes and schedules one
recovery pass; unchanged signatures never run native material discovery. Explicit
gear loading remains available. Recovery keeps fresh native write/ownership checks.

Shared LUT publication reuses one synchronous read-only validation scope per
weapon observation and one material/presence snapshot per garment publication.
Those observations never authorize later Apply/Restore writes. They cannot yield
or escape the operation; the representative weapon identities are revalidated at
scope exit. Multiple receipts for the exact same Unit share that observation.

Changed packets are built in resumable stages with a two-millisecond cooperative
budget in the pure packet builder. Individual native/validation operations remain
synchronous. Texture pixels and wire representations stay exact; stale assignment
or lifecycle generations cannot commit packets. Unchanged publications reuse the
existing packet. Remote transport reception remains available.

Verify deployed steady-state behavior and lifecycle transitions separately from
UI actions. Attribute spikes to a measured method before changing its behavior.
