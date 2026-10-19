// `FilterItemStack` (pure): the filter set in a filtering slot (a plain item, a list filter, an
// attribute filter or a package filter) and the test of candidates against it. The filter items'
// component values are network encoded; [StackWire] decodes the contained stacks.
import 'dart:convert';

import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../core/nbt.dart';
import '../model/package.dart';
import '../model/stack.dart';
import '../model/stack_wire.dart';
import 'item_attribute.dart';

/// `AttributeFilterWhitelistMode`.
enum AttributeFilterWhitelistMode { whitelistDisj, whitelistConj, blacklist }

/// The component names the filters use (`AllDataComponents`).
abstract final class FilterComponents {
  static const String filterItems = 'create:filter_items';
  static const String respectNbt = 'create:filter_items_respect_nbt';
  static const String blacklist = 'create:filter_items_blacklist';
  static const String whitelistMode = 'create:attribute_filter_whitelist_mode';
  static const String matchedAttributes =
      'create:attribute_filter_matched_attributes';

  /// The key inside `minecraft:custom_data` that keeps the attribute entries this process could
  /// not decode from the network form (the attribute registry ids are host assigned).
  static const String privateAttributes = 'CreateLogisticsFilter';
}

/// The filter item keys (`AllItems`).
abstract final class FilterItemKeys {
  static const String list = 'create:filter';
  static const String attribute = 'create:attribute_filter';
  static const String package = 'create:package_filter';
}

/// A filter. The plain filter matches the same item (`isSameItem`, and the same components with
/// `matchNbt`); an empty filter matches everything.
class FilterItemStack {
  /// The stack in the filter slot (`item()`).
  final LStack item;

  const FilterItemStack(this.item);

  static const FilterItemStack empty = FilterItemStack(LStack.empty);

  /// `FilterItemStack.of(stack)`: list, attribute and package filter items are recognised.
  /// [wire] decodes the stacks contained in a list filter.
  static FilterItemStack of(LStack stack, {StackWire? wire}) {
    if (stack.isEmpty) return empty;
    switch (stack.key) {
      case FilterItemKeys.list:
        return ListFilterItemStack(stack, wire);
      case FilterItemKeys.attribute:
        return AttributeFilterItemStack(stack);
      case FilterItemKeys.package:
        return PackageFilterItemStack(stack);
      default:
        return FilterItemStack(stack);
    }
  }

  /// `FilterItemStack.of(registries, tag)`: the saved form is the JSON of the filter stack.
  static FilterItemStack fromJson(String json, {StackWire? wire}) {
    try {
      return of(LStackMapper.fromJson(json), wire: wire);
    } on Object {
      return empty;
    }
  }

  bool get isEmpty => item.isEmpty;

  /// `getMaxStackSize()`: 64 for an empty filter, else the stack's limit.
  int get maxStackSize => item.isEmpty ? 64 : item.maxStack;

  /// `isFilterItem()`: a filter item (list / attribute / package filter), not a plain item.
  bool get isFilterItem => false;

  /// `test(level, stack, matchNBT)`.
  bool test(LStack candidate, {bool matchNbt = false}) {
    if (isEmpty) return true;
    if (matchNbt) {
      if (PackageItem.isPackage(item) && PackageItem.isPackage(candidate)) {
        return _packagesHaveSameData(item, candidate);
      }
      return item.sameItemSameComponents(candidate);
    }
    if (PackageItem.isPackage(item) && PackageItem.isPackage(candidate))
      return true;
    return item.sameItem(candidate);
  }

  /// `test(level, fluidStack)`: [fluidKey] is the registry key of the fluid.
  bool testFluid(String fluidKey, {bool matchNbt = false}) => isEmpty;

  /// The filter stack as saved (JSON in a string, the plugin's own state form).
  String toJson() => item.toJson();

  /// `FilterItem.doPackagesHaveSameData`: order data and order context are ignored.
  static bool _packagesHaveSameData(LStack a, LStack b) {
    if (a.isEmpty) return false;
    if (!a.sameItemSameComponents(b)) return false;
    const ignored = {
      PackageComponents.orderData,
      PackageComponents.orderContext,
    };
    for (final name in a.comps.keys) {
      if (ignored.contains(name)) continue;
      if (b.comps[name] != a.comps[name]) return false;
    }
    return true;
  }

  /// The value of a boolean component (network form: one byte).
  static bool _boolComp(LStack stack, String name, bool fallback) {
    final bytes = stack.compBytes(name);
    if (bytes == null || bytes.isEmpty) return fallback;
    return bytes.first != 0;
  }

  /// The value of an enum component (network form: a varint ordinal).
  static int _ordinalComp(LStack stack, String name) {
    final bytes = stack.compBytes(name);
    if (bytes == null || bytes.isEmpty) return 0;
    var value = 0;
    var shift = 0;
    for (final b in bytes) {
      value |= (b & 0x7F) << shift;
      if (b & 0x80 == 0) break;
      shift += 7;
    }
    return value;
  }

