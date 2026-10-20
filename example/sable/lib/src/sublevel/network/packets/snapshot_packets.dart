// The snapshot payloads: `snapshot_packet` and `snapshot_info_packet`.
//
// Both are *dual* payloads: the same body travels over TCP (a registered Veil
// payload) and over UDP (`SableUDPPacketType.SNAPSHOT` / `SNAPSHOT_INFO`). The
// body layout is the same on both transports, so the TCP codec here is the UDP
// codec too.
//
// ```
// snapshot_packet:      int interpolationTick, VarInt count, count × {
//                         long plotCoordinate, Pose3d pose,
//                         Vector3f linearVelocity, Vector3f angularVelocity }
// snapshot_info_packet: int msSinceLast, int gameTick, bool stopped
// ```
//
// The velocities are `Vector3fc` in Java, so they are three floats on the wire.
//
// Pure: no host imports.
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../math/pose.dart';
import '../../math/vector.dart';
import '../packet.dart';
import '../wire.dart';
import '../udp/udp_packet.dart';

/// One sub-level's movement in a snapshot (`ClientboundSableSnapshotDualPacket.Entry`).
final class SnapshotEntry {
  /// The packed plot coordinate.
  final int plotCoordinate;

  /// The pose at the snapshot's interpolation tick.
  final Pose3d pose;

  /// The linear velocity, in blocks per second.
  final Vector3d linearVelocity;

  /// The angular velocity, in radians per second.
  final Vector3d angularVelocity;

  SnapshotEntry({
    required this.plotCoordinate,
    required Pose3dc pose,
    required Vector3d linearVelocity,
    required Vector3d angularVelocity,
  }) : pose = Pose3d.copy(pose),
       linearVelocity = Vector3d(linearVelocity.x, linearVelocity.y, linearVelocity.z),
       angularVelocity = Vector3d(angularVelocity.x, angularVelocity.y, angularVelocity.z);

  @override
  bool operator ==(Object other) =>
      other is SnapshotEntry &&
      other.plotCoordinate == plotCoordinate &&
      other.pose.position().x == pose.position().x &&
      other.pose.position().y == pose.position().y &&
      other.pose.position().z == pose.position().z &&
      other.pose.orientation().x == pose.orientation().x &&
      other.pose.orientation().y == pose.orientation().y &&
      other.pose.orientation().z == pose.orientation().z &&
      other.pose.orientation().w == pose.orientation().w &&
      other.pose.rotationPoint().x == pose.rotationPoint().x &&
      other.pose.rotationPoint().y == pose.rotationPoint().y &&
      other.pose.rotationPoint().z == pose.rotationPoint().z &&
      other.linearVelocity.x == linearVelocity.x &&
      other.linearVelocity.y == linearVelocity.y &&
      other.linearVelocity.z == linearVelocity.z &&
      other.angularVelocity.x == angularVelocity.x &&
      other.angularVelocity.y == angularVelocity.y &&
      other.angularVelocity.z == angularVelocity.z;

  @override
  int get hashCode => Object.hash(
    plotCoordinate,
    pose.position().x,
    pose.position().y,
    pose.position().z,
    pose.orientation().x,
    pose.orientation().y,
    pose.orientation().z,
    pose.orientation().w,
    linearVelocity.x,
    linearVelocity.y,
    linearVelocity.z,
  );

  @override
  String toString() =>
      'SnapshotEntry[$plotCoordinate, pos=${pose.position()}, '
      'vel=$linearVelocity, ang=$angularVelocity]';
}

/// `ClientboundSableSnapshotDualPacket`.
final class ClientboundSableSnapshotDualPacket implements SablePacket, SableUdpPacket {
  /// `Sable.sablePath("snapshot_packet")`.
  static const String payloadId = 'sable:snapshot_packet';

  /// The interpolation tick every pose in this snapshot belongs to.
  final int interpolationTick;

