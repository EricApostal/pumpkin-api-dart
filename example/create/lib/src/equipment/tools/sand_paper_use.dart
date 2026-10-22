// Pure helper of the sand paper's polishing use (`MiscItemsHost`). Java's `SandPaperItem` is an
// `Item` whose `getUseDuration` is 32 ticks, but the host never starts an item use for an item
// without a `minecraft:consumable` or `minecraft:blocks_attacks` component, so the module counts
// the use down itself on the player tick instead of on `itemUseTick`.

/// `SandPaperItem.getUseDuration(stack, entity)` (`SandPaperItem.java:226-228`): the ticks a
/// polishing use lasts.
const int sandPaperUseDuration = 32;

/// One player's running polishing use.
///
/// `startUsingItem` starts it at [sandPaperUseDuration] (`SandPaperItem.use`,
/// `SandPaperItem.java:48-105`); the use is over when the count reaches zero, which is where Java
/// calls `finishUsingItem` (`SandPaperItem.java:108-135`).
final class SandPaperUse {
  int _remaining = sandPaperUseDuration;

  /// The ticks left until the polish finishes.
  int get remaining => _remaining;

  /// Whether the use is still running.
  bool get isRunning => _remaining > 0;

  /// One player tick; true when the use is over and the polish has to be finished.
  ///
  /// Stays true once the count reached zero, so a late caller cannot restart it.
  bool tick() {
    if (_remaining > 0) _remaining--;
    return _remaining <= 0;
  }
}