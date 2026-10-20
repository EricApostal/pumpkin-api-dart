// The sub-level tracking payloads: `start_tracking_sublevel`,
// `finalize_sub_level`, `stop_tracking_sublevel`, `change_bounds_sublevel`,
// `stop_moving_sublevel`, `change_sub_level_name` and
// `recently_split_sub_level`.
//
// Field order follows the Java `write` methods and `StreamCodec.composite`
// argument order exactly; the wire is read by the installed Sable client, so
// the order is not a local choice. Every plot coordinate is a packed
// `ChunkPos` (`ChunkPos.pack(plotX - originX, plotZ - originZ)`), i.e. relative
// to the plot yard's origin, not a global chunk coordinate.
//
// Pure: no host imports.
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../math/bounding_box.dart';
import '../../math/pose.dart';
import '../packet.dart';
import '../wire.dart';

/// `ClientboundStartTrackingSubLevelPacket`.
///
/// Wire: `long plotCoordinate`, `UUID subLevelID`, `Pose3d lastPose`,
/// `Pose3d pose`, `BoundingBox3i bounds`, optional UTF `name`, `int gameTick`.
final class ClientboundStartTrackingSubLevelPacket implements SablePacket {
  /// `Sable.sablePath("start_tracking_sublevel")`.
  static const String payloadId = 'sable:start_tracking_sublevel';

  /// The packed plot coordinate, relative to the plot yard origin.
  final int plotCoordinate;

  /// The sub-level UUID.
  final String subLevelId;

  /// The pose of the previous game tick.
  final Pose3d lastPose;

  /// The current pose.
  final Pose3d pose;

  /// The local plot bounds.
  final BoundingBox3i bounds;

  /// The display name, or `null`.
  final String? name;

  /// The interpolation tick the snapshot poses belong to.
  final int gameTick;

  ClientboundStartTrackingSubLevelPacket({
    required this.plotCoordinate,
    required this.subLevelId,
    required Pose3dc lastPose,
    required Pose3dc pose,
    required BoundingBox3ic bounds,
    this.name,
    required this.gameTick,
  }) : lastPose = Pose3d.copy(lastPose),
       pose = Pose3d.copy(pose),
       bounds = BoundingBox3i.copy(bounds);

  @override
  String get id => payloadId;

  @override
  void write(PacketWriter buf) {
    buf.writeLong(plotCoordinate);
    buf.writeUuid(subLevelId);
    SableBufferUtils.writePose(buf, lastPose);
    SableBufferUtils.writePose(buf, pose);
    SableBufferUtils.writeBounds(buf, bounds);
    buf.writeBool(name != null);
    final value = name;
    if (value != null) buf.writeString(value);
    buf.writeInt(gameTick);
  }

  /// `ClientboundStartTrackingSubLevelPacket.read`.
  static ClientboundStartTrackingSubLevelPacket read(PacketReader buf) =>
      ClientboundStartTrackingSubLevelPacket(
        plotCoordinate: buf.readLong(),
        subLevelId: buf.readUuid(),
        lastPose: SableBufferUtils.readPose(buf),
        pose: SableBufferUtils.readPose(buf),
        bounds: SableBufferUtils.readBounds(buf),
        name: buf.readBool() ? buf.readString() : null,
        gameTick: buf.readInt(),
      );

  /// `ClientboundStartTrackingSubLevelPacket.CODEC`.
  static final SablePacketCodec<ClientboundStartTrackingSubLevelPacket> codec =
      SableCodec<ClientboundStartTrackingSubLevelPacket>(
        payloadId,
        SablePacketDirection.clientbound,
        (buf, value) => value.write(buf),
        read,
      );

  @override
  String toString() =>
      'ClientboundStartTrackingSubLevelPacket[plot=$plotCoordinate, id=$subLevelId, '
      'name=$name, tick=$gameTick]';
}

/// `ClientboundFinalizeSubLevelPacket`.
///
/// Wire: `long plotCoordinate`.
final class ClientboundFinalizeSubLevelPacket implements SablePacket {
  /// `Sable.sablePath("finalize_sub_level")`.
  static const String payloadId = 'sable:finalize_sub_level';

