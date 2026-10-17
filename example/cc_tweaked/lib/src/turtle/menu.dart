// The slot logic of the turtle menu: vanilla's container click semantics
// (`AbstractContainerMenu.doClick`) over the 54 slots of `TurtleMenu`, written
// against [MenuSlotAccess] so that it needs no host bindings.
//
// The host does not apply clicks in plugin menus: every click arrives as an
// event and the plugin must do what the click means. Two host limits shape
// this file (docs/host-requirements.md, "Turtle GUI"):
//
// * the host has no call to set the **cursor** (carried) stack, and after every
//   click it resends the menu with an empty cursor. A real cursor would be
//   cleared on every click, so the picked up stack is kept by the plugin
//   ([MenuLogic.cursor], a *virtual* cursor): the client shows an empty cursor
//   while the plugin holds the stack. The plugin tells the player what they hold
//   in the action bar, and gives the stack back to the inventory when the menu
//   closes;
// * the host reports a click as slot, button and a [TurtleClick] derived from the
//   packet mode, with drags (`QUICK_CRAFT`) indistinguishable from a click
//   outside the window / a right click on a slot. A drag is recognised by its
//   sequence (start outside the window with button 0, 4 or 8, adds with button 1,
//   5 or 9 on slots, end outside with button 2, 6 or 10) and ignored when the
//   sequence is not complete within [dragTimeoutTicks].
//
// Not done: throwing items out of the menu (Q, click outside): the host cannot
// spawn an item entity. The click is ignored and the stack stays.
//
// Layout (`TurtleMenu`): 0..15 the turtle's slots, 16..42 the player's main
// inventory (inventory slots 9..35), 43..51 the hotbar (0..8), 52 and 53 the
// left and right upgrade.
import 'stack.dart';

/// The slots of the turtle menu.
abstract final class TurtleMenuLayout {
  static const int turtleSlots = 16;
  static const int playerStart = 16;
  static const int hotbarStart = 43;
  static const int leftUpgrade = 52;
  static const int rightUpgrade = 53;
  static const int slotCount = 54;

  /// The menu slot of a player inventory slot (0..8 hotbar, 9..35 main), or
  /// -1 for any other.
  static int menuSlotOfInventory(int inventorySlot) {
    if (inventorySlot >= 9 && inventorySlot <= 35) return playerStart + inventorySlot - 9;
    if (inventorySlot >= 0 && inventorySlot <= 8) return hotbarStart + inventorySlot;
    return -1;
  }

  /// The player inventory slot behind a menu slot, or -1 for the turtle and
  /// upgrade slots.
  static int inventorySlotOfMenu(int menuSlot) {
    if (menuSlot >= playerStart && menuSlot < hotbarStart) return menuSlot - playerStart + 9;
    if (menuSlot >= hotbarStart && menuSlot < leftUpgrade) return menuSlot - hotbarStart;
    return -1;
  }

  static bool isUpgrade(int menuSlot) => menuSlot == leftUpgrade || menuSlot == rightUpgrade;
}

/// The click kinds the host reports (`click-type`).
enum TurtleClick { left, right, shiftLeft, shiftRight, middle, drop, controlDrop, doubleClick, numberKey, unknown }

/// How long a drag may take between its packets, in ticks. The client sends all
/// the packets of a drag in one go when the mouse button is released.
const int dragTimeoutTicks = 3;

/// The 54 slots as the logic reads and writes them.
abstract interface class MenuSlotAccess implements ItemInfo {
  /// A copy of what is in [slot], null if empty.
  TurtleStack? read(int slot);

  /// Stores [stack] (null empties the slot). The stack is not kept.
  void write(int slot, TurtleStack? stack);

  /// `Slot.mayPlace`.
  bool mayPlace(int slot, TurtleStack stack);

  /// The off hand item of the player (the number key 40 swap).
  TurtleStack? readOffhand();

  void writeOffhand(TurtleStack? stack);

  /// Whether the player is in creative mode (middle click clones a stack).
  bool get isCreative;
}

final class _Drag {
  final int type;
  final int startedAt;
  final List<int> slots = [];

  _Drag(this.type, this.startedAt);
}

/// The click logic of one open turtle menu.
final class MenuLogic {
  /// The slots the logic works on; the plugin replaces it for every click (the
  /// player handle inside is only valid during one callback).
  MenuSlotAccess slots;

  /// The stack the player carries (virtual, see the library comment).
  TurtleStack? cursor;

  /// Called after the logic changed what the cursor holds.
  void Function()? onCursorChanged;

  _Drag? _drag;

