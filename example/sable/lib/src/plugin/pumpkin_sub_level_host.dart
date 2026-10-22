// The Pumpkin implementation of `SubLevelHost`: what the sub-level model needs
// that is not chunk or file access.
//
// Java's `SableServerPlatform` answers these from the `ServerLevel`, the
// `SavedDataStorage` and the physics pipeline. The port answers them from:
//
//  * the per-level `ServerSubLevelContainer` (sub-level lookup, poses, mass,
//    velocity) — a sub-level that is not loaded has no answer, so those return
//    the identity/zero value the model documents;
//  * `Server.getWorldPlayers` (the online players of the level);
//  * the level's saved-data files (`SavedDataFiles`): the plugin API has no
//    `SavedDataStorage`, so the three Java saved data objects are written as
//    gzip NBT files next to the level's storage instead of through
//    `computeIfAbsent`.
//
// Host: this file uses `pumpkin_api`.
//
// Java: `dev.ryanhcode.sable.platform.SableServerPlatform` and
// `net.minecraft.world.level.saveddata.SavedDataStorage`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../sublevel/api/sub_level_helper.dart';
import '../sublevel/host/sub_level_host.dart';
import '../sublevel/math/pose.dart';
import '../sublevel/math/vector.dart';
import '../sublevel/model/server_sub_level.dart';
import '../sublevel/model/server_sub_level_container.dart';
import '../sublevel/storage/sub_level_saved_data_files.dart';
import 'pumpkin_level.dart';

/// The host of one level.
///
/// It is owned by the plugin (one per opened level) and installed on the level's
/// container (`ServerSubLevelContainer.hostOrNull`), which is what makes the
/// occupancy/tickets saved data, the tracking points and the physics/tracking
/// systems reachable from the model.
final class PumpkinSubLevelHost implements SubLevelHost {
  PumpkinSubLevelHost({
    required Context context,
    required this.level,
    required this.chunks,
    required this.container,
    required this.savedData,
    this.logger,
  }) : _server = context.getServer().keep();

  /// The level this host serves.
  final PumpkinSableLevel level;

  @override
  final PumpkinPlotChunkHost chunks;

  /// The container of the level, for sub-level lookups.
  final ServerSubLevelContainer container;

  /// The saved-data files of the level.
  final SavedDataFiles savedData;

  /// Where a failure is logged, when the plugin has a logger.
  final void Function(String message, Object error)? logger;

  // The kept server handle: `getWorldPlayers` lives on `Server`, and the model
  // asks for the players of a level on every tracking tick.
  final Server _server;

  /// The tags waiting to be written, by saved-data name.
  final Map<String, Map<String, Object?>> _pending = {};

  /// The saved-data names that changed since the last flush.
  final Set<String> _dirty = {};

  /// Rebuilds the tag of a dirty saved-data name the container owns rather than
  /// a caller: the occupancy bitmap and the force-load ticket list are
  /// regenerated from the container at every save, like the Java `SavedData`
  /// codecs do.
  Map<String, Object?>? Function(String name)? savedDataProvider;

  // ------------------------------------------------------------------ players

  @override
  Iterable<SablePlayer> get players {
    final result = <SablePlayer>[];
    final List<Player> handles;
    try {
      // `Server.getAllPlayers` rather than the `player-interface` import: that
      // one is hidden from the public barrel, and the level filter is a
      // comparison of dimension keys either way.
      handles = _server.getAllPlayers();
    } on Object catch (error) {
      logger?.call('Sable: the player list of ${level.dimensionId} is unavailable', error);
      return result;
    }
    for (final player in handles) {
      try {
        final world = player.getWorld();
        final dimension = world.getDimension();
        world.dispose();
        if (dimension != level.dimensionId) continue;
        final id = player.getId().asString;
        final (x, y, z) = player.getPosition();
        result.add(_PumpkinPlayer(id, (x, y, z), dimension));
      } on Object catch (error) {
        logger?.call('Sable: cannot read a player of ${level.dimensionId}', error);
      } finally {
        player.dispose();
      }
    }
    return result;
  }

  @override
  SablePlayer? playerById(String uuid) {
    for (final player in players) {
      if (player.uuid == uuid) return player;
    }
    return null;
  }

  // ---------------------------------------------------------------- sub-levels

  @override
  SubLevelLookup get subLevels => _lookup ??= _ContainerSubLevelLookup(level, container);
  SubLevelLookup? _lookup;

