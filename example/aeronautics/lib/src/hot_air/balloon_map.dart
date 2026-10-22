// The balloons of one world, and the save data of the ones that unloaded.
//
// Java: `content/blocks/hot_air/balloon/map/{BalloonMap,SavedBalloon,BalloonLevelSavedData}`.
//
// The map owns the live balloons, merges the ones that grew into each other,
// drops the ones that lost all their gas, and keeps the gas of a balloon whose
// last heater unloaded so it can be picked up again.
//
// Pure: no host imports.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:sable/sable.dart'
    show BoundingBox3i, DimensionPhysicsData, ServerSubLevel, SubLevelHelper, Vector3d;

import 'balloon.dart';
import 'balloon_builder.dart';
import 'balloon_world.dart';
import 'lifting_gas.dart';
import 'lifting_gas_provider.dart';
import 'server_balloon.dart';

/// `SavedBalloon`: the bounds, controller and gas of an unloaded balloon.
final class SavedBalloon {
  final BoundingBox3i bounds;
  final Pos controllerPos;
  final List<LiftingGasHolder> gasData;

  SavedBalloon(this.bounds, this.controllerPos, this.gasData);

  Map<String, Object?> toMap() => {
    'bounds': [bounds.minX, bounds.minY, bounds.minZ, bounds.maxX, bounds.maxY, bounds.maxZ],
    'pos': [controllerPos.$1, controllerPos.$2, controllerPos.$3],
    'gasData': [for (final holder in gasData) holder.toMap()],
  };

  static SavedBalloon fromMap(Map<String, Object?> map) {
    final bounds = (map['bounds'] as List?)?.cast<num>() ?? const [0, 0, 0, 0, 0, 0];
    final pos = (map['pos'] as List?)?.cast<num>() ?? const [0, 0, 0];
    final gas = (map['gasData'] as List?) ?? const [];
    return SavedBalloon(
      BoundingBox3i.values(
        bounds[0].toInt(),
        bounds[1].toInt(),
        bounds[2].toInt(),
        bounds[3].toInt(),
        bounds[4].toInt(),
        bounds[5].toInt(),
      ),
      (pos[0].toInt(), pos[1].toInt(), pos[2].toInt()),
      [for (final entry in gas) LiftingGasHolder.fromMap((entry as Map).cast<String, Object?>())],
    );
  }
}

/// `BalloonMap`.
final class BalloonMap {
  /// The live maps, by world id (`BalloonMap.MAP`).
  static final Map<String, BalloonMap> maps = {};

  /// The map of [world], created on first use.
  static BalloonMap of(BalloonWorld world) =>
      maps.putIfAbsent(world.id, () => BalloonMap(world));

  /// Forgets every map (plugin unload, tests).
  static void clear() => maps.clear();

  final BalloonWorld world;

  /// The live balloons.
  final Set<Balloon> balloons = {};

  /// The balloons whose last heater unloaded.
  final List<SavedBalloon> unloadedBalloons = [];

  /// Called when the save data must be written.
  void Function()? onDirty;

  BalloonMap(this.world);

  /// Advances every balloon of [world] by one tick.
  static void tick(BalloonWorld world) => of(world).tickBalloons();

  /// Applies the lift of every balloon of [world] for one physics tick.
  static void physicsTick(BalloonWorld world, double timeStep) {
    for (final balloon in of(world).balloons) {
      if (balloon is ServerBalloon) balloon.applyForces(timeStep);
    }
  }

  /// The air pressure at a world position.
  static double airPressureAt(BalloonWorld world, double x, double y, double z) =>
      DimensionPhysicsData.getAirPressure(world.level, Vector3d(x, y, z));

  /// The air pressure at a world position given as a vector.
  static double airPressureAtVector(BalloonWorld world, Vector3d pos) =>
      DimensionPhysicsData.getAirPressure(world.level, pos);

  /// `saveBalloon`.
  static SavedBalloon saveBalloon(ServerBalloon balloon) => SavedBalloon(
    BoundingBox3i.copy(balloon.bounds),
    balloon.controllerPos,
    balloon.liftingGasHolders,
  );

  /// `attemptBuildBalloon`: the balloon that would be built from [startPos].
  ///
  /// Only the server owns balloons; a client returns `null` (the Java client
  /// balloon is a display-only copy of the server one).
  static Balloon? attemptBuildBalloon(BlockEntityLiftingGasProvider heater, Pos startPos) {
    final world = heater.balloonWorld;
    final graph = BalloonBuilder.buildBalloon(world, startPos);
    if (graph == null) return null;
    if (!world.isServerSide) return null;

    return ServerBalloon(world, startPos, graph, [heater]);
  }

  void addBalloon(Balloon balloon) => balloons.add(balloon);

  void markDirty() => onDirty?.call();

