// `UnpackingHandler` and its implementations (pure). A packager unpacks a box into the inventory
// behind its facing; the handler is chosen by the block at the target position
// (`AllUnpackingHandlers`).
import '../model/inventory.dart';
import '../model/stack.dart';

/// `UnpackingHandler.unpack`: insert [items] into [target], or only check that they fit.
abstract interface class UnpackingHandler {
  Future<bool> unpack(
    ItemInv target,
    List<LStack> items, {
    required bool simulate,
  });
}

/// `DefaultUnpackingHandler`: fills the inventory stack by stack.
final class DefaultUnpackingHandler implements UnpackingHandler {
  const DefaultUnpackingHandler();

  @override
  Future<bool> unpack(
    ItemInv target,
    List<LStack> items, {
    required bool simulate,
  }) async {
    if (!simulate) {
      // Some inventories do not support slot-by-slot precision; the simulate pass already
      // established that everything fits.
      for (final stack in items) {
        await insertStacked(target, stack, simulate: false);
      }
      return true;
    }

    final slots = target.slots;
    for (var slot = 0; slot < slots; slot++) {
      var itemInSlot = await target.stackAt(slot);
      var itemsAddedToSlot = 0;

      for (var boxSlot = 0; boxSlot < items.length; boxSlot++) {
        var toInsert = items[boxSlot];
        if (toInsert.isEmpty) continue;

        final rejected = await target.insert(slot, toInsert, simulate: true);
        if (rejected.count == toInsert.count) continue;

        if (itemInSlot.isEmpty) {
          final limit = await target.slotLimit(slot);
          if (limit < toInsert.count) toInsert = toInsert.withCount(limit);
          items[boxSlot] = LStack.empty;
          itemInSlot = toInsert;
          await target.insert(slot, toInsert, simulate: simulate);
          continue;
        }

        if (!toInsert.sameItemSameComponents(itemInSlot)) continue;

        final remainder = await target.insert(
          slot,
          toInsert,
          simulate: simulate,
        );
        final insertedAmount = toInsert.count - remainder.count;
        final slotLimit = itemInSlot.maxStack < await target.slotLimit(slot)
            ? itemInSlot.maxStack
            : await target.slotLimit(slot);
        final insertable =
            toInsert.count < slotLimit - itemInSlot.count - itemsAddedToSlot
            ? toInsert.count
            : slotLimit - itemInSlot.count - itemsAddedToSlot;

        final added = insertedAmount < insertable
            ? insertedAmount
            : (insertable < 0 ? 0 : insertable);
        itemsAddedToSlot += added;
        items[boxSlot] = toInsert.withCount(toInsert.count - added);
      }
    }

    for (final stack in items) {
      if (stack.isNotEmpty) return false;
    }
    return true;
  }
}

/// `VoidingUnpackingHandler`: a creative crate swallows the contents.
final class VoidingUnpackingHandler implements UnpackingHandler {
  const VoidingUnpackingHandler();

  @override
  Future<bool> unpack(
    ItemInv target,
    List<LStack> items, {
    required bool simulate,
  }) async => true;
}

/// `AllUnpackingHandlers`: the handlers registered per block key.
abstract final class UnpackingHandlers {
  static const UnpackingHandler defaultHandler = DefaultUnpackingHandler();
  static const UnpackingHandler voiding = VoidingUnpackingHandler();

  static const Map<String, UnpackingHandler> _byBlock = {
    'create:creative_crate': voiding,
  };

  static UnpackingHandler of(String blockKey) =>
      _byBlock[blockKey] ?? defaultHandler;
}
