// `dev.simulated_team.simulated.util.SimCodecUtil` and the parts of Sable's
// `SableBufferUtils` that Simulated's payloads use, on the wire.
//
// The two vector shapes are *not* interchangeable, and that is the whole point
// of this file:
//
// | Java codec                              | bytes                                  |
// |-----------------------------------------|----------------------------------------|
// | `SableBufferUtils.write(buf, Vector3dc)`| 3 doubles, no prefix                   |
// | `SimCodecUtil.STREAM_VECTOR3DC`         | VarInt 3, then 3 doubles               |
// | `SimCodecUtil.STREAM_POINT_FORCE`       | VarInt 2, then two `STREAM_VECTOR3DC`  |
// | `SimCodecUtil.BOUNDING_BOX_3D_STREAM_CODEC` | VarInt 6, then 6 doubles           |
//
// `STREAM_VECTOR3DC` is `ByteBufCodecs.DOUBLE.apply(ByteBufCodecs.list(3))`, so
// the count prefix is really there; `SableBufferUtils.write` is the hand-written
// one used by `rope_data` and `physics_staff_drag`.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.util.SimCodecUtil
// create's barrel does not export `Aabb` yet.
// ignore_for_file: implementation_imports
import 'package:create/src/common/bounds.dart' show Aabb;
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:sable/sable.dart' show BoundingBox3d, Quaterniond, Vector3d;

/// `QueuedForceGroup.PointForce`: a force applied at a point.
final class PointForce {
  final Vector3d point;
  final Vector3d force;

  PointForce(Vector3d point, Vector3d force)
    : point = Vector3d.copy(point),
      force = Vector3d.copy(force);

  @override
  bool operator ==(Object other) =>
      other is PointForce &&
      other.point.x == point.x &&
      other.point.y == point.y &&
      other.point.z == point.z &&
      other.force.x == force.x &&
      other.force.y == force.y &&
      other.force.z == force.z;

  @override
  int get hashCode => Object.hash(point.x, point.y, point.z, force.x, force.y, force.z);

  @override
  String toString() => 'PointForce(${point.x}, ${point.y}, ${point.z} -> ${force.x}, ${force.y}, ${force.z})';
}

/// The wire codecs of `SimCodecUtil` plus the `SableBufferUtils` primitives.
abstract final class SimWire {
  // ------------------------------------------------------------- primitives

  /// `SableBufferUtils.write(buf, Vector3dc)` / `read(buf, new Vector3d())`:
  /// 3 doubles, no prefix.
  static void writeVector3d(PacketWriter buf, Vector3d v) {
    buf
      ..writeDouble(v.x)
      ..writeDouble(v.y)
      ..writeDouble(v.z);
  }

  /// The reader of [writeVector3d].
  static Vector3d readVector3d(PacketReader buf) => Vector3d(buf.readDouble(), buf.readDouble(), buf.readDouble());

  /// `SableBufferUtils.write(buf, Quaterniondc)`: 4 *floats* (x, y, z, w), so a
  /// round trip through a packet is lossy exactly as it is in Java.
  static void writeQuaterniond(PacketWriter buf, Quaterniond q) {
    buf
      ..writeFloat(q.x)
      ..writeFloat(q.y)
      ..writeFloat(q.z)
      ..writeFloat(q.w);
  }

  /// The reader of [writeQuaterniond].
  static Quaterniond readQuaterniond(PacketReader buf) =>
      Quaterniond(buf.readFloat(), buf.readFloat(), buf.readFloat(), buf.readFloat());

  /// `STREAM_VECTOR3DC`: `ByteBufCodecs.DOUBLE.apply(ByteBufCodecs.list(3))`, so
  /// a VarInt 3 then the three doubles.
  static void writeVector3dc(PacketWriter buf, Vector3d v) {
    buf
      ..writeVarInt(3)
      ..writeDouble(v.x)
      ..writeDouble(v.y)
      ..writeDouble(v.z);
  }

  /// The reader of [writeVector3dc].
  static Vector3d readVector3dc(PacketReader buf) {
    final size = buf.readVarInt();
    if (size != 3) throw PacketException('Vector3d list has $size element(s), expected 3');
    return Vector3d(buf.readDouble(), buf.readDouble(), buf.readDouble());
  }

  /// `STREAM_POINT_FORCE`: `STREAM_VECTOR3DC.apply(ByteBufCodecs.list(2))`, so a
  /// VarInt 2, the point and the force.
  static void writePointForce(PacketWriter buf, PointForce p) {
    buf.writeVarInt(2);
    writeVector3dc(buf, p.point);
    writeVector3dc(buf, p.force);
  }

  /// The reader of [writePointForce].
  static PointForce readPointForce(PacketReader buf) {
    final size = buf.readVarInt();
    if (size != 2) throw PacketException('PointForce list has $size element(s), expected 2');
    return PointForce(readVector3dc(buf), readVector3dc(buf));
  }

  /// `BOUNDING_BOX_3D_STREAM_CODEC`: VarInt 6, then the six doubles.
  static void writeBoundingBox3d(PacketWriter buf, BoundingBox3d bb) {
    buf
      ..writeVarInt(6)
      ..writeDouble(bb.minX)
      ..writeDouble(bb.minY)
      ..writeDouble(bb.minZ)
      ..writeDouble(bb.maxX)
      ..writeDouble(bb.maxY)
      ..writeDouble(bb.maxZ);
  }

  /// The reader of [writeBoundingBox3d].
  static BoundingBox3d readBoundingBox3d(PacketReader buf) {
    final size = buf.readVarInt();
    if (size != 6) throw PacketException('BoundingBox3d list has $size element(s), expected 6');
    return BoundingBox3d.unchecked(
      buf.readDouble(),
      buf.readDouble(),
      buf.readDouble(),
      buf.readDouble(),
      buf.readDouble(),
      buf.readDouble(),
    );
  }

  /// `HoneyGlueSyncBoundsPacket.writeAABB`: 6 doubles, min corner first.
  static void writeAabb(PacketWriter buf, Aabb bb) {
    buf
      ..writeDouble(bb.minX)
      ..writeDouble(bb.minY)
      ..writeDouble(bb.minZ)
      ..writeDouble(bb.maxX)
      ..writeDouble(bb.maxY)
      ..writeDouble(bb.maxZ);
  }

  /// The reader of [writeAabb].
  static Aabb readAabb(PacketReader buf) => Aabb(
    buf.readDouble(),
    buf.readDouble(),
    buf.readDouble(),
    buf.readDouble(),
    buf.readDouble(),
    buf.readDouble(),
  );

  /// `ResourceKey.streamCodec(Registries.DIMENSION)` / `Identifier.STREAM_CODEC`:
  /// a resource location as a UTF-8 string.
  static void writeResourceLocation(PacketWriter buf, String id) => buf.writeString(id);

  /// The reader of [writeResourceLocation].
  static String readResourceLocation(PacketReader buf) => buf.readString();

  /// `ByteBufCodecs.optional(ByteBufCodecs.STRING_UTF8)`.
  static void writeOptionalString(PacketWriter buf, String? value) => buf.writeOptional(value, (w, v) => w.writeString(v));

  /// The reader of [writeOptionalString].
  static String? readOptionalString(PacketReader buf) => buf.readOptional((r) => r.readString());
}
