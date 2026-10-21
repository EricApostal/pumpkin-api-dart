// The runtime wiring of Aeronautics: which block entities take part in
// sub-level physics, and where the balloon forces are applied.
//
// Java hooks `BalloonMap.physicsTick` into Sable's pre-physics event and lets
// the plot find its actors. The port cannot rely on the plot's block-entity
// lookup (`ServerLevelPlot.actorAt` is a host gap), so it registers the actors
// itself and listens on the physics system's pre-physics list.
// ignore_for_file: implementation_imports
import 'package:create/create.dart';
import 'package:create/src/api/block_state.dart' show BState;
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:sable/sable.dart';

import 'hot_air/balloon_map.dart';
import 'host/world_balloon_world.dart';

/// The runtime state of one world.
final class AeroWorldRuntime {
  AeroWorldRuntime(this.balloonWorld);

  /// The balloon model's view of the world.
  final WorldBalloonWorld balloonWorld;

  /// The physics systems this runtime already listens on.
  final Set<SubLevelPhysicsSystem> listened = {};

  /// The actors already registered in a plot.
  final Set<String> registeredActors = {};

  /// The balloon map of the world.
  BalloonMap get balloons => BalloonMap.of(balloonWorld);
}

/// The aeronautics runtime, keyed by world id.
abstract final class AeronauticsHooks {
  static final Map<String, AeroWorldRuntime> _runtimes = {};

  /// Called when a world's unloaded balloons changed and must be saved.
  static void Function(String worldId)? onBalloonsDirty;

  /// The block entity store, for the block callbacks that need a neighbour's
  /// entity (`BlockBehavior` has no store of its own). Set by the module.
  static BlockEntityStore? store;

  /// The runtime of [world], created on first use.
  static AeroWorldRuntime of(World world) => _runtimes.putIfAbsent(world.getId(), () {
    final runtime = AeroWorldRuntime(balloonWorldOf(world));
    runtime.balloons.onDirty = () => onBalloonsDirty?.call(runtime.balloonWorld.id);
    return runtime;
  });

  /// Forgets every runtime (plugin unload).
  static void clear() {
    _runtimes.clear();
    BalloonMap.clear();
    clearBalloonWorlds();
  }

  /// One server tick of [world]: advances the balloons and re-registers the
  /// actors that moved with their sub-levels.
  static void tickWorld(World world, BlockEntityStore store) {
    final runtime = of(world);

    final subLevels = SubLevelContainer.of(runtime.balloonWorld.level);
    if (subLevels is ServerSubLevelContainer) {
      _ensurePhysicsListener(runtime, subLevels);
    }

    runtime.balloons.tickBalloons();

    for (final entity in store.inWorld(world.getId())) {
      if (entity is! BlockEntitySubLevelActor) continue;
      _registerActor(runtime, entity);
    }
  }

  /// Adds the balloon physics to the pre-physics list of the world's system.
  static void _ensurePhysicsListener(AeroWorldRuntime runtime, ServerSubLevelContainer container) {
    final physics = container.physics;
    if (physics is! SubLevelPhysicsSystem) return;
    if (!runtime.listened.add(physics)) return;

    physics.prePhysicsTickListeners.add((system, timeStep) {
      BalloonMap.physicsTick(runtime.balloonWorld, timeStep);
    });
  }

  /// Puts an actor into the plot that contains it, so the physics system ticks
  /// it.
  static void _registerActor(AeroWorldRuntime runtime, Object candidate) {
    if (candidate is! CreateBlockEntity) return;
    if (candidate is! BlockEntitySubLevelActor) return;
    final CreateBlockEntity be = candidate;
    final BlockEntitySubLevelActor actor = candidate as BlockEntitySubLevelActor;

    final key = '${be.worldId}:${be.pos.x},${be.pos.y},${be.pos.z}';
    if (runtime.registeredActors.contains(key)) return;

    final pos = (be.pos.x, be.pos.y, be.pos.z);
    final subLevel = SubLevelHelper.getContaining(runtime.balloonWorld.level, pos);
    if (subLevel == null) return;

    subLevel.getPlot().blockEntityActors[pos] = actor;
    runtime.registeredActors.add(key);
  }

  /// Forgets an actor that unloaded, so it is registered again when it comes
  /// back.
  static void forgetActor(String worldId, BlockPos pos) {
    _runtimes[worldId]?.registeredActors.remove('$worldId:${pos.x},${pos.y},${pos.z}');
  }

  /// `Balloon.setAssembling`: a balloon's blocks were moved into or out of a
  /// sub-level, so its controller and bounds follow [transform].
  static void balloonsAssembled(World world, AssemblyTransform transform) {
    for (final balloon in of(world).balloons.allBalloons) {
      balloon.setAssembling(transform);
    }
  }

  /// Tells the nearby balloons that a block changed.
  static void blockChanged(World world, BlockPos pos, BState oldState, BState newState) {
    of(world).balloons.updateNearbyBalloons((pos.x, pos.y, pos.z), oldState, newState);
  }
}
