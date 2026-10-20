// The per-block behaviour Create's blocks need on a sub-level, as pure
// functions of the block, the sub-level pose and the entity.
//
// Each function is the body of one Java compat mixin, with the Minecraft types
// replaced by the Dart Create port's records. The host-side glue (the block
// entity callbacks and the block entity classes) is in `create_host.dart`; the
// maths is here so it is testable on the VM without a server.
//
// Pure: no host imports.
//
// Java: `...create.belt.BeltBlockMixin`, `...belt.BeltMovementHandlerMixin`,
// `...ejector.EjectorBlockEntityMixin`, `...saw.SawBlockEntityMixin`,
// `...crushing_wheel.CrushingWheelBlockMixin`, `...funnels.FunnelBlockMixin`,
// `...nozzle.block_entity.NozzleBEFixesMixin`, `...display_link.*`,
// `...redstone_links.RedstoneLinkNetworkHandlerMixin`,
// `...deployer.DeployerBlockEntityMixin`, `...harvester_block_entity.*`.
//
// create's positions and block states are not exported from its public barrel
// yet, so they are imported from `src/` deliberately.
// ignore_for_file: implementation_imports
import 'dart:math' as math;

import 'package:create/src/common/direction.dart' show Axis, AxisDirection, Direction;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:create/src/conveyance/belt/belt_geometry.dart' show BeltSlope;
import 'package:pumpkin_api/src/geometry.dart' show Vec3;

import '../../sublevel/api/sub_level_helper.dart';
import '../../sublevel/host/sub_level_host.dart';
import '../../sublevel/math/pose.dart';
import '../../sublevel/math/vector.dart';
import '../../sublevel/model/sub_level.dart';

/// `BeltBlockCallback`: the tangent motion a belt gives a body that touches it.
abstract final class BeltCollision {
  /// The tangent velocity of the belt at a contact [relativeHitY] above the
  /// belt block, or `null` for the `NONE` result (a sideways belt, or a block
  /// that is not a belt).
  ///
  /// The belt pushes along its facing axis, at `beltMovementSpeed * 20`; a
  /// horizontal belt pushes the other way for a body below its middle, which is
  /// what makes the top surface carry entities along.
  static Vector3d? velocityFor({
    required Direction facing,
    required BeltSlope slope,
    required double beltMovementSpeed,
    required double relativeHitY,
  }) {
    if (slope == BeltSlope.sideways) return null;

    final normal = Direction.fromAxisAndDirection(facing.axis, AxisDirection.positive);
    var speed = beltMovementSpeed * 20.0;
    if (facing.axis == Axis.x) speed = -speed;

    final velocity = Vector3d(
      normal.stepX * speed,
      normal.stepY * speed,
      normal.stepZ * speed,
    );

    if (slope == BeltSlope.horizontal && relativeHitY < 0.5) velocity.negate();
    return velocity;
  }
}

/// `BeltMovementHandlerMixin`: the three transforms `BeltMovementHandler.transportEntity`
/// needs when the belt is on a sub-level.
abstract final class BeltMovement {
  /// `sable$getLocalEntityY`: the entity's height in the belt's frame.
  static double localEntityY(Pose3dc? pose, Vec3 entityPosition) {
    if (pose == null) return entityPosition.$2;
    return pose.transformPositionInverse(Vector3d(entityPosition.$1, entityPosition.$2, entityPosition.$3)).y;
  }

  /// `sable$diffCenter`: the sideways offset of the entity from the belt's
  /// centre line, in the belt's frame.
  static double diffCenter(Pose3dc? pose, Pos pos, Axis axis, Vec3 entityPosition) {
    if (pose == null) {
      return axis == Axis.z
          ? pos.$1 + 0.5 - entityPosition.$1
          : pos.$3 + 0.5 - entityPosition.$3;
    }

    final local = pose.transformPositionInverse(Vector3d(entityPosition.$1, entityPosition.$2, entityPosition.$3));
    return axis == Axis.z ? pos.$1 + 0.5 - local.x : pos.$3 + 0.5 - local.z;
  }

  /// `sable$maxUpStep`: the movement the belt applies, rotated out of the
  /// sub-level.
  static Vec3 transformMovement(Pose3dc? pose, Vec3 movement) {
    if (pose == null) return movement;

    final rotated = pose.transformNormal(Vector3d(movement.$1, movement.$2, movement.$3));
    return (rotated.x, rotated.y, rotated.z);
  }
}

