# Match Your Colors integration

Source: https://github.com/CowboyBingus/MatchYourColors/tree/5a7c4298d1046923c49406f50c7ab2e953aebf49
Release reviewed: v1.3. CowboyBingus code retains the included Zero-Clause BSD license.

`vendor/avatar.lua` includes the updated player/remote-avatar discovery and body-copy watch. Epic LUT retains its local `resolve_live` compatibility entrypoint.
`vendor/engine.lua` includes upstream texture-format/mip support. Epic LUT retains material indices and its existing create_texture calling convention.
`vendor/lobby_sync.lua` is an attributed adaptation of upstream `sync.lua`, preserving stable-lobby gating, exact uint64 handles and PlayFab local-member identity. Epic LUT uses four separate `eplut0` through `eplut3` properties, bounded to 900 payload characters per chunk, instead of MYC's `cbmyc` settings property. Every posted buffer remains retained and immutable; mixed/incomplete packets are discarded.

Epic LUT's codec compares full-table, sparse delta, and XOR byte-plane packets and sends the smaller compressed result. Delta packets identify the original resource, dimensions and baseline checksum, then transmit exact changed float bytes. Receivers reconstruct every channel from their matching original snapshot and reject mismatched baselines. The XOR representation compares every float byte with its baseline and groups the result into four byte planes before compression. It preserves all IEEE-754 bits. Windows LZNT1 and Base64 provide the final encoding. Tables are deduplicated; decoded bytes, table counts, shapes, floats and binding destinations are bounded. Oversized appearances stay local and receive an explanatory status. Peer data is never executed. Textures are applied only to the resolved peer's matching body/armor/helmet kits and garment/material destinations. Removal, malformed packets and shutdown restore only bindings still owned by Epic LUT.

Extended packets use a 16-bit binding count and compact three-byte destinations, supporting up to 4,096 bindings without repeating identical tables. Both clients need the extended-packet build for appearances with more than 128 bindings. The decoder also accepts the earlier full-table, sparse delta and XOR formats. The transport still reserves at most 3,600 payload characters across four member properties: [PlayFab member data has a 4,096-byte aggregate limit and 1,000-character values](https://learn.microsoft.com/en-us/rest/api/playfab/multiplayer/lobby/update-lobby?view=playfab-rest). Increasing the destination count does not increase that network budget.

An outgoing encoding failure keeps receiving enabled and preserves the last successfully encoded packet only while the body, Armor and Helmet kits still match. A kit change removes an obsolete outgoing appearance. Explicitly turning sharing off removes the advertisement and restores received appearances. The local encoding failure remains visible even when transport cleanup reports that the advertisement was removed. A successful native post means the update was accepted by the lobby API; it does not establish that another player's game has rendered it.

The automatic matching algorithm, hood rules, weapon schemes and cape recoloring remain Match Your Colors features. They are not silently enabled in Epic LUT's explicit editor.

## Try sharing

Both players should use the same current development build, especially for appearances with more than 128 bindings. Earlier full-table, sparse delta and XOR packets remain readable by this build. In Configuration, enable **Share full LUT appearance with Epic LUT users**. Turn Match Your Colors matching off when editing the same gear. Join a squad and wait for the lobby to be stable for at least ten seconds. Changes are sent after they settle for about five seconds. A received appearance is applied only while that remote player's visible gear matches the kits recorded in the packet; the receiving player's own outfit can be different. Unmodified games and MYC-only clients do not interpret Epic LUT packets.

This integration has offline codec, native-interface, lifecycle and peer-ownership checks. Two-player live validation is still required before publication as a confirmed multiplayer feature.
