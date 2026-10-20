// The weighted ejector's lid animation as pure arithmetic: `EjectorBlockEntity` drives a
// `LerpedFloat` (`lidProgress`) that chases 1 while launching and is pulled back to 0 at the
// wind-up speed while retracting. Kept here so the direction of the chase and the recharge time
// are testable without a world.
import 'dart:math' as math;

/// The speed of `lidProgress.chase(1, .8f, Chaser.EXP)`.
const double ejectorLidChaseSpeed = .8;

/// `lidProgress.getValue() > 1 - 1 / 16f`: the lid counts as open and starts closing.
const double ejectorLidOpenThreshold = 1 - 1 / 16;

/// `LerpedFloat.tickChaser` with `Chaser.EXP` (`c + (t - c) * s`): the lid moves **towards**
/// the target, so chasing 1 from 0 opens the lid.
double ejectorLidChase(double current, double target, double speed) {
  if (speed == 0) return current;
  return current + (target - current) * speed;
}

/// `Mth.clamp(lidProgress.getValue() - getWindUpSpeed(), 0, 1)`.
double ejectorLidRetract(double current, double windUpSpeed) =>
    math.min(math.max(current - windUpSpeed, 0), 1);
