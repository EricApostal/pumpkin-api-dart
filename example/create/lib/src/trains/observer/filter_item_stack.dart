// `FilterItemStack` (pure) as the track observer needs it: the filter item of the observer, kept as
// its saved item compound (`{id, count, components}`), matched against item and fluid keys. The
// matching of list and attribute filters belongs to the logistics module: it installs [itemMatcher]
// and [fluidMatcher] (the trains module wires them to the `ItemFilterApi` service).
import '../util/ctag.dart';

class FilterItemStack {
  /// `filterItem` is a filter item key, `candidate` an item key.
  static bool Function(String filterItem, String candidate) itemMatcher = (filterItem, candidate) =>
      filterItem == candidate;

  /// `filterItem` is a filter item key, `fluid` a fluid key.
  static bool Function(String filterItem, String fluid) fluidMatcher = _bucketMatches;

  static bool _bucketMatches(String filterItem, String fluid) {
    if (!filterItem.endsWith('_bucket')) return false;
    return filterItem.substring(0, filterItem.length - '_bucket'.length) == fluid;
  }

  /// The saved item stack, `null` for the empty stack.
  final CTag? _stack;

  const FilterItemStack._(this._stack);

  /// `FilterItemStack.empty()`.
  factory FilterItemStack.empty() => const FilterItemStack._(null);

  /// `FilterItemStack.of(ItemStack)` of an item key (count 1), `null` / air for the empty stack.
  factory FilterItemStack.ofItem(String? itemKey) {
    if (itemKey == null || itemKey == 'minecraft:air') return FilterItemStack.empty();
    return FilterItemStack._(
      CTag()
        ..putString('id', itemKey)
        ..putInt('count', 1),
    );
  }

  /// `FilterItemStack.of(registries, tag)`: from a saved item compound (empty when it has no id).
  factory FilterItemStack.of(CTag tag) {
    final id = tag.getString('id');
    if (id.isEmpty || id == 'minecraft:air') return FilterItemStack.empty();
    return FilterItemStack._(tag.copy());
  }

  bool isEmpty() => _stack == null;

  /// The item key of the filter, `null` when empty.
  String? itemKey() => _stack?.getString('id');

  /// `serializeNBT()`: the saved item compound (empty for the empty stack).
  CTag serializeNBT() => _stack?.copy() ?? CTag();

  /// `test(level, ItemStack)`.
  bool testItem(String itemKey) {
    final key = this.itemKey();
    if (key == null) return true;
    return itemMatcher(key, itemKey);
  }

  /// `test(level, FluidStack)`: [fluidKey] is the key of a non-empty fluid.
  bool testFluid(String fluidKey) {
    final key = itemKey();
    if (key == null) return true;
    return fluidMatcher(key, fluidKey);
  }
}
