// `ItemHandlerContainer` (pure): a vanilla `Container` view of an [ItemSlots] handler, the base
// of [StorageInteractionWrapper]. The player type is generic because the container only calls
// [stillValid] / [startOpen] / [stopOpen] with the player it was opened for.
import '../../../contraptions/storage/stacks.dart';

/// `ItemHandlerContainer`.
abstract class ItemHandlerContainer<P> {
  final ItemSlots inv;

  const ItemHandlerContainer(this.inv);

  /// `getContainerSize`.
  int get containerSize => inv.slots;

  /// `getItem`: the stack in [slot].
  StoredStack getItem(int slot) => inv.stackInSlot(slot);

  /// `removeItem`: takes up to [count] items out of [slot] and returns them.
  StoredStack removeItem(int slot, int count) {
    final stack = inv.stackInSlot(slot);
    if (stack.isEmpty || count <= 0) return StoredStack.empty;
    final taken = count < stack.count ? count : stack.count;
    inv.setStackInSlot(slot, stack.shrink(taken));
    return stack.copyWithCount(taken);
  }

  /// `setItem`.
  void setItem(int slot, StoredStack stack) => inv.setStackInSlot(slot, stack);

  /// `removeItemNoUpdate`: removes the whole stack of [slot].
  StoredStack removeItemNoUpdate(int slot) {
    final stack = getItem(slot);
    if (stack.isEmpty) return StoredStack.empty;
    setItem(slot, StoredStack.empty);
    return stack;
  }

  /// `isEmpty`.
  bool get isEmpty {
    for (var i = 0; i < inv.slots; i++) {
      if (inv.stackInSlot(i).isNotEmpty) return false;
    }
    return true;
  }

  /// `canPlaceItem`.
  bool canPlaceItem(int slot, StoredStack stack) =>
      inv.isItemValid(slot, stack);

  /// `clearContent`.
  void clearContent() {
    for (var i = 0; i < inv.slots; i++) {
      inv.setStackInSlot(i, StoredStack.empty);
    }
  }

  /// `getMaxStackSize`: vanilla's default for containers that do not override it.
  int get maxStackSize => 0;

  /// `setChanged`.
  void setChanged() {}

  /// `stillValid`.
  bool stillValid(P player) => false;

  /// `startOpen`.
  void startOpen(P user) {}

  /// `stopOpen`.
  void stopOpen(P user) {}
}
