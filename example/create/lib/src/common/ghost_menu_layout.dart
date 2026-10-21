// The slot layout of the Create ghost menus the server tracks.
//
// Every one of them adds the 36 player slots **before** its own slots (`MenuBase.addPlayerSlots`
// runs first, then the ghost slots: `AbstractFilterMenu.addSlots`, `BlueprintMenu.addSlots`,
// `ScheduleMenu.addSlots`, `FactoryPanelSetItemMenu.addSlots`, `LinkedControllerMenu.addSlots`), so
// the client's menu indices are the player inventory first — `GhostItemMenu.clicked` tests
// `slotId < 36`. The host's plugin menus put their own slots first instead
// (`PluginMenuScreenHandler::new`), so these screens are opened with `playerInventory: false` and
// `36 + ghosts` slots, and the plugin mirrors the real player inventory into the first 36 (see
// `common/menu_mirror.dart`). The indices are pure data: a test pins them, because a menu that is
// opened with the host's layout shows every stack under the wrong index.
import '../logistics/filter/filter_menu_clicks.dart' show ghostMenuPlayerSlots;

/// A ghost menu of the port: the client's menu is `36 player slots + ghostSlots`.
enum GhostMenu {
  /// `create:crafting_blueprint` (`BlueprintMenu`): the nine grid slots, the result and the icon.
  blueprint('create:crafting_blueprint', 11),

  /// `create:schedule` (`ScheduleMenu`): the two item and fluid pickers.
  schedule('create:schedule', 2),

  /// `create:factory_panel_set_item` (`FactoryPanelSetItemMenu`): the gauge's filter.
  factoryPanelSetItem('create:factory_panel_set_item', 1),

  /// `create:linked_controller` (`LinkedControllerMenu`): six buttons, two items each.
  linkedController('create:linked_controller', 12);

  const GhostMenu(this.menuType, this.ghostSlots);

  /// The key of the menu type the client opens.
  final String menuType;

  /// The slots the menu adds after the player inventory (`ghostInventory.getSlots()`).
  final int ghostSlots;

  /// The slot the client shows the player inventory at first (`MenuBase.addPlayerSlots`).
  int get playerSlots => ghostMenuPlayerSlots;

  /// The number of slots the client's menu has, and the number the server tracks.
  int get menuSlots => playerSlots + ghostSlots;

  /// The menu slot of the ghost slot [i].
  int ghostSlot(int i) => playerSlots + i;

  /// Whether [slot] is one of the ghost slots, not the player inventory mirror.
  bool isGhostSlot(int slot) => slot >= playerSlots && slot < menuSlots;

  /// The ghost slot behind the menu slot [slot], `null` for a player inventory slot.
  int? ghostIndexAt(int slot) => isGhostSlot(slot) ? slot - playerSlots : null;

  /// The menu of [menuType], `null` for any other.
  static GhostMenu? ofMenuType(String menuType) {
    for (final menu in values) {
      if (menu.menuType == menuType) return menu;
    }
    return null;
  }
}