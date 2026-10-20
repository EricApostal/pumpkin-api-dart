// Air currents on sub-levels: the fan's stream is computed in the fan's frame,
// so entity bounds, entity positions and the flow vector have to cross the
// sub-level pose.
//
// In Java `AirCurrentMixin` redirects three reads inside
// `AirCurrent.tickAffectedEntities` and `FanProcessingTypeMixin` wraps
// `FanProcessingType.getAt`. The Dart Create port's [AirCurrent] takes the
// entity bounds, position and motion from its own helpers, so the compat layer
// supplies the same three transforms as functions and the port calls them
// where it reads an entity. [fanProcessingTypeAt] is the `getAt` wrapper.
//
// Pure: no host imports.
//
// Java: `...create.airflow.AirCurrentMixin`, `...create.airflow.FanProcessingTypeMixin`.
//
// create's positions and block states are not exported from its public barrel
// yet, so they are imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'package:create/src/common/bounds.dart' show Aabb;
import 'package:pumpkin_api/src/geometry.dart' show Vec3;

import '../../sublevel/host/sub_level_host.dart';
import '../../sublevel/math/bounding_box.dart';
import '../../sublevel/math/pose.dart';
import '../../sublevel/math/vector.dart';
import '../../sublevel/model/sub_level.dart';
import '../../sublevel/api/sub_level_helper.dart';

/// `AirCurrentMixin.sable$reverseProjectEntityBB`: an entity's bounding box in
/// the sub-level's local space, so the fan's segment test sees it where the
/// blocks are.
Aabb reverseProjectEntityBounds(Aabb bounds, Pose3dc? pose) {
  if (pose == null) return bounds;

  final local = BoundingBox3d.fromAabb(bounds).transformInverse(pose);
  return Aabb(local.minX, local.minY, local.minZ, local.maxX, local.maxY, local.maxZ);
}

/// `AirCurrentMixin.sable$reverseProjectAllPositions`: an entity position in
/// the sub-level's local space.
Vec3 reverseProjectPosition(Vec3 position, Pose3dc? pose) {
  if (pose == null) return position;

  final local = pose.transformPositionInverse(Vector3d(position.$1, position.$2, position.$3));
  return (local.x, local.y, local.z);
}

/// `AirCurrentMixin.sable$transformFlowVector`: the flow vector is local to the
/// fan's sub-level, so it is rotated out before it is added to the entity's
/// motion.
///
/// The result is the motion the fan sets: the previous motion plus the clamped
/// flow acceleration, scaled by `0.125`.
Vec3 transformFlowVector(
  (int, int, int) flow,
  double acceleration,
  Vec3 previousMotion,
  double maxAcceleration,
  Pose3dc? pose,
) {
  if (pose == null) {
    return (
      previousMotion.$1 +
          _clamp(flow.$1 * acceleration - previousMotion.$1, -maxAcceleration, maxAcceleration) * 0.125,
      previousMotion.$2 +
          _clamp(flow.$2 * acceleration - previousMotion.$2, -maxAcceleration, maxAcceleration) * 0.125,
      previousMotion.$3 +
          _clamp(flow.$3 * acceleration - previousMotion.$3, -maxAcceleration, maxAcceleration) * 0.125,
    );
  }

  final nonIntFlow = Vector3d(flow.$1.toDouble(), flow.$2.toDouble(), flow.$3.toDouble());
  pose.transformNormal(nonIntFlow, nonIntFlow);

  final xIn = _clamp(nonIntFlow.x * acceleration - previousMotion.$1, -maxAcceleration, maxAcceleration);
  final yIn = _clamp(nonIntFlow.y * acceleration - previousMotion.$2, -maxAcceleration, maxAcceleration);
  final zIn = _clamp(nonIntFlow.z * acceleration - previousMotion.$3, -maxAcceleration, maxAcceleration);

  return (previousMotion.$1 + xIn * 0.125, previousMotion.$2 + yIn * 0.125, previousMotion.$3 + zIn * 0.125);
}

/// `FanProcessingTypeMixin.getAt`: the fan processing type at [pos], looking
/// through the sub-level the position is in and every sub-level overlapping it.
///
/// [lookup] is `FanProcessingType.getAt(level, pos)`; the caller supplies it so
/// this file stays free of the processing registry.
T? fanProcessingTypeAt<T>(
  SableLevel level,
  Vector3d origin,
  T? Function((int, int, int) pos) lookup,
) {
  final subLevel = SubLevelHelper.getContainingPos(level, origin);
  return SubLevelHelper.runIncludingSubLevels<T>(level, origin, true, subLevel, (_, pos) => lookup(pos));
}

/// `Mth.clamp`.
double _clamp(double value, double min, double max) => value < min ? min : (value > max ? max : value);

/// The pose a fan's sub-level has, or `null` when [subLevel] is `null`.
Pose3dc? poseOfSubLevel(SubLevel? subLevel) => subLevel?.logicalPose;
