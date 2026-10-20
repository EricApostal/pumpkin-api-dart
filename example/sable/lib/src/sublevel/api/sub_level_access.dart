// `dev.ryanhcode.sable.companion.SubLevelAccess`: the read-only view of a
// sub-level that other mods (and the companion library) code against.
//
// Pure: no host imports.
import '../math/bounding_box.dart';
import '../math/pose.dart';

/// Access to basic read-only sub-level info.
abstract interface class SubLevelAccess {
  /// The current pose of this sub-level.
  Pose3dc get logicalPose;

  /// The pose of this sub-level from the previous tick.
  Pose3dc get lastPose;

  /// The global bounding box of this sub-level.
  BoundingBox3dc get boundingBox;

  /// The UUID of this sub-level: networked and consistent across saving/loading.
  String get uniqueId;

  /// The display name of this sub-level, if present.
  String? get name;
}
