// The swivel bearing: a kinetic bearing that assembles the structure in front of
// it into a sub-level, then holds that sub-level with a hinge.
//
// The bearing's cogwheel drives the target angle; a redstone signal locks the
// hinge. While locked, the hinge's motor is a PD controller whose gains scale
// with the two bodies' inertia around the hinge axis, so a heavy ship and a light
// one settle at the same rate.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.content.blocks.swivel_bearing.SwivelBearingBlockEntity
import 'dart:math' as math;

import 'package:sable/sable.dart' show Quaterniond, Vector3d;

/// The redstone behaviour of the bearing (`LockingSetting`).
enum SwivelLockingSetting {
  lockedAlways,
  lockedDefault,
  unlockedDefault,
  unlockedAlways;

  /// `shouldLock(signal)`.
  bool shouldLock(int signal) => switch (this) {
    SwivelLockingSetting.unlockedAlways => false,
    SwivelLockingSetting.lockedAlways => true,
    SwivelLockingSetting.lockedDefault => signal > 0,
    SwivelLockingSetting.unlockedDefault => signal <= 0,
  };

  /// The translation key suffix (`simulated.generic.<name>`).
  String get translationKey => switch (this) {
    SwivelLockingSetting.lockedAlways => 'simulated.generic.swivel_default_always_locked',
    SwivelLockingSetting.lockedDefault => 'simulated.generic.swivel_default_locked',
    SwivelLockingSetting.unlockedDefault => 'simulated.generic.swivel_default_unlocked',
    SwivelLockingSetting.unlockedAlways => 'simulated.generic.swivel_default_always_unlocked',
  };

  static SwivelLockingSetting of(int value) =>
      value >= 0 && value < values.length ? values[value] : lockedDefault;
}

/// The hinge motor the bearing asks for.
final class SwivelMotorSettings {
  /// The target angle, in radians.
  final double goal;

  /// The proportional gain.
  final double stiffness;

  /// The derivative gain.
  final double damping;

  const SwivelMotorSettings(this.goal, this.stiffness, this.damping);
}

/// The state of one swivel bearing.
final class SwivelBearingLogic {
  /// The smallest inertia the gains are computed with.
  static const double minimumInertia = 10;

  /// The target angle, in degrees, from the last tick.
  double lastTargetAngleDegrees = 0;

  /// The target angle, in degrees.
  double targetAngleDegrees = 0;

  /// The angle limit from a sequenced context (negative: none).
  double sequencedAngleLimit = -1;

  /// The locking setting.
  SwivelLockingSetting lockingSetting = SwivelLockingSetting.lockedDefault;

  /// Whether the bearing is assembled.
  bool assembled = false;

  /// Whether the bearing is locked (its `powered` state).
  bool locking = false;

  /// `limitCogSpeed(speed)`: the cogwheel speed clamped to the config.
  static double limitSpeed(double speed, {required double maxSwivelRpm}) =>
      speed.clamp(-maxSwivelRpm, maxSwivelRpm);

  /// `tick()`: advance the target angle.
  ///
  /// [cogSpeed] is the cogwheel's speed in RPM, [facing] the bearing's facing
  /// name, [physicsPaused] whether the physics is paused, and [sequenced] whether
  /// a sequencer drives the bearing. Returns the new target angle in degrees.
  double tick({
    required double cogSpeed,
    required String facing,
    required bool physicsPaused,
    required bool sequenced,
    required double maxSwivelRpm,
  }) {
    lastTargetAngleDegrees = targetAngleDegrees;

    var angularSpeed = cogSpeed / 60 / 20 * 360;
    var shouldUpdateAngle = assembled;

    if (sequencedAngleLimit >= 0) {
      angularSpeed = angularSpeed.clamp(-sequencedAngleLimit, sequencedAngleLimit);
      sequencedAngleLimit = math.max(0, sequencedAngleLimit - angularSpeed.abs());
    } else if (physicsPaused && !sequenced) {
      shouldUpdateAngle = false;
    }

    if (shouldUpdateAngle) {
      // A bearing whose facing points along a negative axis turns the other way.
      final negativeFacing = facing == 'down' || facing == 'north' || facing == 'west';
      if (negativeFacing) angularSpeed = -angularSpeed;

      // Java's `%` keeps the sign; Dart's does not.
      targetAngleDegrees = (targetAngleDegrees + angularSpeed).remainder(360);
    }

    return targetAngleDegrees;
  }