/// `EjectorBlockEntityMixin`: the impulse a weighted ejector gives a sub-level
/// above it, and the reaction on the sub-level it stands on.
abstract final class EjectorLaunch {
  /// The local impulse (`facingStep * vx + (0, vy, 0)`) that launches a 1 kpg
  /// body to the launcher's target, or `null` when the target is directly above
  /// (the launch angle is undefined and Create does not launch).
  ///
  /// This is Eriksonn's closed form: with a horizontal speed cap `c`, the
  /// horizontal speed is the smallest of `c` and the speed that reaches the
  /// target height in the time the flight takes, and the vertical speed follows
  /// from the ballistic equation.
  static Vector3d? computeLocalImpulse({
    required double horizontalDistance,
    required double verticalDistance,
    required double gravity,
    required Direction facing,
  }) {
    if (horizontalDistance == 0) return null;
    if (gravity <= 0) return null;

    final c = 3.0 * math.max(1.0, horizontalDistance / 10.0);
    final px = horizontalDistance;
    final py = verticalDistance;

    var vx = c;
    if (py > 0) {
      vx = math.min(c, px * math.sqrt(0.5 * gravity / py));
    }

    final vy = vx * py / px + 0.5 * gravity * px / vx;

    return Vector3d(
      facing.stepX * vx,
      vy,
      facing.stepZ * vx,
    );
  }

  /// The global impulse: the local one rotated out of the launcher's sub-level.
  static Vector3d toGlobal(Pose3dc? pose, Vector3d localImpulse) {
    if (pose == null) return Vector3d.copy(localImpulse);
    return pose.transformNormal(localImpulse);
  }
}

/// `SawBlockEntityMixin` / `SawMovementBehaviourMixin`: the velocity of an item
/// a saw drops, measured between the cut block and the saw, both projected out
/// of their sub-levels.
abstract final class SawDrop {
  /// `dropItemFromCutTree`'s `deltaMovement`: the global vector from the saw to
  /// the cut block, transformed back into the saw's sub-level when it has one.
  static Vector3d itemDeltaMovement(
    SableLevel level,
    Vector3d sawCenter,
    Vector3d breakingCenter,
    SubLevel? sawSubLevel,
  ) {
    final diff = SubLevelHelper.projectOutOfSubLevel(level, breakingCenter)
      ..sub(SubLevelHelper.projectOutOfSubLevel(level, sawCenter));

    if (sawSubLevel != null) sawSubLevel.logicalPose.transformNormalInverse(diff, diff);
    return diff;
  }

  /// `sable$fixSpeed`: the distance between two points across sub-levels.
  static double distanceAcrossSubLevels(SableLevel level, Vec3 a, Vec3 b) => math.sqrt(
    SubLevelHelper.distanceSquaredWithSubLevels(
      level,
      Vector3d(a.$1, a.$2, a.$3),
      Vector3d(b.$1, b.$2, b.$3),
    ),
  );
}

/// `CrushingWheelBlockMixin`: the push a crushing wheel gives an entity standing
/// on it.
abstract final class CrushingWheel {
  /// The impulse in the sub-level's local space, or `null` when the entity is
  /// below the wheel's upper quarter or not on the ground.
  static Vector3d? pushImpulse({
    required Axis axis,
    required double speed,
    required Vector3d entityLocalPosition,
    required Pos pos,
    required bool onGround,
  }) {
    if (entityLocalPosition.y < pos.$2 + 1.25 || !onGround) return null;

    var x = 0.0;
    var z = 0.0;

    if (axis == Axis.x) {
      z = speed / 20.0;
      x += (pos.$1 + 0.5 - entityLocalPosition.x) * 0.1;
    }

    if (axis == Axis.z) {
      x = speed / -20.0;
      z += (pos.$3 + 0.5 - entityLocalPosition.z) * 0.1;
    }

    return Vector3d(x, 0.0, z);
  }

  /// The global impulse: the local one rotated out of the sub-level.
  static Vector3d toGlobal(Pose3dc? pose, Vector3d impulse) =>
      pose == null ? Vector3d.copy(impulse) : pose.transformNormal(impulse);
}

/// The range checks Create performs between two block entities, measured across
/// sub-levels.
abstract final class CreateRangeChecks {
  /// `DisplayLinkBlockEntityMixin.getTargetPosition` and
  /// `DisplayLinkBlockEntityMixin.sable$accountForSubLevels`: whether the
  /// display link's target is within [range] of the link.
  static bool withinRange(
    SableLevel level,
    Vec3 a,
    Vec3 b,
    double range,
  ) => SubLevelHelper.distanceSquaredWithSubLevels(
    level,
    Vector3d(a.$1, a.$2, a.$3),
    Vector3d(b.$1, b.$2, b.$3),
  ) <
      range * range;

