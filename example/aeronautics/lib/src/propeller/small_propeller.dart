// The maths of the small propellers (wooden, andesite, smart): the rotation
// ramp, the airflow and thrust they produce, and the smart propeller's hinge.
//
// Java: `content/blocks/propeller/small/{BasePropellerBlockEntity,smart_propeller/SmartPropellerBlockEntity}`.
//
// The small propellers sit on a shaft, so their speed comes straight from the
// kinetic network; a smart propeller additionally tilts with the sub-level's
// orientation, which changes its thrust direction.
//
// Pure: no host imports.
// ignore_for_file: implementation_imports
import 'dart:math' as math;

import 'package:create/src/common/direction.dart' show Axis, AxisDirection, Direction;
import 'package:create/src/kinetics/settings.dart' show convertToAngular;
import 'package:sable/sable.dart' show Matrix3d, Quaterniond, Vector3d;

import 'geometry.dart';

/// `BasePropellerBlockEntity`, server side.
final class SmallPropellerLogic {
  /// How quickly the propeller reaches the shaft speed.
  static const double rotationLerp = 0.15;

  /// The current rotation speed, in degrees per tick.
  double rotationSpeed = 0;

  /// The angle last tick (client smoothing).
  double previousAngle = 0;

  /// The angle this tick.
  double angle = 0;

  /// The facing of the block.
  Direction facing = Direction.up;

  /// Whether the wrench reversed the propeller.
  bool reversed = false;

  /// `updateRotationSpeed`.
  void updateRotationSpeed(double inputSpeed) {
    var nextSpeed = convertToAngular(inputSpeed);
    if (inputSpeed == 0) nextSpeed = 0;
    rotationSpeed = rotationSpeed + (nextSpeed - rotationSpeed) * rotationLerp;
  }

  /// `tick`: advance the angle.
  void tick() {
    previousAngle = angle;
    angle += rotationSpeed;
  }

  /// `getDirectionIndependentSpeed`.
  double get directionIndependentSpeed {
    final axisStep = facing.axisDirection == AxisDirection.positive ? 1.0 : -1.0;
    final direction = reversed ? -1.0 : 1.0;
    return axisStep * rotationSpeed * (10 / 3) * direction;
  }

  /// `getAirflow`.
  double airflow(double configAirflow) => configAirflow * directionIndependentSpeed;

  /// `getThrust`.
  double thrust(double configThrust) => configThrust * directionIndependentSpeed;

  /// `isActive`.
  bool get isActive => rotationSpeed.abs() > 0.01;
}

/// `SmartPropellerBlockEntity`, server side.
final class SmartPropellerLogic extends SmallPropellerLogic {
  /// The hinge angle, in degrees; starts at 180 for a ceiling mount.
  double hingeAngle = 0;

  /// The target the hinge eases towards.
  double hingeTarget = 0;

  /// The horizontal axis of the block.
  Axis horizontalAxis = Axis.x;

  /// Whether the propeller hangs from the ceiling.
  bool ceiling = false;

  /// The thrust direction, in the sub-level's frame.
  final Vector3d thrustDir = Vector3d();

  /// `setThrustDirection`: the thrust is up, tilted by the hinge.
  void updateThrustDirection() {
    final direction = hingeDirection(horizontalAxis);
    final rotation = Quaterniond().fromAxisAngle(
      Vector3d(direction.stepX.toDouble(), direction.stepY.toDouble(), direction.stepZ.toDouble()),
      -hingeAngle * math.pi / 180.0,
    );
    thrustDir.set(0, 1, 0);
    rotation.transform(thrustDir, thrustDir);
  }

  /// `getHingeAngle`: the pitch of the sub-level around the hinge axis, clamped
  /// to 45 degrees.
  ///
  /// [orientation] is the orientation of the sub-level the propeller is on, or
  /// `null` when it is not on one (then the hinge stays at its mount angle).
  void updateHingeAngle(Quaterniond? orientation) {
    if (orientation == null) {
      hingeTarget = ceiling ? 180 : 0;
      return;
    }

    final pendulum = Quaterniond.copy(orientation);
    if (horizontalAxis == Axis.z) {
      pendulum.mul(Quaterniond().fromAxisAngle(Vector3d(0, 1, 0), math.pi / 2));
    }

    final matrix = Matrix3d().setFromQuaternion(pendulum);
    final pitch = math.atan2(matrix.m01, matrix.m11);
    var angle = -pitch * 180 / math.pi;

    if (horizontalAxis == Axis.x) angle *= -1;

    angle = angle.clamp(-45.0, 45.0);
    if (ceiling) angle = 180 - angle;

    hingeTarget = angle;
  }

  /// `tickChaser` with the linear chase the Java block entity uses.
  void tickHinge(double chaseFactor) {
    hingeAngle += (hingeTarget - hingeAngle) * chaseFactor;
  }
}
