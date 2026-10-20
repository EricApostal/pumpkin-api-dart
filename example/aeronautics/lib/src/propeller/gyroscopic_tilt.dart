// The gyroscopic propeller bearing's tilt: the propeller hangs like a pendulum
// and swings to align with gravity, within 12 degrees of its mount.
//
// Java: `content/blocks/propeller/bearing/gyroscopic_propeller_bearing/GyroscopicPropellerBearingBlockEntity`.
//
// The tilt is a unit vector; the quaternion is the shortest rotation from the
// block's facing to that vector, which the contraption entity uses to render
// the contraption. A redstone signal locks the tilt to the mount.
//
// Pure: no host imports.
// ignore_for_file: implementation_imports
import 'dart:math' as math;

import 'package:create/src/common/direction.dart' show Direction;
import 'package:sable/sable.dart' show Quaterniond, Vector3d;

import 'geometry.dart';

/// `GyroscopicPropellerBearingBlockEntity`'s tilt state.
final class GyroscopicTilt {
  /// The maximum swing away from the mount, in radians.
  static const double maxConeAngle = 12 * math.pi / 180;

  /// The normal of the bearing's facing.
  final Vector3d blockNormal = Vector3d();

  /// The current tilt, a unit vector.
  final Vector3d tiltVector = Vector3d(0, 1, 0);

  /// The rotation from [blockNormal] to [tiltVector].
  final Quaterniond tiltQuat = Quaterniond();

  /// The rotation last tick (client smoothing).
  final Quaterniond previousTiltQuat = Quaterniond();

  /// Whether a redstone signal locks the tilt.
  bool powered = false;

  /// Whether the tilt was set at least once.
  bool initialized = false;

  /// The length of the gravity vector at the bearing.
  double currentGravity = 0;

  /// The physics time since the last game tick, in ticks.
  double physicsTimer = 0;

  /// Sets the block normal from [facing].
  void setFacing(Direction facing) {
    blockNormal.set(facing.stepX.toDouble(), facing.stepY.toDouble(), facing.stepZ.toDouble());
  }

  /// Initializes the tilt to the mount on the first tick.
  void initializeIfNeeded(Direction facing) {
    setFacing(facing);
    if (initialized) return;
    tiltVector.setFrom(blockNormal);
    initialized = true;
    applyTilt();
  }

  /// `forceTilt`: jumps the tilt to the mount (after a wrench).
  void forceTilt(Direction facing) {
    setFacing(facing);
    tiltVector.setFrom(blockNormal);
    applyTilt();
    previousTiltQuat.setFrom(tiltQuat);
  }

  /// `updateTilt`: swings towards the gravity direction (or the mount when
  /// powered).
  ///
  /// [subLevelOrientation] is the orientation of the sub-level, or `null` when
  /// the bearing is not on one; [gravity] is the gravity vector at the bearing.
  void updateTilt(
    Vector3d tilt,
    Quaterniond? subLevelOrientation,
    Vector3d gravity,
    double stepScale,
  ) {
    currentGravity = gravity.length;

    final target = Vector3d();
    if (currentGravity > 0 && subLevelOrientation != null) {
      target.setFrom(gravity).mul(-1 / currentGravity);
      subLevelOrientation.transformInverse(target, target);
    } else {
      target.setFrom(blockNormal);
    }

    setTilt(tilt, target, 0.05 * stepScale, lerpDistance: 1);
  }

  /// `setTilt`: clamps [target] into the cone and steps [tilt] towards it.
  void setTilt(Vector3d tilt, Vector3d target, double maxStep, {required double lerpDistance}) {
    if (powered) target.setFrom(blockNormal);

    clampIntoCone(target, blockNormal, maxConeAngle);
    target.lerp(blockNormal, 1 - lerpDistance);

    final difference = Vector3d.copy(target).sub(tilt);
    if (difference.lengthSquared > maxStep * maxStep) {
      tilt.add(difference.normalize().mul(maxStep));
    } else {
      tilt.setFrom(target);
    }
  }

  /// `getLerpDistance`: how strongly the tilt follows the target. A bearing
  /// with no contraption, at low speed or winding down, holds its tilt.
  double lerpDistance({
    required bool hasContraption,
    required double speed,
    required bool disassemblySlowdown,
    double countdownRatio = 1,
  }) {
    var distance = hasContraption ? 1.0 : 0.0;
    if (speed.abs() < 1) distance *= speed.abs();
    if (disassemblySlowdown) distance *= countdownRatio;
    return distance;
  }

  /// `applyTilt`: recomputes the quaternion and the thrust direction.
  void applyTilt() {
    tiltVector.normalize();
    rotationBetween(blockNormal, tiltVector, tiltQuat);
    previousTiltQuat.setFrom(tiltQuat);
  }

  /// The thrust direction the physics tick uses.
  Vector3d get thrustDirection => tiltVector;
}
