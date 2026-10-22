// The pure decision of `GhostItemMenu.quickMoveStack` for the ghost menus whose ghost inventory
// allows repeats (the redstone requester, the linked controller, the factory gauge filter and the
// schedule pickers). See `lib/src/common/ghost_quick_move.dart`.
import 'package:create/src/common/ghost_quick_move.dart';
import 'package:create/src/logistics/filter/filter_menu_clicks.dart' show ghostMenuPlayerSlots;
import 'package:create/src/logistics/model/stack.dart';
import 'package:test/test.dart';

/// A `ghostEmpty` that reports exactly the ghost slots in [slots] as empty.
bool Function(int) emptyAt(Set<int> slots) => (i) => slots.contains(i);

/// A `ghostEmpty` for a ghost inventory with a free slot everywhere.
bool _allEmpty(int i) => true;

/// A `ghostEmpty` for a full ghost inventory.
bool _noneEmpty(int i) => false;

void main() {
  final iron = LStack('minecraft:iron_ingot', 16, maxStack: 64);
  final gold = LStack('minecraft:gold_ingot', 3);

  group('shift-click from a player inventory slot (`quickMoveStack(index < 36)`)', () {
    test('one item of the source goes into the first empty ghost slot', () {
      final move = ghostQuickMove(
        menuSlot: 5,
        source: iron,
        ghostSlots: 9,
        ghostEmpty: _allEmpty,
      );
      expect(move.isNone, isFalse);
      expect(move.take, isFalse);
      expect(move.ghost, 0);
      expect(move.stack.key, 'minecraft:iron_ingot');
      expect(move.stack.count, 1, reason: 'Java copies one item (`copy.setCount(1)`)');
    });

    test('the first *empty* slot wins, later free slots are ignored', () {
      final move = ghostQuickMove(
        menuSlot: ghostMenuPlayerSlots - 1,
        source: gold,
        ghostSlots: 4,
        // Slots 0 and 2 hold an item, 1 and 3 are free.
        ghostEmpty: emptyAt(const {1, 3}),
      );
      expect(move.ghost, 1);
      expect(move.stack.count, 1);
    });

    test('no empty ghost slot leaves the player inventory alone', () {
      final move = ghostQuickMove(
        menuSlot: 0,
        source: iron,
        ghostSlots: 2,
        ghostEmpty: _noneEmpty,
      );
      expect(move.isNone, isTrue);
      expect(move.take, isFalse);
    });

    test('an empty player inventory slot transfers nothing', () {
      final move = ghostQuickMove(
        menuSlot: 12,
        source: LStack.empty,
        ghostSlots: 9,
        ghostEmpty: _allEmpty,
      );
      expect(move.isNone, isTrue);
    });

    test('a menu with no ghost slot has nowhere to put the item', () {
      final move = ghostQuickMove(
        menuSlot: 3,
        source: iron,
        ghostSlots: 0,
        ghostEmpty: _allEmpty,
      );
      expect(move.isNone, isTrue);
    });
  });

  group('shift-click on a ghost slot (`quickMoveStack(index >= 36)`)', () {
    test('one item leaves the ghost slot', () {
      final move = ghostQuickMove(
        menuSlot: ghostMenuPlayerSlots + 2,
        source: LStack.empty,
        ghostSlots: 9,
        ghostEmpty: _noneEmpty,
      );
      expect(move.isNone, isFalse);
      expect(move.take, isTrue);
      expect(move.ghost, 2);
    });

    test('an empty ghost slot extracts nothing', () {
      final move = ghostQuickMove(
        menuSlot: ghostMenuPlayerSlots + 2,
        source: LStack.empty,
        ghostSlots: 9,
        ghostEmpty: emptyAt(const {2}),
      );
      expect(move.isNone, isTrue);
      expect(move.take, isFalse);
    });
  });

  group('out-of-range slots', () {
    test('a negative menu slot', () {
      expect(
        ghostQuickMove(menuSlot: -1, source: iron, ghostSlots: 9, ghostEmpty: _allEmpty).isNone,
        isTrue,
      );
    });

    test('the first slot past the ghost inventory', () {
      expect(
        ghostQuickMove(
          menuSlot: ghostMenuPlayerSlots + 9,
          source: iron,
          ghostSlots: 9,
          ghostEmpty: _allEmpty,
        ).isNone,
        isTrue,
      );
    });

    test('a slot far past the menu', () {
      expect(
        ghostQuickMove(
          menuSlot: ghostMenuPlayerSlots + 99,
          source: iron,
          ghostSlots: 9,
          ghostEmpty: _allEmpty,
        ).isNone,
        isTrue,
      );
    });
  });
}