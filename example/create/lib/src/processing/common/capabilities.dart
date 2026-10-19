// Capabilities: how machines expose their storage to their neighbours (pure interfaces).
//
// NeoForge asks a block entity for `Capabilities.ItemHandler.BLOCK` with a side. Here a block
// entity of a plugin machine implements [ItemStorageProvider] / [FluidStorageProvider]; the
// lookup service (`StorageLookup`, see `host/storage_lookup.dart`) finds the provider at a
// position, and for blocks that are not plugin machines (chests, barrels, furnaces, ...) goes
// through the host's item / fluid handlers.
import 'stack.dart';
import 'storage.dart';

/// A block entity that has item storage reachable from the outside.
abstract interface class ItemStorageProvider {
  /// The storage seen from [side] (a `Direction` name: `down`, `up`, `north`, `south`,
  /// `west`, `east`; `null` = from inside / any side), or `null` when the block has none there.
  ItemStorage? itemStorage(String? side);
}

/// A block entity that has fluid storage reachable from the outside.
abstract interface class FluidStorageProvider {
  FluidStorage? fluidStorage(String? side);
}

/// A block entity that takes fuel items from outside (the blaze burner:
/// `BlazeBurnerBlock.tryInsert`). The mechanical arm and belts look for it.
abstract interface class FuelAcceptor {
  /// `tryInsert(state, level, pos, stack, doNotConsume, forceOverflow, simulate)`: returns what
  /// is left of [stack] (the whole stack when the fuel is not accepted).
  PStack tryInsertFuel(PStack stack, {bool doNotConsume = false, bool forceOverflow = false, bool simulate = false});
}
