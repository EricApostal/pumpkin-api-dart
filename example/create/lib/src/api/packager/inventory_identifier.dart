// `InventoryIdentifier` (pure): the registry of finders that identify an inventory spanning
// several block faces, so two packagers on the same inventory do not request items from each
// other. The identifier model itself is the logistics module's `InventoryIdentifier`
// (`SingleInventoryId`, `PairInventoryId`, ...); this file adds the API's finder registry and the
// built-in double chest finder.
//
// The finder receives the [BlockGetter] when one is available, which is what the vanilla double
// chest check needs. Multiblock containers (tanks, vaults) fall back to a single position here:
// the pure [BlockGetter] has no block entity / controller lookup.
import '../../common/direction.dart';
import '../../common/pos.dart';
import '../../logistics/model/inventory.dart';
import '../block_state.dart';

/// `InventoryIdentifier.Finder`.
typedef InventoryIdentifierFinder = InventoryIdentifier? Function(
  BState state,
  BlockFacePos face,
  BlockGetter? level,
);

/// `InventoryIdentifier.REGISTRY` and the common identifiers.
abstract final class InventoryIdentifiers {
  /// `REGISTRY`: block key to finder.
  static final Map<String, InventoryIdentifierFinder> registry = {
    'minecraft:chest': doubleChest,
    'minecraft:trapped_chest': doubleChest,
  };

  /// `REGISTRY.register(block, finder)`.
  static void register(String blockKey, InventoryIdentifierFinder finder) =>
      registry[blockKey] = finder;

  /// `InventoryIdentifier.get(level, face)`: the registered finder, else the single-position
  /// fallback of `AllInventoryIdentifiers.fallback`.
  static InventoryIdentifier? get(
    BState state,
    BlockFacePos face, {
    BlockGetter? level,
  }) => (registry[state.key] ?? fallback)(state, face, level);

  /// `AllInventoryIdentifiers.fallback`: one position per face unless a finder says otherwise.
  static InventoryIdentifier? fallback(
    BState state,
    BlockFacePos face,
    BlockGetter? level,
  ) => SingleInventoryId(face.$1);

  /// `AllInventoryIdentifiers.chest`: a double chest spans its two halves.
  static InventoryIdentifier? doubleChest(
    BState state,
    BlockFacePos face,
    BlockGetter? level,
  ) {
    final type = state['type'];
    if (type == null || type == 'single' || level == null)
      return SingleInventoryId(face.$1);
    final facing = state.dir('facing') ?? Direction.north;
    final other = type == 'left'
        ? face.$1.relative(facing.clockWise)
        : face.$1.relative(facing.counterClockWise);
    return PairInventoryId(face.$1, other);
  }

  /// Removes every registration (tests and reloads).
  static void clear() {
    registry
      ..clear()
      ..['minecraft:chest'] = doubleChest
      ..['minecraft:trapped_chest'] = doubleChest;
  }
}
