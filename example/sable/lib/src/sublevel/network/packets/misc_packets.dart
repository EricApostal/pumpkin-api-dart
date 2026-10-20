// The remaining TCP payloads: `freeze_player`, `udp_activation`,
// `enter_gizmo_mode`, `punch_sub_level` and `gizmo_move_sublevel`.
//
// `punch_sub_level` and `gizmo_move_sublevel` are the two serverbound payloads;
// the plugin handles them. `punchCurve` is the mass-to-impulse curve the punch
// handler uses (it is pure, so it lives here with the payload that carries the
// punch).
//
// Pure: no host imports.
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../math/vector.dart';
import '../packet.dart';
import '../wire.dart';

/// `ClientboundFreezePlayerPacket`.
///
/// Wire: `UUID subLevelID`, `Vector3d localPosition`.
final class ClientboundFreezePlayerPacket implements SablePacket {
  /// `Sable.sablePath("freeze_player")`.
  static const String payloadId = 'sable:freeze_player';

  final String subLevelId;

  /// The position, in the sub-level's local space.
  final Vector3d localPosition;

  ClientboundFreezePlayerPacket(this.subLevelId, Vector3d localPosition)
    : localPosition = Vector3d(localPosition.x, localPosition.y, localPosition.z);

  @override
  String get id => payloadId;

  @override
  void write(PacketWriter buf) {
    buf.writeUuid(subLevelId);
    SableBufferUtils.writeVector3d(buf, localPosition);
  }

  /// `ClientboundFreezePlayerPacket.read`.
  static ClientboundFreezePlayerPacket read(PacketReader buf) =>
      ClientboundFreezePlayerPacket(buf.readUuid(), SableBufferUtils.readVector3d(buf));

  /// `ClientboundFreezePlayerPacket.CODEC`.
  static final SablePacketCodec<ClientboundFreezePlayerPacket> codec =
      SableCodec<ClientboundFreezePlayerPacket>(
        payloadId,
        SablePacketDirection.clientbound,
        (buf, value) => value.write(buf),
        read,
      );

  @override
  String toString() => 'ClientboundFreezePlayerPacket[$subLevelId, $localPosition]';
}

/// `ClientboundSableUDPActivationPacket`.
///
/// Wire: `UUID uuid`.
final class ClientboundSableUdpActivationPacket implements SablePacket {
  /// `Sable.sablePath("udp_activation")`.
  static const String payloadId = 'sable:udp_activation';

  /// The token the client echoes back in its `AUTH` datagram.
  final String uuid;

  const ClientboundSableUdpActivationPacket(this.uuid);

  @override
  String get id => payloadId;

  @override
  void write(PacketWriter buf) => buf.writeUuid(uuid);

  /// `ClientboundSableUDPActivationPacket.read`.
  static ClientboundSableUdpActivationPacket read(PacketReader buf) =>
      ClientboundSableUdpActivationPacket(buf.readUuid());

  /// `ClientboundSableUDPActivationPacket.CODEC`.
  static final SablePacketCodec<ClientboundSableUdpActivationPacket> codec =
      SableCodec<ClientboundSableUdpActivationPacket>(
        payloadId,
        SablePacketDirection.clientbound,
        (buf, value) => value.write(buf),
        read,
      );

  @override
  String toString() => 'ClientboundSableUdpActivationPacket[$uuid]';
}

/// `ClientboundEnterGizmoPacket`: empty body.
final class ClientboundEnterGizmoPacket implements SablePacket {
  /// `Sable.sablePath("enter_gizmo_mode")`.
  static const String payloadId = 'sable:enter_gizmo_mode';

  const ClientboundEnterGizmoPacket();

  @override
  String get id => payloadId;

  @override
  void write(PacketWriter buf) {}

  /// `ClientboundEnterGizmoPacket.read`.
  static ClientboundEnterGizmoPacket read(PacketReader buf) => const ClientboundEnterGizmoPacket();

  /// `ClientboundEnterGizmoPacket.CODEC`.
  static final SablePacketCodec<ClientboundEnterGizmoPacket> codec =
      SableCodec<ClientboundEnterGizmoPacket>(
        payloadId,
        SablePacketDirection.clientbound,
        (buf, value) => value.write(buf),
        read,
      );

  @override
  String toString() => 'ClientboundEnterGizmoPacket';
}

