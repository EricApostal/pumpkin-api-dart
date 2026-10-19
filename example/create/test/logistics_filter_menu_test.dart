// Pure click rules of the filter screens (`GhostItemMenu` of the Java port): the ghost slots of
// the list and attribute filters, the display slot, and the shift-click of the player inventory.
import 'package:create/src/logistics/filter/filter_menu_clicks.dart';
import 'package:create/src/logistics/model/stack.dart';
import 'package:test/test.dart';

LStack s(String key, [int count = 1]) => LStack.of(key, count);

void main() {
  group('menu layout', () {
    test('the filter item keys map to the three screens', () {
      expect(FilterMenuKind.of('create:filter'), FilterMenuKind.list);
      expect(FilterMenuKind.of('create:attribute_filter'), FilterMenuKind.attribute);
      expect(FilterMenuKind.of('create:package_filter'), FilterMenuKind.package);
      expect(FilterMenuKind.of('minecraft:stone'), isNull);
    });

    test('the menu types map back', () {
      for (final kind in FilterMenuKind.values) {
        expect(FilterMenuKind.ofMenuType(kind.menuType), kind);
      }
      expect(FilterMenuKind.ofMenuType('create:toolbox'), isNull);
    });

    test('the ghost slot counts follow the Java handlers', () {
      expect(ghostSlotCount(FilterMenuKind.list), 18);
      expect(ghostSlotCount(FilterMenuKind.attribute), 2);
      expect(ghostSlotCount(FilterMenuKind.package), 0);
      expect(FilterGhostMenu(FilterMenuKind.list).slots.length, 18);
      expect(FilterGhostMenu(FilterMenuKind.package).slots, isEmpty);
    });
  });

  group('list filter ghost slots', () {
    late FilterGhostMenu menu;

    setUp(() => menu = FilterGhostMenu(FilterMenuKind.list));

    GhostClick click(int menuSlot, GhostClickMode mode, {LStack carried = LStack.empty, int button = 0, LStack source = LStack.empty, bool creative = false}) =>
        menu.click(menuSlot: menuSlot, button: button, mode: mode, carried: carried, source: source, creative: creative);

    test('a click with a stack on the cursor sets one item', () {
      final result = click(ghostMenuPlayerSlots, GhostClickMode.pickup, carried: s('minecraft:stone', 32));
      expect(result.changedSlot, 0);
      expect(result.stack.count, 1);
      expect(result.stack.key, 'minecraft:stone');
      expect(menu.apply(result), isTrue);
      expect(menu.slots[0].count, 1);
    });

    test('a click with an empty cursor clears the slot', () {
      menu.slots[3] = s('minecraft:stone', 1);
      final result = click(ghostMenuPlayerSlots + 3, GhostClickMode.pickup);
      expect(menu.apply(result), isTrue);
      expect(menu.slots[3].isEmpty, isTrue);
    });

    test('a right click also sets one item', () {
      final result = click(ghostMenuPlayerSlots, GhostClickMode.pickup, button: 1, carried: s('minecraft:stone', 32));
      expect(result.stack.count, 1);
    });

    test('throwing out of a ghost slot does nothing', () {
      menu.slots[0] = s('minecraft:stone');
      expect(click(ghostMenuPlayerSlots, GhostClickMode.throw_, carried: s('minecraft:stone')).isEmpty, isTrue);
    });

    test('a drag cannot enter a ghost slot (the client refuses it too)', () {
      expect(click(ghostMenuPlayerSlots, GhostClickMode.quickCraft, carried: s('minecraft:stone')).isEmpty, isTrue);
    });

    test('a creative clone copies the slot to the cursor at its stack size', () {
      menu.slots[2] = s('minecraft:stone', 1);
      final clone = click(ghostMenuPlayerSlots + 2, GhostClickMode.clone, creative: true);
      expect(clone.changedSlot, -1);
      expect(clone.cursor?.count, 64);
      // a non-creative player or a cursor that is not empty clones nothing
      expect(click(ghostMenuPlayerSlots + 2, GhostClickMode.clone).isEmpty, isTrue);
      expect(click(ghostMenuPlayerSlots + 2, GhostClickMode.clone, carried: s('minecraft:dirt'), creative: true).isEmpty, isTrue);
    });

    test('a shift-click from the player inventory fills the first empty slot with one item', () {
      menu.slots[0] = s('minecraft:stone');
      final result = click(4, GhostClickMode.quickMove, source: s('minecraft:dirt', 12));
      expect(result.changedSlot, 1);
      expect(result.stack.count, 1);
      expect(result.stack.key, 'minecraft:dirt');
      // the player's stack is not consumed by a ghost menu
      expect(result.cursor, isNull);
    });

    test('a repeated item is refused (allowRepeats is false)', () {
      menu.slots[0] = s('minecraft:stone');
      // the loop stops at the first slot that already holds the item
      expect(click(0, GhostClickMode.quickMove, source: s('minecraft:stone', 12)).isEmpty, isTrue);
      // a different item still finds the first empty slot
      expect(click(0, GhostClickMode.quickMove, source: s('minecraft:dirt')).changedSlot, 1);
    });

    test('a full ghost inventory takes nothing', () {
      for (var i = 0; i < menu.slots.length; i++) {
        menu.slots[i] = s('minecraft:item_$i');
      }
      expect(click(0, GhostClickMode.quickMove, source: s('minecraft:dirt')).isEmpty, isTrue);
    });

    test('clicks outside the menu and the player inventory do nothing', () {
      expect(click(-1, GhostClickMode.pickup, carried: s('minecraft:stone')).isEmpty, isTrue);
      expect(click(-999, GhostClickMode.pickup, carried: s('minecraft:stone')).isEmpty, isTrue);
      expect(click(ghostMenuPlayerSlots + 18, GhostClickMode.pickup, carried: s('minecraft:stone')).isEmpty, isTrue);
      expect(click(0, GhostClickMode.pickup, carried: s('minecraft:stone')).isEmpty, isTrue);
    });

    test('a shift-click with an empty cursor leaves an empty slot alone', () {
      expect(menu.apply(click(ghostMenuPlayerSlots, GhostClickMode.quickMove)), isFalse);
      expect(menu.slots.every((stack) => stack.isEmpty), isTrue);
    });
  });

  group('attribute filter ghost slots', () {
    late FilterGhostMenu menu;

    setUp(() => menu = FilterGhostMenu(FilterMenuKind.attribute));

    test('the display slot never takes items', () {
      final display = ghostMenuPlayerSlots + attributeDisplaySlot;
      expect(menu.click(menuSlot: display, button: 0, mode: GhostClickMode.pickup, carried: s('minecraft:stone')).isEmpty, isTrue);
      expect(menu.click(menuSlot: display, button: 0, mode: GhostClickMode.quickMove, carried: s('minecraft:stone')).isEmpty, isTrue);
    });

    test('the reference slot takes a clicked item', () {
      final result = menu.click(menuSlot: ghostMenuPlayerSlots, button: 0, mode: GhostClickMode.pickup, carried: s('minecraft:stone', 5));
      expect(result.changedSlot, 0);
      expect(result.stack.count, 1);
    });

    test('a shift-click on the reference slot clears the display slot', () {
      final result = menu.click(menuSlot: ghostMenuPlayerSlots, button: 0, mode: GhostClickMode.quickMove, carried: LStack.empty);
      expect(result.changedSlot, attributeDisplaySlot);
      expect(result.stack.isEmpty, isTrue);
    });

    test('a shift-click from the player inventory replaces the reference item', () {
      menu.slots[0] = s('minecraft:stone');
      final result = menu.click(menuSlot: 3, button: 0, mode: GhostClickMode.quickMove, carried: LStack.empty, source: s('minecraft:dirt', 12));
      expect(result.changedSlot, 0);
      expect(result.stack.key, 'minecraft:dirt');
      expect(result.stack.count, 1);
    });
  });

  group('package filter', () {
    test('has no ghost slots and ignores the shift-click of the player inventory', () {
      final menu = FilterGhostMenu(FilterMenuKind.package);
      expect(menu.click(menuSlot: 0, button: 0, mode: GhostClickMode.quickMove, carried: LStack.empty, source: s('minecraft:stone')).isEmpty, isTrue);
      expect(menu.click(menuSlot: ghostMenuPlayerSlots, button: 0, mode: GhostClickMode.pickup, carried: s('minecraft:stone')).isEmpty, isTrue);
    });
  });
}
