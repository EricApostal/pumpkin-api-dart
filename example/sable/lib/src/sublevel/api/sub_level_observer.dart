// `dev.ryanhcode.sable.api.sublevel.SubLevelObserver`: observes additions,
// removals, and ticking of sub-levels.
//
// Pure: no host imports.
import '../model/sub_level.dart';
import '../model/sub_level_container.dart';
import '../storage/sub_level_removal_reason.dart';

/// Observes additions, removals, and ticking of sub-levels.
abstract interface class SubLevelObserver {
  /// Called after a sub-level is added to a [SubLevelContainer].
  void onSubLevelAdded(SubLevel subLevel) {}

  /// Called before a sub-level is removed from a [SubLevelContainer].
  void onSubLevelRemoved(SubLevel subLevel, SubLevelRemovalReason reason) {}

  /// Called every tick for each [SubLevelContainer].
  void tick(SubLevelContainer subLevels) {}
}
