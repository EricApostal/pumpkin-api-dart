// The Create blocks whose behaviour on a sub-level needs a block entity: belts,
// chain conveyors and display links.
//
// The behaviour itself is pure; only the block entity lookup is host data. The
// registry keeps a pluggable lookup (`CreateCompatBlocks.blockEntityLookup`), so
// these listeners and the belt collision callback live here and are unit tested
// with fake block entities. The plugin installs the real lookup in
// `create_host.dart`.
//
// Java: `...create.belt.BeltBlockMixin`, `...create.chain_conveyor.ChainConveyorBlockMixin`,
// `...create.display_link.DisplayLinkBlockMixin`.
//
// create's positions and block states are not exported from its public barrel
// yet, so they are imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:create/src/conveyance/belt/belt_geometry.dart' show BeltSlope;

import '../../sublevel/api/block/block_sub_level_assembly_listener.dart';
import '../../sublevel/api/physics/callback/block_sub_level_collision_callback.dart';
import '../../sublevel/host/sub_level_host.dart';
import '../../sublevel/math/vector.dart';
import 'create_behaviours.dart';
import 'create_blocks.dart';

/// What a belt tells the collision callback.
final class BeltTangentState {
  final Direction facing;
  final BeltSlope slope;
  final double beltMovementSpeed;

  const BeltTangentState(this.facing, this.slope, this.beltMovementSpeed);
}

/// Reads the belt data out of a block entity, `null` when it is not a belt.
typedef BeltStateReader = BeltTangentState? Function(Object blockEntity);

/// `BeltBlockMixin`: a belt on a sub-level gives the bodies touching it a
/// tangent velocity.
///
/// The callback is registered for `create:belt`. It runs on the physics thread,
/// so the world it reads is the one the current step runs in: the plugin sets
/// [currentStepWorldId] around a step (the Dart equivalent of
/// `SubLevelPhysicsSystem.getCurrentlySteppingSystem()`).
final class BeltBlockCallback implements BlockSubLevelCollisionCallback {
  const BeltBlockCallback();

  /// The JNI form of the result: `[x, y, z, remove ? 1 : 0]`.
  @override
  List<double> onCollision(
    int x,
    int y,
    int z,
    int otherX,
    int otherY,
    int otherZ,
    double x1,
    double y1,
    double z1,
    double impactVelocity,
    bool hasOtherBlock,
  ) {
    final result = sable$onCollision(
      (x, y, z),
      hasOtherBlock ? (otherX, otherY, otherZ) : null,
      Vector3d(x1, y1, z1),
      impactVelocity,
    );
    final motion = result.tangentMotion;
    return [motion.x, motion.y, motion.z, result.removeCollision ? 1.0 : 0.0];
  }

  @override
  CollisionResult sable$onCollision(
    Pos hitBlockPos,
    Pos? otherHitBlockPos,
    Vector3d impactPosition,
    double impactVelocity,
  ) {
    final reader = CreateCompatBlocks.beltStateReader;
    if (reader == null) return CollisionResult.none;

    final entity = CreateCompatBlocks.blockEntityLookup?.call(currentStepWorldId, hitBlockPos);
    if (entity == null) return CollisionResult.none;

    final belt = reader(entity);
    if (belt == null) return CollisionResult.none;

    final velocity = BeltCollision.velocityFor(
      facing: belt.facing,
      slope: belt.slope,
      beltMovementSpeed: belt.beltMovementSpeed,
      relativeHitY: impactPosition.y - hitBlockPos.$2,
    );

    return velocity == null ? CollisionResult.none : CollisionResult(velocity, false);
  }

  /// The identifier of the world the physics step runs in: a dimension key or a world id, the
  /// same string [CreateCompatBlocks.blockEntityLookup] is given (which resolves it).
  static String currentStepWorldId = '';
}

/// `ChainConveyorBlockMixin`: a chain conveyor moved by assembly re-checks its
/// connections, and so do the conveyors it was connected to.
final class ChainConveyorAssemblyListener implements BlockSubLevelAssemblyListener {
  const ChainConveyorAssemblyListener();

  @override
  void beforeMove(
    SableLevel originLevel,
    SableLevel resultingLevel,
    BState newState,
    Pos oldPos,
    Pos newPos,
  ) {
    final be = CreateCompatBlocks.blockEntityLookup?.call(originLevel.dimensionId, oldPos);
    if (be == null) return;
    CreateCompatBlocks.chainConveyorValidate?.call(be);
  }

  @override
  void afterMove(
    SableLevel originLevel,
    SableLevel resultingLevel,
    BState newState,
    Pos oldPos,
    Pos newPos,
  ) {
    final be = CreateCompatBlocks.blockEntityLookup?.call(resultingLevel.dimensionId, newPos);
    if (be == null) return;
    CreateCompatBlocks.chainConveyorCheckInvalid?.call(be);
  }
}

/// `DisplayLinkBlockMixin`: a display link moved by assembly keeps its target.
final class DisplayLinkAssemblyListener implements BlockSubLevelAssemblyListener {
  const DisplayLinkAssemblyListener();

  @override
  void beforeMove(
    SableLevel originLevel,
    SableLevel resultingLevel,
    BState newState,
    Pos oldPos,
    Pos newPos,
  ) {}

  @override
  void afterMove(
    SableLevel originLevel,
    SableLevel resultingLevel,
    BState newState,
    Pos oldPos,
    Pos newPos,
  ) {
    final before = CreateCompatBlocks.blockEntityLookup?.call(originLevel.dimensionId, oldPos);
    final after = CreateCompatBlocks.blockEntityLookup?.call(resultingLevel.dimensionId, newPos);
    if (before == null || after == null) return;

    final target = CreateCompatBlocks.displayLinkTarget?.call(before);
    if (target == null) return;
    CreateCompatBlocks.displayLinkRetarget?.call(after, target);
  }
}
