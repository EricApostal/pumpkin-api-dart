// `ItemHandlerBeltSegment` (pure): the one-slot item handler a belt segment exposes to hoppers,
// funnels and the machines around it. It inserts into the belt inventory at its own index and
// extracts the item that sits on that segment.
import 'belt_inventory.dart';
import '../../processing/common/stack.dart' show PStack;
import '../../processing/common/storage.dart' show ItemStorage;
import '../items/inventory.dart';
import '../items/item_data.dart';
import '../items/stack_bridge.dart';
import 'transported_item.dart';

/// `ItemHandlerBeltSegment`.
class BeltSegmentInventory implements ItemInventory {
  final BeltInventory beltInventory;

  /// The belt index of this segment (`offset`).
  final int offset;

  BeltSegmentInventory(this.beltInventory, this.offset);

  @override
  int get slots => 1;

  @override
  ItemValue getStack(int slot) =>
      beltInventory.getStackAtOffset(offset)?.stack ?? ItemValue.empty;

  @override
  int slotLimit(int slot) {
    final s = getStack(0);
    return s.isEmpty ? 64 : s.maxStack;
  }

  @override
  bool isItemValid(int slot, ItemValue stack) => true;

  @override
  ItemValue insert(int slot, ItemValue stack, {bool simulate = false}) {
    if (!beltInventory.canInsertAt(offset)) return stack;
    final (fits, overflow) = limitCountToMaxStackSize(stack);
    if (!simulate) {
      final transported = TransportedItemStack(fits)
        ..insertedAt = offset
        ..beltPosition =
            offset + .5 + (beltInventory.beltMovementPositive ? -1 : 1) / 16
        ..prevBeltPosition =
            offset + .5 + (beltInventory.beltMovementPositive ? -1 : 1) / 16;
      beltInventory.addItem(transported);
      beltInventory.env.notifyUpdate();
    }
    return overflow;
  }

  @override
  ItemValue extract(int slot, int amount, {bool simulate = false}) {
    final transported = beltInventory.getStackAtOffset(offset);
    if (transported == null) return ItemValue.empty;
    final take = amount < transported.stack.count
        ? amount
        : transported.stack.count;
    if (take <= 0) return ItemValue.empty;
    if (simulate) return transported.stack.withCount(take);
    final (taken, rest) = transported.stack.split(take);
    transported.stack = rest;
    if (rest.isEmpty) {
      beltInventory.toRemove.add(transported);
    } else {
      beltInventory.env.notifyUpdate();
    }
    return taken;
  }
}

/// The segment as the processing machines' [ItemStorage] (PStack): what
/// `StorageLookup.pluginItemStorage` finds next to a machine.
final class BeltSegmentStorage implements ItemStorage {
  final BeltSegmentInventory inner;

  BeltSegmentStorage(this.inner);

  @override
  int get slots => 1;

  @override
  PStack stackIn(int slot) => toPStack(inner.getStack(slot));

  @override
  PStack insert(int slot, PStack stack, {bool simulate = false}) =>
      toPStack(inner.insert(slot, fromPStack(stack), simulate: simulate));

  @override
  PStack extract(int slot, int amount, {bool simulate = false}) =>
      toPStack(inner.extract(slot, amount, simulate: simulate));

  @override
  int slotLimit(int slot) => inner.slotLimit(slot);

  @override
  bool isItemValid(int slot, PStack stack) =>
      inner.isItemValid(slot, fromPStack(stack));
}
