// The slot layout of the ghost menus the server tracks (`GhostMenu`). The client's menu of every
// Create `GhostItemMenu` puts the 36 player slots first (`MenuBase.addPlayerSlots`), so the server
// tracks `36 + ghosts` slots — one per client menu slot — and mirrors the player inventory into the
// first 36 (`common/menu_mirror.dart`). These are the indices the plugin emits, so a menu that is
// opened with the host's own layout (`[plugin slots][36 player]`) shows every stack under the wrong
// index: this pins the layout against that regression.
import 'package:create/src/common/ghost_menu_layout.dart';
import 'package:create/src/logistics/filter/filter_menu_clicks.dart'
    show ghostMenuPlayerSlots, inventoryIndexAt;
import 'package:create/src/redstone/link/controller_items.dart' show ControllerItems;
import 'package:create/src/trains/schedule/schedule_menu.dart';
import 'package:test/test.dart';

List<int> slotsOf(GhostMenu menu) =>
    [for (var i = 0; i < menu.ghostSlots; i++) menu.ghostSlot(i)];

void main() {
  group('ghost menu layout', () {
    test('every menu puts the 36 player slots first', () {
      for (final menu in GhostMenu.values) {
        expect(menu.playerSlots, ghostMenuPlayerSlots, reason: menu.menuType);
        expect(menu.playerSlots, 36, reason: menu.menuType);
        expect(menu.menuSlots, 36 + menu.ghostSlots, reason: menu.menuType);
        expect(menu.ghostSlot(0), 36, reason: menu.menuType);
        expect(
          menu.ghostSlot(menu.ghostSlots - 1),
          menu.menuSlots - 1,
          reason: menu.menuType,
        );
      }
    });

    test('the player inventory is the first 36 slots, the ghosts follow', () {
      for (final menu in GhostMenu.values) {
        expect(menu.isGhostSlot(35), isFalse, reason: menu.menuType);
        expect(menu.ghostIndexAt(35), isNull, reason: menu.menuType);
        expect(menu.isGhostSlot(36), isTrue, reason: menu.menuType);
        expect(menu.ghostIndexAt(36), 0, reason: menu.menuType);
        expect(menu.isGhostSlot(menu.menuSlots), isFalse, reason: menu.menuType);
        expect(menu.ghostIndexAt(menu.menuSlots), isNull, reason: menu.menuType);
      }
    });

    test('the mirror slots are the main inventory, then the hotbar', () {
      // `MenuBase.addPlayerSlots` adds the rows 9 to 35 first and the hotbar 0 to 8 last.
      expect(inventoryIndexAt(0), 9);
      expect(inventoryIndexAt(26), 35);
      expect(inventoryIndexAt(27), 0);
      expect(inventoryIndexAt(35), 8);
      expect(inventoryIndexAt(36), isNull);
    });

    test('the menu type of each screen maps back', () {
      expect(GhostMenu.ofMenuType('create:crafting_blueprint'), GhostMenu.blueprint);
      expect(GhostMenu.ofMenuType('create:schedule'), GhostMenu.schedule);
      expect(
        GhostMenu.ofMenuType('create:factory_panel_set_item'),
        GhostMenu.factoryPanelSetItem,
      );
      expect(GhostMenu.ofMenuType('create:linked_controller'), GhostMenu.linkedController);
      expect(GhostMenu.ofMenuType('create:toolbox'), isNull);
    });

    test('the blueprint menu is the nine grid slots, the result and the icon', () {
      const menu = GhostMenu.blueprint;
      expect(menu.ghostSlots, 11);
      expect(menu.menuSlots, 47);
      expect(slotsOf(menu), [36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46]);
      // `BlueprintMenu.onCraftMatrixChanged` writes the result to the slot `36 + 9`.
      expect(menu.ghostSlot(9), 45);
    });

    test('the schedule menu is the two item and fluid pickers', () {
      const menu = GhostMenu.schedule;
      expect(menu.ghostSlots, ScheduleMenu.slots);
      expect(menu.menuSlots, 38);
      expect(slotsOf(menu), [36, 37]);
    });

    test('the factory panel menu is the one gauge filter slot', () {
      const menu = GhostMenu.factoryPanelSetItem;
      expect(menu.ghostSlots, 1);
      expect(menu.menuSlots, 37);
      expect(slotsOf(menu), [36]);
    });

    test('the linked controller menu is the twelve frequency slots', () {
      const menu = GhostMenu.linkedController;
      expect(menu.ghostSlots, ControllerItems.slotCount);
      expect(menu.menuSlots, 48);
      expect(slotsOf(menu), [for (var i = 36; i < 48; i++) i]);
    });
  });
}