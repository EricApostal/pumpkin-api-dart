// The click rules of the three filter screens (`GhostItemMenu` and its subclasses of the Java
// port) as pure functions: the menu slot layout, which ghost slot a click writes, what the
// attribute filter's reference and display slots do, and the shift-click of the player inventory.
// The screens are plugin menus the server tracks with a mirror of the player inventory, so the
// plugin applies the ghost clicks itself (see `filter_menu_session.dart`). Pure; no host access.
import '../model/stack.dart';
import 'filter_item_stack.dart';

/// Which filter screen is open (`FilterMenu`, `AttributeFilterMenu`, `PackageFilterMenu`).
enum FilterMenuKind {
  list('create:filter'),
  attribute('create:attribute_filter'),
  package('create:package_filter');

  const FilterMenuKind(this.menuType);

  /// The key of the menu type the client opens.
  final String menuType;

  static FilterMenuKind? of(String filterItemKey) => switch (filterItemKey) {
    FilterItemKeys.list => list,
    FilterItemKeys.attribute => attribute,
    FilterItemKeys.package => package,
    _ => null,
  };

  static FilterMenuKind? ofMenuType(String menuType) {
    for (final kind in values) {
      if (kind.menuType == menuType) return kind;
    }
    return null;
  }
}

/// The mode of a click, the `ContainerInput` of the click packet.
enum GhostClickMode { pickup, quickMove, swap, clone, throw_, quickCraft, pickupAll }

/// The number of player inventory slots `MenuBase.addPlayerSlots` adds. Every filter menu adds
/// them before its ghost slots, so the ghost slots start at this index.
const int ghostMenuPlayerSlots = 36;

/// The menu slot of the player inventory index [inventoryIndex] (`MenuBase.addPlayerSlots`: the
/// main inventory 9 to 35 first, then the hotbar 0 to 8).
int playerMenuSlotOf(int inventoryIndex) =>
    inventoryIndex >= 9 ? inventoryIndex - 9 : inventoryIndex + 27;

/// The player inventory index of the menu slot [menuSlot], `null` for a ghost slot.
int? inventoryIndexAt(int menuSlot) {
  if (menuSlot < 0 || menuSlot >= ghostMenuPlayerSlots) return null;
  return menuSlot < 27 ? menuSlot + 9 : menuSlot - 27;
}

/// The number of slots the menu of [kind] has on the client: the player inventory, then the ghost
/// slots (`AbstractFilterMenu.addSlots`).
int filterMenuSlotCount(FilterMenuKind kind) =>
    ghostMenuPlayerSlots + ghostSlotCount(kind);

/// The display slot of the attribute filter (`AttributeFilterMenu.init` puts a name tag listing
/// the selected attributes there). It never takes items.
const int attributeDisplaySlot = 1;

/// `createGhostInventory().getSlots()`.
int ghostSlotCount(FilterMenuKind kind) => switch (kind) {
  FilterMenuKind.list => 18,
  FilterMenuKind.attribute => 2,
  FilterMenuKind.package => 0,
};

/// `GhostItemMenu.allowRepeats()`: all three filter menus are false, so a list filter refuses a
/// second copy of an item it already contains and drags cannot enter the ghost slots.
bool ghostMenuAllowRepeats(FilterMenuKind kind) => false;

/// What one click did to the ghost inventory.
final class GhostClick {
  /// The ghost slot whose contents changed, `-1` for none.
  final int changedSlot;

  /// The new contents of [changedSlot].
  final LStack stack;

  /// The stack the cursor should hold after the click, `null` to leave it alone.
  final LStack? cursor;

  const GhostClick.none()
    : changedSlot = -1,
      stack = LStack.empty,
      cursor = null;

  const GhostClick(this.changedSlot, this.stack, {this.cursor});

  bool get isEmpty => changedSlot < 0 && cursor == null;
}

