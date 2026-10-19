// `ToolboxInventory` and its item handler rules: 8 compartments of 4 stacks, each with a
// filter, stacking that settles empty slots to the end, and the rule of what shares a
// compartment. Pure; stacks are [TStack] values (the host converts to and from item stacks).
import 'dart:math' as math;

/// An item stack as the toolbox sees it. [comps] are the data components (wire name and
/// bytes, sorted by name) so stacks with different components do not merge.
final class TStack {
  final String key;
  final int count;
  final int maxStack;

  /// `isDamageableItem()`: the item has durability (it cannot stack then).
  final bool damageable;
  final List<(String, List<int>)> comps;

  const TStack(this.key, this.count, {this.maxStack = 64, this.damageable = false, this.comps = const []});

  static const TStack empty = TStack('minecraft:air', 0, maxStack: 64);

  bool get isEmpty => count <= 0 || key == 'minecraft:air';

  /// `ItemStack.isStackable()`.
  bool get stackable => maxStack > 1 && !damageable;

  TStack copyWithCount(int n) => TStack(key, n, maxStack: maxStack, damageable: damageable, comps: comps);

  /// `ItemStack.isSameItemSameComponents`.
  bool sameItemSameComponents(TStack o) {
    if (key != o.key || comps.length != o.comps.length) return false;
    for (var i = 0; i < comps.length; i++) {
      if (comps[i].$1 != o.comps[i].$1) return false;
      final a = comps[i].$2, b = o.comps[i].$2;
      if (a.length != b.length) return false;
      for (var j = 0; j < a.length; j++) {
        if (a[j] != b[j]) return false;
      }
    }
    return true;
  }

  @override
  String toString() => isEmpty ? 'empty' : '$key x$count';
}

/// `ToolboxInventory.canItemsShareCompartment`.
bool canItemsShareCompartment(TStack a, TStack b, {bool Function(String key)? isBeltConnector}) {
  if (!a.stackable && !b.stackable && a.damageable && b.damageable) return a.key == b.key;
  final belt = isBeltConnector ?? (k) => k == 'create:belt_connector';
  if (belt(a.key) && belt(b.key)) return true;
  return a.sameItemSameComponents(b);
}

/// `ItemStackHandler`-like inventory with the toolbox rules.
class ToolboxInv {
  static const compartments = 8;
  static const stacksPerCompartment = 4;
  static const slotCount = compartments * stacksPerCompartment;
  static const slotLimit = 64;

  final List<TStack> slots = List.filled(slotCount, TStack.empty);
  List<TStack> filters = List.filled(compartments, TStack.empty, growable: true);

  bool settling = false;
  bool limitedMode = false;

  /// Called after any change (`notifyUpdate`).
  void Function()? onChanged;

  /// `canFitInsideContainerItems`: items that cannot go into containers (shulker boxes...).
  bool Function(TStack stack) canFit = (_) => true;

  TStack getStack(int slot) => slots[slot];

  /// `settle(compartment)`.
  void settle(int compartment) {
    var totalCount = 0;
    var valid = true;
    var shouldBeEmpty = false;
    var sample = TStack.empty;
    for (var i = 0; i < stacksPerCompartment; i++) {
      final s = slots[compartment * stacksPerCompartment + i];
      totalCount += s.isEmpty ? 0 : s.count;
      if (!shouldBeEmpty) {
        shouldBeEmpty = s.isEmpty || s.count != s.maxStack;
      } else if (!s.isEmpty) {
        valid = false;
        sample = s;
      }
    }
    if (valid) return;
    settling = true;
    final base = compartment * stacksPerCompartment;
    if (!sample.stackable) {
      for (var i = 0; i < stacksPerCompartment; i++) {
        if (!slots[base + i].isEmpty) continue;
        for (var j = i + 1; j < stacksPerCompartment; j++) {
          final s = slots[base + j];
          if (s.isEmpty) continue;
          setStackInSlot(base + i, s);
          setStackInSlot(base + j, TStack.empty);
          break;
        }
      }
    } else {
      for (var i = 0; i < stacksPerCompartment; i++) {
        final copy = totalCount <= 0 ? TStack.empty : sample.copyWithCount(math.min(totalCount, sample.maxStack));
        setStackInSlot(base + i, copy);
        totalCount -= copy.isEmpty ? 0 : copy.count;
      }
    }
    settling = false;
    _notify();
  }

  /// `isItemValid(slot, stack)`.
  bool isItemValid(int slot, TStack stack) {
    if (!canFit(stack)) return false;
    if (slot < 0 || slot >= slotCount) return false;
    final filter = filters[slot ~/ stacksPerCompartment];
    if (limitedMode && filter.isEmpty) return false;
    return filter.isEmpty || canItemsShareCompartment(filter, stack);
  }

  /// `setStackInSlot`: also sets the compartment filter when it is empty.
  void setStackInSlot(int slot, TStack stack) {
    slots[slot] = stack.isEmpty ? TStack.empty : stack;
    _contentsChanged(slot);
    final compartment = slot ~/ stacksPerCompartment;
    if (!stack.isEmpty && filters[compartment].isEmpty) {
      filters[compartment] = stack.copyWithCount(1);
      _notify();
    }
  }

  void _contentsChanged(int slot) {
    if (!settling) settle(slot ~/ stacksPerCompartment);
    _notify();
  }

  void _notify() => onChanged?.call();

