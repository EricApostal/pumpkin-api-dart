// The decision logic of the threshold switch (`ThresholdSwitchBlockEntity.updateCurrentLevel`),
// pure: the stock level the switch sees and the redstone state it drives. The lookups for the
// observed inventories (`ObservedContainer`) and for the fluids stay in `observer_blocks.dart`,
// which owns the host bindings.
import 'dart:math' as math;

import 'observed_container.dart';

/// `ThresholdSwitchBlockEntity.isSuitableInventory`: a stock ticker's inventory is not a stock
/// the switch can count (Java also rejects a target whose item handler is a
/// `ProcessingInventory`; the host does not expose that distinction).
bool thresholdTargetSupported(String blockKey) => blockKey != 'create:stock_ticker';

/// `Mth.clamp(int, int, int)`: `Math.min(Math.max(value, min), max)`. Unlike Dart's
/// `num.clamp` it accepts an inverted range, settling on [max].
int thresholdClamp(int value, int min, int max) => math.min(math.max(value, min), max);

/// The item scan of `updateCurrentLevel`: the counted [`current`] and the capacity [`max`] of
/// the slots of [container], each giving the space of its stack
/// (`Math.min(stack.getMaxStackSize(), inv.getSlotLimit(slot))`, or `Math.min(64, slotLimit)`
/// while the slot is empty). The switch leaves the minimum at 0.
Future<({int current, int max})> thresholdItemLevels(
  ObservedContainer container, {
  required bool Function(String itemKey) test,
}) async {
  var current = 0;
  var max = 0;
  for (var slot = 0; slot < container.slots; slot++) {
    final observed = await container.slot(slot, detail: true);
    final space = observed.isEmpty
        ? math.min(64, observed.limit)
        : math.min(observed.maxStack, observed.limit);
    if (space == 0) continue;
    max += space;
    if (!observed.isEmpty && test(observed.key)) current += observed.count;
  }
  return (current: current, max: max);
}

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
