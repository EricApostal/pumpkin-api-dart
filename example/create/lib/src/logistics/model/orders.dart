// Orders and summaries (pure): `PackageOrder`, `PackageOrderWithCrafts`, the order data stored on
// package items, `InventorySummary` and `PackagingRequest`.
import 'package:dart_mappable/dart_mappable.dart';

import 'stack.dart';

part 'orders.mapper.dart';

/// `PackageOrder`: the stacks of a request (`entries`).
@MappableClass()
class PackageOrder with PackageOrderMappable {
  final List<BigStack> entries;

  const PackageOrder(this.entries);

  static const PackageOrder emptyOrder = PackageOrder([]);

  factory PackageOrder.empty() => const PackageOrder([]);

  List<BigStack> get stacks => entries;

  bool get isEmpty => entries.isEmpty;
}

/// `PackageOrderWithCrafts.CraftingEntry`.
@MappableClass()
class CraftingEntry with CraftingEntryMappable {
  final PackageOrder pattern;
  final int count;

  const CraftingEntry(this.pattern, this.count);
}

/// `PackageOrderWithCrafts`: an order and the crafting recipes it was made for.
@MappableClass()
class PackageOrderWithCrafts with PackageOrderWithCraftsMappable {
  final PackageOrder orderedStacks;
  final List<CraftingEntry> orderedCrafts;

  const PackageOrderWithCrafts(this.orderedStacks, this.orderedCrafts);

  factory PackageOrderWithCrafts.empty() => const PackageOrderWithCrafts(PackageOrder([]), []);

  /// `simple(stacks)`.
  factory PackageOrderWithCrafts.simple(List<BigStack> stacks) => PackageOrderWithCrafts(PackageOrder(stacks), const []);

  /// `singleRecipe(pattern)`.
  factory PackageOrderWithCrafts.singleRecipe(List<BigStack> pattern) =>
      PackageOrderWithCrafts(PackageOrder.empty(), [CraftingEntry(PackageOrder(pattern), 1)]);

  /// The codec with its legacy alternative (`entries` at the top level, 6.0.0 - 6.0.2).
  static PackageOrderWithCrafts decode(Map<String, dynamic> map) {
    if (map.containsKey('ordered_stacks')) return PackageOrderWithCraftsMapper.fromMap(map);
    final entries = map['entries'];
    if (entries is List) {
      return PackageOrderWithCrafts.simple([for (final e in entries) BigStackMapper.fromMap((e as Map).cast<String, dynamic>())]);
    }
    return PackageOrderWithCrafts.empty();
  }

  /// `hasCraftingInformation(context)`: exactly one recipe.
  static bool hasCraftingInformation(PackageOrderWithCrafts? context) => context != null && context.orderedCrafts.length == 1;

  /// `getCraftingInformation()`.
  List<BigStack> get craftingInformation => orderedCrafts.first.pattern.stacks;

  List<BigStack> get stacks => orderedStacks.stacks;

  bool get isEmpty => orderedStacks.isEmpty;

  /// `orderedStacksMatchOrderedRecipes()`.
  bool orderedStacksMatchOrderedRecipes() {
    if (orderedCrafts.isEmpty) return false;
    final ordered = InventorySummary();
    final crafts = InventorySummary();
    for (final s in stacks) {
      ordered.addBig(s);
    }
    for (final ce in orderedCrafts) {
      for (final bis in ce.pattern.stacks) {
        crafts.add(bis.stack, bis.count * ce.count);
      }
    }
    final entries = ordered.getStacks();
    if (entries.length != crafts.getStacks().length) return false;
    for (final bis in entries) {
      if (crafts.countOf(bis.stack) != bis.count) return false;
    }
    return true;
  }
}

/// `PackageItem.PackageOrderData`: the order information of a package (`create:package_order_data`).
@MappableClass()
class PackageOrderData with PackageOrderDataMappable {
  final int orderId;
  final int linkIndex;
  final bool isFinalLink;
  final int fragmentIndex;
  final bool isFinal;
  final PackageOrderWithCrafts? orderContext;

  const PackageOrderData(this.orderId, this.linkIndex, this.isFinalLink, this.fragmentIndex, this.isFinal, [this.orderContext]);
}

/// `InventorySummary`: the items of an inventory (or a whole network) as counts per distinct
/// stack. Insertion ordered by item, like the Java identity map is not, but the order is not
/// observable (all consumers sort by count or look up).
class InventorySummary {
  final Map<String, List<BigStack>> _items = {};
  List<BigStack>? _byCount;
  int _totalCount = 0;

  /// `contributingLinks`.
  int contributingLinks = 0;

  /// `InventorySummary.EMPTY` (never add to it).
  static final InventorySummary empty = InventorySummary();

  Map<String, List<BigStack>> get itemMap => _items;

  /// `add(InventorySummary)`.
  void addSummary(InventorySummary summary) {
    for (final list in summary._items.values) {
      for (final e in list) {
        addBig(e);
      }
    }
    contributingLinks += summary.contributingLinks;
  }

  /// `add(ItemStack)`: uses the count of the stack.
  void addStack(LStack stack) => add(stack, stack.count);