  MenuLogic(this.slots);

  // -- Slot rules -----------------------------------------------------------------

  /// `Slot.getMaxStackSize(stack)`: upgrade slots hold one, the others the
  /// item's stack size.
  int maxStackSize(int slot, TurtleStack stack) =>
      TurtleMenuLayout.isUpgrade(slot) ? 1 : slots.maxStack(stack.item);

  bool _valid(int slot) => slot >= 0 && slot < TurtleMenuLayout.slotCount;

  /// `Slot.safeInsert`: inserts up to [amount] of [stack] into [slot], returns
  /// what is left of [stack].
  TurtleStack? _safeInsert(int slot, TurtleStack stack, int amount) {
    if (!slots.mayPlace(slot, stack)) return stack;
    final current = slots.read(slot);
    final room = maxStackSize(slot, stack) - (current?.count ?? 0);
    var toInsert = amount < stack.count ? amount : stack.count;
    if (toInsert > room) toInsert = room;
    if (toInsert <= 0) return stack;
    if (current == null) {
      slots.write(slot, stack.copy(count: toInsert));
    } else if (current.sameItem(stack)) {
      current.count += toInsert;
      slots.write(slot, current);
    } else {
      return stack;
    }
    final left = stack.copy(count: stack.count - toInsert);
    return left.isEmpty ? null : left;
  }

  // -- Entry point -------------------------------------------------------------------

  /// Handles one click. [slot] is `-999` outside the window, [tick] the
  /// current server tick (for the drag timeout).
  void click(int slot, int button, TurtleClick type, int tick) {
    if (_handleDrag(slot, button, tick)) return;
    switch (type) {
      case TurtleClick.left:
      case TurtleClick.right:
        _pickup(slot, type == TurtleClick.left);
      case TurtleClick.shiftLeft:
      case TurtleClick.shiftRight:
        _quickMove(slot);
      case TurtleClick.numberKey:
        _swap(slot, button);
      case TurtleClick.middle:
        _clone(slot);
      case TurtleClick.doubleClick:
        _pickupAll(slot, button);
      case TurtleClick.drop:
      case TurtleClick.controlDrop:
      case TurtleClick.unknown:
        // Throwing needs an item entity: ignored.
        break;
    }
    onCursorChanged?.call();
  }

  // -- Pickup (left and right click) ------------------------------------------------------

  void _pickup(int slot, bool primary) {
    if (slot == -999 || slot < 0) return; // throwing the cursor: not possible
    if (!_valid(slot)) return;
    final slotStack = slots.read(slot);
    final carried = cursor;
    if (slotStack == null) {
      if (carried != null) {
        cursor = _safeInsert(slot, carried, primary ? carried.count : 1);
      }
    } else if (carried == null) {
      final amount = primary ? slotStack.count : (slotStack.count + 1) ~/ 2;
      final taken = slotStack.copy(count: amount);
      slotStack.count -= amount;
      slots.write(slot, slotStack.count <= 0 ? null : slotStack);
      cursor = taken;
    } else if (slots.mayPlace(slot, carried)) {
      if (slotStack.sameItem(carried)) {
        cursor = _safeInsert(slot, carried, primary ? carried.count : 1);
      } else if (carried.count <= maxStackSize(slot, carried)) {
        cursor = slotStack;
        slots.write(slot, carried);
      }
    } else if (slotStack.sameItem(carried)) {
      // Take what fits onto the cursor stack.
      final max = slots.maxStack(carried.item);
      final take = slotStack.count < max - carried.count ? slotStack.count : max - carried.count;
      if (take > 0) {
        carried.count += take;
        slotStack.count -= take;
        slots.write(slot, slotStack.count <= 0 ? null : slotStack);
      }
    }
  }

  // -- Quick move (shift click) ------------------------------------------------------------

  /// `TurtleMenu.quickMoveStack` repeated as `doClick` does: moves the stack
  /// of [slot] to the other side, again while the slot still holds the same
  /// item.
  void _quickMove(int slot) {
    if (!_valid(slot)) return;
    var moved = _quickMoveStack(slot);
    var guard = 0;
    while (moved != null && guard++ < 64) {
      final now = slots.read(slot);
      if (now == null || !now.sameItem(moved)) break;
      moved = _quickMoveStack(slot);
    }
  }

  TurtleStack? _quickMoveStack(int slot) {
    if (slot >= 0 && slot < TurtleMenuLayout.turtleSlots) return _tryItemMerge(slot, 16, 52, true);
    if (slot >= TurtleMenuLayout.turtleSlots) return _tryItemMerge(slot, 0, 16, false);
    return null;
  }

