# Shared LUT receiver recovery

The receiver previously used only garment Unit IDs to decide whether an unchanged peer packet was already applied. During mission/ship transitions, a Unit can be present before its helmet/armor materials or Pattern texture slots are ready. Those late destinations were missed. Likewise, the game can restore an original LUT pointer while retaining the same Unit/material, leaving the receiver believing its custom camo was still applied. R5 also retained a completed peer record after an apply failure, preventing a later retry of the same packet.

Remote garment discovery now signs the available Unit, mesh, material and texture-slot destinations in deterministic order. Texture pointers are excluded so our own uploads do not trigger repeated reapplication. New or replaced materials and newly available slots cause a fresh capture after prior owned bindings have been restored.

Between packet changes, the receiver repairs only an exact known-original pointer reset using its retained immutable GPU texture. Healthy bindings are left alone; unknown/foreign replacements are never repaired or adopted. This allocates no replacement texture. Failed applies and pending restoration retain retry state, and transient destination-read failures are deferred safely. R6 preserves its separate weapon identity, permissions and session handling; the new repair path applies to garments.

The PlayFab stable-lobby guard, packet format, float precision, compression, peer identity/kit checks and sharing consent are unchanged. No native transport offsets or posting delays were relaxed.

Validation covers independent armor/helmet Pattern palettes, late materials and zero texture slots on unchanged Units, stable enumeration order, game resets, retained GPU buffers, healthy-binding isolation, foreign replacements, failed apply and restoration retries, transient target reads, and explicit sharing-off cleanup. Full two-player ship/mission testing remains required before claiming the reported multiplayer issue is resolved live.