  /// The private attribute entries of a filter (see [FilterComponents.privateAttributes]).
  static List<ItemAttributeEntry> _privateAttributeEntries(LStack stack) {
    final bytes = stack.compBytes('minecraft:custom_data');
    if (bytes == null) return const [];
    try {
      final root = NetworkNbt.decode(bytes);
      if (root == null) return const [];
      final value = root.asCompound[FilterComponents.privateAttributes];
      if (value == null || value.kind != NbtKind.string) return const [];
      final list = jsonDecode(value.value as String) as List<dynamic>;
      final out = <ItemAttributeEntry>[];
      for (final e in list) {
        if (e is! Map) continue;
        final entry = ItemAttributeEntry.fromMap(e.cast<String, dynamic>());
        if (entry != null) out.add(entry);
      }
      return out;
    } on Object {
      return const [];
    }
  }
}

/// `FilterItemStack.ListFilterItemStack`: an allow or deny list of stacks.
final class ListFilterItemStack extends FilterItemStack {
  final List<FilterItemStack> containedItems;
  final bool shouldRespectNbt;
  final bool isBlacklist;

  ListFilterItemStack(super.item, StackWire? wire)
    : shouldRespectNbt = FilterItemStack._boolComp(
        item,
        FilterComponents.respectNbt,
        false,
      ),
      isBlacklist = FilterItemStack._boolComp(
        item,
        FilterComponents.blacklist,
        false,
      ),
      containedItems = _readContained(item, wire);

  static List<FilterItemStack> _readContained(LStack filter, StackWire? wire) {
    final bytes = filter.compBytes(FilterComponents.filterItems);
    if (bytes == null || wire == null) return const [];
    try {
      final slots = PacketBuffer.decode(bytes, wire.readContents);
      return [
        for (final s in slots)
          if (s.isNotEmpty) FilterItemStack.of(s, wire: wire),
      ];
    } on Object {
      return const [];
    }
  }

  @override
  bool get isFilterItem => true;

  @override
  bool test(LStack candidate, {bool matchNbt = false}) {
    for (final entry in containedItems) {
      if (entry.test(candidate, matchNbt: shouldRespectNbt))
        return !isBlacklist;
    }
    return isBlacklist;
  }

  @override
  bool testFluid(String fluidKey, {bool matchNbt = false}) {
    for (final entry in containedItems) {
      if (entry.testFluid(fluidKey, matchNbt: shouldRespectNbt))
        return !isBlacklist;
    }
    return isBlacklist;
  }
}

/// `FilterItemStack.AttributeFilterItemStack`: attribute tests combined by a whitelist mode.
final class AttributeFilterItemStack extends FilterItemStack {
  final AttributeFilterWhitelistMode whitelistMode;
  final List<ItemAttributeEntry> attributeTests;

  AttributeFilterItemStack(super.item)
    : whitelistMode = _mode(item),
      attributeTests = FilterItemStack._privateAttributeEntries(item);

  static AttributeFilterWhitelistMode _mode(LStack filter) {
    final ordinal = FilterItemStack._ordinalComp(
      filter,
      FilterComponents.whitelistMode,
    );
    return ordinal >= 0 && ordinal < AttributeFilterWhitelistMode.values.length
        ? AttributeFilterWhitelistMode.values[ordinal]
        : AttributeFilterWhitelistMode.whitelistDisj;
  }

  @override
  bool get isFilterItem => true;

  @override
  bool test(LStack candidate, {bool matchNbt = false}) {
    for (final entry in attributeTests) {
      final matches = entry.attribute.appliesTo(candidate) != entry.inverted;
      if (matches) {
        switch (whitelistMode) {
          case AttributeFilterWhitelistMode.blacklist:
            return false;
          case AttributeFilterWhitelistMode.whitelistConj:
            continue;
          case AttributeFilterWhitelistMode.whitelistDisj:
            return true;
        }
      } else {
        switch (whitelistMode) {
          case AttributeFilterWhitelistMode.blacklist:
          case AttributeFilterWhitelistMode.whitelistDisj:
            continue;
          case AttributeFilterWhitelistMode.whitelistConj:
            return false;
        }
      }
    }
    return switch (whitelistMode) {
      AttributeFilterWhitelistMode.blacklist => true,
      AttributeFilterWhitelistMode.whitelistConj => true,
      AttributeFilterWhitelistMode.whitelistDisj => false,
    };
  }

  @override
  bool testFluid(String fluidKey, {bool matchNbt = false}) => false;
}

/// `FilterItemStack.PackageFilterItemStack`: matches packages by their address.
final class PackageFilterItemStack extends FilterItemStack {
  final String filterString;

  PackageFilterItemStack(super.item)
    : filterString = PackageItem.getAddress(item);

  @override
  bool get isFilterItem => true;

  @override
  bool test(LStack candidate, {bool matchNbt = false}) =>
      PackageItem.isPackage(candidate) &&
      PackageItem.matchBoxAddress(candidate, filterString);

  @override
  bool testFluid(String fluidKey, {bool matchNbt = false}) => false;
}
