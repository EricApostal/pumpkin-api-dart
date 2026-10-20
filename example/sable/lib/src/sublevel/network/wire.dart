// `dev.ryanhcode.sable.util.SableBufferUtils`: the primitive writers and
// readers Sable's payloads share.
//
// The wire format is `FriendlyByteBuf`, so the primitives come from
// `pumpkin_api_core`'s [PacketReader] / [PacketWriter]. What is added here are
// the Sable-specific composites, in exactly the order the Java class writes
// them:
//
// | value             | bytes                                              |
// |-------------------|----------------------------------------------------|
// | `Vector3d`        | 3 doubles                                          |
// | `Vector3f`        | 3 floats                                           |
// | `Quaterniond`     | 4 floats (x, y, z, w)                              |
// | `Pose3d`          | position (3 doubles), orientation (4 floats), rotation point (3 doubles) |
// | `BoundingBox3i`   | 6 ints: minX, minY, minZ, maxX, maxY, maxZ         |
//
// Pure: no host imports.
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../math/bounding_box.dart';
import '../math/pose.dart';
import '../math/vector.dart';

/// The `SableBufferUtils` codec primitives.
abstract final class SableBufferUtils {
  // ---------------------------------------------------------------- vectors

  /// `write(buf, Vector3dc)`.
  static void writeVector3d(PacketWriter buf, Vector3d value) {
    buf.writeDouble(value.x);
    buf.writeDouble(value.y);
    buf.writeDouble(value.z);
  }

  /// `write(buf, Vector3fc)`. [value] holds doubles; the wire keeps floats, so
  /// a round trip through a packet is lossy in the same way the Java code is.
  static void writeVector3f(PacketWriter buf, Vector3d value) {
    buf.writeFloat(value.x);
    buf.writeFloat(value.y);
    buf.writeFloat(value.z);
  }

  /// `read(buf, new Vector3d())`.
  static Vector3d readVector3d(PacketReader buf, [Vector3d? dest]) {
    final out = dest ?? Vector3d();
    return out.set(buf.readDouble(), buf.readDouble(), buf.readDouble());
  }

  /// `read(buf, new Vector3f())`.
  static Vector3d readVector3f(PacketReader buf, [Vector3d? dest]) {
    final out = dest ?? Vector3d();
    return out.set(buf.readFloat(), buf.readFloat(), buf.readFloat());
  }

  // ------------------------------------------------------------ orientations

  /// `write(buf, Quaterniondc)`.
  static void writeQuaterniond(PacketWriter buf, Quaterniond value) {
    buf.writeFloat(value.x);
    buf.writeFloat(value.y);
    buf.writeFloat(value.z);
    buf.writeFloat(value.w);
  }

  /// `read(buf, new Quaterniond())`.
  static Quaterniond readQuaterniond(PacketReader buf, [Quaterniond? dest]) {
    final out = dest ?? Quaterniond();
    return out.set(buf.readFloat(), buf.readFloat(), buf.readFloat(), buf.readFloat());
  }

  // ------------------------------------------------------------------- poses

  /// `write(buf, Pose3dc)`: position, orientation, rotation point. The scale is
  /// not on the wire, exactly as in Java.
  static void writePose(PacketWriter buf, Pose3dc value) {
    writeVector3d(buf, value.position());
    writeQuaterniond(buf, value.orientation());
    writeVector3d(buf, value.rotationPoint());
  }

  /// `read(buf, new Pose3d())`.
  static Pose3d readPose(PacketReader buf, [Pose3d? dest]) {
    final out = dest ?? Pose3d();
    readVector3d(buf, out.position());
    readQuaterniond(buf, out.orientation());
    readVector3d(buf, out.rotationPoint());
    return out;
  }

  // ------------------------------------------------------------------ bounds

  /// `write(buf, BoundingBox3ic)`.
  static void writeBounds(PacketWriter buf, BoundingBox3ic value) {
    buf.writeInt(value.minX);
    buf.writeInt(value.minY);
    buf.writeInt(value.minZ);
    buf.writeInt(value.maxX);
    buf.writeInt(value.maxY);
    buf.writeInt(value.maxZ);
  }

  /// `read(buf, new BoundingBox3i())`.
  static BoundingBox3i readBounds(PacketReader buf, [BoundingBox3i? dest]) {
    final out = dest ?? BoundingBox3i();
    return out.setValues(
      buf.readInt(),
      buf.readInt(),
      buf.readInt(),
      buf.readInt(),
      buf.readInt(),
      buf.readInt(),
    );
  }

  // --------------------------------------------------------------- utilities

  /// `ChunkPos.pack(x, z)`: x in the low 32 bits, z in the high 32.
  static int packChunk(int x, int z) => (x & 0xFFFFFFFF) | (z & 0xFFFFFFFF) << 32;

  /// `ChunkPos.getX(packed)`.
  static int unpackChunkX(int packed) => packed & 0xFFFFFFFF;

  /// `ChunkPos.getZ(packed)`.
  static int unpackChunkZ(int packed) => (packed >>> 32) & 0xFFFFFFFF;
}
