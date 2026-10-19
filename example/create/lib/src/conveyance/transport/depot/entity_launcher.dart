// `EntityLauncher` (pure): the projectile trajectory of the weighted ejector, a line by line port
// of Create's class (the iterative motion of `LivingEntity.travel`).
import 'dart:math' as math;

import '../../../common/direction.dart';
import '../../../common/pos.dart';
import '../../../common/vec_helper.dart';

/// `EntityLauncher`.
class EntityLauncher {
  int horizontalDistance = 0;
  int verticalDistance = 0;

  double _yMotion = 0;
  double _xMotion = 0;
  double _totalFlyingTicks = 0;

  EntityLauncher(int horizontalDistance, int verticalDistance) {
    set(horizontalDistance, verticalDistance);
  }

  void clamp(int max) {
    set(
      math.min(horizontalDistance, max),
      verticalDistance.sign * math.min(verticalDistance.abs(), max),
    );
  }

  void set(int horizontalDistance, int verticalDistance) {
    this.horizontalDistance = horizontalDistance;
    this.verticalDistance = verticalDistance;
    _recalculateTrajectory();
  }

  int getHorizontalDistance() => horizontalDistance;

  int getVerticalDistance() => verticalDistance;

  double getTotalFlyingTicks() => _totalFlyingTicks;

  Vec3 getGlobalPos(double t, Direction d, Pos launcher) {
    final start = (launcher.$1 + 0.5, launcher.$2 + 0.5, launcher.$3 + 0.5);
    final xt = x(t);
    final yt = y(t);
    final progress = (t / getTotalFlyingTicks()).clamp(0.0, 1.0);
    final correctionStrength = math.pow(progress, 3).toDouble();
    final vec = (
      0.0,
      yt + (verticalDistance - yt) * correctionStrength * 0.5,
      xt + (horizontalDistance - xt) * correctionStrength,
    );
    final rotated = VecHelper.rotate(
      vec,
      180 + AngleHelper.horizontalAngle(d),
      Axis.y,
    );
    return (
      rotated.$1 + start.$1,
      rotated.$2 + start.$2,
      rotated.$3 + start.$3,
    );
  }

  Vec3 getGlobalVelocity(double t, Direction d, Pos launcher) =>
      VecHelper.rotate(
        (0.0, dy(t), dx(t)),
        180 + AngleHelper.horizontalAngle(d),
        Axis.y,
      );

  /// `EntityLauncher.applyMotion`: the velocity a living entity gets when it is launched.
  Vec3 motionFor(Direction facing) {
    final motion = VecHelper.rotate(
      (0.0, _yMotion, _xMotion),
      AngleHelper.horizontalAngle(facing),
      Axis.y,
    );
    return (motion.$1 * .91, motion.$2 * .98, motion.$3 * .91);
  }

  double x(double t) =>
      (_xMotion * -10.6033 * (-1 + math.pow(0.91, t))).toDouble();

  double y(double t) {
    final f = math.pow(0.98, t);
    return (_yMotion * -49.4983 * f +
            49.4983 * _yMotion -
            194.033 * f -
            3.92 * t +
            194.033)
        .toDouble();
  }

  double dx(double t) => (_xMotion * math.pow(0.91, t)).toDouble();

  double dy(double t) {
    final f = math.pow(0.98, t);
    return (_yMotion * f + ((f - 1) / (0.98 - 1)) * -0.0784).toDouble();
  }

  void _recalculateTrajectory() {
    final xTarget = horizontalDistance.toDouble();
    final yTarget = verticalDistance.toDouble();

    final xError =
        (-0.0007 * math.pow(xTarget + .5, 2) + 0.484) -
        (math.min(5, yTarget) / 5) *
            math.min(1, 0.076 * xTarget - 0.0014 * xTarget * xTarget);

    final yPeak =
        math.max(0, yTarget + (xTarget + .5) / 8) + (xTarget <= 1 ? 1 : 4);
    _yMotion = math.sqrt(2 * yPeak / 13) + 0.015 * yPeak;
    final tPeak =
        math.log(98 / (25 * _yMotion + 98)) /
        (2 * math.log(7) - 2 * math.log(5) - math.log(2));
    _totalFlyingTicks =
        math.sqrt(yPeak - _yMotion) * 4.87 + 0.115 * (yPeak - _yMotion) + tPeak;
    _xMotion =
        ((xTarget - xError + .5) /
                (-10.6033 * (-1 + math.pow(0.91, _totalFlyingTicks))))
            .toDouble();
  }
}
