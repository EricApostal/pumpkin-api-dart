// `dev.ryanhcode.sable.api.block.propeller.BlockEntityPropeller`: a spinning
// propeller that produces thrust.
//
// Pure: no host imports.
//
// create's positions are not exported from its public barrel yet, so they are
// imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart' show Pos;

import '../../host/sub_level_host.dart';
import '../../math/vector.dart';
import '../../physics/dimension_physics.dart';
import '../sub_level_helper.dart';

/// Spinny spin spin, woosh woosh.
abstract interface class BlockEntityPropeller {
  /// The direction of the propeller.
  Direction getBlockDirection();

  /// The airflow, in m/s.
  double getAirflow();

  /// The thrust, in pN.
  double getThrust();

  /// Whether the propeller is active and thrust should be computed.
  bool isActive();

  /// The thrust scaled by `-1 * airflow scaling * air pressure`.
  double getScaledThrust() =>
      -getThrust() * getAirflowScaling() * getCurrentAirPressure();

  /// The air pressure at the block.
  double getCurrentAirPressure() {
    final level = getLevel();
    final pos = Vector3d(getBlockPos().$1 + 0.5, getBlockPos().$2 + 0.5, getBlockPos().$3 + 0.5);
    return DimensionPhysicsData.getAirPressure(level, SubLevelHelper.projectOutOfSubLevel(level, pos));
  }

  /// How much of the airflow reaches the propeller, `0..1`.
  double getAirflowScaling() {
    final airflow = getAirflow();
    if (airflow.abs() <= 0.001) return 1.0;

    final level = getLevel();
    final pos = Vector3d(getBlockPos().$1 + 0.5, getBlockPos().$2 + 0.5, getBlockPos().$3 + 0.5);
    final subLevel = SubLevelHelper.getContaining(level, getBlockPos());
    if (subLevel == null) return 1.0;

    final velocity = SubLevelHelper.getVelocityOfSubLevel(level, subLevel, pos, Vector3d());
    final step = getBlockDirection();
    final thrustDirection = subLevel.logicalPose.transformNormal(
      Vector3d(step.stepX.toDouble(), step.stepY.toDouble(), step.stepZ.toDouble()),
    );

    return ((airflow + velocity.dot(thrustDirection)) / airflow).clamp(0.0, 1.0);
  }

  /// The level of the block entity.
  SableLevel getLevel();

  /// The position of the block entity.
  Pos getBlockPos();
}
