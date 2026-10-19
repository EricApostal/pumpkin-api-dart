// Item inventories seen by the logistics logic (pure): `CreateItemHandler` as an async
// interface, the in-memory inventory (`CreateItemStackHandler`) and the helpers of
// `TransferUtil` / `ItemHelper` the packagers use. The host implementation is
// `host/host_inventory.dart`.
import '../../common/common.dart';
import 'stack.dart';

/// `CreateItemHandler`: slots with stacks. Reads and writes are async because the host's are.
abstract interface class ItemInv {
  int get slots;

  /// `getStackInSlot` (a copy).
  Future<LStack> stackAt(int slot);

  /// `getSlotLimit`.
  Future<int> slotLimit(int slot);

  /// `isItemValid`.
  Future<bool> isValid(int slot, LStack stack);

  /// `extractItem(slot, amount, simulate)`; empty when nothing could be taken.
  Future<LStack> extract(int slot, int amount, {bool simulate = false});

  /// `insertItem(slot, stack, simulate)`; returns the remainder (empty when everything went in).
  Future<LStack> insert(int slot, LStack stack, {bool simulate = false});
}

/// An inventory that can do the stacked insert in one operation (the host's `insert` with no
/// slot). [insertStacked] uses it when present.
abstract interface class StackedInserter {
  Future<LStack> insertAnywhere(LStack stack, {bool simulate = false});
}

/// `BottomlessItemHandler`: a creative crate's inventory; it has one template stack and gives out
/// as many items as asked for and swallows everything.
abstract interface class BottomlessInv implements ItemInv {}

/// `CreateItemStackHandler` / `ItemStackHandler`: a fixed number of slots held in memory.
class MemoryInv implements ItemInv {
  final List<LStack> stacks;
  final int limit;
  final bool Function(int slot, LStack stack)? validator;

  /// Called after a change (`onContentsChanged`).
  void Function(int slot)? onChanged;

  MemoryInv(int size, {this.limit = 64, this.validator})
    : stacks = List.filled(size, LStack.empty, growable: false);

  MemoryInv.of(List<LStack> contents, {this.limit = 64, this.validator})
    : stacks = List.of(contents, growable: false);

  @override
  int get slots => stacks.length;

  @override
  Future<LStack> stackAt(int slot) async => stacks[slot];

  /// Synchronous read.
  LStack at(int slot) => stacks[slot];

  /// `setStackInSlot`.
  void set(int slot, LStack stack) {
    stacks[slot] = stack.isEmpty ? LStack.empty : stack;
    onChanged?.call(slot);
  }

  @override
  Future<int> slotLimit(int slot) async => limit;

  @override
  Future<bool> isValid(int slot, LStack stack) async =>
      validator?.call(slot, stack) ?? true;

  @override
  Future<LStack> extract(int slot, int amount, {bool simulate = false}) async =>
      extractNow(slot, amount, simulate: simulate);

  /// Synchronous [extract].
  LStack extractNow(int slot, int amount, {bool simulate = false}) {
    if (amount <= 0) return LStack.empty;
    final existing = stacks[slot];
    if (existing.isEmpty) return LStack.empty;
    final toExtract = amount < existing.maxStack ? amount : existing.maxStack;
    if (existing.count <= toExtract) {
      if (!simulate) {
        stacks[slot] = LStack.empty;
        onChanged?.call(slot);
      }
      return existing;
    }
    if (!simulate) {
      stacks[slot] = existing.withCount(existing.count - toExtract);
      onChanged?.call(slot);
    }
    return existing.withCount(toExtract);
  }

  @override
  Future<LStack> insert(
    int slot,
    LStack stack, {
    bool simulate = false,
  }) async => insertNow(slot, stack, simulate: simulate);

  /// Synchronous [insert].
  LStack insertNow(int slot, LStack stack, {bool simulate = false}) {
    if (stack.isEmpty) return LStack.empty;
    if (validator != null && !validator!(slot, stack)) return stack;
    final existing = stacks[slot];
    var cap = limit < stack.maxStack ? limit : stack.maxStack;
    if (existing.isNotEmpty) {
      if (!existing.sameItemSameComponents(stack)) return stack;
      cap -= existing.count;
    }
    if (cap <= 0) return stack;
    final reachedLimit = stack.count > cap;
    if (!simulate) {
      if (existing.isEmpty) {
        stacks[slot] = reachedLimit ? stack.withCount(cap) : stack;
      } else {
        stacks[slot] = existing.withCount(
          existing.count + (reachedLimit ? cap : stack.count),
        );
      }
      onChanged?.call(slot);
    }
    return reachedLimit ? stack.withCount(stack.count - cap) : LStack.empty;
  }

  /// `ItemHelper.getNonEmptyStacks`.
  List<LStack> nonEmpty() => [
    for (final s in stacks)
      if (s.isNotEmpty) s,
  ];