  /// `insertItem(slot, stack, simulate)`; returns the remainder.
  TStack insertItem(int slot, TStack stack, {bool simulate = false}) {
    if (stack.isEmpty) return TStack.empty;
    if (!isItemValid(slot, stack)) return stack;
    final existing = slots[slot];
    var limit = math.min(slotLimit, stack.maxStack);
    if (!existing.isEmpty) {
      if (!stack.sameItemSameComponents(existing)) return stack;
      limit -= existing.count;
    }
    if (limit <= 0) return stack;
    final reachedLimit = stack.count > limit;
    if (!simulate) {
      if (existing.isEmpty) {
        // The filter is assigned by the transactional insert in Java; setStackInSlot does the same.
        setStackInSlotNoFilter(slot, reachedLimit ? stack.copyWithCount(limit) : stack);
        _assignFilter(slot, stack);
      } else {
        slots[slot] = existing.copyWithCount(existing.count + (reachedLimit ? limit : stack.count));
      }
      _contentsChanged(slot);
    }
    return reachedLimit ? stack.copyWithCount(stack.count - limit) : TStack.empty;
  }

  void setStackInSlotNoFilter(int slot, TStack stack) => slots[slot] = stack;

  void _assignFilter(int slot, TStack stack) {
    final compartment = slot ~/ stacksPerCompartment;
    if (filters[compartment].isEmpty) {
      filters[compartment] = stack.copyWithCount(1);
      _notify();
    }
  }

  /// `extractItem(slot, amount, simulate)`.
  TStack extractItem(int slot, int amount, {bool simulate = false}) {
    if (amount == 0) return TStack.empty;
    final existing = slots[slot];
    if (existing.isEmpty) return TStack.empty;
    final toExtract = math.min(amount, existing.maxStack);
    if (existing.count <= toExtract) {
      if (!simulate) {
        slots[slot] = TStack.empty;
        _contentsChanged(slot);
      }
      return existing;
    }
    if (!simulate) {
      slots[slot] = existing.copyWithCount(existing.count - toExtract);
      _contentsChanged(slot);
    }
    return existing.copyWithCount(toExtract);
  }

  /// `distributeToCompartment(stack, compartment, simulate)`; returns the remainder.
  TStack distributeToCompartment(TStack stack, int compartment, {bool simulate = false}) {
    if (stack.isEmpty) return stack;
    if (filters[compartment].isEmpty) return stack;
    var rest = stack;
    for (var i = stacksPerCompartment - 1; i >= 0; i--) {
      final slot = compartment * stacksPerCompartment + i;
      rest = insertItem(slot, rest, simulate: simulate);
      if (rest.isEmpty) return TStack.empty;
    }
    return rest;
  }

  /// `takeFromCompartment(amount, compartment, simulate)`.
  TStack takeFromCompartment(int amount, int compartment, {bool simulate = false}) {
    if (amount == 0) return TStack.empty;
    var remaining = amount;
    var lastValid = TStack.empty;
    for (var i = stacksPerCompartment - 1; i >= 0; i--) {
      final slot = compartment * stacksPerCompartment + i;
      final extracted = extractItem(slot, remaining, simulate: simulate);
      remaining -= extracted.isEmpty ? 0 : extracted.count;
      if (!extracted.isEmpty) lastValid = extracted;
      if (remaining == 0) return lastValid.copyWithCount(amount);
    }
    if (remaining == amount) return TStack.empty;
    return lastValid.copyWithCount(amount - remaining);
  }

  /// `TransferUtil.insertItemStacked(inventory, stack, simulate)`: merges into matching stacks
  /// first, then empty slots; returns the remainder.
  TStack insertStacked(TStack stack, {bool simulate = false}) {
    if (stack.isEmpty) return TStack.empty;
    var rest = stack;
    // first pass: slots that already hold a matching stack
    for (var i = 0; i < slotCount && !rest.isEmpty; i++) {
      if (slots[i].isEmpty) continue;
      rest = insertItem(i, rest, simulate: simulate);
    }
    for (var i = 0; i < slotCount && !rest.isEmpty; i++) {
      if (!slots[i].isEmpty) continue;
      rest = insertItem(i, rest, simulate: simulate);
    }
    return rest;
  }

  /// `inLimitedMode`: compartments without a filter accept nothing while [action] runs.
  void inLimitedMode(void Function() action) {
    limitedMode = true;
    try {
      action();
    } finally {
      limitedMode = false;
    }
  }

  /// The total count in a compartment (`ToolboxMenu.totalCountInCompartment`).
  int totalCountInCompartment(int compartment) {
    var count = 0;
    for (var i = 0; i < stacksPerCompartment; i++) {
      final s = slots[compartment * stacksPerCompartment + i];
      count += s.isEmpty ? 0 : s.count;
    }
    return count;
  }

  /// The comparator signal: `ItemHelper.calcRedstoneFromInventory` on the 32 slots.
  int comparatorSignal() {
    var i = 0;
    var f = 0.0;
    for (final s in slots) {
      if (!s.isEmpty) {
        f += s.count / math.min(slotLimit, s.maxStack);
        i++;
      }
    }
    f = f / slotCount;
    return (f * 14.0).floor() + (i > 0 ? 1 : 0);
  }

  void copyFrom(ToolboxInv other) {
    for (var i = 0; i < slotCount; i++) {
      slots[i] = other.slots[i];
    }
    filters = List.of(other.filters);
  }
}
