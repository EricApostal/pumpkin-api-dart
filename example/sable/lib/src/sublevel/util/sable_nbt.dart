// `dev.ryanhcode.sable.util.SableNBTUtils`, over the plain map NBT model the
// sub-level storage uses (`Map<String, Object?>`).
//
// The Java version writes `Pose3d`, `BoundingBox3d`, `Vector3d` and `Quaterniond`
// as nested compounds; the key names and layout are kept exactly, so data
// written by the Java mod reads back.
//
// Pure: no host imports.
import '../../math/bounding_box.dart';
import '../../math/pose.dart';
import '../../math/vector.dart';
import 'uuid.dart';

/// The NBT helpers of Sable.
abstract final class SableNbt {
  /// `SableNBTUtils.writeUUID`: four ints.
  static List<int> writeUuid(String uuid) => uuidToInts(uuid);

  /// `SableNBTUtils.readUUID`.
  static String readUuid(Object? tag) {
    if (tag is! List) throw const FormatException('UUID tag is not an int array');
    return uuidFromInts([for (final i in tag) (i as num).toInt()]);
  }

  /// `putUUID(tag, key, uuid)`.
  static void putUuid(Map<String, Object?> tag, String key, String uuid) =>
      tag[key] = writeUuid(uuid);

  /// `getUUID(tag, key)`.
  static String? getUuid(Map<String, Object?> tag, String key) {
    final value = tag[key];
    return value == null ? null : readUuid(value);
  }

  /// `writePose3d`: `position`, `orientation`, `rotation_point`.
  ///
  /// The Java writer omits `scale`; the reader assumes `(1, 1, 1)`.
  static Map<String, Object?> writePose3d(Pose3dc pose) => {
    'position': writeVector3d(pose.position()),
    'orientation': writeQuaternion(pose.orientation()),
    'rotation_point': writeVector3d(pose.rotationPoint()),
  };

  /// `readPose3d`.
  static Pose3d readPose3d(Object? tag) {
    final map = _compound(tag);
    return Pose3d.full(
      readVector3d(map['position']),
      readQuaternion(map['orientation']),
      readVector3d(map['rotation_point']),
      Vector3d(1.0, 1.0, 1.0),
    );
  }

  /// `writeQuaternion`: `x`, `y`, `z`, `w` doubles.
  static Map<String, Object?> writeQuaternion(Quaterniond quat) => {
    'x': quat.x,
    'y': quat.y,
    'z': quat.z,
    'w': quat.w,
  };

  /// `readQuaternion`.
  static Quaterniond readQuaternion(Object? tag) {
    final map = _compound(tag);
    return Quaterniond(
      _double(map['x']),
      _double(map['y']),
      _double(map['z']),
      _double(map['w']),
    );
  }

  /// `writeVector3d`: `x`, `y`, `z` doubles.
  static Map<String, Object?> writeVector3d(Vector3d vector) => {
    'x': vector.x,
    'y': vector.y,
    'z': vector.z,
  };

  /// `readVector3d`.
  static Vector3d readVector3d(Object? tag) {
    final map = _compound(tag);
    return Vector3d(_double(map['x']), _double(map['y']), _double(map['z']));
  }

  /// `writeBoundingBox`: the six double corners.
  static Map<String, Object?> writeBoundingBox(BoundingBox3dc bounds) => {
    'minX': bounds.minX,
    'minY': bounds.minY,
    'minZ': bounds.minZ,
    'maxX': bounds.maxX,
    'maxY': bounds.maxY,
    'maxZ': bounds.maxZ,
  };

  /// `readBoundingBox`.
  static BoundingBox3d readBoundingBox(Object? tag) {
    final map = _compound(tag);
    return BoundingBox3d.full(
      _double(map['minX']),
      _double(map['minY']),
      _double(map['minZ']),
      _double(map['maxX']),
      _double(map['maxY']),
      _double(map['maxZ']),
    );
  }

  static Map<String, Object?> _compound(Object? tag) =>
      tag is Map ? Map<String, Object?>.from(tag) : <String, Object?>{};

  static double _double(Object? value) => value is num ? value.toDouble() : 0.0;
}
