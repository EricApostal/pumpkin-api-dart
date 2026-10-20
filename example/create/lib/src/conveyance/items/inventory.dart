// Item inventories as the logistics blocks see them (pure): `CreateItemHandler`. Reads and
// writes are `FutureOr`, because the host's own containers (chests, hoppers, ...) can only
// be reached asynchronously while the inventories of this module (vault slots, chute,
// depot, belt segment) answer at once.
import 'dart:async';

import 'item_data.dart';

/// `CreateItemHandler`: a list of slots with insert / extract that report what did not fit.
abstract interface class ItemInventory {
  /// `getSlots()`.
  int get slots;

  /// `getStackInSlot(slot)` (never mutated by the caller: [ItemValue] is immutable).
  FutureOr<ItemValue> getStack(int slot);

  /// `getSlotLimit(slot)`.
  FutureOr<int> slotLimit(int slot);

  /// `isItemValid(slot, stack)`.
  FutureOr<bool> isItemValid(int slot, ItemValue stack);

  /// `insertItem(slot, stack, simulate)`: the remainder ([ItemValue.empty] when all went in).
  FutureOr<ItemValue> insert(int slot, ItemValue stack, {bool simulate = false});

  /// `extractItem(slot, amount, simulate)`: what was (or would be) taken.
  FutureOr<ItemValue> extract(int slot, int amount, {bool simulate = false});
}

/// An inventory that counts its changes (`VersionedInventoryWrapper`): funnels and chutes
/// remember the version at which nothing could be moved and wait for a new one.
mixin VersionedInventory {
  static int _nextId = 0;

  final int inventoryId = _nextId++;
  int _version = 0;

  int get version => _version;

  void incrementVersion() => _version++;
}

/// `ItemStackHandler` / `CreateItemStackHandler`: an inventory in memory.
class ListInventory with VersionedInventory implements ItemInventory {
  final List<ItemValue> stacks;
  final int slotLimitValue;

  /// Called after a slot changed (`onContentsChanged`).
  void Function(int slot)? onChanged;

  /// `isItemValid` override.
  bool Function(int slot, ItemValue stack)? validator;

  ListInventory(int size, {int slotLimit = 64, this.onChanged, this.validator})
    // Growable: `resize` grows the list when a saved multiblock is larger than the
    // default (`ItemVaultBlockEntity.read` reads the saved `Size`). A fixed-length
    // `List.filled` made that throw `Cannot add to a fixed-length list`, so a vault
    // whose saved size exceeded the default lost its contents on load.
    : stacks = List<ItemValue>.filled(size, ItemValue.empty, growable: true),
      slotLimitValue = slotLimit;

  @override
  int get slots => stacks.length;

  @override
  ItemValue getStack(int slot) => stacks[slot];

  @override
  int slotLimit(int slot) => slotLimitValue;

  @override
  bool isItemValid(int slot, ItemValue stack) => validator?.call(slot, stack) ?? true;

  /// `setStackInSlot`.
  void setStack(int slot, ItemValue stack) {
    final before = stacks[slot];
    stacks[slot] = stack.isEmpty ? ItemValue.empty : stack;
    if (!before.matches(stacks[slot])) {
      incrementVersion();
      onChanged?.call(slot);
    }
  }

  /// Resizes keeping the stacks that still fit.
  void resize(int size) {
    if (size < stacks.length) {
      stacks.removeRange(size, stacks.length);
    } else {
      stacks.addAll(List<ItemValue>.filled(size - stacks.length, ItemValue.empty));
    }
  }

  @override
  ItemValue insert(int slot, ItemValue stack, {bool simulate = false}) {
    if (stack.isEmpty) return ItemValue.empty;
    if (!isItemValid(slot, stack)) return stack;
    final existing = stacks[slot];
    var limit = slotLimitValue < stack.maxStack ? slotLimitValue : stack.maxStack;
    if (existing.isNotEmpty) {
      if (!stack.sameItemSameComponents(existing)) return stack;
      limit -= existing.count;
    }
    if (limit <= 0) return stack;
    final reachedLimit = stack.count > limit;
    if (!simulate) {
      stacks[slot] = existing.isEmpty ? stack.withCount(reachedLimit ? limit : stack.count) : existing.grow(reachedLimit ? limit : stack.count);
      incrementVersion();
      onChanged?.call(slot);
    }
    return reachedLimit ? stack.withCount(stack.count - limit) : ItemValue.empty;
  }