  final int plotCoordinate;

  const ClientboundFinalizeSubLevelPacket(this.plotCoordinate);

  @override
  String get id => payloadId;

  @override
  void write(PacketWriter buf) => buf.writeLong(plotCoordinate);

  /// `ClientboundFinalizeSubLevelPacket.read`.
  static ClientboundFinalizeSubLevelPacket read(PacketReader buf) =>
      ClientboundFinalizeSubLevelPacket(buf.readLong());

  /// `ClientboundFinalizeSubLevelPacket.CODEC`.
  static final SablePacketCodec<ClientboundFinalizeSubLevelPacket> codec =
      SableCodec<ClientboundFinalizeSubLevelPacket>(
        payloadId,
        SablePacketDirection.clientbound,
        (buf, value) => value.write(buf),
        read,
      );

  @override
  String toString() => 'ClientboundFinalizeSubLevelPacket[$plotCoordinate]';
}

/// `ClientboundStopTrackingSubLevelPacket`.
///
/// Wire: `long plotCoordinate`.
final class ClientboundStopTrackingSubLevelPacket implements SablePacket {
  /// `Sable.sablePath("stop_tracking_sublevel")`.
  static const String payloadId = 'sable:stop_tracking_sublevel';

  final int plotCoordinate;

  const ClientboundStopTrackingSubLevelPacket(this.plotCoordinate);

  @override
  String get id => payloadId;

  @override
  void write(PacketWriter buf) => buf.writeLong(plotCoordinate);

  /// `ClientboundStopTrackingSubLevelPacket.read`.
  static ClientboundStopTrackingSubLevelPacket read(PacketReader buf) =>
      ClientboundStopTrackingSubLevelPacket(buf.readLong());

  /// `ClientboundStopTrackingSubLevelPacket.CODEC`.
  static final SablePacketCodec<ClientboundStopTrackingSubLevelPacket> codec =
      SableCodec<ClientboundStopTrackingSubLevelPacket>(
        payloadId,
        SablePacketDirection.clientbound,
        (buf, value) => value.write(buf),
        read,
      );

  @override
  String toString() => 'ClientboundStopTrackingSubLevelPacket[$plotCoordinate]';
}

/// `ClientboundChangeBoundsSubLevelPacket`.
///
/// Wire: `long plotCoordinate`, `BoundingBox3i bounds`.
final class ClientboundChangeBoundsSubLevelPacket implements SablePacket {
  /// `Sable.sablePath("change_bounds_sublevel")`.
  static const String payloadId = 'sable:change_bounds_sublevel';

  final int plotCoordinate;
  final BoundingBox3i bounds;

  ClientboundChangeBoundsSubLevelPacket(this.plotCoordinate, BoundingBox3ic bounds)
    : bounds = BoundingBox3i.copy(bounds);

  @override
  String get id => payloadId;

  @override
  void write(PacketWriter buf) {
    buf.writeLong(plotCoordinate);
    SableBufferUtils.writeBounds(buf, bounds);
  }

  /// `ClientboundChangeBoundsSubLevelPacket.read`.
  static ClientboundChangeBoundsSubLevelPacket read(PacketReader buf) =>
      ClientboundChangeBoundsSubLevelPacket(buf.readLong(), SableBufferUtils.readBounds(buf));

  /// `ClientboundChangeBoundsSubLevelPacket.CODEC`.
  static final SablePacketCodec<ClientboundChangeBoundsSubLevelPacket> codec =
      SableCodec<ClientboundChangeBoundsSubLevelPacket>(
        payloadId,
        SablePacketDirection.clientbound,
        (buf, value) => value.write(buf),
        read,
      );

  @override
  String toString() => 'ClientboundChangeBoundsSubLevelPacket[$plotCoordinate, $bounds]';
}

/// `ClientboundStopMovingSubLevelPacket`.
///
/// Wire: `long plotCoordinate`.
final class ClientboundStopMovingSubLevelPacket implements SablePacket {
  /// `Sable.sablePath("stop_moving_sublevel")`.
  static const String payloadId = 'sable:stop_moving_sublevel';

  final int plotCoordinate;

  const ClientboundStopMovingSubLevelPacket(this.plotCoordinate);

