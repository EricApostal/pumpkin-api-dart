// `GhostItemMenu.quickMoveStack` for the ghost menus whose ghost inventory allows repeats
// (`allowRepeats() == true`: the redstone requester, the linked controller, the factory gauge
// filter and the schedule pickers). The Java method
// (`foundation/gui/menu/GhostItemMenu.java:103-124`) is:
//
//     if (index < 36) {              // a player-inventory slot
//         ItemStack stackToInsert = slot.getItem();
//         for (int i = 0; i < ghostInventory.getSlots(); i++) {
//             if (!allowRepeats() && sameItemSameComponents(ghost[i], stackToInsert)) break;
//             if (ghost[i].isEmpty()) { copy.setCount(1); insertItem(i, copy); break; }
//         }
//     } else {                       // a ghost slot
//         ghostInventory.extractItem(index - 36, 1, false);   // one item leaves
//     }
//
// `allowRepeats()` is true for every menu that uses this helper, so the "stop at the first slot
// with the same item" rule is dropped and a shift-click from the player inventory always looks for
// the first *empty* ghost slot. The decision is pure: the caller supplies the ghost occupancy and
// applies the result to its own session, then pushes the updated slot(s) to the client.
import '../logistics/filter/filter_menu_clicks.dart' show ghostMenuPlayerSlots;
import '../logistics/model/stack.dart';

/// What a `GhostItemMenu.quickMoveStack` shift-click transfers on a ghost menu that allows repeats.
final class GhostQuickMove {
  /// The ghost slot the click touches (`0` based), `-1` for [none].
  final int ghost;

  /// The one-item stack to write into [ghost] (empty for [GhostQuickMove.take] and [none]).
  final LStack stack;

  /// Whether the click removes one item from [ghost] instead of writing [stack]
  /// (`ghostInventory.extractItem(ghost, 1, false)`).
  final bool take;

  const GhostQuickMove._(this.ghost, this.stack, this.take);

  /// The click transfers nothing (`quickMoveStack` returned `ItemStack.EMPTY` without a change).
  static const GhostQuickMove none = GhostQuickMove._(-1, LStack.empty, false);

  /// The click copies one item of [stack] into ghost slot [ghost].
  const GhostQuickMove.write(int ghost, LStack stack) : this._(ghost, stack, false);

  /// The click removes one item from ghost slot [ghost].
  const GhostQuickMove.take(int ghost) : this._(ghost, LStack.empty, true);

  /// Whether the click transfers nothing.
  bool get isNone => ghost < 0;
}

/// `GhostItemMenu.quickMoveStack(playerIn, menuSlot)` of a ghost menu whose `allowRepeats()` is
/// `true`.
///
/// [menuSlot] is the client's menu slot: `0..35` is the player inventory mirror, `36` on are the
/// ghost slots (`GhostMenu`). [source] is the stack of the mirror slot (read only for a shift-click
/// from it). [ghostSlots] is `ghostInventory.getSlots()` and [ghostEmpty] answers whether ghost slot
/// [i] is empty (the Java loop stops at the first empty slot and skips an empty extract target).
///
/// A slot outside the menu, an empty source, no empty ghost slot, and an empty ghost slot in the
/// extract direction all return [GhostQuickMove.none].
GhostQuickMove ghostQuickMove({
  required int menuSlot,
  required LStack source,
  required int ghostSlots,
  required bool Function(int ghost) ghostEmpty,
}) {
  if (menuSlot < 0) return GhostQuickMove.none;
  if (menuSlot < ghostMenuPlayerSlots) {
    // `quickMoveStack(index < 36)`: a copy of one item into the first empty ghost slot.
    if (source.isEmpty) return GhostQuickMove.none;
    for (var i = 0; i < ghostSlots; i++) {
      if (ghostEmpty(i)) return GhostQuickMove.write(i, source.withCount(1));
    }
    return GhostQuickMove.none;
  }
  final ghost = menuSlot - ghostMenuPlayerSlots;
  if (ghost < 0 || ghost >= ghostSlots) return GhostQuickMove.none;
  // `quickMoveStack(index >= 36)`: one item leaves the ghost slot; an empty slot is a no-op.
  if (ghostEmpty(ghost)) return GhostQuickMove.none;
  return GhostQuickMove.take(ghost);
}