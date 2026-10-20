// The host-side half of the Create compatibility layer: the adapters that need
// Create's block entity classes (and therefore the wasm host API).
//
// This file is a separate entry point (`sable_create_host.dart`) on purpose:
// `package:sable/sable.dart` stays loadable on the plain Dart VM, while a plugin
// imports this one to install the adapters. Everything behavioural lives in the
// pure layer; what is here is the wiring: the block entity lookup, the belt
// reader, the fan propeller and the world -> level resolver.
//
// Java: `...create.fans_provide_force.EncasedFanBlockEntityMixin` (the fan is the
// only block that needs its own class; the others are covered by the pure
// listeners in `create_block_hooks.dart`).
//
// create's classes are not exported from its public barrel yet, so they are
// imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:create/src/conveyance/belt/belt_block_entity.dart' show BeltBlockEntity;
import 'package:create/src/conveyance/belt/belt_geometry.dart' show BeltSlope;
import 'package:create/src/conveyance/chain/chain_conveyor_block_entity.dart';
import 'package:create/src/core/block_entity.dart' show BlockEntityStore;
import 'package:create/src/kinetics/settings.dart' show convertToAngular;
import 'package:create/src/processing/fan/encased_fan_block.dart';
import 'package:create/src/redstone/display/display_link_block.dart';
import 'package:pumpkin_api/pumpkin_api.dart' show BlockPos;

import '../../sublevel/api/block/block_entity_propeller.dart';
import '../../sublevel/api/block/block_entity_sub_level_propeller_actor.dart';
import '../../sublevel/api/physics.dart' show ForceGroup, RigidBodyHandle;
import '../../sublevel/api/sub_level_helper.dart';
import '../../sublevel/host/sub_level_host.dart';
import '../../sublevel/math/vector.dart';
import '../../sublevel/model/server_sub_level.dart';
import '../../sublevel/model/sub_level.dart';
import '../../sublevel/physics/dimension_physics.dart';
import 'create_block_hooks.dart';
import 'create_blocks.dart';

/// `World` -> `SableLevel` for the Create block entities.
///
/// A Create block entity holds a `World`; Sable speaks [SableLevel]. The plugin
/// installs the adapter here at load time; without it the fan degrades to "not
/// on a sub-level" instead of guessing.
typedef CreateSableLevelResolver = SableLevel? Function(Object world);

/// The propeller of an encased fan: `EncasedFanBlockEntityMixin`.
///
/// The fan is a propeller on a sub-level exactly as an aeronautics propeller is:
/// its rotation becomes an airflow and a thrust along its facing, and a block in
/// front of it blocks the flow.
final class FanPropellerActor implements BlockEntitySubLevelPropellerActor, BlockEntityPropeller {
  final EncasedFanBlockEntity fan;

  /// Whether the block in front of the fan is not air
  /// (`sable$blocked`, refreshed every sub-level tick).
  bool blocked = false;

  FanPropellerActor(this.fan);

  /// `sable$tick`: refresh [blocked] from the block in front of the fan.
  @override
  void sable$tick(ServerSubLevel subLevel) {
    final world = fan.world;
    if (world == null) {
      blocked = true;
      return;
    }

    final facing = getBlockDirection();
    final front = fan.pos.copyWith(
      x: fan.pos.x + facing.stepX,
      y: fan.pos.y + facing.stepY,
      z: fan.pos.z + facing.stepZ,
    );
    blocked = !world.getBlockState(pos: front).isAir;
  }

  /// `BlockEntitySubLevelActor`'s dependency defaults: a fan has none.
  @override
  Iterable<SubLevel>? sable$getLoadingDependencies() => null;

  @override
  Iterable<SubLevel>? sable$getConnectionDependencies() => null;

  @override
  BlockEntityPropeller getPropeller() => this;

  @override
  Direction getBlockDirection() {
    final dir = fan.blockState.dirOf('facing');
    return dir == null ? Direction.north : Direction.values[dir.index];
  }

  /// `sable$getPropSpeed`: the angular speed, signed by the facing axis, times
  /// `10 / 3`.
  double get propSpeed {
    final rotationSpeed = convertToAngular(fan.speed);
    return getBlockDirection().axisDirection.step * rotationSpeed * (10 / 3);
  }

  @override
  double getAirflow() => 0.1 * propSpeed;

  @override
  double getThrust() => 0.3 * propSpeed;

  @override
  bool isActive() => !blocked && propSpeed.abs() > 0.01;

  @override
  SableLevel getLevel() {
    final world = fan.world;
    final level = world == null ? null : CreateHostCompat.levelResolver?.call(world);
    if (level == null) {
      throw StateError('CreateHostCompat.levelResolver is not installed (fan at ${fan.pos})');
    }
    return level;
  }

  @override
  Pos getBlockPos() => (fan.pos.x, fan.pos.y, fan.pos.z);

  // `BlockEntityPropeller`'s default methods are not inherited by implementers.

  @override
  double getScaledThrust() => -getThrust() * getAirflowScaling() * getCurrentAirPressure();

  @override
  double getCurrentAirPressure() {
    final level = getLevel();
    final pos = getBlockPos();
    final center = Vector3d(pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5);
    return DimensionPhysicsData.getAirPressure(level, SubLevelHelper.projectOutOfSubLevel(level, center));
  }