/// `ServerboundPunchSubLevelPacket`.
///
/// Wire: `BlockPos punchedBlock`, `Vector3d localPosition`,
/// `Vector3d direction`.
final class ServerboundPunchSubLevelPacket implements SablePacket {
  /// `Sable.sablePath("punch_sub_level")`.
  static const String payloadId = 'sable:punch_sub_level';

  /// The block the player punched; it identifies the target sub-level.
  final (int, int, int) punchedBlock;

  /// The hit position, relative to the target's centre of mass, in global space.
  final Vector3d localPosition;

  /// The punch direction in world space (or in the tracked sub-level's plot
  /// space).
  final Vector3d direction;

  ServerboundPunchSubLevelPacket(this.punchedBlock, Vector3d localPosition, Vector3d direction)
    : localPosition = Vector3d(localPosition.x, localPosition.y, localPosition.z),
      direction = Vector3d(direction.x, direction.y, direction.z);

  @override
  String get id => payloadId;

  @override
  void write(PacketWriter buf) {
    buf.writeBlockPos(punchedBlock);
    SableBufferUtils.writeVector3d(buf, localPosition);
    SableBufferUtils.writeVector3d(buf, direction);
  }

  /// `ServerboundPunchSubLevelPacket.read`.
  static ServerboundPunchSubLevelPacket read(PacketReader buf) => ServerboundPunchSubLevelPacket(
    buf.readBlockPos(),
    SableBufferUtils.readVector3d(buf),
    SableBufferUtils.readVector3d(buf),
  );

  /// `ServerboundPunchSubLevelPacket.CODEC`.
  static final SablePacketCodec<ServerboundPunchSubLevelPacket> codec =
      SableCodec<ServerboundPunchSubLevelPacket>(
        payloadId,
        SablePacketDirection.serverbound,
        (buf, value) => value.write(buf),
        read,
      );

  /// The punch impulse curve: given a sub-level's mass, the strength scalar
  /// applied to the player's punch strength attribute.
  ///
  /// [Tuning page](https://www.desmos.com/calculator/ziovwc5a2v), by Eriksonn.
  static double punchCurve(double x) {
    // Falloff scale when x >= 1.
    const s = 2.0;

    // Falloff exponent when x >= 1.
    const e = 0.5;

    // Slope at mass = 1.
    const k = 0.8;

    // Velocity impulse at zero mass.
    const p = 1.75;

    final u = x - 1;
    final g = k / (s * e);

    if (x < 1) {
      return (((p + k - 2) * u + k - 1) * u + 1) * x;
    }
    final inverseE = 1 / (e - 1);
    return s * (math.pow(u + math.pow(g, inverseE), e) - math.pow(g, e * inverseE)) + 1;
  }

  @override
  String toString() =>
      'ServerboundPunchSubLevelPacket[$punchedBlock, $localPosition, $direction]';
}

/// `ServerboundGizmoMoveSubLevelPacket`.
///
/// Wire: `UUID subLevel`, `Vector3d position`.
final class ServerboundGizmoMoveSubLevelPacket implements SablePacket {
  /// `Sable.sablePath("gizmo_move_sublevel")`.
  static const String payloadId = 'sable:gizmo_move_sub_level';

  final String subLevel;

  /// The new position of the sub-level.
  final Vector3d position;

  ServerboundGizmoMoveSubLevelPacket(this.subLevel, Vector3d position)
    : position = Vector3d(position.x, position.y, position.z);

  @override
  String get id => payloadId;

  @override
  void write(PacketWriter buf) {
    buf.writeUuid(subLevel);
    SableBufferUtils.writeVector3d(buf, position);
  }

  /// `ServerboundGizmoMoveSubLevelPacket.read`.
  static ServerboundGizmoMoveSubLevelPacket read(PacketReader buf) =>
      ServerboundGizmoMoveSubLevelPacket(buf.readUuid(), SableBufferUtils.readVector3d(buf));

  /// `ServerboundGizmoMoveSubLevelPacket.CODEC`.
  static final SablePacketCodec<ServerboundGizmoMoveSubLevelPacket> codec =
      SableCodec<ServerboundGizmoMoveSubLevelPacket>(
        payloadId,
        SablePacketDirection.serverbound,
        (buf, value) => value.write(buf),
        read,
      );

  @override
  String toString() => 'ServerboundGizmoMoveSubLevelPacket[$subLevel, $position]';
}
