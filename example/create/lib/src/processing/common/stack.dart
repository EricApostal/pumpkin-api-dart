// Item and fluid stacks as plain values (pure), the common currency of the processing
// machines: recipes, inventories, belts and the host adapters all speak these.
//
// The host stack (`ItemStack`) is an owned resource and its components are raw bytes, so
// machines keep their contents as [PStack] / [PFluid] and convert at the edge
// (`host/stack_host.dart`).

/// `ItemStack.EMPTY`'s key.
const String airKey = 'minecraft:air';

/// The full resource location of an item key.
///
/// The host's `ItemStack.getRegistryKey()` returns vanilla items without their namespace
/// (`cobblestone`), while every recipe ingredient, tag and item key of the mod is
/// `namespace:path`. Keys that already have a namespace are returned unchanged.
String namespacedItemKey(String key) =>
    key.isEmpty || key.contains(':') ? key : 'minecraft:$key';

/// An item stack: item key, count and the data components that make two stacks of the same
/// item different. Components are `(name, value bytes)` pairs sorted by name: vanilla ones by
/// wire name, `create:*` ones prefixed with `custom:` (the convention of the equipment module).
final class PStack {
  final String key;
  final int count;

  /// `Item.getDefaultMaxStackSize()`; 64 unless known otherwise.
  final int maxStack;
  final List<(String, List<int>)> comps;

  const PStack(this.key, this.count, {this.maxStack = 64, this.comps = const []});

  static const PStack empty = PStack(airKey, 0);

  bool get isEmpty => count <= 0 || key == airKey;
  bool get isNotEmpty => !isEmpty;

  /// `ItemStack.copyWithCount`.
  PStack withCount(int c) => c <= 0 ? empty : PStack(key, c, maxStack: maxStack, comps: comps);

  /// `ItemStack.copy`-like resize helpers.
  PStack grow(int n) => withCount(count + n);
  PStack shrink(int n) => withCount(count - n);

  /// `ItemStack.isStackable`: stacking limit above 1.
  bool get isStackable => maxStack > 1;

  /// `ItemStack.getMaxStackSize`.
  int get maxCount => maxStack;

  /// `ItemStack.isItemEqual` (item only).
  bool sameItem(PStack other) => key == other.key;

  /// `ItemStack.isSameItemSameComponents`.
  bool sameItemSameComponents(PStack other) => key == other.key && _compsEqual(comps, other.comps);

  /// A stack with [name] set to [bytes] (replacing an earlier value).
  PStack withComponent(String name, List<int> bytes) {
    final next = [
      for (final c in comps)
        if (c.$1 != name) c,
      (name, List<int>.of(bytes)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return PStack(key, count, maxStack: maxStack, comps: next);
  }

  PStack withoutComponent(String name) => PStack(
    key,
    count,
    maxStack: maxStack,
    comps: [
      for (final c in comps)
        if (c.$1 != name) c,
    ],
  );

  List<int>? component(String name) {
    for (final c in comps) {
      if (c.$1 == name) return c.$2;
    }
    return null;
  }

  bool hasComponent(String name) => component(name) != null;

  @override
  bool operator ==(Object other) =>
      other is PStack &&
      (isEmpty && other.isEmpty || key == other.key && count == other.count && _compsEqual(comps, other.comps));

  @override
  int get hashCode => isEmpty ? 0 : Object.hash(key, count, comps.length);

  @override
  String toString() => isEmpty ? 'PStack.empty' : '$count x $key${comps.isEmpty ? '' : ' +${comps.length} comps'}';
}

bool _compsEqual(List<(String, List<int>)> a, List<(String, List<int>)> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].$1 != b[i].$1) return false;
    final x = a[i].$2, y = b[i].$2;
    if (x.length != y.length) return false;
    for (var j = 0; j < x.length; j++) {
      if (x[j] != y[j]) return false;
    }
  }
  return true;
}

/// A fluid stack in millibuckets; [comps] are the fluid's components (potion contents, ...).
final class PFluid {
  final String key;
  final int amount;
  final List<(String, List<int>)> comps;

  const PFluid(this.key, this.amount, {this.comps = const []});

  static const PFluid empty = PFluid('minecraft:empty', 0);

  bool get isEmpty => amount <= 0 || key == 'minecraft:empty';
  bool get isNotEmpty => !isEmpty;

  PFluid withAmount(int a) => a <= 0 ? empty : PFluid(key, a, comps: comps);

  /// `FluidStack.isSameFluidSameComponents`.
  bool sameFluid(PFluid other) => key == other.key && _compsEqual(comps, other.comps);

  @override
  bool operator ==(Object other) =>
      other is PFluid && (isEmpty && other.isEmpty || key == other.key && amount == other.amount && _compsEqual(comps, other.comps));

  @override
  int get hashCode => isEmpty ? 0 : Object.hash(key, amount, comps.length);

  @override
  String toString() => isEmpty ? 'PFluid.empty' : '$amount mB $key';
}

/// Millibuckets in a bucket (`FluidType.BUCKET_VOLUME`).
const int bucketVolume = 1000;
