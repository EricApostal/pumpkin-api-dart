// The two placement payloads, which share a shape:
//
//   int hand ordinal          (`InteractionHand.ordinal()`, not the HAND boolean)
//   BlockPos parentPos
//   BlockPos childPos
//   Direction parentFacing    (VarInt 3d data value)
//   Direction childFacing
//
// The difference is only in what the server does with them, which is in
// `content/blocks/spring/spring_placement.dart` and
// `content/blocks/merging_glue/merging_glue_placement.dart`.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.network.packets.PlaceSpringPacket
//       …packets.PlaceMergingGluePacket
// create's internals are pure but not exported from the barrel yet.
// ignore_for_file: implementation_imports
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../sim_packet.dart';

/// `simulated:place_spring` — the player linked two blocks with a spring.
final class PlaceSpringPacket implements SimPacket {
  static const String type = 'simulated:place_spring';

  final Pos parentPos;
  final Pos childPos;
  final Direction parentFacing;
  final Direction childFacing;

  /// `InteractionHand` ordinal: 0 is the main hand, 1 the off hand.
  final int hand;

  const PlaceSpringPacket(this.parentPos, this.childPos, this.parentFacing, this.childFacing, this.hand);

  @override
  String get id => type;

  static final SimCodec<PlaceSpringPacket> codec = SimCodec(
    type,
    SimPacketDirection.serverbound,
    (w, p) {
      w
        ..writeInt(p.hand)
        ..writeBlockPos(p.parentPos)
        ..writeBlockPos(p.childPos)
        ..writeVarInt(p.parentFacing.data3d)
        ..writeVarInt(p.childFacing.data3d);
    },
    // The wire order is the codec's (`hand` first), not the record's.
    (r) {
      final hand = r.readInt();
      return PlaceSpringPacket(
        r.readBlockPos(),
        r.readBlockPos(),
        _direction(r.readVarInt()),
        _direction(r.readVarInt()),
        hand,
      );
    },
  );
}

/// `simulated:place_merging_glue` — the player linked two sub-levels with
/// merging glue.
final class PlaceMergingGluePacket implements SimPacket {
  static const String type = 'simulated:place_merging_glue';

  final Pos parentPos;
  final Pos childPos;
  final Direction parentFacing;
  final Direction childFacing;

  /// `InteractionHand` ordinal: 0 is the main hand, 1 the off hand.
  final int hand;

  const PlaceMergingGluePacket(this.parentPos, this.childPos, this.parentFacing, this.childFacing, this.hand);

  @override
  String get id => type;

  static final SimCodec<PlaceMergingGluePacket> codec = SimCodec(
    type,
    SimPacketDirection.serverbound,
    (w, p) {
      w
        ..writeInt(p.hand)
        ..writeBlockPos(p.parentPos)
        ..writeBlockPos(p.childPos)
        ..writeVarInt(p.parentFacing.data3d)
        ..writeVarInt(p.childFacing.data3d);
    },
    // The wire order is the codec's (`hand` first), not the record's.
    (r) {
      final hand = r.readInt();
      return PlaceMergingGluePacket(
        r.readBlockPos(),
        r.readBlockPos(),
        _direction(r.readVarInt()),
        _direction(r.readVarInt()),
        hand,
      );
    },
  );
}

/// `Direction.from3DDataValue`.
Direction _direction(int data3d) {
  if (data3d < 0 || data3d >= Direction.values.length) {
    throw PacketException('Invalid Direction 3d data value $data3d');
  }
  return Direction.values[data3d];
}
