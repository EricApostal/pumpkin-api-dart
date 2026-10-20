// `dev.simulated_team.simulated.api.BearingSlowdownController`: the easing curve
// a bearing uses to bring a contraption to rest on a symmetry-aligned angle.
//
// The maths is the Java maths, including the constants: the controller predicts
// where a constant-speed turn would stop, rounds that to the nearest symmetry
// angle, and interpolates towards it with a `(1 - t)^SMOOTHING_FACTOR` curve.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.api.BearingSlowdownController
import 'dart:math' as math;

import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart' show Pos;

/// How many symmetries a contraption has around the bearing axis.
///
/// Java: `BearingSlowdownController.ContraptionSymmetry`
enum ContraptionSymmetry {
  /// No symmetry: a full turn is the smallest repeat.
  none(360),

  /// Half turn.
  half(180),

  /// Quarter turn.
  quarter(90);

  const ContraptionSymmetry(this.angle);

  /// The smallest repeat angle, in degrees.
  final double angle;
}

/// The slowdown controller.
///
/// Java: `BearingSlowdownController`
final class BearingSlowdownController {
  /// How strongly the curve leans towards the target angle.
  static const double timerScale = 3.5;

  /// The exponent of the easing curve.
  static const double smoothingFactor = 2.5;

  /// The longest slowdown, in ticks.
  static const double maxTicks = 30;

  double _maxTime = 0;
  double _initialVelocity = 0;
  double _clampedTime = 0;
  double _countdown = 0;
  double _initialAngle = 0;
  ContraptionSymmetry _symmetry = ContraptionSymmetry.none;
  double _linearDistance = 0;
  double _scaledOffset = 0;
  double _targetStoppingPoint = 0;
  double _angleOffset = 0;

  BearingSlowdownController();

  /// The maximum slowdown time, after the symmetry scaling.
  double get maxTime => _maxTime;

  /// The initial velocity, in degrees per tick.
  double get initialVelocity => _initialVelocity;

  /// The time left, in ticks.
  double get countdown => _countdown;

  /// The symmetry the controller was generated for.
  ContraptionSymmetry get symmetry => _symmetry;

  /// The angle the contraption stops at.
  double get targetStoppingPoint => _targetStoppingPoint;

  /// `generate(maxTime, initialAngle, initialVelocity, facing, blocks)`.
  void generateFromBlocks({
    required double maxTime,
    required double initialAngle,
    required double initialVelocity,
    required Direction facingDirection,
    required Map<Pos, String> blocks,
  }) => generate(
    maxTime: maxTime,
    initialAngle: initialAngle,
    initialVelocity: initialVelocity,
    symmetry: symmetryOf(blocks, facingDirection),
  );

  /// `generate(maxTime, initialAngle, initialVelocity, symmetry)`.
  void generate({
    required double maxTime,
    required double initialAngle,
    required double initialVelocity,
    required ContraptionSymmetry symmetry,
  }) {
    _maxTime = math.min(maxTime, maxTicks);
    _symmetry = symmetry;
    _initialAngle = initialAngle;
    _initialVelocity = initialVelocity;

    _maxTime = maxTime * math.sqrt(symmetry.angle / 90);
    _maxTime = math.min(_maxTime, maxTicks);

    _generateConstants();
    _applyVelocityClamping();
    _countdown = _clampedTime;
  }

  /// `getSymmetry(facingDirection, attachedContraption)`: whether the blocks
  /// repeat after a quarter turn and/or a half turn around [facingDirection].
  static ContraptionSymmetry symmetryOf(Map<Pos, String> blocks, Direction facingDirection) {
    var halfSymmetry = true;
    var quarterSymmetry = true;

    for (final entry in blocks.entries) {
      final current = entry.value;
      final r1 = rotate90(entry.key, facingDirection);
      final r2 = rotate90(r1, facingDirection);

      if (blocks[r1] != current) quarterSymmetry = false;
      if (blocks[r2] != current) halfSymmetry = false;
    }

    if (quarterSymmetry) return ContraptionSymmetry.quarter;
    if (halfSymmetry) return ContraptionSymmetry.half;
    return ContraptionSymmetry.none;
  }

  /// `Rotate90`: a quarter turn of [pos] around [dir], about the origin.
  static Pos rotate90(Pos pos, Direction dir) {
    final x1 = pos.$1;
    final y1 = pos.$2;
    final z1 = pos.$3;

    final x2 = dir.stepX;
    final y2 = dir.stepY;
    final z2 = dir.stepZ;
    final dotProduct = x1 * x2 + y1 * y2 + z1 * z2;

    return (
      y1 * z2 - z1 * y2 + dotProduct * x2,
      z1 * x2 - x1 * z2 + dotProduct * y2,
      x1 * y2 - y1 * x2 + dotProduct * z2,
    );
  }

