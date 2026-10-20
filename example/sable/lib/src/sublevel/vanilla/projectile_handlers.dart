// Projectiles and sub-levels: inheriting the velocity of the ship they are
// fired from, and landing on one.
//
// Java patches `Projectile#shootFromRotation`, `AbstractArrow#onHitBlock` and
// `ProjectileUtil#getEntityHitResult`. A plugin sees the launch and the hit
// through host events and can apply the body impulse itself, so what is left
// here is the geometry: which direction a shot leaves in, how much of the
// ship's velocity it carries, and where an arrow sticks.
//
// Java: dev.ryanhcode.sable.mixin.entity.projectile.ProjectileMixin
// Java: dev.ryanhcode.sable.mixin.entity.arrows_hit_blocks.AbstractArrowMixin
// Java: dev.ryanhcode.sable.mixin.recoil.ProjectileDispenseBehaviorMixin
//
// Pure: no host imports.
import 'dart:math' as math;

import '../math/vector.dart';
import '../model/sub_level.dart';

/// A shot direction, in world space, plus the velocity it inherits.
final class ProjectileLaunch {
  /// `Projectile#shoot(DDDFF)` arguments, rotated into world space.
  final Vector3d direction;

  /// The shooter's inherited sub-level velocity, in m/tick, or `null`.
  final Vector3d? inheritedVelocity;

  const ProjectileLaunch(this.direction, this.inheritedVelocity);

  /// The delta movement after the launch, with the inherited velocity added.
  Vector3d applyTo(Vector3d deltaMovement) {
    final inherited = inheritedVelocity;
    if (inherited == null) return Vector3d.copy(deltaMovement);
    return Vector3d(deltaMovement.x + inherited.x, deltaMovement.y + inherited.y, deltaMovement.z + inherited.z);
  }
}

/// What an arrow does when it hits a block of a sub-level.
final class ArrowImpact {
  /// The impulse applied to the sub-level's body, in the body's own frame
  /// (m/tick).
  final Vector3d localImpulse;

  /// Where [localImpulse] is applied, in the plot's coordinates: the arrow's
  /// position.
  final Vector3d impulsePoint;

  /// The arrow's new delta movement (the vector from the arrow to the hit
  /// point, so it visually stops in the block).
  final Vector3d deltaMovement;

  /// The position the arrow is nudged to, in the plot's coordinates.
  final Vector3d localPosition;

  /// The rotation the arrow takes (degrees).
  final double yaw;
  final double pitch;

  const ArrowImpact({
    required this.localImpulse,
    required this.impulsePoint,
    required this.deltaMovement,
    required this.localPosition,
    required this.yaw,
    required this.pitch,
  });
}

/// Projectile helpers.
abstract final class SubLevelProjectiles {
  /// `ProjectileMixin#sable$zeroVelocityBeforeShooting`: a projectile fired from
  /// inside a sub-level must leave along the *world* direction, not the local
  /// one.
  static Vector3d shootDirection(SubLevel? containing, Vector3d localDirection) {
    if (containing == null) return Vector3d.copy(localDirection);
    return containing.logicalPose.transformNormal(Vector3d.copy(localDirection));
  }

  /// `ProjectileMixin#sable$shootFromRotation` tail: add the shooter's inherited
  /// velocity to the shot.
  static Vector3d inheritVelocity(Vector3d deltaMovement, Vector3d? inheritedVelocity) {
    if (inheritedVelocity == null) return Vector3d.copy(deltaMovement);
    return Vector3d(
      deltaMovement.x + inheritedVelocity.x,
      deltaMovement.y + inheritedVelocity.y,
      deltaMovement.z + inheritedVelocity.z,
    );
  }

  /// A complete launch: the direction rotated into world space and the inherited
  /// velocity, ready for the plugin to apply to the spawned projectile.
  static ProjectileLaunch launch({
    required SubLevel? containing,
    required Vector3d localDirection,
    required Vector3d? inheritedVelocity,
  }) =>
      ProjectileLaunch(
        shootDirection(containing, localDirection),
        inheritedVelocity,
      );

  /// `AbstractArrowMixin#sable$setDeltaMovement` + `sable$setPosRaw`: the arrow
  /// sticks at the local hit point and pushes the body back.
  ///
  /// Returns `null` when the hit is not inside a sub-level, in which case the
  /// host's own handling is correct.
  ///
  /// [inGround] is `AbstractArrow#isInGround()` *before* the hit is processed;
  /// the Java code skips the impulse for an arrow that is already stuck.
  static ArrowImpact? arrowImpact({
    required SubLevel? containing,
    required Vector3d arrowPosition,
    required Vector3d hitPosition,
    required Vector3d deltaMovement,
    required bool inGround,
    bool clientSide = false,
    double nudge = 0.05,
  }) {
    if (containing == null) return null;

    final localPosition = containing.logicalPose.transformPositionInverse(Vector3d.copy(arrowPosition));
    final diff = Vector3d(
      hitPosition.x - localPosition.x,
      hitPosition.y - localPosition.y,
      hitPosition.z - localPosition.z,
    );

    var impulse = Vector3d();
    if (!clientSide && !inGround) {
      impulse = containing.logicalPose.transformNormalInverse(Vector3d.copy(deltaMovement));
    }

    final length = diff.length;
    final nudgeVector = length == 0
        ? Vector3d()
        : Vector3d(diff.x / length * nudge, diff.y / length * nudge, diff.z / length * nudge);

    final localHit = Vector3d(
      localPosition.x - nudgeVector.x,
      localPosition.y - nudgeVector.y,
      localPosition.z - nudgeVector.z,
    );

    final horizontal = math.sqrt(diff.x * diff.x + diff.z * diff.z);
    return ArrowImpact(
      localImpulse: impulse,
      impulsePoint: localPosition,
      deltaMovement: diff,
      localPosition: localHit,
      yaw: math.atan2(diff.x, diff.z) * 180.0 / math.pi,
      pitch: math.atan2(diff.y, horizontal) * 180.0 / math.pi,
    );
  }

  /// `ProjectileDispenseBehaviorMixin`: a dispenser inside a sub-level pushes
  /// the ship backwards when it fires.
  ///
  /// [direction] is the dispenser's facing as a unit vector; the impulse is
  /// `-1.5` along it, applied at [position] in the plot's coordinates.
  static Vector3d dispenserRecoil(Vector3d direction, {double magnitude = 1.5}) =>
      Vector3d(-direction.x * magnitude, -direction.y * magnitude, -direction.z * magnitude);
}
