// End Sea physics: the dimension overrides and the clientbound payload.
//
// `EndSeaPhysics.STREAM_CODEC` is `ByteBufCodecs.fromCodec(CODEC)`, which is not
// a field-by-field codec at all: the record is written as an **NBT compound**
// through `NbtOps`, so the keys below are the wire format:
//
//   dimension       string
//   priority        int, absent when empty
//   start_y         double
//   depth_gradient  double (default 1 when absent)
//   drag            double (default 1 when absent)
//
// `end_sea` then prefixes a VarInt count and repeats that compound per entry.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.content.end_sea.EndSeaPhysics
//       …network.packets.end_sea.ClientboundEndSeaPacket
// create's NBT model and packet-buffer extensions are pure but not exported from
// the barrel.
// ignore_for_file: implementation_imports
import 'package:create/src/core/byte_buf.dart';
import 'package:create/src/core/nbt.dart' show NbtKind, NbtValue;
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../network/sim_packet.dart';

/// One dimension's End Sea settings.
final class EndSeaPhysics {
  /// The dimension id (`minecraft:the_end`).
  final String dimension;

  /// The priority; a lower number wins when several entries match.
  final int? priority;

  /// The y below which the sea starts.
  final double startY;

  /// How fast the pull grows with depth.
  final double depthGradient;

  /// The drag multiplier.
  final double drag;

  const EndSeaPhysics({
    required this.dimension,
    this.priority,
    required this.startY,
    this.depthGradient = 1.0,
    this.drag = 1.0,
  });

  /// `EndSeaPhysics.CODEC` written as an NBT compound (`fromCodec`).
  ///
  /// The two `optionalFieldOf(..., 1d)` fields are *omitted* when they hold the
  /// default, which is what the Java codec does; writing them anyway would
  /// still decode, but it would not be the same bytes.
  NbtValue toNbt() {
    final map = <String, NbtValue>{
      'dimension': NbtValue.string(dimension),
      'start_y': NbtValue.double64(startY),
    };
    if (priority != null) map['priority'] = NbtValue.int32(priority!);
    if (depthGradient != 1.0) map['depth_gradient'] = NbtValue.double64(depthGradient);
    if (drag != 1.0) map['drag'] = NbtValue.double64(drag);
    return NbtValue.compound(map);
  }

  /// The reader of [toNbt]; throws when a required key is missing.
  static EndSeaPhysics fromNbt(NbtValue tag) {
    if (tag.kind != NbtKind.compound) throw PacketException('EndSeaPhysics is not a compound');
    final map = tag.asCompound;
    final dimension = map['dimension'];
    final startY = map['start_y'];
    if (dimension == null || dimension.kind != NbtKind.string) {
      throw const PacketException('EndSeaPhysics is missing `dimension`');
    }
    if (startY == null || startY.kind != NbtKind.double) {
      throw const PacketException('EndSeaPhysics is missing `start_y`');
    }
    double? optionalDouble(String key) {
      final v = map[key];
      if (v == null) return null;
      if (v.kind != NbtKind.double) throw PacketException('EndSeaPhysics `$key` is not a double');
      return v.value as double;
    }

    final priority = map['priority'];
    return EndSeaPhysics(
      dimension: dimension.value as String,
      priority: priority?.value as int?,
      startY: startY.value as double,
      depthGradient: optionalDouble('depth_gradient') ?? 1.0,
      drag: optionalDouble('drag') ?? 1.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EndSeaPhysics &&
      other.dimension == dimension &&
      other.priority == priority &&
      other.startY == startY &&
      other.depthGradient == depthGradient &&
      other.drag == drag;

  @override
  int get hashCode => Object.hash(dimension, priority, startY, depthGradient, drag);

  @override
  String toString() => 'EndSeaPhysics($dimension, startY: $startY)';
}

/// `simulated:end_sea` — every dimension's sea settings.
final class ClientboundEndSeaPacket implements SimPacket {
  static const String type = 'simulated:end_sea';

  final List<EndSeaPhysics> physics;

  ClientboundEndSeaPacket(Iterable<EndSeaPhysics> physics) : physics = List<EndSeaPhysics>.unmodifiable(physics);

  @override
  String get id => type;

  static final SimCodec<ClientboundEndSeaPacket> codec = SimCodec(
    type,
    SimPacketDirection.clientbound,
    (w, p) {
      w.writeInt(p.physics.length);
      for (final entry in p.physics) {
        w.writeNbt(entry.toNbt());
      }
    },
    (r) {
      final count = r.readInt();
      if (count < 0) throw PacketException('Negative End Sea entry count $count');
      return ClientboundEndSeaPacket([
        for (var i = 0; i < count; i++)
          if (r.readNbt() case final tag?) EndSeaPhysics.fromNbt(tag) else throw const PacketException('Missing End Sea entry'),
      ]);
    },
  );
}
