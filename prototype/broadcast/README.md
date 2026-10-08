# Epic LUT Broadcast POC 0.1

Experimental, undeployed, two-player proof of concept. Manual DDS publish and
receive; no automatic editor synchronization, NAT traversal, reconnect, respawn
reapply, or release readiness. Python 3 is required for this prototype only.
Native runtime adapters and discovery foundation: CowboyBingus; included license.

## Two-PC test

1. Use a LAN or trusted VPN connection. This TCP transport authenticates the room
   token but does not encrypt LUT data. No Steam integration or relay is used.
2. Host: `python peer.py --listen YOUR_LAN_OR_VPN_IP --token YOUR_PRIVATE_ROOM_TOKEN`
3. Guest: `python peer.py --connect HOST_LAN_OR_VPN_IP --token YOUR_PRIVATE_ROOM_TOKEN`
   Use the same token, at least 16 characters. Windows may request a firewall rule;
   limit it to the intended private network. Each transport start clears old mailboxes.
4. Load the separate `epic_lut_broadcast_poc/mod.lua` through the existing compatible
   Live Lua Loader. Do not replace Epic LUT. This package is not a BSL patch.
   The module checks the same executable/game hashes as the current editor.
5. Join the same game session. Inspect the roster in the Lua console:
   `for _, p in ipairs(EpicLUTBroadcast.peers()) do print(p.peer, p.owned, p.player) end`
6. Export an edited DDS using Epic LUT. Publish it:
   `EpicLUTBroadcast.publish([[C:/path/to/export.dds]], 'armor')`
   Use `'helmet'` for helmet. One palette is applied across the selected gear scope;
   this version does not transmit per-material outfit mappings.
7. On the receiving PC, confirm the sender's 16-digit peer ID from the roster:
   `EpicLUTBroadcast.receive('SENDER_PEER_ID')`
   This validates DDS data and binds a new local texture to that remote character.
   Repeat in the opposite direction for mutual visibility.
8. Restore before disabling/unloading, leaving the session, or changing equipment:
   `assert(EpicLUTBroadcast.restore())`

Receive refuses local-player targeting, unknown peers, and target materials also
used by another roster character. It restores the previous receive before applying
a new one. Failed partial writes use the existing binding-session rollback.
GPU buffers are retained within the module's session budget; there is no speculative
buffer destruction. Avoid hot-unloading/reloading this experimental module.

## Acceptance evidence still required

- Distinct armor: sender's edit appears on the correct remote character.
- Same armor on both players: each remains independently colored, or the shared
  material guard rejects the operation before recoloring it.
- Both directions, armor and helmet, repeated Apply, then original restoration.
- Compare appearance on each PC; a transport test alone is not rendering proof.
- Remote record offsets, peer-ID correspondence across clients and ownership are
  hypotheses until tested live. Discovery fails closed when a roster is incomplete.

Build from repository root: `python prototype/broadcast/build.py`.
Offline checks: `python prototype/broadcast/test_peer.py` and
`python prototype/broadcast/check_lua.py`.