  /// `updateServoCoefficients`: the hinge motor for the current state.
  ///
  /// [inertiaA] and [inertiaB] are the two bodies' inertia around the hinge
  /// axis; pass `null` for a body that is not a sub-level.
  SwivelMotorSettings? motorFor({
    required bool hasHandle,
    required double partialTick,
    required double? inertiaA,
    required double? inertiaB,
    required double stiffness,
    required double damping,
    required double friction,
  }) {
    if (!assembled || !hasHandle) return null;

    if (!locking) {
      // Unlocked: passive damping only.
      return SwivelMotorSettings(0, 0, friction);
    }

    final a = inertiaA ?? double.maxFinite;
    final b = inertiaB ?? double.maxFinite;
    final both = inertiaA != null && inertiaB != null;
    final totalInertia = math.max(minimumInertia, both ? math.max(a, b) : math.min(a, b));

    final goal = angleLerp(partialTick, lastTargetAngleDegrees, targetAngleDegrees) * math.pi / 180.0;
    return SwivelMotorSettings(goal, stiffness * totalInertia, damping * totalInertia);
  }

  /// `setTargetAngleFromCurrentOrientation`: keep the angle the bearing is at when
  /// it starts locking.
  ///
  /// [orientationA] is the containing sub-level's orientation (identity when the
  /// bearing is in the world), [blockOrientationA] the bearing block's rotation,
  /// [orientationB] the attached sub-level's orientation and [blockOrientationB]
  /// the plate's rotation.
  void setTargetAngleFromCurrentOrientation({
    required Quaterniond orientationA,
    required Quaterniond blockOrientationA,
    required Quaterniond orientationB,
    required Quaterniond blockOrientationB,
  }) {
    final localB = Quaterniond.copy(orientationA)
        .mul(blockOrientationA)
        .conjugate()
        .mul(Quaterniond.copy(orientationB).mul(blockOrientationB));

    final d = localB.y;
    final currentAngle = -2.0 * math.atan2(-d, localB.w) * 180 / math.pi;
    targetAngleDegrees = currentAngle;
    lastTargetAngleDegrees = currentAngle;
  }

  /// `read`.
  void read({required double targetAngle, required bool assembled}) {
    targetAngleDegrees = targetAngle;
    lastTargetAngleDegrees = targetAngle;
    this.assembled = assembled;
  }

  /// `write`.
  Map<String, Object?> write() => {
    'TargetAngle': targetAngleDegrees,
    if (sequencedAngleLimit >= 0) 'SequencedAngleLimit': sequencedAngleLimit,
  };
}

/// `AngleHelper.angleLerp(partialTick, from, to)`: the shortest way around.
double angleLerp(double partialTick, double from, double to) {
  var delta = to - from;
  delta %= 360;
  if (delta > 180) delta -= 360;
  if (delta < -180) delta += 360;
  return from + delta * partialTick;
}

/// The position of the hinge anchor of a bearing at [pos] facing [facing].
Vector3d hingeAnchor((int, int, int) pos, String facing) {
  final (dx, dy, dz) = switch (facing) {
    'down' => (0, -1, 0),
    'up' => (0, 1, 0),
    'north' => (0, 0, -1),
    'south' => (0, 0, 1),
    'west' => (-1, 0, 0),
    'east' => (1, 0, 0),
    _ => (0, 1, 0),
  };
  return Vector3d(pos.$1 + dx + 0.5, pos.$2 + dy + 0.5, pos.$3 + dz + 0.5);
}