  @override
  ItemValue extract(int slot, int amount, {bool simulate = false}) {
    if (amount <= 0) return ItemValue.empty;
    final existing = stacks[slot];
    if (existing.isEmpty) return ItemValue.empty;
    final toExtract = amount < existing.maxStack ? amount : existing.maxStack;
    if (existing.count <= toExtract) {
      if (!simulate) {
        stacks[slot] = ItemValue.empty;
        incrementVersion();
        onChanged?.call(slot);
      }
      return existing;
    }
    if (!simulate) {
      stacks[slot] = existing.shrink(toExtract);
      incrementVersion();
      onChanged?.call(slot);
    }
    return existing.withCount(toExtract);
  }

  /// Whether every slot is empty.
  bool get isEmpty => stacks.every((s) => s.isEmpty);

  /// The non empty stacks (`ItemHelper.getNonEmptyStacks`).
  List<ItemValue> get nonEmptyStacks => [
    for (final s in stacks)
      if (s.isNotEmpty) s,
  ];

  void clear() {
    for (var i = 0; i < stacks.length; i++) {
      stacks[i] = ItemValue.empty;
    }
    incrementVersion();
  }
}

/// `SameSizeCombinedInvWrapper`: several inventories of the same size as one.
class CombinedInventory with VersionedInventory implements ItemInventory {
  final List<ItemInventory> parts;
  final int partSize;

  CombinedInventory(this.parts) : partSize = parts.isEmpty ? 0 : parts.first.slots;

  @override
  int get slots => partSize * parts.length;

  ItemInventory _part(int slot) => parts[slot ~/ partSize];
  int _local(int slot) => slot % partSize;

  @override
  FutureOr<ItemValue> getStack(int slot) => _part(slot).getStack(_local(slot));

  @override
  FutureOr<int> slotLimit(int slot) => _part(slot).slotLimit(_local(slot));

  @override
  FutureOr<bool> isItemValid(int slot, ItemValue stack) => _part(slot).isItemValid(_local(slot), stack);

  @override
  FutureOr<ItemValue> insert(int slot, ItemValue stack, {bool simulate = false}) {
    final r = _part(slot).insert(_local(slot), stack, simulate: simulate);
    if (!simulate) incrementVersion();
    return r;
  }

  @override
  FutureOr<ItemValue> extract(int slot, int amount, {bool simulate = false}) {
    final r = _part(slot).extract(_local(slot), amount, simulate: simulate);
    if (!simulate) incrementVersion();
    return r;
  }
}

/// The version of an inventory for `VersionedInventoryTrackerBehaviour`: the id of the
/// inventory and its change counter, `null` for inventories that do not count changes.
(int, int)? versionOf(ItemInventory? inv) {
  if (inv is VersionedInventory) {
    final v = inv as VersionedInventory;
    return (v.inventoryId, v.version);
  }
  return null;
}

// -- Helpers on inventories (`TransferUtil`, `ItemHelper`) ----------------------------------

/// `TransferUtil.insertItemStacked`: fills stacks that already hold the item first, then the
/// other slots. Returns the remainder.
Future<ItemValue> insertStacked(ItemInventory? inv, ItemValue stack, {bool simulate = false}) async {
  if (inv == null || stack.isEmpty) return stack;
  var remainder = stack;
  final slotCount = inv.slots;
  // Pass 1: slots that already contain the same item.
  for (var slot = 0; slot < slotCount && remainder.isNotEmpty; slot++) {
    final existing = await inv.getStack(slot);
    if (existing.isEmpty || !existing.sameItemSameComponents(remainder)) continue;
    remainder = await inv.insert(slot, remainder, simulate: simulate);
  }
  // Pass 2: any slot.
  for (var slot = 0; slot < slotCount && remainder.isNotEmpty; slot++) {
    remainder = await inv.insert(slot, remainder, simulate: simulate);
  }
  return remainder;
}

