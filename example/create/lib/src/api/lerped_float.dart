// `LerpedFloat` of catnip (pure): a float that chases a target, used by animations that the
// server also tracks (sliding doors, whistles, ...).
import '../common/direction.dart' show toFloat, mthEqual;

/// How a [LerpedFloat] approaches its target (`LerpedFloat.Chaser`).
typedef Chaser = double Function(double current, double speed, double target);

abstract final class Chasers {
  /// `Chaser.IDLE`.
  static double idle(double c, double s, double t) => c;

  /// `Chaser.LINEAR`: moves by at most `speed` per tick.
  static double linear(double c, double s, double t) => toFloat(c + (t - c).clamp(-s, s));

  /// `Chaser.EXP`: moves by `speed` times the remaining distance.
  static double exp(double c, double s, double t) => toFloat(c + ((t - c) * s));
}

/// A linearly interpolated value that can chase a target.
final class LerpedFloat {
  double previousValue = 0;
  double value = 0;
  double chaseTarget = 0;
  double chaseSpeed = 0;
  Chaser? chaseFunction;

  LerpedFloat.linear();

  /// `startWithValue`.
  LerpedFloat startWithValue(double v) {
    final f = toFloat(v);
    previousValue = f;
    chaseTarget = f;
    value = f;
    return this;
  }

  /// `chase(value, speed, chaser)`.
  LerpedFloat chase(double target, double speed, Chaser chaser) {
    chaseTarget = toFloat(target);
    chaseSpeed = toFloat(speed);
    chaseFunction = chaser;
    return this;
  }

  /// `tickChaser`.
  void tickChaser() {
    previousValue = value;
    final f = chaseFunction;
    if (f == null) return;
    if (mthEqual(value, chaseTarget)) {
      value = chaseTarget;
      return;
    }
    value = f(value, chaseSpeed, chaseTarget);
  }

  /// `getValue(partialTicks)`.
  double getValue([double partialTicks = 1]) => toFloat(previousValue + (value - previousValue) * partialTicks);

  /// `settled()`.
  bool settled() => mthEqual(previousValue, value) && (chaseFunction == null || mthEqual(value, chaseTarget));
}
