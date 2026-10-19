// The decision logic of the threshold switch (`ThresholdSwitchBlockEntity.updateCurrentLevel`),
// pure: the stock level the switch sees and the redstone state it drives. The inventory scan
// itself needs the host's item and fluid handlers and stays in `observer_blocks.dart`.
import 'dart:math' as math;

/// `ThresholdSwitchBlockEntity.isSuitableInventory`: a stock ticker's inventory is not a stock
/// the switch can count (Java also rejects a target whose item handler is a
/// `ProcessingInventory`; the host does not expose that distinction).
bool thresholdTargetSupported(String blockKey) => blockKey != 'create:stock_ticker';

/// `Mth.clamp(int, int, int)`: `Math.min(Math.max(value, min), max)`. Unlike Dart's
/// `num.clamp` it accepts an inverted range, settling on [max].
int thresholdClamp(int value, int min, int max) => math.min(math.max(value, min), max);

/// `ThresholdSwitchBlockEntity.updateCurrentLevel`: the redstone state after observing
/// [current]. The switch turns off at or below [offWhenBelow] and on at or above
/// [onWhenAbove], and keeps its state in between (the hysteresis). Returns the new state and
/// whether it changed.
({bool state, bool changed}) thresholdRedstoneState({
  required bool state,
  required int current,
  required int onWhenAbove,
  required int offWhenBelow,
}) {
  var next = state;
  if (state && current <= offWhenBelow) {
    next = false;
  } else if (!state && current >= onWhenAbove) {
    next = true;
  }
  return (state: next, changed: next != state);
}

/// The `level` block property of the switch: 0 for an empty stock, else 1 to 5 for the fill of
/// the observed range. A degenerate range gives 0, like Java's `(int)` of NaN.
int thresholdDisplayLevel({
  required int current,
  required int min,
  required int max,
}) {
  if (current <= 0) return 0;
  final normed = (current - min) / (max - min);
  if (normed.isNaN) return 0;
  // Java would overflow the 0..5 property here; stay at the ends of the scale instead.
  if (!normed.isFinite) return normed.isNegative ? 0 : 5;
  return (1 + normed * 4).toInt();
}
