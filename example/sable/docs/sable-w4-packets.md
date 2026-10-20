# Sable payloads: registry ids and wire compatibility

The plugin is server-only and the user keeps the **real Sable client** installed,
so every payload must be byte-compatible with
`sable/common/src/main/java/dev/ryanhcode/sable/network/**`.

Channel: `VeilPacketManager.create(Sable.MOD_ID, "1")` — a payload's
`CustomPacketPayload.Type` is `Sable.sablePath(name)` = `sable:<name>`.
`SableChannel` in `example/sable/lib/src/sublevel/network/packet.dart` holds the
three strings (`sable`, `1`, `sable:1`); they are wire compatibility, not local
choices.

## The 21 payloads

15 clientbound and 2 serverbound on TCP (`SableTCPPackets.init` order, which is
the order of `SablePackets.allClientbound` / `allServerbound`), plus the 6 UDP
types of `SableUDPPacketType` whose two dual payloads are also TCP payloads.

| # | id | direction | body | registry ids |
|---|---|---|---|---|
| 1 | `sable:snapshot_packet` | both (TCP + UDP `SNAPSHOT`) | `int` tick, VarInt count, entries of `long` plot, `Pose3d`, `Vector3f` lin, `Vector3f` ang | **none** |
| 2 | `sable:snapshot_info_packet` | both (TCP + UDP `SNAPSHOT_INFO`) | `int` ms, `int` tick, `bool` stopped | **none** |
| 3 | `sable:stop_moving_sublevel` | clientbound | `long` plot | **none** |
| 4 | `sable:change_sub_level_name` | clientbound | `UUID`, optional UTF name | **none** |
| 5 | `sable:start_tracking_sublevel` | clientbound | `long` plot, `UUID`, `Pose3d` last, `Pose3d` now, `BoundingBox3i`, optional UTF name, `int` tick | **none** |
| 6 | `sable:finalize_sub_level` | clientbound | `long` plot | **none** |
| 7 | `sable:stop_tracking_sublevel` | clientbound | `long` plot | **none** |
| 8 | `sable:change_bounds_sublevel` | clientbound | `long` plot, `BoundingBox3i` | **none** |
| 9 | `sable:freeze_player` | clientbound | `UUID`, `Vector3d` | **none** |
| 10 | `sable:physics_property` | clientbound | NBT (`PhysicsBlockPropertiesDefinition.CODEC`) | **block / tag ids as strings** |
| 11 | `sable:floating_material` | clientbound | UTF material id, NBT (`FloatingBlockMaterial.CODEC`) | **material id as a string** |
| 12 | `sable:dimension_physics` | clientbound | VarInt count, `DimensionPhysics` records | **dimension id as a string** |
| 13 | `sable:recently_split_sub_level` | clientbound | `UUID`, `UUID`, `Pose3d` | **none** |
| 14 | `sable:udp_activation` | clientbound | `UUID` | **none** |
| 15 | `sable:enter_gizmo_mode` | clientbound | empty | **none** |
| 16 | `sable:punch_sub_level` | serverbound | `BlockPos`, `Vector3d`, `Vector3d` | **none** |
| 17 | `sable:gizmo_move_sublevel` | serverbound | `UUID`, `Vector3d` | **none** |
| — | `PING` (UDP 0) | both | UTF text | none |
| — | `AUTH` (UDP 3) | serverbound | UTF token (player UUID) | none |
| — | `KEEP_ALIVE_CLIENTBOUND` (UDP 4) | clientbound | empty | none |
| — | `ALIVE_SERVERBOUND` (UDP 5) | serverbound | empty | none |

Plot coordinates are packed `ChunkPos.pack(plotX - originX, plotZ - originZ)` —
**relative to the plot-yard origin**, never a global chunk coordinate. `originX`
/ `originZ` are the container's, so the same sub-level has a different packed
value in a container with a different origin; the client only ever compares it
with values from the same server, so that is fine, but a plugin must not assume
`ChunkPos.getX(packed)` is a world chunk.

## Payloads that carry a registry id

**No payload carries a numeric registry id.** The three that name registry
entries name them by *resource identifier string*:

1. `sable:physics_property` — `selector` is a block id (`minecraft:stone`) or a
   block tag (`#minecraft:logs`); each key of `properties` and of every
   `overrides` value is a physics-property id (`sable:mass`, `sable:inertia`,
   `sable:volume`, `sable:restitution`, `sable:friction`, `sable:fragile`,
   `sable:floating_material`, `sable:floating_scale`). The value's NBT *kind* is
   fixed by the property id, which is how `Codec.dispatchedMap` finds the
   decoder.
2. `sable:floating_material` — the material id (`sable:air`), and the body is
   the material's NBT.
3. `sable:dimension_physics` — the dimension id (`minecraft:overworld`); the
   client rebuilds the `ResourceKey<Level>` from it.

That is deliberate in Sable: the client's registry is the *vanilla* one plus its
own datapack entries, and ids are resolved by name on arrival, so nothing in the
port can drift with the host's registry order. **Do not "optimise" any of these
into a VarInt registry id** — a host-side numeric id would be the host's
ordering, which the client does not share.

Consequences to keep in mind:

* a block state is never on the wire; only block *ids* and *tags* are, and the
  client applies a definition to every state of the block it resolves, exactly
  like `PhysicsBlockPropertiesDefinitionLoader.applyToBlocks`;
* a tag selector only works if the client has the same tag data (vanilla tags,
  or the mod's own `data/sable/tags/...`), which is why the datapack is shipped
  by the client mod;
* the material table (`FloatingBlockMaterialDataHandler.allMaterials`) is filled
  on the client by payload #11 and on the server by the datapack; a block whose
  `sable:floating_material` names a material the client does not have resolves
  to `null` and simply does not float, which is the Java behaviour too.

## Field order, and how it is pinned

The field order of every hand-written codec is the Java `write` order, and
`test/packets_test.dart` re-encodes each value with a `PacketWriter` in that
order and compares the bytes, so a reordering is a test failure rather than a
silent protocol break. The NBT-backed payloads are checked by decoding the tag
and asserting the field names, kinds and the "omit the default" behaviour of
`optionalFieldOf`.

## UDP

`SableUDPPacketType`'s **ordinal is on the wire** (`u8` after the VarInt21 frame
length): `PING=0, SNAPSHOT=1, SNAPSHOT_INFO=2, AUTH=3,
KEEP_ALIVE_CLIENTBOUND=4, ALIVE_SERVERBOUND=5`. `SableUdpPacketType`'s
declaration order is therefore part of the protocol.

UDP is optional: `SubLevelTrackingSystem` sends movement over UDP only when the
player completed the handshake, and falls back to TCP otherwise, with the same
payload bodies (`_sendSnapshots`). A player whose client disabled UDP gets
identical packets over the other socket.

## Chunks

`SubLevelTrackingSystem` sends a plot's chunks with
`chunk-streaming.send-chunk-at` (the host's real
`LEVEL_CHUNK_WITH_LIGHT` packet) instead of encoding them itself, and keeps the
chunks loaded with `chunk-tickets.force-load-chunk`
(`PhysicsChunkTicketManager.subLevelLoadedTicketType`). Java bundles the two
payloads and the chunk packets in one `ClientboundBundlePacket`; a plugin cannot
put a vanilla chunk packet in a bundle, so the sync is a sequence — start,
chunks, finalize — on one connection.