  /// `add(BigItemStack)`.
  void addBig(BigStack entry) => add(entry.stack, entry.count);

  void addAllStacks(Iterable<LStack> list) {
    for (final s in list) {
      add(s, s.count);
    }
  }

  void addAllBig(Iterable<BigStack> list) {
    for (final e in list) {
      add(e.stack, e.count);
    }
  }

  InventorySummary copy() {
    final out = InventorySummary();
    for (final list in _items.values) {
      for (final e in list) {
        out.add(e.stack, e.count);
      }
    }
    return out;
  }

  /// `add(stack, count)`: a negative count removes (summaries are corrected that way).
  void add(LStack stack, int count) {
    if (count == 0 || stack.isEmpty) return;
    _byCount = null;
    if (_totalCount < BigStack.inf) _totalCount += count;
    final stacks = _items.putIfAbsent(stack.key, () => []);
    for (final existing in stacks) {
      if (existing.stack.sameItemSameComponents(stack)) {
        if (existing.count < BigStack.inf) existing.count += count;
        return;
      }
    }
    var s = stack;
    if (s.count > s.maxStack) s = s.withCount(1);
    stacks.add(BigStack(s, count));
  }

  /// `erase(stack)`.
  bool erase(LStack stack) {
    final stacks = _items[stack.key];
    if (stacks == null) return false;
    for (var i = 0; i < stacks.length; i++) {
      final existing = stacks[i];
      if (!existing.stack.sameItemSameComponents(stack)) continue;
      _totalCount -= existing.count;
      stacks.removeAt(i);
      _byCount = null;
      return true;
    }
    return false;
  }

  /// `getCountOf(stack)`.
  int countOf(LStack stack) {
    final list = _items[stack.key];
    if (list == null) return 0;
    for (final e in list) {
      if (e.stack.sameItemSameComponents(stack)) return e.count;
    }
    return 0;
  }

  /// `getTotalOfMatching(filter)`.
  int totalOfMatching(bool Function(LStack stack) filter) {
    var sum = 0;
    for (final list in _items.values) {
      for (final e in list) {
        if (filter(e.stack)) sum += e.count;
      }
    }
    return sum;
  }

  /// `getStacks()`: the cached sorted list if there is one, else all entries.
  List<BigStack> getStacks() => _byCount ?? [for (final l in _items.values) ...l];

  /// `getStacksByCount()`: sorted by count, descending (stable for equal counts).
  List<BigStack> getStacksByCount() {
    final cached = _byCount;
    if (cached != null) return cached;
    final all = [for (final l in _items.values) ...l];
    // List.sort is not stable; sort by (count desc, insertion index).
    final indexed = all.asMap().entries.toList()
      ..sort((a, b) {
        final c = b.value.count.compareTo(a.value.count);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    return _byCount = [for (final e in indexed) e.value];
  }

  int get totalCount => _totalCount;

  bool get isEmpty => _items.isEmpty;

  /// `InventorySummary.CODEC`: a list of big stacks.
  List<BigStack> toList() => [for (final l in _items.values) ...l];

  static InventorySummary fromList(Iterable<BigStack> list) => InventorySummary()..addAllBig(list);

  /// `divideAndSendTo`: the chunks (at most 100 entries) of the response packets, as
  /// `(last, entries)`. An empty summary is one final empty chunk.
  List<(bool, List<BigStack>)> divideForResponse() {
    final stacks = getStacksByCount();
    if (stacks.isEmpty) return [(true, const <BigStack>[])];
    final out = <(bool, List<BigStack>)>[];
    var current = <BigStack>[];
    var remaining = stacks.length;
    for (final entry in stacks) {
      current.add(entry);
      remaining--;
      if (remaining == 0) break;
      if (current.length < 100) continue;
      out.add((false, current));
      current = <BigStack>[];
    }
    out.add((true, current));
    return out;
  }
}

/// `PackagingRequest`: a pending extraction at one packager.
class PackagingRequest {
  final LStack item;
  int count;
  final String address;
  final int linkIndex;

  /// `MutableBoolean finalLink`: shared between the requests of one link.
  final MutableFlag finalLink;

  /// `MutableInt packageCounter`: shared between the requests of one order.
  final MutableCounter packageCounter;
  final int orderId;
  final PackageOrderWithCrafts? context;

  PackagingRequest(this.item, this.count, this.address, this.linkIndex, this.finalLink, this.packageCounter, this.orderId, this.context);

  factory PackagingRequest.create(
    LStack item,
    int count,
    String address,
    int linkIndex,
    MutableFlag finalLink,
    int packageCount,
    int orderId,
    PackageOrderWithCrafts? context,
  ) => PackagingRequest(item, count, address, linkIndex, finalLink, MutableCounter(packageCount), orderId, context);

  void subtract(int toSubtract) => count -= toSubtract;

  bool get isEmpty => count == 0;
}

/// `MutableBoolean`.
class MutableFlag {
  bool value;

  MutableFlag([this.value = false]);
}

/// `MutableInt`.
class MutableCounter {
  int value;

  MutableCounter([this.value = 0]);

  /// `getAndIncrement()`.
  int getAndIncrement() => value++;
}