  /// `RedstoneLinkNetworkHandlerMixin.sable$projectComparisons`: whether two
  /// link locations are within [linkRange], with both projected out of their
  /// sub-levels.
  static bool linksWithinRange(
    SableLevel level,
    Vector3d fromCenter,
    Vector3d toCenter,
    int linkRange,
  ) =>
      SubLevelHelper.distanceSquaredWithSubLevels(level, fromCenter, toCenter) <
      linkRange * linkRange;

  /// `ClickToLinkBlockItemMixin`: whether the clicked block is within [range] of
  /// the item's target.
  static bool blockWithinRange(SableLevel level, Pos a, Pos b, double range) =>
      SubLevelHelper.distanceSquaredWithSubLevelsTo(
        level,
        Vector3d(a.$1 + 0.5, a.$2 + 0.5, a.$3 + 0.5),
        b.$1 + 0.5,
        b.$2 + 0.5,
        b.$3 + 0.5,
      ) <
      range * range;
}

/// `FunnelBlockMixin` / `NozzleBEFixesMixin`: a block centre projected out of
/// its sub-level, for the collision and particle checks of the block.
abstract final class ProjectedBlockCenter {
  /// The world position of the centre of [pos].
  static Vec3 of(SableLevel level, Pos pos) {
    final projected = SubLevelHelper.projectOutOfSubLevel(
      level,
      Vector3d(pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5),
    );
    return (projected.x, projected.y, projected.z);
  }
}

/// `DeployerBlockEntityMixin` / `HarvesterBlockEntityMixin`: the position a
/// block entity acts on, looked up through the sub-level it is in.
abstract final class GatheredBlockPos {
  /// The deployer's target: the first position in [pos] or one of its six
  /// neighbours that holds a non-air block.
  static Pos? deployerTarget(
    SableLevel level,
    Vector3d center,
    SubLevel? containing,
    bool Function(Pos pos) hasBlock,
  ) {
    Pos? gather(SubLevel? _, Pos candidate) {
      if (hasBlock(candidate)) return candidate;
      for (final direction in Direction.values) {
        final offset = (
          candidate.$1 + direction.stepX,
          candidate.$2 + direction.stepY,
          candidate.$3 + direction.stepZ,
        );
        if (hasBlock(offset)) return candidate;
      }
      return null;
    }

    return SubLevelHelper.runIncludingSubLevels<Pos>(level, center, true, containing, gather);
  }

  /// The harvester's target: the first position that holds a valid crop.
  static Pos? harvesterTarget(
    SableLevel level,
    Vector3d center,
    SubLevel? containing,
    bool Function(Pos pos) isValidCrop,
  ) => SubLevelHelper.runIncludingSubLevels<Pos>(level, center, true, containing, (_, pos) {
    return isValidCrop(pos) ? pos : null;
  });

  /// `BlockPos.containing(helper.projectOutOfSubLevel(level, center))`: the
  /// fallback when no sub-level has a valid position.
  static Pos projected(SableLevel level, Vector3d center) {
    final projected = SubLevelHelper.projectOutOfSubLevel(level, center);
    return (projected.x.floor(), projected.y.floor(), projected.z.floor());
  }
}

/// `ChuteBlockEntityMixin`: the direction a chute looks for a handler in, once
/// the sub-level it is in has rotated it.
abstract final class ChuteDirection {
  /// The direction to query, given the chute's own direction [side] and the
  /// sub-level the neighbour is in (`null` for the main level).
  static Direction resolve(Direction side, Pose3dc? neighbourSubLevel) {
    final opposite = side.opposite;
    final mut = Vector3d(
      opposite.stepX.toDouble(),
      opposite.stepY.toDouble(),
      opposite.stepZ.toDouble(),
    );

    if (neighbourSubLevel != null) neighbourSubLevel.transformNormalInverse(mut, mut);
    return _approximateNearest(mut.x, mut.y, mut.z);
  }

  /// `Direction.getApproximateNearest(x, y, z)`.
  static Direction _approximateNearest(double x, double y, double z) {
    final ax = x.abs();
    final ay = y.abs();
    final az = z.abs();
    if (ax >= ay && ax >= az) return x > 0 ? Direction.east : Direction.west;
    if (ay >= ax && ay >= az) return y > 0 ? Direction.up : Direction.down;
    return z > 0 ? Direction.south : Direction.north;
  }
}
