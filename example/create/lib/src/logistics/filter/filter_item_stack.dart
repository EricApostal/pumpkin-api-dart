// `FilterItemStack`: the filter set in a filtering slot (a plain item, a list filter, an attribute
// filter or a package filter) and the test of candidates against it. OWNER: filter part.
import '../model/package.dart';
import '../model/stack.dart';

/// A filter. The plain filter matches the same item (`isSameItem`, and the same components with
/// `matchNbt`); an empty filter matches everything.
class FilterItemStack {
  /// The stack in the filter slot (`item()`).
  final LStack item;

  const FilterItemStack(this.item);

  static const FilterItemStack empty = FilterItemStack(LStack.empty);

  /// `FilterItemStack.of(stack)`: list, attribute and package filter items are recognised.
  static FilterItemStack of(LStack stack) => stack.isEmpty ? empty : FilterItemStack(stack);

  bool get isEmpty => item.isEmpty;

  /// `isFilterItem()`: a filter item (list / attribute / package filter), not a plain item.
  bool get isFilterItem => false;

  /// `test(level, stack, matchNBT)`.
  bool test(LStack candidate, {bool matchNbt = false}) {
    if (isEmpty) return true;
    if (!item.sameItem(candidate)) return false;
    return !matchNbt || item.sameItemSameComponents(candidate);
  }

  /// `test(level, fluidStack)`: [fluidKey] is the registry key of the fluid.
  bool testFluid(String fluidKey, {bool matchNbt = false}) => isEmpty;

  /// A package address filter helper for the plain case.
  static bool packageAddressMatches(LStack box, String address) => PackageItem.matchAddress(PackageItem.getAddress(box), address);
}
