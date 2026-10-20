// `dev.ryanhcode.sable.api.block.BlockEntitySubLevelActor`: a block entity that
// is ticked with the sub-level it is mounted on.
//
// Pure: no host imports.
import '../../model/server_sub_level.dart';
import '../../model/sub_level.dart';
import '../physics.dart';

/// A block entity taking part in sub-level physics.
abstract interface class BlockEntitySubLevelActor {
  /// Called once per server game tick while on [subLevel].
  void sable$tick(ServerSubLevel subLevel) {}

  /// Called once per **physics** tick; there may be several per game tick.
  void sable$physicsTick(ServerSubLevel subLevel, RigidBodyHandle handle, double timeStep) {}

  /// The sub-levels that must load and unload together with this one.
  ///
  /// By default the connection dependencies are used. May be called after
  /// chunks unloaded, so it must not touch the level.
  Iterable<SubLevel>? sable$getLoadingDependencies() => sable$getConnectionDependencies();

  /// The sub-levels that systems should treat as one with this one.
  Iterable<SubLevel>? sable$getConnectionDependencies() => null;
}
