// The default members of the sable propeller interfaces.
//
// `BlockEntityPropeller` and `BlockEntitySubLevelPropellerActor` carry default
// bodies in Java, which an `implements` clause does not inherit in Dart. These
// mixins hold the same bodies once, so a propeller block entity only supplies
// its direction, airflow and thrust.
import 'package:sable/sable.dart';

/// The `BlockEntityPropeller` defaults.
mixin PropellerBlockEntityMixin implements BlockEntityPropeller {
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
}

/// The `BlockEntitySubLevelPropellerActor` defaults.
mixin SubLevelPropellerActorMixin implements BlockEntitySubLevelPropellerActor {
  @override
  void sable$tick(ServerSubLevel subLevel) {}

  @override
  void sable$physicsTick(ServerSubLevel subLevel, RigidBodyHandle handle, double timeStep) {
    final propeller = getPropeller();
    if (!propeller.isActive()) return;

    final direction = propeller.getBlockDirection();
    applyForces(
      subLevel,
      Vector3d(direction.stepX.toDouble(), direction.stepY.toDouble(), direction.stepZ.toDouble()),
      timeStep,
    );
  }

  @override
  Iterable<SubLevel>? sable$getLoadingDependencies() => sable$getConnectionDependencies();

  @override
  Iterable<SubLevel>? sable$getConnectionDependencies() => null;

  /// The thrust applied at the propeller's block centre, into the propulsion
  /// force group.
  @override
  void applyForces(ServerSubLevel subLevel, Vector3d thrustDirection, double timeStep) {
    final thrust = Vector3d.copy(thrustDirection).mul(getPropeller().getScaledThrust() * timeStep);
    final pos = getPropeller().getBlockPos();
    final group = subLevel.getOrCreateQueuedForceGroup(ForceGroup.propulsion);
    group.applyAndRecordPointForce(
      Vector3d(pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5),
      thrust,
    );
  }
}
