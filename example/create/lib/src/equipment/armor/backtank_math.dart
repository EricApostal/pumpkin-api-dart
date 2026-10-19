// The numbers of `BacktankUtil`, `BacktankItem` and `BacktankBlockEntity`. Pure.
import 'dart:math' as math;

abstract final class BacktankMath {
  /// `maxAir(enchantLevel)`: the base volume plus the capacity enchantment bonus.
  static int maxAir({required int airInBacktank, required int enchantedCapacity, required int enchantLevel}) =>
      airInBacktank + enchantedCapacity * enchantLevel;

  /// `getAir`: the stored air, capped to the maximum.
  static int air(int stored, int maxAir) => math.min(stored, maxAir);

  /// `consumeAir`: the new air after using [amount].
  static int consume(int air, int amount, int maxAir) => math.min(math.max(air - amount, 0), maxAir);

  /// `sendWarning` condition: a threshold is crossed downwards.
  static bool crossesWarning(num air, num newAir, num threshold) => !(newAir > threshold) && air > threshold;

  /// `canAbsorbDamage` cost: `Math.max(maxAirWithoutEnchants() / usesPerTank, 1)` (integer division).
  static int usageCost(int maxAirWithoutEnchants, int usesPerTank) => math.max(maxAirWithoutEnchants ~/ usesPerTank, 1);

  /// `BacktankItem.getBarWidth`.
  static int barWidth(int remaining, int maxAir) => (13.0 * (remaining / maxAir).clamp(0.0, 1.0)).round();

  /// `ComparatorUtil.fractionToRedstoneLevel`.
  static int fractionToRedstoneLevel(double frac) => (frac * 14 + (frac > 0 ? 1 : 0)).clamp(0.0, 15.0).floor();

  /// `BacktankBlockEntity.tick` refill per cycle: `clamp(((int) abs - 100) / 20, 1, 5)`.
  static int refillIncrement(double speed) => (((speed.abs()).truncate() - 100) ~/ 20).clamp(1, 5);

  /// `BacktankBlockEntity.tick` wait between refills: `clamp((int)(128f - abs / 5f) - 108, 0, 20)`.
  static int refillTimer(double speed) => ((128.0 - speed.abs() / 5.0).truncate() - 108).clamp(0, 20);

  /// Sorting key of `getAllWithAir`: ascending air.
  static int compareAir(int a, int b) => a.compareTo(b);
}