  /// `TransferUtil.insertItemStacked` on memory.
  LStack insertStackedNow(LStack stack, {bool simulate = false}) {
    if (stack.isEmpty) return stack;
    var rest = stack;
    for (var pass = 0; pass < 2 && rest.isNotEmpty; pass++) {
      for (var slot = 0; slot < slots && rest.isNotEmpty; slot++) {
        if (pass == 0 && stacks[slot].isEmpty) continue;
        rest = insertNow(slot, rest, simulate: simulate);
      }
    }
    return rest;
  }

  void clear() {
    for (var i = 0; i < stacks.length; i++) {
      stacks[i] = LStack.empty;
    }
  }
}

/// `TransferUtil.insertItemStacked` / `ResourceHandlerUtil.insertStacking`: fills the slots that
/// already hold the item first, then the empty ones. Returns the remainder.
Future<LStack> insertStacked(
  ItemInv inv,
  LStack stack, {
  bool simulate = false,
}) async {
  if (stack.isEmpty) return stack;
  if (inv is StackedInserter)
    return (inv as StackedInserter).insertAnywhere(stack, simulate: simulate);
  var rest = stack;
  for (var pass = 0; pass < 2 && rest.isNotEmpty; pass++) {
    for (var slot = 0; slot < inv.slots && rest.isNotEmpty; slot++) {
      final present = await inv.stackAt(slot);
      if (pass == 0 ? present.isEmpty : present.isNotEmpty) continue;
      rest = await inv.insert(slot, rest, simulate: simulate);
    }
  }
  return rest;
}

/// A coherent view of an inventory used for one pass of the logic: all stacks read once.
Future<List<LStack>> readAll(ItemInv inv) async => [
  for (var i = 0; i < inv.slots; i++) await inv.stackAt(i),
];

// ------------------------------------------------------------------------------------------------
// InventoryIdentifier

/// A block face: position and side (`BlockFace`).
typedef BlockFacePos = (Pos pos, Direction face);

/// `InventoryIdentifier`: names an inventory that spans several block faces, so that two packagers
/// on the same inventory do not request items from each other.
sealed class InventoryIdentifier {
  const InventoryIdentifier();

  bool contains(BlockFacePos face);
}

/// `InventoryIdentifier.Single`.
final class SingleInventoryId extends InventoryIdentifier {
  final Pos pos;

  const SingleInventoryId(this.pos);

  @override
  bool contains(BlockFacePos face) => pos == face.$1;

  @override
  bool operator ==(Object other) =>
      other is SingleInventoryId && other.pos == pos;

  @override
  int get hashCode => pos.hashCode;
}

/// `InventoryIdentifier.Pair` (two chest halves); the positions are ordered.
final class PairInventoryId extends InventoryIdentifier {
  final Pos first;
  final Pos second;

  PairInventoryId._(this.first, this.second);

  factory PairInventoryId(Pos a, Pos b) {
    // BlockPos.compareTo: y, then z, then x.
    int cmp(Pos p, Pos q) {
      if (p.y != q.y) return p.y - q.y;
      if (p.z != q.z) return p.z - q.z;
      return p.x - q.x;
    }

    return cmp(a, b) < 0 ? PairInventoryId._(a, b) : PairInventoryId._(b, a);
  }

  @override
  bool contains(BlockFacePos face) => first == face.$1 || second == face.$1;

  @override
  bool operator ==(Object other) =>
      other is PairInventoryId &&
      other.first == first &&
      other.second == second;

  @override
  int get hashCode => Object.hash(first, second);
}

/// `InventoryIdentifier.Bounds` (a vault).
final class BoundsInventoryId extends InventoryIdentifier {
  final BlockBounds bounds;

  const BoundsInventoryId(this.bounds);

  @override
  bool contains(BlockFacePos face) => bounds.isInside(face.$1);

  @override
  bool operator ==(Object other) =>
      other is BoundsInventoryId && other.bounds == bounds;

  @override
  int get hashCode => bounds.hashCode;
}

/// `InventoryIdentifier.MultiFace`.
final class MultiFaceInventoryId extends InventoryIdentifier {
  final Pos pos;
  final Set<Direction> sides;

  const MultiFaceInventoryId(this.pos, this.sides);

  @override
  bool contains(BlockFacePos face) => pos == face.$1 && sides.contains(face.$2);

  @override
  bool operator ==(Object other) =>
      other is MultiFaceInventoryId &&
      other.pos == pos &&
      other.sides.length == sides.length &&
      other.sides.containsAll(sides);

  @override
  int get hashCode => Object.hash(pos, Object.hashAllUnordered(sides));
}

/// `IdentifiedInventory`: an inventory with its (optional) identifier.
final class IdentifiedInventory {
  final InventoryIdentifier? identifier;
  final ItemInv handler;

  const IdentifiedInventory(this.identifier, this.handler);
}
