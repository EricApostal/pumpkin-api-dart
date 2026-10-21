// The handle payloads: one player pulling a handle, and the set of players
// pulling handles at all.
//
// `players_holding_handles` is `ByteBufCodecs.collection(HashSet::new,
// UUIDUtil.STREAM_CODEC)`, which is a VarInt count then the uuids — the same
// shape as a list.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.network.packets.UpdatePlayerUsingHandlePacket
//       …packets.handle.ClientboundPlayersHoldingHandlePacket
// create's internals are pure but not exported from the barrel yet.
// ignore_for_file: implementation_imports
import 'package:create/src/common/pos.dart' show Pos;


import '../sim_packet.dart';

/// `simulated:update_player_handle` — the player grabbed (`remove == false`) or
/// released a handle, at [desiredRange].
final class UpdatePlayerUsingHandlePacket implements SimPacket {
  static const String type = 'simulated:update_player_handle';

  final double desiredRange;
  final bool remove;

  /// The block the player is interacting with.
  final Pos interactionPos;

  const UpdatePlayerUsingHandlePacket(this.desiredRange, this.remove, this.interactionPos);

  @override
  String get id => type;

  static final SimCodec<UpdatePlayerUsingHandlePacket> codec = SimCodec(
    type,
    SimPacketDirection.serverbound,
    (w, p) => w
      ..writeFloat(p.desiredRange)
      ..writeBool(p.remove)
      ..writeBlockPos(p.interactionPos),
    (r) => UpdatePlayerUsingHandlePacket(r.readFloat(), r.readBool(), r.readBlockPos()),
  );
}

/// `simulated:players_holding_handles` — the uuids a client draws the arm for.
final class ClientboundPlayersHoldingHandlePacket implements SimPacket {
  static const String type = 'simulated:players_holding_handles';

  final List<String> uuids;

  ClientboundPlayersHoldingHandlePacket(Iterable<String> uuids) : uuids = List<String>.unmodifiable(uuids);

  @override
  String get id => type;

  static final SimCodec<ClientboundPlayersHoldingHandlePacket> codec = SimCodec(
    type,
    SimPacketDirection.clientbound,
    (w, p) => w.writeList(p.uuids, (w, uuid) => w.writeUuid(uuid)),
    (r) => ClientboundPlayersHoldingHandlePacket(r.readList((r) => r.readUuid())),
  );
}
