// `dev.ryanhcode.sable.sublevel.tracking_points.SubLevelTrackingPointObserver`:
// projects a sub-level's tracking points into world space when the sub-level is
// deleted.
//
// A tracking point is where a player was when they left. While it sits in a
// sub-level it is stored in the sub-level's local space; if that sub-level is
// deleted (`SubLevelRemovalReason.REMOVED`, not an unload), the point would be
// meaningless, so it is transformed by the sub-level's last pose and becomes a
// world point (`SubLevelTrackingPointObserver.java:26-44`).
//
// Pure: no host imports.
import '../model/server_sub_level.dart';
import '../model/sub_level.dart';
import '../storage/sub_level_removal_reason.dart';
import '../api/sub_level_observer.dart';
import '../math/vector.dart';
import 'tracking_point.dart';

/// Projects tracking points out of sub-levels when they are removed.
final class SubLevelTrackingPointObserver with SubLevelObserver {
  /// The points of one level.
  final TrackingPointStore store;

  SubLevelTrackingPointObserver(this.store);

  @override
  void onSubLevelRemoved(SubLevel subLevel, SubLevelRemovalReason reason) {
    if (reason != SubLevelRemovalReason.removed) return;
    if (subLevel is! ServerSubLevel) return;

    final pointer = subLevel.lastSerializationPointer;
    for (final entry in store.getAllTrackingPoints().toList(growable: false)) {
      final point = entry.value;
      // Java only projects points that were saved together with this
      // sub-level; a point whose pointer is null was never saved and keeps its
      // global placeholder instead.
      if (!point.inSubLevel ||
          point.lastSavedSubLevelPointer == null ||
          point.lastSavedSubLevelPointer != pointer) {
        continue;
      }

      final worldPoint = subLevel.logicalPose.transformPosition(Vector3d.copy(point.point));
      store.setTrackingPoint(
        entry.key,
        TrackingPoint(false, null, null, worldPoint, null),
      );
    }
  }
}