  /// The loaded sub-level with [subLevelId], or `null`.
  ServerSubLevel? _loaded(String subLevelId) {
    final subLevel = container.getSubLevelById(subLevelId);
    return subLevel is ServerSubLevel ? subLevel : null;
  }

  @override
  Pose3dc poseForSaving(String subLevelId) {
    // Java asks the physics body for the pose it will save
    // (`SableServerPlatform.getPoseForSaving`); the port's authoritative pose is
    // the sub-level's logical pose, which `SubLevelSerializer.serialize`
    // recentres on the centre of mass itself.
    final subLevel = _loaded(subLevelId);
    if (subLevel == null) {
      logger?.call(
        'Sable: poseForSaving($subLevelId) has no loaded sub-level; using the identity pose',
        StateError('sub-level is not loaded'),
      );
      return Pose3d();
    }
    return Pose3d.copy(subLevel.logicalPose);
  }

  @override
  (double, double, double) centerOfMass(String subLevelId) {
    final subLevel = _loaded(subLevelId);
    if (subLevel == null) return (0.0, 0.0, 0.0);
    final tracker = subLevel.getSelfMassTracker();
    if (tracker.isInvalid()) return (0.0, 0.0, 0.0);
    final center = tracker.getCenterOfMass();
    return (center.x, center.y, center.z);
  }

  @override
  (double, double, double, double, double, double)? velocity(String subLevelId) {
    final subLevel = _loaded(subLevelId);
    final body = subLevel?.physicsBody;
    if (body == null) return null;
    final linear = body.getLinearVelocity();
    final angular = body.getAngularVelocity();
    return (linear.x, linear.y, linear.z, angular.x, angular.y, angular.z);
  }

  // --------------------------------------------------------------- saved data

  @override
  Map<String, Object?>? readSavedData(String name) {
    try {
      return savedData.read(name);
    } on Object catch (error) {
      logger?.call('Sable: reading the saved data "$name" failed', error);
      return null;
    }
  }

  @override
  void writeSavedData(String name, Map<String, Object?> data) {
    _pending[name] = data;
    _dirty.add(name);
  }

  @override
  void markSavedDataDirty(String name) => _dirty.add(name);

  /// Whether [name] has unsaved changes.
  bool isSavedDataDirty(String name) => _dirty.contains(name);

  /// The names with unsaved changes.
  Set<String> get dirtySavedDataNames => Set.unmodifiable(_dirty);

  /// Writes every dirty saved-data file.
  ///
  /// Java's `SavedDataStorage` does this at the end of the tick and on a level
  /// save; the plugin calls it from the same two places. A name the container
  /// owns (the occupancy, the tickets) is rebuilt by [savedDataProvider].
  void flushSavedData() {
    for (final name in _dirty.toList()) {
      final tag = _pending.remove(name) ?? savedDataProvider?.call(name);
      _dirty.remove(name);
      if (tag == null) continue;
      try {
        savedData.write(name, tag);
      } on Object catch (error) {
        // Keep it dirty: the next flush must try again, or the change is lost.
        _dirty.add(name);
        _pending[name] = tag;
        logger?.call('Sable: writing the saved data "$name" failed', error);
      }
    }
  }

  /// Releases the kept server handle.
  void dispose() => _server.dispose();
}

/// A player of one level, snapshotted (the `Player` resource is released right
/// after it is read).
final class _PumpkinPlayer implements SablePlayer {
  _PumpkinPlayer(this.uuid, this.position, this.dimensionId);

  @override
  final String uuid;

  @override
  final (double, double, double) position;

  @override
  final String dimensionId;
}

/// The `Sable.HELPER` lookups, over the level's container.
final class _ContainerSubLevelLookup implements SubLevelLookup {
  _ContainerSubLevelLookup(this.level, this.container);

  final PumpkinSableLevel level;
  final ServerSubLevelContainer container;

  @override
  Object? containing(String dimensionId, (double, double, double) position) {
    if (dimensionId != level.dimensionId) return null;
    return SubLevelHelper.getContainingPos(
      level,
      Vector3d(position.$1, position.$2, position.$3),
    );
  }

  @override
  Object? trackingSubLevel(SablePlayer player) {
    if (player.dimensionId != level.dimensionId) return null;
    // `Sable.HELPER.getTrackingSubLevel`: the sub-level the player is inside.
    // The plot grid is what answers, and it is container state, so this works
    // whether or not the player's chunk is loaded.
    final (x, y, z) = player.position;
    return SubLevelHelper.getContainingPos(level, Vector3d(x, y, z));
  }
}