  TurtleStack? _tryItemMerge(int slot, int first, int last, bool reverse) {
    final clicked = slots.read(slot);
    if (clicked == null) return null;
    final original = clicked.copy();
    if (!_moveItemStackTo(clicked, first, last, reverse)) return null;
    slots.write(slot, clicked.isEmpty ? null : clicked);
    if (clicked.count != original.count) return original;
    return null;
  }

  /// `AbstractContainerMenu.moveItemStackTo`: first onto existing stacks, then
  /// into the first empty slot that accepts it. Changes [stack] to what is
  /// left.
  bool _moveItemStackTo(TurtleStack stack, int start, int end, bool reverse) {
    var moved = false;
    final stackable = slots.maxStack(stack.item) > 1;
    if (stackable) {
      var i = reverse ? end - 1 : start;
      while (stack.count > 0 && (reverse ? i >= start : i < end)) {
        final target = slots.read(i);
        if (target != null && target.sameItem(stack)) {
          final max = maxStackSize(i, target);
          final total = target.count + stack.count;
          if (total <= max) {
            target.count = total;
            stack.count = 0;
            slots.write(i, target);
            moved = true;
          } else if (target.count < max) {
            stack.count -= max - target.count;
            target.count = max;
            slots.write(i, target);
            moved = true;
          }
        }
        i += reverse ? -1 : 1;
      }
    }
    if (stack.count > 0) {
      var i = reverse ? end - 1 : start;
      while (reverse ? i >= start : i < end) {
        if (slots.read(i) == null && slots.mayPlace(i, stack)) {
          final max = maxStackSize(i, stack);
          final put = stack.count < max ? stack.count : max;
          slots.write(i, stack.copy(count: put));
          stack.count -= put;
          moved = true;
          break;
        }
        i += reverse ? -1 : 1;
      }
    }
    return moved;
  }

  // -- Number key swap ---------------------------------------------------------------------

  /// `ClickType.SWAP`: [button] is the hotbar slot 0..8, or 40 for the off hand.
  void _swap(int slot, int button) {
    if (!_valid(slot)) return;
    final TurtleStack? hot;
    if (button >= 0 && button <= 8) {
      hot = slots.read(TurtleMenuLayout.hotbarStart + button);
    } else if (button == 40) {
      hot = slots.readOffhand();
    } else {
      return;
    }
    final current = slots.read(slot);
    if (hot == null && current == null) return;

    void setHot(TurtleStack? stack) {
      if (button == 40) {
        slots.writeOffhand(stack);
      } else {
        slots.write(TurtleMenuLayout.hotbarStart + button, stack);
      }
    }

    // The slot being the hot bar slot itself changes nothing.
    if (button >= 0 && button <= 8 && slot == TurtleMenuLayout.hotbarStart + button) return;

    if (hot == null) {
      setHot(current);
      slots.write(slot, null);
    } else if (current == null) {
      if (!slots.mayPlace(slot, hot)) return;
      final max = maxStackSize(slot, hot);
      if (hot.count > max) {
        slots.write(slot, hot.copy(count: max));
        hot.count -= max;
        setHot(hot);
      } else {
        setHot(null);
        slots.write(slot, hot);
      }
    } else if (slots.mayPlace(slot, hot)) {
      final max = maxStackSize(slot, hot);
      if (hot.count > max) {
        // Put the part that fits; the old stack goes to the player's inventory
        // if there is room (otherwise nothing changes).
        final rest = _giveToPlayer(current);
        if (rest != null) return;
        slots.write(slot, hot.copy(count: max));
        hot.count -= max;
        setHot(hot);
      } else {
        setHot(current);
        slots.write(slot, hot);
      }
    }
  }

  // -- Clone (middle click) -----------------------------------------------------------------

  void _clone(int slot) {
    if (!slots.isCreative || cursor != null || !_valid(slot)) return;
    final stack = slots.read(slot);
    if (stack == null) return;
    cursor = stack.copy(count: slots.maxStack(stack.item));
  }

  // -- Double click ---------------------------------------------------------------------------

  /// `ClickType.PICKUP_ALL`: collects the items equal to the cursor stack from
  /// every slot onto the cursor stack, stacks that are not full first.
  void _pickupAll(int slot, int button) {
    final carried = cursor;
    if (carried == null) return;
    final max = slots.maxStack(carried.item);
    for (var pass = 0; pass < 2; pass++) {
      for (var i = 0; i < TurtleMenuLayout.slotCount && carried.count < max; i++) {
        final stack = slots.read(i);
        if (stack == null || !stack.sameItem(carried)) continue;
        if (pass == 0 && stack.count == maxStackSize(i, stack)) continue;
        final take = stack.count < max - carried.count ? stack.count : max - carried.count;
        carried.count += take;
        stack.count -= take;
        slots.write(i, stack.count <= 0 ? null : stack);
      }
    }
  }

