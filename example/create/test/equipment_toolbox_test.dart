import 'package:create/src/equipment/toolbox/toolbox_model.dart';
import 'package:test/test.dart';

TStack s(String k, int n, {int max = 64, bool dmg = false, List<(String, List<int>)> comps = const []}) =>
    TStack(k, n, maxStack: max, damageable: dmg, comps: comps);

void main() {
  test('sharing a compartment', () {
    expect(canItemsShareCompartment(s('a', 1), s('a', 5)), isTrue);
    expect(canItemsShareCompartment(s('a', 1), s('b', 1)), isFalse);
    expect(canItemsShareCompartment(s('a', 1, comps: [('x', [1])]), s('a', 1)), isFalse);
    // damageable tools share by item
    expect(canItemsShareCompartment(s('pick', 1, max: 1, dmg: true, comps: [('damage', [1])]), s('pick', 1, max: 1, dmg: true)), isTrue);
    expect(canItemsShareCompartment(s('create:belt_connector', 1, comps: [('x', [1])]), s('create:belt_connector', 1)), isTrue);
  });

  test('inserting sets the filter and fills from the last slot', () {
    final inv = ToolboxInv();
    var rest = inv.distributeToCompartment(s('a', 10), 0);
    expect(rest.count, 10); // no filter yet: nothing is distributed
    expect(inv.insertItem(0, s('a', 10)).isEmpty, isTrue);
    expect(inv.filters[0].key, 'a');
    // settle keeps the items in the first slots
    expect(inv.slots[0].count, 10);
    // now distribute 100 more: fills slots 3,2,1,0 (reverse order), settle compacts to the front
    rest = inv.distributeToCompartment(s('a', 100), 0);
    expect(rest.isEmpty, isTrue);
    expect(inv.totalCountInCompartment(0), 110);
    expect(inv.slots[0].count, 64);
    expect(inv.slots[1].count, 46);
    expect(inv.slots[2].isEmpty, isTrue);
  });

  test('wrong items are refused', () {
    final inv = ToolboxInv();
    inv.insertItem(0, s('a', 1));
    final r = inv.insertItem(1, s('b', 3));
    expect(r.count, 3);
    expect(inv.isItemValid(1, s('b', 1)), isFalse);
    expect(inv.isItemValid(4, s('b', 1)), isTrue); // another compartment, no filter
  });

  test('limited mode refuses unfiltered compartments', () {
    final inv = ToolboxInv();
    inv.insertItem(0, s('a', 1));
    inv.inLimitedMode(() {
      expect(inv.isItemValid(4, s('b', 1)), isFalse);
      expect(inv.isItemValid(1, s('a', 1)), isTrue);
      final rest = inv.insertStacked(s('b', 5));
      expect(rest.count, 5);
    });
  });

  test('take from compartment', () {
    final inv = ToolboxInv();
    inv.insertItem(0, s('a', 64));
    inv.insertItem(1, s('a', 20));
    expect(inv.totalCountInCompartment(0), 84);
    final t = inv.takeFromCompartment(30, 0);
    expect(t.count, 30);
    expect(inv.totalCountInCompartment(0), 54);
    final simulated = inv.takeFromCompartment(100, 0, simulate: true);
    expect(simulated.count, 54);
    expect(inv.totalCountInCompartment(0), 54);
    expect(inv.takeFromCompartment(5, 3).isEmpty, isTrue);
  });

  test('unstackable items settle to the front without merging', () {
    final inv = ToolboxInv();
    inv.insertItem(2, s('pick', 1, max: 1, dmg: true));
    inv.insertItem(3, s('pick', 1, max: 1, dmg: true));
    expect(inv.slots[0].isEmpty, isFalse);
    expect(inv.slots[1].isEmpty, isFalse);
    expect(inv.slots[2].isEmpty, isTrue);
    expect(inv.slots[3].isEmpty, isTrue);
  });

  test('filter stays after emptying; comparator', () {
    final inv = ToolboxInv();
    inv.insertItem(0, s('a', 64));
    expect(inv.comparatorSignal(), (1 / 32 * 14).floor() + 1);
    inv.extractItem(0, 64);
    expect(inv.filters[0].key, 'a');
    expect(inv.comparatorSignal(), 0);
  });

  test('a number-key swap replaces the slot and returns the displaced stack', () {
    final inv = ToolboxInv();
    inv.insertItem(0, s('a', 10));
    final refused = inv.swapIn(0, s('b', 5));
    // the compartment is filtered to 'a', so the swap is refused (`mayPlace` is false)
    expect(refused, isNull);
    expect(inv.slots[0].key, 'a');
    expect(inv.slots[0].count, 10);

    // an unfiltered compartment takes the hotbar stack and filters itself to it
    final swapped = inv.swapIn(4, s('b', 5));
    expect(swapped, isNotNull);
    expect(swapped!.isEmpty, isTrue); // the slot was empty
    expect(inv.slots[4].key, 'b');
    expect(inv.slots[4].count, 5);
    expect(inv.filters[1].key, 'b');

    // a different item is refused once the compartment is filtered
    expect(inv.swapIn(4, s('c', 1)), isNull);

    // swapping a matching stack replaces the slot's contents and returns them
    final out = inv.swapIn(4, s('b', 2));
    expect(out, isNotNull);
    expect(out!.key, 'b');
    expect(out.count, 5);
    expect(inv.slots[4].count, 2);

    // swapping an empty hotbar slot out of a filled slot takes the items
    final out2 = inv.swapIn(4, TStack.empty);
    expect(out2!.count, 2);
    expect(inv.slots[4].isEmpty, isTrue);
  });
}