/// `GhostItemMenu.clicked` and `quickMoveStack` for a filter screen.
final class FilterGhostMenu {
  FilterGhostMenu(this.kind, {List<LStack>? slots})
    : slots = slots ?? List<LStack>.filled(ghostSlotCount(kind), LStack.empty, growable: false) {
    assert(this.slots.length == ghostSlotCount(kind), 'a ${kind.name} filter has ${ghostSlotCount(kind)} ghost slots');
  }

  final FilterMenuKind kind;

  /// The ghost inventory; mutated only through [apply].
  final List<LStack> slots;

  /// Applies [click] to the ghost inventory and returns whether anything changed.
  bool apply(GhostClick click) {
    if (click.changedSlot < 0) return click.cursor != null;
    if (click.changedSlot >= slots.length) return false;
    final previous = slots[click.changedSlot];
    slots[click.changedSlot] = click.stack;
    return previous.count != click.stack.count ||
        !previous.sameItemSameComponents(click.stack);
  }

  /// The click of [mode] on [menuSlot] (0 based, the player inventory slots first).
  ///
  /// [carried] is the server's cursor stack, [source] the stack of the clicked player inventory
  /// slot (read only for a shift-click from it) and [creative] the player's game mode.
  GhostClick click({
    required int menuSlot,
    required int button,
    required GhostClickMode mode,
    required LStack carried,
    LStack source = LStack.empty,
    bool creative = false,
  }) {
    if (menuSlot < 0 || menuSlot == -999) return const GhostClick.none();

    if (menuSlot < ghostMenuPlayerSlots) {
      if (mode != GhostClickMode.quickMove || source.isEmpty) return const GhostClick.none();
      return _quickMoveFromPlayer(source);
    }

    final ghost = menuSlot - ghostMenuPlayerSlots;
    if (ghost < 0 || ghost >= slots.length) return const GhostClick.none();

    // `GhostItemMenu.clicked`: THROW is ignored, CLONE copies in creative mode, everything else
    // writes one item of the cursor into the slot.
    if (mode == GhostClickMode.throw_) return const GhostClick.none();
    if (kind == FilterMenuKind.attribute) {
      if (ghost == attributeDisplaySlot) return const GhostClick.none();
      // `AttributeFilterMenu.quickMoveStack(index == 36)` clears the selected-attributes slot.
      // (Java writes index 37 of a two slot handler, which throws; the intent is the display
      // slot.)
      if (ghost == 0 && mode == GhostClickMode.quickMove) {
        return const GhostClick(attributeDisplaySlot, LStack.empty);
      }
    }
    if (mode == GhostClickMode.clone) {
      if (!creative || carried.isNotEmpty) return const GhostClick.none();
      final stack = slots[ghost];
      return stack.isEmpty
          ? const GhostClick.none()
          : GhostClick(-1, LStack.empty, cursor: stack.withCount(stack.maxStack));
    }
    // `canDragTo`: the client refuses a drag into the ghost slots of a menu without repeats, so
    // the server must refuse it too (the two ghost inventories have to stay in step).
    if (mode == GhostClickMode.quickCraft && !ghostMenuAllowRepeats(kind)) {
      return const GhostClick.none();
    }
    return GhostClick(ghost, carried.isEmpty ? LStack.empty : carried.withCount(1));
  }

  /// `GhostItemMenu.quickMoveStack(index < 36)` and the attribute filter's override.
  GhostClick _quickMoveFromPlayer(LStack source) {
    switch (kind) {
      case FilterMenuKind.package:
        // `PackageFilterMenu.quickMoveStack` returns empty without doing anything.
        return const GhostClick.none();
      case FilterMenuKind.attribute:
        // The reference item replaces ghost slot 0 (`setStackInSlot(0, copy)`).
        return GhostClick(0, source.withCount(1));
      case FilterMenuKind.list:
        for (var i = 0; i < slots.length; i++) {
          // `allowRepeats()` is false: stop at the first ghost slot that already has the item.
          if (!ghostMenuAllowRepeats(kind) && slots[i].sameItemSameComponents(source)) {
            return const GhostClick.none();
          }
          if (slots[i].isEmpty) return GhostClick(i, source.withCount(1));
        }
        return const GhostClick.none();
    }
  }
}