  // -- Drag --------------------------------------------------------------------------------------

  /// Recognises a drag sequence. Returns true when the click belongs to a drag.
  bool _handleDrag(int slot, int button, int tick) {
    final drag = _drag;
    if (drag != null && tick - drag.startedAt > dragTimeoutTicks) _drag = null;
    final active = _drag;
    if (slot == -999 && (button == 0 || button == 4 || button == 8) && cursor != null) {
      // A drag start (or a click outside, which does nothing either way).
      _drag = _Drag((button >> 2) & 3, tick);
      return true;
    }
    if (active == null) return false;
    if (slot >= 0 && (button == 1 || button == 5 || button == 9)) {
      _addToDrag(active, slot);
      return true;
    }
    if (slot == -999 && (button == 2 || button == 6 || button == 10)) {
      _drag = null;
      _finishDrag(active);
      onCursorChanged?.call();
      return true;
    }
    _drag = null;
    return false;
  }

  bool _canQuickReplace(int slot, TurtleStack carried) {
    final stack = slots.read(slot);
    if (stack == null) return true;
    if (stack.sameItem(carried)) {
      return stack.count <= slots.maxStack(carried.item);
    }
    return false;
  }

  void _addToDrag(_Drag drag, int slot) {
    final carried = cursor;
    if (carried == null || !_valid(slot) || drag.slots.contains(slot)) return;
    if (!_canQuickReplace(slot, carried) || !slots.mayPlace(slot, carried)) return;
    if (drag.type == 2 || carried.count > drag.slots.length) drag.slots.add(slot);
  }

  void _finishDrag(_Drag drag) {
    final source = cursor;
    if (source == null || drag.slots.isEmpty) return;
    if (drag.slots.length == 1) {
      _pickup(drag.slots.first, drag.type == 0);
      return;
    }
    var remaining = source.count;
    final placeCount = switch (drag.type) {
      0 => source.count ~/ drag.slots.length,
      1 => 1,
      _ => slots.maxStack(source.item),
    };
    for (final slot in drag.slots) {
      if (!_canQuickReplace(slot, source) || !slots.mayPlace(slot, source)) continue;
      if (drag.type != 2 && source.count < drag.slots.length) continue;
      final existing = slots.read(slot);
      final placed = existing?.count ?? 0;
      final max = slots.maxStack(source.item) < maxStackSize(slot, source) ? slots.maxStack(source.item) : maxStackSize(slot, source);
      final count = placeCount + placed < max ? placeCount + placed : max;
      remaining -= count - placed;
      slots.write(slot, source.copy(count: count));
    }
    cursor = remaining <= 0 ? null : source.copy(count: remaining);
  }

  // -- Closing --------------------------------------------------------------------------------------

  /// Puts the cursor stack into the player's inventory (the menu is closing).
  /// Returns what did not fit.
  TurtleStack? returnCursor() {
    final carried = cursor;
    cursor = null;
    if (carried == null) return null;
    return _giveToPlayer(carried);
  }

  /// Puts [stack] into the player's main inventory and hotbar (merging first).
  TurtleStack? _giveToPlayer(TurtleStack stack) {
    final rest = stack.copy();
    // Hotbar and main inventory, like `Inventory.add`: hotbar first.
    final order = [
      for (var i = TurtleMenuLayout.hotbarStart; i < TurtleMenuLayout.leftUpgrade; i++) i,
      for (var i = TurtleMenuLayout.playerStart; i < TurtleMenuLayout.hotbarStart; i++) i,
    ];
    final max = slots.maxStack(rest.item);
    for (final i in order) {
      if (rest.count <= 0) break;
      final current = slots.read(i);
      if (current != null && current.count < max && current.sameItem(rest)) {
        final take = rest.count < max - current.count ? rest.count : max - current.count;
        current.count += take;
        rest.count -= take;
        slots.write(i, current);
      }
    }
    for (final i in order) {
      if (rest.count <= 0) break;
      if (slots.read(i) == null) {
        final put = rest.count < max ? rest.count : max;
        slots.write(i, rest.copy(count: put));
        rest.count -= put;
      }
    }
    return rest.count <= 0 ? null : rest;
  }
}