  @override
  String get id => payloadId;

  @override
  void write(PacketWriter buf) => buf.writeLong(plotCoordinate);

  /// `ClientboundStopMovingSubLevelPacket.read`.
  static ClientboundStopMovingSubLevelPacket read(PacketReader buf) =>
      ClientboundStopMovingSubLevelPacket(buf.readLong());

  /// `ClientboundStopMovingSubLevelPacket.CODEC`.
  static final SablePacketCodec<ClientboundStopMovingSubLevelPacket> codec =
      SableCodec<ClientboundStopMovingSubLevelPacket>(
        payloadId,
        SablePacketDirection.clientbound,
        (buf, value) => value.write(buf),
        read,
      );

  @override
  String toString() => 'ClientboundStopMovingSubLevelPacket[$plotCoordinate]';
}

/// `ClientboundChangeSubLevelNamePacket`.
///
/// Wire: `UUID subLevelID`, `ByteBufCodecs.optional(STRING_UTF8) name`.
final class ClientboundChangeSubLevelNamePacket implements SablePacket {
  /// `Sable.sablePath("change_sub_level_name")`.
  static const String payloadId = 'sable:change_sub_level_name';

  final String subLevelId;

  /// The new name, or `null` to clear it.
  final String? name;

  const ClientboundChangeSubLevelNamePacket(this.subLevelId, this.name);

  @override
  String get id => payloadId;

  @override
  void write(PacketWriter buf) {
    buf.writeUuid(subLevelId);
    buf.writeOptional(name, (w, value) => w.writeString(value));
  }

  /// `ClientboundChangeSubLevelNamePacket.CODEC`.
  static ClientboundChangeSubLevelNamePacket read(PacketReader buf) =>
      ClientboundChangeSubLevelNamePacket(buf.readUuid(), buf.readOptional((r) => r.readString()));

  /// `ClientboundChangeSubLevelNamePacket.CODEC`.
  static final SablePacketCodec<ClientboundChangeSubLevelNamePacket> codec =
      SableCodec<ClientboundChangeSubLevelNamePacket>(
        payloadId,
        SablePacketDirection.clientbound,
        (buf, value) => value.write(buf),
        read,
      );

  @override
  String toString() => 'ClientboundChangeSubLevelNamePacket[$subLevelId, $name]';
}

/// `ClientboundRecentlySplitSubLevelPacket`.
///
/// Wire: `UUID splitSubLevelID`, `UUID splitFromID`, `Pose3d pose`.
final class ClientboundRecentlySplitSubLevelPacket implements SablePacket {
  /// `Sable.sablePath("recently_split_sub_level")`.
  static const String payloadId = 'sable:recently_split_sub_level';

  final String splitSubLevelId;
  final String splitFromId;

  /// The pose the sub-level had before it was split off.
  final Pose3d pose;

  ClientboundRecentlySplitSubLevelPacket({
    required this.splitSubLevelId,
    required this.splitFromId,
    required Pose3d pose,
  }) : pose = Pose3d.copy(pose);

  @override
  String get id => payloadId;

  @override
  void write(PacketWriter buf) {
    buf.writeUuid(splitSubLevelId);
    buf.writeUuid(splitFromId);
    SableBufferUtils.writePose(buf, pose);
  }

  /// `ClientboundRecentlySplitSubLevelPacket.CODEC`.
  static ClientboundRecentlySplitSubLevelPacket read(PacketReader buf) =>
      ClientboundRecentlySplitSubLevelPacket(
        splitSubLevelId: buf.readUuid(),
        splitFromId: buf.readUuid(),
        pose: SableBufferUtils.readPose(buf),
      );

  /// `ClientboundRecentlySplitSubLevelPacket.CODEC`.
  static final SablePacketCodec<ClientboundRecentlySplitSubLevelPacket> codec =
      SableCodec<ClientboundRecentlySplitSubLevelPacket>(
        payloadId,
        SablePacketDirection.clientbound,
        (buf, value) => value.write(buf),
        read,
      );

  @override
  String toString() =>
      'ClientboundRecentlySplitSubLevelPacket[$splitSubLevelId from $splitFromId]';
}