  void _generateConstants() {
    final symmetryAngle = _symmetry.angle;
    // Distance the contraption travels if it never slows down.
    _linearDistance = _maxTime * _initialVelocity;
    // Where it would stop if it slowed down at the optimal rate.
    final optimalStoppingPoint = _initialAngle + _linearDistance / smoothingFactor;
    // Rounded to the nearest angle the symmetry allows.
    _targetStoppingPoint = symmetryAngle * (optimalStoppingPoint / symmetryAngle).roundToDouble();
    // The angular distance left to travel.
    _angleOffset = _initialAngle - _targetStoppingPoint;
    _scaledOffset = _angleOffset * smoothingFactor + _linearDistance;
  }

  void _applyVelocityClamping() {
    // Shorten the animation when the curve's peak velocity is too low.
    final maxVelocity = _maxVelocity();
    final targetVelocityClamp = 120 / _maxTime;
    if (maxVelocity < targetVelocityClamp) {
      _clampedTime = _maxTime * maxVelocity / targetVelocityClamp;
      _clampedTime = math.max(_clampedTime, 2);
      _linearDistance = _clampedTime * _initialVelocity;
    } else {
      _clampedTime = _maxTime;
    }
  }

  double _maxVelocity() {
    final a = (1 + smoothingFactor) * _angleOffset + _linearDistance;
    final b = (1 + smoothingFactor) * (smoothingFactor * _angleOffset + _linearDistance);
    final normalizedTimeAtMaxVelocity = (a + _linearDistance) / b;

    var maxVelocity = _initialVelocity.abs();
    if (b.abs() > 0.001 &&
        normalizedTimeAtMaxVelocity > 0 &&
        normalizedTimeAtMaxVelocity < 1) {
      // Velocity at the inflection point of the curve.
      var estimatedTurnaroundVelocity =
          -a * math.pow((smoothingFactor - 1) * a / b, smoothingFactor - 1) / _maxTime;
      estimatedTurnaroundVelocity = estimatedTurnaroundVelocity.abs();
      maxVelocity = math.max(estimatedTurnaroundVelocity, maxVelocity);
    }
    return maxVelocity;
  }

  /// The time elapsed, in ticks.
  double get time => _clampedTime - _countdown;

  /// Advances the countdown by one tick; true when the goal is reached.
  bool stepGoal() {
    if (_countdown > 0) {
      _countdown--;
      if (_countdown <= 0.5) {
        _countdown = 0;
        return true;
      }
    }
    return false;
  }

  /// The angle at [partialTick].
  double angle(double partialTick) {
    final t = time + partialTick;
    if (t >= _clampedTime) return _targetStoppingPoint;
    final normalizedTime = t / _clampedTime;
    final lerpParameter = math.pow(1 - normalizedTime, smoothingFactor).toDouble();
    return _targetStoppingPoint + (_angleOffset + normalizedTime * _scaledOffset) * lerpParameter;
  }

  /// The angular velocity at [partialTick].
  double speed(double partialTick) {
    final t = time + partialTick;
    if (t >= _clampedTime) return 0;
    final normalizedTime = t / _clampedTime;
    final lerpDerivative = math.pow(1 - normalizedTime, smoothingFactor - 1).toDouble();
    return (_linearDistance - (1 + smoothingFactor) * normalizedTime * _scaledOffset) *
        lerpDerivative /
        _clampedTime;
  }

  /// Restores the controller from saved data.
  void read(Map<String, Object?> tag) {
    _countdown = _float(tag['CurrentTime']);
    _maxTime = _float(tag['DisassemblyTimerTotal']);
    final symmetryIndex = _int(tag['Symmetry']);
    _symmetry = symmetryIndex >= 0 && symmetryIndex < ContraptionSymmetry.values.length
        ? ContraptionSymmetry.values[symmetryIndex]
        : ContraptionSymmetry.none;
    _initialAngle = _float(tag['InitialSlowdownAngle']);
    _initialVelocity = _float(tag['InitialSlowdownVelocity']);
    _generateConstants();
    _applyVelocityClamping();
  }

  /// Writes the controller to saved data.
  Map<String, Object?> write() => {
    'CurrentTime': _countdown,
    'DisassemblyTimerTotal': _maxTime,
    'Symmetry': _symmetry.index,
    'InitialSlowdownAngle': _initialAngle,
    'InitialSlowdownVelocity': _initialVelocity,
  };

  static double _float(Object? value) => value is num ? value.toDouble() : 0;

  static int _int(Object? value) => value is num ? value.toInt() : 0;
}
