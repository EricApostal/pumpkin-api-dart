// `dev.ryanhcode.sable.companion.math.JOMLConversion`: conversions between the
// immutable record vectors the rest of the Create port uses (`Vec3`, `Pos`) and
// the mutable JOML-shaped types of `vector.dart`.
//
// The Java constants `ZERO`, `ONE`, `HALF` and `QUAT_IDENTITY` are read-only
// views there; here they are getters that hand out a fresh value, so a caller
// cannot corrupt a shared constant.
//
// Pure: no host imports.
import 'package:pumpkin_api/src/geometry.dart' show Vec3;

import '../../common/bounds.dart' show Aabb;
import '../../common/pos.dart' show Pos;
import 'vector.dart';

/// Conversions between Mojang and JOML math types.
abstract final class JOMLConversion {
  /// A zero vector.
  static Vector3d get zero => Vector3d();

  /// A `(1, 1, 1)` vector.
  static Vector3d get one => Vector3d(1.0, 1.0, 1.0);

  /// A `(0.5, 0.5, 0.5)` vector.
  static Vector3d get half => Vector3d(0.5, 0.5, 0.5);

  /// The identity quaternion.
  static Quaterniond get quatIdentity => Quaterniond();

  /// `toJOML(Position)`.
  static Vector3d toJoml(Vec3 vec3) => Vector3d(vec3.$1, vec3.$2, vec3.$3);

  /// `toJOML(Position, Vector3d dest)`.
  static Vector3d toJomlInto(Vec3 vec3, Vector3d dest) => dest.set(vec3.$1, vec3.$2, vec3.$3);

  /// `toJOML(Vec3i)`.
  static Vector3i toJomlVec3i(Pos vec3) => Vector3i(vec3.$1, vec3.$2, vec3.$3);

  /// `toJOML(Vec3i, Vector3i dest)`.
  static Vector3i toJomlVec3iInto(Pos vec3, Vector3i dest) => dest.set(vec3.$1, vec3.$2, vec3.$3);

  /// `atLowerCornerOf(Vec3i)`.
  static Vector3d atLowerCornerOf(Pos pos) =>
      Vector3d(pos.$1.toDouble(), pos.$2.toDouble(), pos.$3.toDouble());

  /// `atLowerCornerWithOffset(Vec3i, double, double, double)`.
  static Vector3d atLowerCornerWithOffset(Pos pos, double offsetX, double offsetY, double offsetZ) =>
      Vector3d(pos.$1 + offsetX, pos.$2 + offsetY, pos.$3 + offsetZ);

  /// `atCenterOf(Vec3i)`.
  static Vector3d atCenterOf(Pos pos) =>
      Vector3d(pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5);

  /// `atBottomCenterOf(Vec3i)`.
  static Vector3d atBottomCenterOf(Pos pos) =>
      Vector3d(pos.$1 + 0.5, pos.$2.toDouble(), pos.$3 + 0.5);

  /// `upFromBottomCenterOf(Vec3i, double)`.
  static Vector3d upFromBottomCenterOf(Pos pos, double verticalOffset) =>
      Vector3d(pos.$1 + 0.5, pos.$2 + verticalOffset, pos.$3 + 0.5);

  /// `toMojang(Vector3dc)`: a record vector.
  static Vec3 toMojang(Vector3d vec) => (vec.x, vec.y, vec.z);

  /// `toMojang(Vector3ic)`: a record block position.
  static Pos toMojangVec3i(Vector3i vec) => (vec.x, vec.y, vec.z);

  /// `getAABBCenter(AABB)`.
  static Vector3d getAabbCenter(Aabb aabb) => Vector3d(
    (aabb.minX + aabb.maxX) / 2.0,
    (aabb.minY + aabb.maxY) / 2.0,
    (aabb.minZ + aabb.maxZ) / 2.0,
  );

  /// `getAABBCenter(AABB, Vector3d dest)`.
  static Vector3d getAabbCenterInto(Aabb aabb, Vector3d dest) => dest.set(
    (aabb.minX + aabb.maxX) / 2.0,
    (aabb.minY + aabb.maxY) / 2.0,
    (aabb.minZ + aabb.maxZ) / 2.0,
  );
}