  @override
  double getAirflowScaling() {
    final airflow = getAirflow();
    if (airflow.abs() <= 0.001) return 1.0;

    final level = getLevel();
    final pos = getBlockPos();
    final center = Vector3d(pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5);
    final subLevel = SubLevelHelper.getContaining(level, pos);
    if (subLevel == null) return 1.0;

    final velocity = SubLevelHelper.getVelocityOfSubLevel(level, subLevel, center, Vector3d());
    final step = getBlockDirection();
    final thrustDirection = subLevel.logicalPose.transformNormal(
      Vector3d(step.stepX.toDouble(), step.stepY.toDouble(), step.stepZ.toDouble()),
    );

    return ((airflow + velocity.dot(thrustDirection)) / airflow).clamp(0.0, 1.0);
  }

  /// `BlockEntitySubLevelPropellerActor.sable$physicsTick`: apply the thrust
  /// every physics tick while the fan turns and is not blocked.
  @override
  void sable$physicsTick(ServerSubLevel subLevel, RigidBodyHandle handle, double timeStep) {
    if (!isActive()) return;

    final direction = getBlockDirection();
    applyForces(
      subLevel,
      Vector3d(direction.stepX.toDouble(), direction.stepY.toDouble(), direction.stepZ.toDouble()),
      timeStep,
    );
  }

  /// `BlockEntitySubLevelPropellerActor.applyForces`.
  @override
  void applyForces(ServerSubLevel subLevel, Vector3d thrustDirection, double timeStep) {
    final thrust = Vector3d.copy(thrustDirection).mul(getScaledThrust() * timeStep);

    final pos = getBlockPos();
    final thrustPosition = Vector3d(pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5);

    final forceGroup = subLevel.getOrCreateQueuedForceGroup(ForceGroup.propulsion);
    forceGroup.applyAndRecordPointForce(Vector3d.copy(thrustPosition), thrust);
  }
}

/// Installs the host-side Create adapters into the pure compat layer.
abstract final class CreateHostCompat {
  /// `World` -> `SableLevel`; installed by the plugin.
  static CreateSableLevelResolver? levelResolver;

  /// The block entity store the adapters read (`ActuatorRuntime.instance.store`
  /// unless overridden).
  static BlockEntityStore? blockEntitiesOverride;

  static bool _installed = false;

  /// Whether the host adapters are installed.
  static bool get installed => _installed;

  /// The block entity store, or `null` before the Create plugin loaded.
  static BlockEntityStore? get blockEntities => blockEntitiesOverride;

  /// Installs the lookups the pure listeners use and, when Create is loaded,
  /// registers the fan propeller.
  ///
  /// Call it after `CreateCompat.install()`.
  static void install({BlockEntityStore? blockEntities}) {
    if (_installed) return;
    _installed = true;
    blockEntitiesOverride = blockEntities;

    CreateCompatBlocks.blockEntityLookup = _blockEntityAt;
    CreateCompatBlocks.beltStateReader = _beltState;
    CreateCompatBlocks.chainConveyorValidate = _validateChainConveyor;
    CreateCompatBlocks.chainConveyorCheckInvalid = _invalidateChainConveyor;
    CreateCompatBlocks.displayLinkTarget = _displayLinkTarget;
    CreateCompatBlocks.displayLinkRetarget = _displayLinkRetarget;
  }

  /// Forgets the host-side wiring (tests, plugin unload).
  static void uninstall() {
    _installed = false;
    CreateCompatBlocks.blockEntityLookup = null;
    CreateCompatBlocks.beltStateReader = null;
    CreateCompatBlocks.chainConveyorValidate = null;
    CreateCompatBlocks.chainConveyorCheckInvalid = null;
    CreateCompatBlocks.displayLinkTarget = null;
    CreateCompatBlocks.displayLinkRetarget = null;
    levelResolver = null;
    blockEntitiesOverride = null;
    BeltBlockCallback.currentStepWorldId = '';
  }

  /// Sets the world the belt collision callback runs in, for the duration of a
  /// physics step.
  static void beginStep(String worldId) => BeltBlockCallback.currentStepWorldId = worldId;

  /// Clears the world of the physics step.
  static void endStep() => BeltBlockCallback.currentStepWorldId = '';

  static Object? _blockEntityAt(String worldId, Pos pos) =>
      blockEntities?.at(worldId, BlockPos(x: pos.$1, y: pos.$2, z: pos.$3));

  static BeltTangentState? _beltState(Object blockEntity) {
    if (blockEntity is! BeltBlockEntity) return null;

    final state = blockEntity.beltState;
    return BeltTangentState(
      state.dir('facing') ?? Direction.north,
      BeltSlope.fromName(state['slope']),
      blockEntity.beltMovementSpeed,
    );
  }

  static void _validateChainConveyor(Object blockEntity) {
    if (blockEntity is ChainConveyorBlockEntity) blockEntity.notifyConnectedToValidate();
  }

  static void _invalidateChainConveyor(Object blockEntity) {
    if (blockEntity is ChainConveyorBlockEntity) blockEntity.checkInvalid = true;
  }

  static Pos? _displayLinkTarget(Object blockEntity) =>
      blockEntity is DisplayLinkBlockEntity ? blockEntity.targetPosition : null;

  static void _displayLinkRetarget(Object blockEntity, Pos target) {
    if (blockEntity is DisplayLinkBlockEntity) blockEntity.target(target);
  }
}