/// `ItemHelper.extract(inv, test, mode, amount, simulate)`.
Future<ItemValue> extractMatching(
  ItemInventory inv,
  bool Function(ItemValue stack) test,
  ExtractionCountMode mode,
  int amount, {
  bool simulate = false,
}) async {
  var extracting = ItemValue.empty;
  final amountRequired = mode == ExtractionCountMode.exactly;
  var checkHasEnoughItems = amountRequired;
  var hasEnoughItems = !checkHasEnoughItems;
  var potentialOtherMatch = false;
  final maxExtractionCount = amount;
  var currentTest = test;

  extraction:
  while (true) {
    extracting = ItemValue.empty;
    for (var slot = 0; slot < inv.slots; slot++) {
      final slotStack = await inv.getStack(slot);
      if (slotStack.isEmpty) continue;
      final amountToExtractFromThisSlot = _min(maxExtractionCount - extracting.count, slotStack.maxStack);
      final stack = await inv.extract(slot, amountToExtractFromThisSlot, simulate: true);
      if (stack.isEmpty) continue;
      if (!currentTest(stack)) continue;
      if (extracting.isNotEmpty && !stack.canAmountsStack(extracting)) {
        potentialOtherMatch = true;
        continue;
      }
      extracting = extracting.isEmpty ? stack : extracting.grow(stack.count);
      if (!simulate && hasEnoughItems) await inv.extract(slot, stack.count);
      if (extracting.count >= maxExtractionCount) {
        if (checkHasEnoughItems) {
          hasEnoughItems = true;
          checkHasEnoughItems = false;
          continue extraction;
        } else {
          break extraction;
        }
      }
    }
    if (extracting.isNotEmpty && !hasEnoughItems && potentialOtherMatch) {
      final blackListed = extracting;
      final previous = currentTest;
      currentTest = (i) => previous(i) && !i.sameItemSameComponents(blackListed);
      continue;
    }
    if (checkHasEnoughItems) {
      checkHasEnoughItems = false;
    } else {
      break;
    }
  }
  if (amountRequired && extracting.count < amount) return ItemValue.empty;
  return extracting;
}

int _min(int a, int b) => a < b ? a : b;

/// `ItemHelper.extract(inv, test, amountFunction, simulate)`: the amount per item type comes
/// from [amountFunction] (0 skips the stack).
Future<ItemValue> extractWithAmountFunction(
  ItemInventory inv,
  bool Function(ItemValue stack) test,
  int Function(ItemValue stack) amountFunction, {
  bool simulate = false,
}) async {
  var extracting = ItemValue.empty;
  var maxExtractionCount = 64;
  for (var slot = 0; slot < inv.slots; slot++) {
    if (extracting.isEmpty) {
      final stackInSlot = await inv.getStack(slot);
      if (stackInSlot.isEmpty || !test(stackInSlot)) continue;
      final maxForItem = amountFunction(stackInSlot);
      if (maxForItem == 0) continue;
      maxExtractionCount = _min(maxExtractionCount, maxForItem);
    }
    final stack = await inv.extract(slot, maxExtractionCount - extracting.count, simulate: true);
    if (stack.isEmpty || !test(stack)) continue;
    if (extracting.isNotEmpty && !stack.canAmountsStack(extracting)) continue;
    extracting = extracting.isEmpty ? stack : extracting.grow(stack.count);
    if (!simulate) await inv.extract(slot, stack.count);
    if (extracting.count >= maxExtractionCount) break;
  }
  return extracting;
}

/// `ItemHelper.calcRedstoneFromInventory`.
Future<int> redstoneFromInventory(ItemInventory? inv) async {
  if (inv == null) return 0;
  var i = 0;
  var f = 0.0;
  var totalSlots = inv.slots;
  for (var j = 0; j < inv.slots; j++) {
    final limit = await inv.slotLimit(j);
    if (limit == 0) {
      totalSlots--;
      continue;
    }
    final stack = await inv.getStack(j);
    if (stack.isNotEmpty) {
      f += stack.count / _min(limit, stack.maxStack);
      i++;
    }
  }
  if (totalSlots == 0) return 0;
  f = f / totalSlots;
  return (f * 14.0).floor() + (i > 0 ? 1 : 0);
}

/// `ItemHelper.limitCountToMaxStackSize`: (the part that fits one stack, the overflow).
(ItemValue, ItemValue) limitCountToMaxStackSize(ItemValue stack) {
  if (stack.count <= stack.maxStack) return (stack, ItemValue.empty);
  return (stack.withCount(stack.maxStack), stack.withCount(stack.count - stack.maxStack));
}