  /// One entry per moving sub-level the player tracks.
  final List<SnapshotEntry> entries;

  const ClientboundSableSnapshotDualPacket(this.interpolationTick, this.entries);

  @override
  String get id => payloadId;

  @override
  SableUdpPacketType get type => SableUdpPacketType.snapshot;

  @override
  void write(PacketWriter buf) {
    buf.writeInt(interpolationTick);
    buf.writeVarInt(entries.length);
    for (final entry in entries) {
      buf.writeLong(entry.plotCoordinate);
      SableBufferUtils.writePose(buf, entry.pose);
      SableBufferUtils.writeVector3f(buf, entry.linearVelocity);
      SableBufferUtils.writeVector3f(buf, entry.angularVelocity);
    }
  }

  /// `ClientboundSableSnapshotDualPacket(ByteBuf)`.
  static ClientboundSableSnapshotDualPacket read(PacketReader buf) {
    final tick = buf.readInt();
    final count = buf.readVarInt();
    if (count < 0) throw PacketException('Negative snapshot entry count $count');
    final entries = <SnapshotEntry>[];
    for (var i = 0; i < count; i++) {
      entries.add(
        SnapshotEntry(
          plotCoordinate: buf.readLong(),
          pose: SableBufferUtils.readPose(buf),
          linearVelocity: SableBufferUtils.readVector3f(buf),
          angularVelocity: SableBufferUtils.readVector3f(buf),
        ),
      );
    }
    return ClientboundSableSnapshotDualPacket(tick, entries);
  }

  /// `ClientboundSableSnapshotDualPacket.CODEC`.
  static final SablePacketCodec<ClientboundSableSnapshotDualPacket> codec =
      SableCodec<ClientboundSableSnapshotDualPacket>(
        payloadId,
        SablePacketDirection.both,
        (buf, value) => value.write(buf),
        read,
      );

  @override
  String toString() => 'ClientboundSableSnapshotDualPacket[tick=$interpolationTick, ${entries.length} entries]';
}

/// `ClientboundSableSnapshotInfoDualPacket`.
final class ClientboundSableSnapshotInfoDualPacket implements SablePacket, SableUdpPacket {
  /// `Sable.sablePath("snapshot_info_packet")`.
  static const String payloadId = 'sable:snapshot_info_packet';

  /// The wall-clock milliseconds since the previous snapshot was sent.
  final int msSinceLast;

  /// The interpolation tick of the snapshot that follows.
  final int gameTick;

  /// Whether the player's tracked sub-levels are all stopped.
  final bool stopped;

  const ClientboundSableSnapshotInfoDualPacket({
    required this.msSinceLast,
    required this.gameTick,
    required this.stopped,
  });

  @override
  String get id => payloadId;

  @override
  SableUdpPacketType get type => SableUdpPacketType.snapshotInfo;

  @override
  void write(PacketWriter buf) {
    buf.writeInt(msSinceLast);
    buf.writeInt(gameTick);
    buf.writeBool(stopped);
  }

  /// `ClientboundSableSnapshotInfoDualPacket(ByteBuf)`.
  static ClientboundSableSnapshotInfoDualPacket read(PacketReader buf) =>
      ClientboundSableSnapshotInfoDualPacket(
        msSinceLast: buf.readInt(),
        gameTick: buf.readInt(),
        stopped: buf.readBool(),
      );

  /// `ClientboundSableSnapshotInfoDualPacket.CODEC`.
  static final SablePacketCodec<ClientboundSableSnapshotInfoDualPacket> codec =
      SableCodec<ClientboundSableSnapshotInfoDualPacket>(
        payloadId,
        SablePacketDirection.both,
        (buf, value) => value.write(buf),
        read,
      );

  @override
  String toString() =>
      'ClientboundSableSnapshotInfoDualPacket[$msSinceLast ms, tick=$gameTick, stopped=$stopped]';
}
