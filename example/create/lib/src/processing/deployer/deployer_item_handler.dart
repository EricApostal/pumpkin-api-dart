// `DeployerItemHandler` (pure): the item handler the deployer exposes to hoppers and funnels.
// Slot 0..n-1 are the overflow stacks, the last slot is the item in the fake player's hand.
//
// Ported from `content/kinetics/deployer/DeployerItemHandler.java`. The handler works on
// callbacks so it has no host bindings: the block entity supplies the held stack, the overflow
// list and the filter test.
import '../common/stack.dart';
import '../common/storage.dart';

/// `DeployerItemHandler`.
final class DeployerItemHandler implements ItemStorage {
  /// The overflow stacks (owned by the block entity).
  final List<PStack> overflow;

  /// The stack in the fake player's main hand.
  final PStack Function() getHeld;

  /// Puts a stack into the fake player's main hand.
  final void Function(PStack stack) setHeld;

  /// `isItemValid`: the deployer's filter.
  final bool Function(PStack stack) validator;

  /// Whether a filter item is set (`!filtering.getFilter().isEmpty()`): the filtered item stays
  /// in the hand and cannot be pulled out.
  final bool Function()? isFilterActive;

  /// Called after the contents changed (`setChanged` / `sendData`).
  final void Function() onChanged;

  DeployerItemHandler({
    required this.overflow,
    required this.getHeld,
    required this.setHeld,
    required this.validator,
    this.isFilterActive,
    required this.onChanged,
  });

  @override
  int get slots => 1 + overflow.length;

  @override
  PStack stackIn(int slot) =>
      slot >= overflow.length ? getHeld() : overflow[slot];

  @override
  int slotLimit(int slot) {
    final stack = stackIn(slot);
    return stack.isEmpty ? 64 : stack.maxStack;
  }

  @override
  bool isItemValid(int slot, PStack stack) => validator(stack);

  @override
  PStack insert(int slot, PStack stack, {bool simulate = false}) {
    if (stack.isEmpty) return PStack.empty;
    if (slot < overflow.length) return stack;
    if (!validator(stack)) return stack;

    final held = getHeld();
    if (held.isEmpty) {
      // `ItemHelper.limitCountToMaxStackSize`: one stack of the item's max size.
      final limit = stack.maxStack;
      if (stack.count <= limit) {
        if (!simulate) {
          setHeld(stack);
          onChanged();
        }
        return PStack.empty;
      }
      if (!simulate) {
        setHeld(stack.withCount(limit));
        onChanged();
      }
      return stack.withCount(stack.count - limit);
    }

    if (!held.sameItemSameComponents(stack)) return stack;

    final space = held.maxStack - held.count;
    if (space <= 0) return stack;
    final moved = stack.count < space ? stack.count : space;
    if (!simulate) {
      setHeld(held.withCount(held.count + moved));
      onChanged();
    }
    return moved >= stack.count
        ? PStack.empty
        : stack.withCount(stack.count - moved);
  }

  @override
  PStack extract(int slot, int amount, {bool simulate = false}) {
    if (amount == 0) return PStack.empty;

    if (slot < overflow.length) {
      final stack = overflow[slot];
      if (stack.isEmpty) return PStack.empty;
      final toExtract = amount < stack.count ? amount : stack.count;
      if (!simulate) {
        final rest = stack.count - toExtract;
        if (rest <= 0) {
          overflow.removeAt(slot);
        } else {
          overflow[slot] = stack.withCount(rest);
        }
        onChanged();
      }
      return stack.withCount(toExtract);
    }

    final held = getHeld();
    if (held.isEmpty) return PStack.empty;
    if ((isFilterActive?.call() ?? false) && validator(held)) {
      return PStack.empty;
    }
    if (!simulate) {
      final toExtract = amount < held.count ? amount : held.count;
      final rest = held.count - toExtract;
      setHeld(rest <= 0 ? PStack.empty : held.withCount(rest));
      onChanged();
      return held.withCount(toExtract);
    }
    return held.withCount(amount < held.count ? amount : held.count);
  }
}
