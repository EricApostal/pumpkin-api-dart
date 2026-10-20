// The steering wheel's angle state machine, kept apart from the kinetic block
// entity so it runs on the VM in tests.
//
// The wheel turns itself to a target angle at a fixed speed, reports that as
// generated rotation while it turns, and stops when it arrives. The direction of
// the generated rotation depends on the wheel's facing and whether it is mounted
// on the floor or the ceiling, so a wheel on the left of the ship turns the ship
// the same way as one on the right.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.content.blocks.steering_wheel.SteeringWheelBlockEntity
// create/sable internals are not exported from their barrels yet.
// ignore_for_file: implementation_imports

import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/kinetics/settings.dart' show convertToAngular;

/// The angle machine of one steering wheel.
final class SteeringWheelLogic {
  /// The speed the wheel turns at, in RPM.
  static const int rpm = 16;

  /// The largest angle the value box allows, in degrees.
  static const double maxAngleLimit = 360;

  /// The angle the wheel is at, in degrees.
  double angle = 0;

  /// The angle the player asked for, in degrees.
  double targetAngle = 0;

  /// The angle last sent by the client (may lead [targetAngle] while held).
  double targetAngleToUpdate = 0;

  /// The angle limit set with the value box, in degrees.
  double angleLimit = 180;

  /// Ticks left of the current turn.
  int inUse = 0;

  /// The angular distance the current turn may still cover.
  double sequencedAngleLimit = 0;

  /// The speed the wheel reports to its kinetic network.
  double generatedSpeed = 0;

  /// The speed the wheel turns itself at.
  double logicalSpeed = 0;

  /// Whether a player is holding the wheel.
  bool held = false;

  /// The steering input, in `[-1, 1]`: the target angle relative to the limit.
  double get steeringInput => (targetAngleToUpdate / angleLimit).clamp(-1.0, 1.0);

  /// `directionConvert(val)`: the sign of a value around the wheel's axis.
  double directionConvert(double value, Direction facing) =>
      -steeringDirection(value, facing);

  /// `updateTargetAngle(absoluteTarget)`.
  ///
  /// [facing] and [onFloor] decide the sign of the generated speed.
  void updateTargetAngle(
    double absoluteTarget, {
    required Direction facing,
    required bool onFloor,
  }) {
    absoluteTarget = absoluteTarget.clamp(-angleLimit, angleLimit);
    if (targetAngle == absoluteTarget) return;

    targetAngle = absoluteTarget;
    final relativeAngle = absoluteTarget - angle;

    if (relativeAngle.abs() < 0.001 && inUse <= 0) {
      generatedSpeed = 0;
      return;
    }

    final rotationSpeed = rpm * relativeAngle.sign;
    if (rotationSpeed == 0) return;

    final relativeValue = relativeAngle / rotationSpeed;
    if (relativeValue <= 0 && inUse <= 0) {
      generatedSpeed = 0;
      return;
    }

    final degreesPerTick = convertToAngular(rotationSpeed);
    inUse = (relativeAngle / degreesPerTick).ceil() + 2;
    sequencedAngleLimit = relativeAngle.abs();
    logicalSpeed = rotationSpeed;

    final horizontal = facing == Direction.north || facing == Direction.west;
    generatedSpeed = (horizontal == onFloor) ? -logicalSpeed : logicalSpeed;
  }

  /// `tick()`: integrate the angle and run down the turn timer.
  ///
  /// Returns true when the turn finished this tick (the network needs an update).
  bool tick({required Direction facing, required bool onFloor}) {
    var finished = false;

    if (generatedSpeedForOutput != 0) integrateAngle();

    if (inUse > 0) {
      inUse--;
      if (inUse == 0) {
        sequencedAngleLimit = 0;
        generatedSpeed = 0;
        finished = true;
      }
    } else {
      updateTargetAngle(targetAngleToUpdate, facing: facing, onFloor: onFloor);
    }

    return finished;
  }

  /// `getGeneratedSpeed()`: zero once the turn is over.
  double get generatedSpeedForOutput => inUse == 0 ? 0 : generatedSpeed;

  /// `getLogicalSpeed()`.
  double get logicalSpeedForOutput => inUse == 0 ? 0 : logicalSpeed;

  /// `getAngularSpeed()`: degrees per tick.
  double get angularSpeed {
    if (inUse == 0) return 0;
    return convertToAngular(logicalSpeed);
  }

  /// `integrateAngle()`: advance the angle by the angular speed, limited by the
  /// sequenced angle limit.
  void integrateAngle() {
    var speed = angularSpeed;
    if (sequencedAngleLimit >= 0) {
      speed = speed.clamp(-sequencedAngleLimit, sequencedAngleLimit);
      sequencedAngleLimit -= speed.abs();
      if (sequencedAngleLimit < 0) sequencedAngleLimit = 0;
    }
    angle += speed;
  }

  /// The comparator output read from [side] (`getAnalogOutputSignalFrom`).
  ///
  /// The facing side reports "held", the two sides next to it report the
  /// steering input as a redstone level.
  int analogOutput(Direction facing, Direction side) {
    if (facing == side) return held ? 15 : 0;
    if (angle.abs() < 0.99) return 0;

    final frac = (targetAngleToUpdate / angleLimit).clamp(-1.0, 1.0);
    final sign = (facing.stepX == 1 || facing.stepZ == 1) ? -1 : 1;
    final value = (frac < 0 ? (frac * 15).floor() : (frac * 15).ceil()) * sign;

    if (facing.clockWise == side && value > 0) return value;
    if (facing.counterClockWise == side && value < 0) return -value;
    return 0;
  }

  /// `write()`: the saved fields.
  Map<String, Object?> write() => {
    'Angle': angle,
    'TargetAngle': targetAngle,
    if (targetAngleToUpdate != targetAngle) 'TargetAngleToUpdate': targetAngleToUpdate,
    'InUse': inUse,
    'SequencedAngleLimit': sequencedAngleLimit,
    'GeneratedSpeed': generatedSpeed,
  };

  /// `read()`.
  void read(Map<String, Object?> tag) {
    angle = _double(tag['Angle']);
    targetAngle = _double(tag['TargetAngle']);
    targetAngleToUpdate = tag.containsKey('TargetAngleToUpdate')
        ? _double(tag['TargetAngleToUpdate'])
        : targetAngle;
    inUse = _int(tag['InUse']);
    sequencedAngleLimit = _double(tag['SequencedAngleLimit']);
    generatedSpeed = _double(tag['GeneratedSpeed']);
  }

  static double _double(Object? value) => value is num ? value.toDouble() : 0;

  static int _int(Object? value) => value is num ? value.toInt() : 0;
}

/// `KineticBlockEntity.convertToDirection` for the steering wheel's facing: a
/// wheel whose facing points along a negative axis turns the other way.
double steeringDirection(double value, Direction facing) =>
    (facing.stepX + facing.stepY + facing.stepZ) > 0 ? value : -value;
