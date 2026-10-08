# Match Your Colors integration

Source: https://github.com/CowboyBingus/MatchYourColors/tree/5a7c4298d1046923c49406f50c7ab2e953aebf49
Release reviewed: v1.3. CowboyBingus code retains the included Zero-Clause BSD license.

`vendor/avatar.lua` includes the updated player/remote-avatar discovery and body-copy watch. Epic LUT retains its local `resolve_live` compatibility entrypoint.
`vendor/engine.lua` includes upstream texture-format/mip support. Epic LUT retains material indices and its existing create_texture calling convention.
`vendor/lobby_sync.lua` is an attributed adaptation of upstream `sync.lua`, preserving stable-lobby gating, exact uint64 handles and PlayFab local-member identity. Epic LUT uses four separate `eplut0` through `eplut3` properties, bounded to 900 payload characters per chunk, instead of MYC's `cbmyc` settings property. Every posted buffer remains retained and immutable; mixed/incomplete packets are discarded.

Epic LUT's own codec transmits full float tables, compressed with Windows LZNT1 and encoded as Base64. Tables are deduplicated; decoded bytes, table counts, shapes, floats and binding destinations are bounded. Oversized appearances stay local and receive an explanatory status. Peer data is never executed. Textures are applied only to the resolved peer's matching body/armor/helmet kits and garment/material destinations. Removal, malformed packets and shutdown restore only bindings still owned by Epic LUT.

The automatic matching algorithm, hood rules, weapon schemes and cape recoloring remain Match Your Colors features. They are not silently enabled in Epic LUT's explicit editor.

## Try sharing

Both players need this Epic LUT candidate. In Configuration, enable **Share full LUT appearance with Epic LUT users**. Turn Match Your Colors matching off when editing the same gear. Join a squad and wait for the lobby to be stable for at least ten seconds. Changes are sent after they settle for about five seconds. The receiver must be wearing the corresponding gear kits. Unmodified games and MYC-only clients do not interpret Epic LUT full-table packets.

This integration has offline codec, native-interface, lifecycle and peer-ownership checks. Two-player live validation is still required before publication as a confirmed multiplayer feature.