  /// Tells the nearby balloons that a block changed.
  void updateNearbyBalloons(Pos pos, BState oldState, BState newState) {
    final oldAirtight = world.isAirtight(oldState);
    final newAirtight = world.isAirtight(newState);

    if (oldAirtight != newAirtight) {
      for (final balloon in _balloonsNear(pos)) {
        if (newAirtight) {
          balloon.onAirtightBlockAdded(pos);
        } else {
          balloon.onAirtightBlockRemoved(pos);
        }
      }
      return;
    }

    final oldSolid = BalloonBuilder.isSolid(oldState);
    final newSolid = BalloonBuilder.isSolid(newState);

    if (oldSolid != newSolid) {
      for (final balloon in _balloonsNear(pos)) {
        if (newSolid) {
          balloon.onSolidBlockAdded(pos);
        } else {
          balloon.onSolidBlockRemoved(pos);
        }
      }
    }
  }

  /// One tick of every balloon, then the removals and merges.
  void tickBalloons() {
    for (final balloon in balloons) {
      balloon.tick();
    }
    _removeBalloons();
    _mergeBalloons();
    markDirty();
  }

  /// Merges balloons that grew into each other: the one whose volume contains
  /// the other's controller absorbs it.
  void _mergeBalloons() {
    final removed = <Balloon>[];

    for (final balloon in balloons) {
      if (removed.contains(balloon)) continue;

      for (final other in balloons) {
        if (identical(balloon, other) || removed.contains(other)) continue;

        if (balloon.bounds.intersects(other.bounds) &&
            balloon.layerGraph.getLayerAt(other.controllerPos) != null) {
          balloon.onRemoved();
          other.merge(balloon);
          removed.add(balloon);
          break;
        }
      }
    }

    balloons.removeAll(removed);
  }

  void _removeBalloons() {
    balloons.removeWhere((balloon) {
      if (balloon.isValid) return false;
      balloon.onRemoved();
      return true;
    });
  }

  /// Removes [balloon] and detaches its heaters.
  void removeBalloon(Balloon balloon) => balloon.onRemoved();

  /// The balloon whose volume contains [pos], or `null`.
  Balloon? balloonAt(Pos pos) {
    for (final balloon in balloons) {
      final bounds = balloon.bounds;
      if (bounds.containsValues(pos.$1, pos.$2, pos.$3) && balloon.layerGraph.hasBlockAt(pos)) {
        return balloon;
      }
    }
    return null;
  }

  List<Balloon> _balloonsNear(Pos pos) {
    const padding = 24;
    final near = <Balloon>[];
    for (final balloon in balloons) {
      final bounds = balloon.bounds;
      if (pos.$1 > bounds.minX - padding &&
          pos.$2 > bounds.minY - padding &&
          pos.$3 > bounds.minZ - padding &&
          pos.$1 < bounds.maxX + padding &&
          pos.$2 < bounds.maxY + padding &&
          pos.$3 < bounds.maxZ + padding) {
        near.add(balloon);
      }
    }
    return near;
  }

  /// The live balloons.
  Iterable<Balloon> get allBalloons => balloons;

  /// Whether the map has no live balloon.
  bool get isEmpty => balloons.isEmpty;

  /// Moves [balloon] to the unloaded list, keeping its gas.
  void unloadBalloon(ServerBalloon balloon) {
    final saved = saveBalloon(balloon);
    balloons.remove(balloon);
    unloadedBalloons.add(saved);
    markDirty();
  }

  /// The gas of the balloons that unloaded.
  Iterable<SavedBalloon> get unloaded => unloadedBalloons;

  /// `BalloonLevelSavedData.save`: the unloaded balloons first, then every live one.
  ///
  /// Saving the live balloons is what keeps their gas across a restart: they go back into
  /// [unloadedBalloons] when the world loads, and the heater that rebuilds the balloon takes the
  /// gas from there ([loadUnloaded]).
  List<SavedBalloon> savedBalloons() => [
    ...unloadedBalloons,
    for (final balloon in balloons)
      if (balloon is ServerBalloon) saveBalloon(balloon),
  ];

  /// Restores the unloaded balloons from save data.
  void loadUnloaded(List<SavedBalloon> saved) => unloadedBalloons.addAll(saved);

  /// Removes the balloons whose controller was inside a removed sub-level plot.
  void onSubLevelRemoved(SubLevelPlotView plot) {
    balloons.removeWhere((balloon) {
      if (balloon.isAssembling) return false;
      if (!plot.contains(balloon.controllerPos)) return false;
      balloon.onRemoved();
      return true;
    });
  }
}

/// What [BalloonMap.onSubLevelRemoved] needs from a plot.
abstract interface class SubLevelPlotView {
  /// `LevelPlot.contains(x, z)`: whether the plot's chunk grid covers the column.
  bool contains(Pos pos);
}

/// The server sub-level of a plot, when the caller has one.
ServerSubLevel? serverSubLevelAt(BalloonWorld world, Pos pos) {
  final subLevel = SubLevelHelper.getContaining(world.level, pos);
  return subLevel is ServerSubLevel ? subLevel : null;
}
