// The rope payloads: breaking a rope, riding it, and the two clientbound
// updates.
//
// `rope_data` is one of the hand-written codecs, and its layout is worth
// spelling out because a single field out of place makes the client render a
// rope through the world:
//
//   int interpolationTick
//   BlockPos ownerPos            (packed long)
//   UUID uuid                    (two longs)
//   int pointCount
//   pointCount x Vector3d        (3 doubles each, `SableBufferUtils.write`)
//   bool hasStart; BlockPos      (only when true)
//   bool hasEnd;   BlockPos      (only when true)
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.network.packets.RopeBreakPacket
//       …packets.RopeRidingPacket
//       …packets.rope.ClientboundRopeDataPacket
//       …packets.rope.ClientboundRopeStoppedPacket
// create's internals are pure but not exported from the barrel yet.
// ignore_for_file: implementation_imports
import 'package:create/src/common/pos.dart' show Pos;
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:sable/sable.dart' show Vector3d;

import '../sim_packet.dart';
import '../sim_wire.dart';

/// `simulated:break_rope` — the player cut a rope.
final class RopeBreakPacket implements SimPacket {
  static const String type = 'simulated:break_rope';

  /// The strand's uuid.
  final String uuid;

  const RopeBreakPacket(this.uuid);

  @override
  String get id => type;

  static final SimCodec<RopeBreakPacket> codec = SimCodec(
    type,
    SimPacketDirection.serverbound,
    (w, p) => w.writeUuid(p.uuid),
    (r) => RopeBreakPacket(r.readUuid()),
  );
}

/// `simulated:ride_rope` — the player grabbed (`stop == false`) or let go of a
/// rope.
final class RopeRidingPacket implements SimPacket {
  static const String type = 'simulated:ride_rope';

  final String uuid;
  final bool stop;

  const RopeRidingPacket(this.uuid, this.stop);

  @override
  String get id => type;

  static final SimCodec<RopeRidingPacket> codec = SimCodec(
    type,
    SimPacketDirection.serverbound,
    (w, p) => w
      ..writeUuid(p.uuid)
      ..writeBool(p.stop),
    (r) => RopeRidingPacket(r.readUuid(), r.readBool()),
  );
}

/// `simulated:rope_data` — a strand's point list, for the clients watching it.
final class ClientboundRopeDataPacket implements SimPacket {
  static const String type = 'simulated:rope_data';

  final int interpolationTick;

  /// The block entity that owns the strand.
  final Pos ownerPos;

  final String uuid;
  final List<Vector3d> points;

  /// The block the rope starts at, when it is attached to one.
  final Pos? startAttachmentPos;

  /// The block the rope ends at, when it is attached to one.
  final Pos? endAttachmentPos;

  ClientboundRopeDataPacket({
    required this.interpolationTick,
    required this.ownerPos,
    required this.uuid,
    required List<Vector3d> points,
    this.startAttachmentPos,
    this.endAttachmentPos,
  }) : points = List<Vector3d>.unmodifiable(points);

  @override
  String get id => type;

  static final SimCodec<ClientboundRopeDataPacket> codec = SimCodec(
    type,
    SimPacketDirection.clientbound,
    (w, p) {
      w
        ..writeInt(p.interpolationTick)
        ..writeBlockPos(p.ownerPos)
        ..writeUuid(p.uuid)
        ..writeInt(p.points.length);
      for (final point in p.points) {
        SimWire.writeVector3d(w, point);
      }
      w.writeOptional(p.startAttachmentPos, (w, v) => w.writeBlockPos(v));
      w.writeOptional(p.endAttachmentPos, (w, v) => w.writeBlockPos(v));
    },
    (r) {
      final tick = r.readInt();
      final owner = r.readBlockPos();
      final uuid = r.readUuid();
      // `ClientboundRopeDataPacket.write` uses `buf.writeInt(points.size())`,
      // not a VarInt count like the other list codecs.
      final count = r.readInt();
      if (count < 0) throw PacketException('Negative rope point count $count');
      final points = [for (var i = 0; i < count; i++) SimWire.readVector3d(r)];
      return ClientboundRopeDataPacket(
        interpolationTick: tick,
        ownerPos: owner,
        uuid: uuid,
        points: points,
        startAttachmentPos: r.readOptional((r) => r.readBlockPos()),
        endAttachmentPos: r.readOptional((r) => r.readBlockPos()),
      );
    },
  );
}

/// `simulated:rope_stopped` — the strand came to rest, so the client can stop
/// interpolating it.
final class ClientboundRopeStoppedPacket implements SimPacket {
  static const String type = 'simulated:rope_stopped';

  final Pos ownerPos;

  const ClientboundRopeStoppedPacket(this.ownerPos);

  @override
  String get id => type;

  static final SimCodec<ClientboundRopeStoppedPacket> codec = SimCodec(
    type,
    SimPacketDirection.clientbound,
    (w, p) => w.writeBlockPos(p.ownerPos),
    (r) => ClientboundRopeStoppedPacket(r.readBlockPos()),
  );
}
