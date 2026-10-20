// The `ItemFilterApi` contract (pure): the filter items and the service the other modules use to
// match a candidate against one. Declared apart from `api/redstone.dart` so the filter model and
// its tests do not need the host bindings.

/// The filter item of a filtering slot: its item key, count and data components.
///
/// A plain item is `FilterItemValue(key)`. A list or attribute filter carries its contents in
/// the `create:filter_items` / `create:attribute_filter_*` components, so a caller that has the
/// stack passes them as `(component name, wire bytes)` (the same bytes `ItemStack.getComponents`
/// and the custom `create:*` components return). A slot that only remembers the item key (the
/// smart observer, the deployer) passes `FilterItemValue.key(key)`; the filter then matches
/// itself, exactly like a freshly crafted filter, whose empty component patch makes Java treat it
/// as a plain stack (`FilterItemStack.of`, Java `FilterItemStack.java:27-34`).
final class FilterItemValue {
  final String key;
  final int count;

  /// Component name -> network-encoded value.
  final List<(String, List<int>)> components;

  const FilterItemValue(this.key, {this.count = 1, this.components = const []});

  /// A stack of [key] with no components.
  const FilterItemValue.key(this.key)
    : count = 1,
      components = const [];

  /// `ItemStack.isEmpty()`: the empty filter slot matches everything.
  bool get isEmpty => count <= 0 || key == 'minecraft:air';
}

/// List and attribute filter items (logistics module): the filter slots store the filter item;
/// matching a stack against a filter item (`create:filter`, `create:attribute_filter`) is the
/// logistics module's `FilterItemStack`.
///
/// Both tests are world-free: Java's `FilterItem.testDirect` / `ListFilterItemStack.test` only
/// compare stacks, and the fluid of a filter item is resolved through the
/// `FilterItemStack.filterFluid` hook, which the filter part fills from `FluidItemSpec` and the
/// fluid rules rather than from a level (Java's `resolveFluid` takes the level only because
/// `GenericItemEmptying` looks the item's fluid handler up in it). [worldId] is accepted for the
/// slots that have one and is not used.
abstract interface class ItemFilterApi {
  /// Whether [candidateItem] passes [filter] (a plain item matches itself).
  bool testItem(String worldId, FilterItemValue filter, String candidateItem);

  /// Whether [fluidKey] passes [filter] (a bucket filter matches its fluid).
  bool testFluid(String worldId, FilterItemValue filter, String fluidKey);
}
