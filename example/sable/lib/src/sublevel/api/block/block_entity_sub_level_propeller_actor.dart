// `dev.ryanhcode.sable.api.block.propeller.BlockEntitySubLevelPropellerActor`:
// a propeller block entity mounted on a sub-level.
//
// Pure: no host imports.
//
// create's positions are not exported from its public barrel yet, so they are
// imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart' show Pos;

import '../../model/server_sub_level.dart';
import '../../math/vector.dart';
import '../physics.dart';
import 'block_entity_propeller.dart';
import 'block_entity_sub_level_actor.dart';

/// A propeller mounted on a sub-level: applies its thrust every physics tick.
abstract interface class BlockEntitySubLevelPropellerActor
    implements BlockEntitySubLevelActor {
  /// Scratch vectors, as in the Java interface (reused to avoid allocation).
  static final Vector3d thrustVector = Vector3d();
  static final Vector3d thrustPosition = Vector3d();

  /// The propeller this actor drives.
  BlockEntityPropeller getPropeller();

  @override
  void sable$physicsTick(ServerSubLevel subLevel, RigidBodyHandle handle, double timeStep) {
    final prop = getPropeller();
    if (prop.isActive()) {
      final direction = prop.getBlockDirection();
      applyForces(
        subLevel,
        Vector3d(direction.stepX.toDouble(), direction.stepY.toDouble(), direction.stepZ.toDouble()),
        timeStep,
      );
    }
  }

  /// Applies the propeller thrust along [thrustDirection].
  void applyForces(ServerSubLevel subLevel, Vector3d thrustDirection, double timeStep) {
    final prop = getPropeller();
    final thrust = Vector3d.copy(thrustDirection).mul(prop.getScaledThrust() * timeStep);

    final pos = prop.getBlockPos();
    thrustPosition.set(pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5);
    thrustVector.setFrom(thrust);

    final forceGroup = subLevel.getOrCreateQueuedForceGroup(ForceGroup.propulsion);
    forceGroup.applyAndRecordPointForce(Vector3d.copy(thrustPosition), Vector3d.copy(thrustVector));
  }
}

/// `Direction.getStep()` as a vector, for callers that only have a direction.
Vector3d directionStep(Direction direction) =>
    Vector3d(direction.stepX.toDouble(), direction.stepY.toDouble(), direction.stepZ.toDouble());

/// `Vec3.atCenterOf(BlockPos)` as a vector.
Vector3d centerOfBlock(Pos pos) => Vector3d(pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5);
