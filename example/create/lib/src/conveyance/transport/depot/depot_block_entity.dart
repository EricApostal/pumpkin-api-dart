// `DepotBlockEntity` (server behaviour): the depot's `DepotBehaviour`, its nine-slot item handler
// (the held item plus the processing output buffer) and the direct belt input / transported item
// handler views the belts and machines use.
import 'dart:async';

import '../../../common/direction.dart';
import '../../../core/block_entity.dart';
import '../../behaviours/belt_interfaces.dart';
import '../../belt/transported_item.dart';
import '../../items/inventory.dart';
import '../../items/item_data.dart';
import '../../runtime.dart';
import '../transport_inventory_api.dart';
import 'depot_behaviour.dart';

/// `DepotBlockEntity`.
class DepotBlockEntity extends CreateBlockEntity
    implements
        ItemInventoryProvider,
        DirectBeltInput,
        TransportedItemStackHandler {
  late final DepotBehaviour depotBehaviour;
  late final _DepotInventory _inventory = _DepotInventory(this);

  DepotBlockEntity(super.worldId, super.pos) {
    depotBehaviour = addBehaviour(DepotBehaviour());
    depotBehaviour.addSubBehaviours();
  }

  ConveyanceRuntime get rt => ConveyanceRuntime.i;

  // -- Item handler ----------------------------------------------------------------------------

  @override
  ItemInventory? itemInventory(Direction? side) => _inventory;

  /// `getHeldItem`.
  ItemValue getHeldItem() => depotBehaviour.getHeldItemStack();

  /// `setHeldItem`: a new transported stack that keeps the old angle.
  void setHeldItem(ItemValue item) {
    final stack = TransportedItemStack(item);
    final held = depotBehaviour.heldItem;
    if (held != null) stack.angle = held.angle;
    depotBehaviour.setHeldItem(stack);
  }

  // -- DirectBeltInput -------------------------------------------------------------------------

  @override
  bool get canSupportBeltFunnels => true;

  @override
  bool canInsertFromSide(Direction side) => !depotBehaviour.isOccupied(side);

  @override
  bool isOccupied(Direction side) => depotBehaviour.isOccupied(side);

  @override
  FutureOr<ItemValue> handleInsertion(
    TransportedItemStack transported,
    Direction side, {
    bool simulate = false,
  }) => depotBehaviour.tryInsertingFromSide(transported, side, simulate).stack;

  // -- TransportedItemStackHandler -------------------------------------------------------------

  @override
  void handleCenteredProcessingOnAllItems(
    double maxDistanceFromCenter,
    ItemProcessor processFunction,
  ) => depotBehaviour.applyToAllItemsPure(
    maxDistanceFromCenter,
    processFunction,
  );

  @override
  void handleProcessingOnAllItems(ItemProcessor processFunction) =>
      handleCenteredProcessingOnAllItems(.51, processFunction);

  @override
  void handleProcessingOnItem(
    TransportedItemStack item,
    TransportedResult result,
  ) => handleCenteredProcessingOnAllItems(
    .51,
    (t) => identical(t, item) ? result : null,
  );

  @override
  (double, double, double) getWorldPositionOf(
    TransportedItemStack transported,
  ) => (this.pos.x + .5, this.pos.y + .5, this.pos.z + .5);
}

/// `DepotItemHandler`: slot 0 is the held item, slots 1..8 the processing output buffer.
final class _DepotInventory implements ItemInventory {
  static const int _mainSlot = 0;

  final DepotBlockEntity be;

  _DepotInventory(this.be);

  DepotBehaviour get behaviour => be.depotBehaviour;

  @override
  int get slots => 9;

  @override
  ItemValue getStack(int slot) {
    if (slot == _mainSlot) return behaviour.getHeldItemStack();
    final bufferSlot = slot - 1;
    if (bufferSlot < 0 || bufferSlot >= behaviour.processingOutputBuffer.slots)
      return ItemValue.empty;
    return behaviour.processingOutputBuffer.getStack(bufferSlot);
  }

  @override
  int slotLimit(int slot) => slot == _mainSlot
      ? (behaviour.maxStackSize == 0 ? 64 : behaviour.maxStackSize)
      : 64;

  @override
  bool isItemValid(int slot, ItemValue stack) =>
      slot == _mainSlot && behaviour.isItemValid(stack);

  @override
  ItemValue insert(int slot, ItemValue stack, {bool simulate = false}) {
    if (slot != _mainSlot) return stack;
    if (behaviour.getHeldItemStack().isNotEmpty && !behaviour.canMergeItems())
      return stack;
    if (!behaviour.isOutputEmpty() && !behaviour.canMergeItems()) return stack;
    return behaviour.insert(TransportedItemStack(stack), simulate);
  }

  @override
  ItemValue extract(int slot, int amount, {bool simulate = false}) {
    if (slot != _mainSlot) {
      final bufferSlot = slot - 1;
      if (bufferSlot < 0 ||
          bufferSlot >= behaviour.processingOutputBuffer.slots)
        return ItemValue.empty;
      return behaviour.processingOutputBuffer.extract(
        bufferSlot,
        amount,
        simulate: simulate,
      );
    }
    final held = behaviour.heldItem;
    if (held == null) return ItemValue.empty;
    final (taken, rest) = held.stack.split(amount);
    if (!simulate) {
      if (rest.isEmpty) {
        behaviour.heldItem = null;
      } else {
        held.stack = rest;
      }
      be.markDirty();
    }
    return taken;
  }
}
