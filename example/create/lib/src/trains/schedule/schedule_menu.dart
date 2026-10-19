// `ScheduleMenu` (pure state): the host menu of the schedule item. It is a `HeldItemGhostItemMenu`
// with two ghost slots (the item / fluid / frequency pickers of the conditions). The server keeps
// the ghost contents only to answer `GhostItemSubmitPacket`; `saveData` does nothing, the schedule
// itself is saved by `ScheduleEditPacket`. The menu is opened by `schedule_host.dart`.
import '../../protocol/item_stack.dart' show ItemStackData;

class ScheduleMenu {
  /// `static final int slots = 2`.
  static const int slots = 2;

  /// The uuid of the player the menu was opened for.
  final String playerUuid;

  /// `slotsActive`.
  bool slotsActive = true;

  /// `targetSlotsActive`.
  int targetSlotsActive = 1;

  /// `ghostInventory`.
  final List<ItemStackData> ghostInventory = List.filled(slots, ItemStackData.empty);

  ScheduleMenu(this.playerUuid);

  /// `allowRepeats()`.
  bool get allowRepeats => true;

  /// `ghostInventory.setStackInSlot(slot, item)`; slots outside the inventory are ignored.
  bool setGhost(int slot, ItemStackData item) {
    if (slot < 0 || slot >= slots) return false;
    ghostInventory[slot] = item;
    return true;
  }
}
