// The player inventory mirror of a plugin menu whose client layout is a Create `GhostItemMenu`.
//
// Every Create ghost menu adds the 36 player slots **before** its own slots
// (`MenuBase.addPlayerSlots` runs first, then the ghost slots: `AbstractFilterMenu.addSlots`,
// `BlueprintMenu.addSlots`, `ScheduleMenu.addSlots`), so the client's menu indices are the player
// inventory first and the ghost slots from 36 on. The host's plugin menus put their own slots
// first (`PluginMenuScreenHandler::new`), so such a menu is opened with `playerInventory: false`
// and `36 + ghosts` slots: the plugin mirrors the real player inventory into the first 36 and
// writes the clicks on them back — the layout the filter screens and the redstone requester use.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../logistics/filter/filter_menu_clicks.dart'
    show ghostMenuPlayerSlots, inventoryIndexAt;

/// Sends the real player inventory to the mirror slots `0` to `35` of the player's open menu.
Future<void> fillPlayerMirror(Player player) async {
  final playerInventory = player.getInventory();
  final inventory = playerInventory.asInventory();
  playerInventory.dispose();
  try {
    for (var menuSlot = 0; menuSlot < ghostMenuPlayerSlots; menuSlot++) {
      final index = inventoryIndexAt(menuSlot);
      if (index == null) continue;
      await setMenuSlot(player, menuSlot, inventory.getItem(slot: index));
    }
  } finally {
    inventory.dispose();
  }
}

/// Puts [stack] into [menuSlot] of the player's open menu, `null` (or an empty stack) clears it.
Future<void> setMenuSlot(Player player, int menuSlot, ItemStack? stack) async {
  try {
    if (stack == null || await stack.getCount() == 0) {
      player.clearPluginMenuSlot(menuSlot);
    } else {
      player.setPluginMenuSlot(menuSlot, stack);
    }
  } on Object {
    // the menu closed meanwhile
  }
}

/// `Events.menuSlotChanged` for a mirror slot: writes the click back into the real inventory and
/// returns `true`. Any other slot is the menu's own and left to the caller (`false`).
Future<bool> applyPlayerMirrorChange(Player player, MenuSlotChange change) async {
  final index = inventoryIndexAt(change.slot);
  if (index == null) return false;
  final playerInventory = player.getInventory();
  final inventory = playerInventory.asInventory();
  playerInventory.dispose();
  try {
    final real = inventory.getItem(slot: index);
    // The mirror can fall behind the real inventory (an item picked up while the screen is open).
    // When it did, the menu's value is stale: keep the real stack and correct the client instead
    // of overwriting it.
    if (!await sameStack(change.previous, real)) {
      await setMenuSlot(player, change.slot, real);
      return true;
    }
    final count = await change.stack.getCount();
    await inventory.setItem(
      slot: index,
      item: count <= 0 ? null : change.stack,
    );
  } finally {
    inventory.dispose();
  }
  return true;
}

/// Whether two stacks hold the same item (`ItemStack.isSameItemSameComponents`, compared on the
/// registry key and the count: the components the mirror could differ in follow the item key).
Future<bool> sameStack(ItemStack? a, ItemStack? b) async {
  final aEmpty = a == null || await a.getCount() <= 0;
  final bEmpty = b == null || await b.getCount() <= 0;
  if (aEmpty || bEmpty) return aEmpty && bEmpty;
  if (await a.getCount() != await b.getCount()) return false;
  return await a.getRegistryKey() == await b.getRegistryKey();
}

/// The stack of the player inventory slot behind the menu slot [menuSlot], `null` when the menu
/// slot is not a mirror slot.
Future<ItemStack?> playerStackAt(Player player, int menuSlot) async {
  final index = inventoryIndexAt(menuSlot);
  if (index == null) return null;
  final playerInventory = player.getInventory();
  final inventory = playerInventory.asInventory();
  playerInventory.dispose();
  try {
    return inventory.getItem(slot: index);
  } finally {
    inventory.dispose();
  }
}

/// The stack in the player's hotbar slot [hotbar] (`GhostItemMenu.quickMoveStack` number keys).
Future<ItemStack?> hotbarStack(Player player, int hotbar) async {
  if (hotbar < 0 || hotbar > 8) return null;
  final playerInventory = player.getInventory();
  final inventory = playerInventory.asInventory();
  playerInventory.dispose();
  try {
    return inventory.getItem(slot: hotbar);
  } finally {
    inventory.dispose();
  }
}