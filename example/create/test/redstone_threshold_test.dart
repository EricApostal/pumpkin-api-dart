import 'package:create/src/common/common.dart';
import 'package:create/src/conveyance/items/inventory.dart';
import 'package:create/src/conveyance/items/item_data.dart';
import 'package:create/src/redstone/link/frequency.dart';
import 'package:create/src/redstone/link/link_network.dart';
import 'package:create/src/redstone/observer/observed_container.dart';
import 'package:create/src/redstone/observer/threshold_logic.dart';
import 'package:create/src/redstone/support/placement.dart';
import 'package:test/test.dart';

/// A linkable with a fixed key, for the frequency matching of the network.
class _Link extends RedstoneLinkable {
  _Link(this.location, this.networkKey, {this.transmit = 0, this.listening = false});

  @override
  Pos location;
  @override
  NetworkKey networkKey;
  final int transmit;
  final bool listening;
  int received = -1;

  @override
  int get transmittedStrength => listening ? 0 : transmit;

  @override
  void setReceivedStrength(int power) => received = power;

  @override
  bool get isListening => listening;

  @override
  bool get isAlive => true;
}

NetworkKey _key(String a, {int aColor = -1, String? b, int bColor = -1}) => Couple<Frequency>(
  Frequency.of(a, color: aColor),
  b == null ? Frequency.empty : Frequency.of(b, color: bColor),
);

void main() {
  group('frequency matching', () {
    test('a colour change makes a different frequency', () {
      final handler = RedstoneLinkNetworkHandler(linkRange: () => 256)..onLoadWorld('w');
      final plain = _Link((0, 0, 0), _key('minecraft:redstone'), transmit: 15);
      final red = _Link((1, 0, 0), _key('minecraft:redstone', aColor: 0xFF0000), listening: true);
      handler.addToNetwork('w', red);
      handler.addToNetwork('w', plain);
      expect(red.received, isNot(15), reason: 'an undyed stack must not drive a dyed one');
    });

    test('the same colour matches on both slots', () {
      final handler = RedstoneLinkNetworkHandler(linkRange: () => 256)..onLoadWorld('w');
      final tx = _Link((0, 0, 0), _key('minecraft:iron_ingot', b: 'minecraft:redstone'), transmit: 7);
      final rx = _Link((2, 0, 0), _key('minecraft:iron_ingot', b: 'minecraft:redstone'), listening: true);
      handler.addToNetwork('w', rx);
      handler.addToNetwork('w', tx);
      expect(rx.received, 7);
    });

    test('slot order matters: (a, b) is not (b, a)', () {
      final handler = RedstoneLinkNetworkHandler(linkRange: () => 256)..onLoadWorld('w');
      final tx = _Link((0, 0, 0), _key('minecraft:iron_ingot', b: 'minecraft:gold_ingot'), transmit: 15);
      final rx = _Link((1, 0, 0), _key('minecraft:gold_ingot', b: 'minecraft:iron_ingot'), listening: true);
      handler.addToNetwork('w', rx);
      handler.addToNetwork('w', tx);
      expect(rx.received, isNot(15));
    });

    test('one empty slot is a valid frequency and only matches the same empty slot', () {
      final handler = RedstoneLinkNetworkHandler(linkRange: () => 256)..onLoadWorld('w');
      final tx = _Link((0, 0, 0), _key('minecraft:redstone'), transmit: 5);
      final same = _Link((1, 0, 0), _key('minecraft:redstone'), listening: true);
      final other = _Link((1, 0, 0), _key('minecraft:redstone', b: 'minecraft:gold_ingot'), listening: true);
      handler.addToNetwork('w', same);
      handler.addToNetwork('w', other);
      handler.addToNetwork('w', tx);
      expect(same.received, 5);
      expect(other.received, isNot(5));
    });

    test('range is checked per receiver against the transmitter', () {
      var range = 16;
      final handler = RedstoneLinkNetworkHandler(linkRange: () => range)..onLoadWorld('w');
      final tx = _Link((0, 0, 0), _key('minecraft:redstone'), transmit: 15);
      final inRange = _Link((15, 0, 0), _key('minecraft:redstone'), listening: true);
      final outOfRange = _Link((16, 0, 0), _key('minecraft:redstone'), listening: true);
      handler.addToNetwork('w', inRange);
      handler.addToNetwork('w', outOfRange);
      handler.addToNetwork('w', tx);
      expect(inRange.received, 15);
      expect(outOfRange.received, isNot(15));
      range = 20;
      handler.updateNetworkOf('w', tx);
      expect(outOfRange.received, 15, reason: 'the range is read on every check');
    });
  });

  group('threshold logic', () {
    test('turns on at onWhenAbove and off at offWhenBelow', () {
      expect(
        thresholdRedstoneState(state: false, current: 127, onWhenAbove: 128, offWhenBelow: 64),
        (state: false, changed: false),
      );
      expect(
        thresholdRedstoneState(state: false, current: 128, onWhenAbove: 128, offWhenBelow: 64),
        (state: true, changed: true),
      );
      expect(
        thresholdRedstoneState(state: true, current: 65, onWhenAbove: 128, offWhenBelow: 64),
        (state: true, changed: false),
      );
      expect(
        thresholdRedstoneState(state: true, current: 64, onWhenAbove: 128, offWhenBelow: 64),
        (state: false, changed: true),
      );
    });

    test('stays in its state between the two thresholds (hysteresis)', () {
      for (final state in [true, false]) {
        expect(
          thresholdRedstoneState(state: state, current: 96, onWhenAbove: 128, offWhenBelow: 64),
          (state: state, changed: false),
        );
      }
    });

    test('inverted onWhenBelow ranges settle like Mth.clamp', () {
      expect(thresholdClamp(5, 0, 10), 5);
      expect(thresholdClamp(-5, 0, 10), 0);
      expect(thresholdClamp(50, 0, 10), 10);
      expect(thresholdClamp(5, 10, 0), 0, reason: 'min above max gives max');
    });

    test('the level property is 0 when empty and 1..5 across the range', () {
      expect(thresholdDisplayLevel(current: 0, min: 0, max: 128), 0);
      expect(thresholdDisplayLevel(current: 32, min: 0, max: 128), 2);
      expect(thresholdDisplayLevel(current: 128, min: 0, max: 128), 5);
      expect(thresholdDisplayLevel(current: 5, min: 5, max: 5), 0, reason: 'no range, no fill');
    });

    test('the unsupported target check skips stock tickers', () {
      expect(thresholdTargetSupported('minecraft:chest'), isTrue);
      expect(thresholdTargetSupported('create:stock_ticker'), isFalse);
    });
  });

  group('observed containers', () {
    // A single block vault: `vaultCapacity` (20) slots of 64 items each, answered by the vault's
    // `ItemInventoryProvider` (`ItemVaultBlockEntity.itemInventory`). The observer and the
    // threshold switch read it through [PluginInventoryContainer]: the host's `ItemHandlers`
    // never sees a plugin inventory (the block does not register one).
    ListInventory vault({int slotLimit = 64}) => ListInventory(20, slotLimit: slotLimit);

    test('a plugin inventory is read slot by slot like the item handler capability', () async {
      final inventory = vault()
        ..setStack(0, const ItemValue('minecraft:iron_ingot', 3))
        ..setStack(19, const ItemValue('minecraft:gold_ingot', 64));
      final container = PluginInventoryContainer(inventory);

      expect(container.slots, 20);
      final first = await container.slot(0, detail: true);
      expect(first.key, 'minecraft:iron_ingot');
      expect(first.count, 3);
      expect(first.limit, 64);
      expect(first.isEmpty, isFalse);
      expect((await container.slot(1)).isEmpty, isTrue, reason: 'an empty slot has no item');
      expect((await container.slot(1)).key, 'minecraft:air');
      // The scans that run every tick read the key and the count only.
      final cheap = await container.slot(0);
      expect(cheap.key, 'minecraft:iron_ingot');
      expect(cheap.count, 3);
    });

    test('the threshold switch counts the stock and the capacity of a vault', () async {
      final container = PluginInventoryContainer(
        vault()
          ..setStack(0, const ItemValue('minecraft:iron_ingot', 3))
          ..setStack(19, const ItemValue('minecraft:gold_ingot', 64)),
      );

      final filtered = await thresholdItemLevels(container, test: (key) => key == 'minecraft:iron_ingot');
      expect(filtered.current, 3, reason: 'only the filtered item is counted');
      expect(filtered.max, 20 * 64, reason: 'every slot gives min(64, slotLimit)');

      final unfiltered = await thresholdItemLevels(container, test: (_) => true);
      expect(unfiltered.current, 67);
      expect(unfiltered.max, 20 * 64);
    });

    test('a slot limit below the stack size caps the space of the slot', () async {
      final container = PluginInventoryContainer(
        vault(slotLimit: 1)..setStack(0, const ItemValue('minecraft:iron_ingot', 1)),
      );
      final levels = await thresholdItemLevels(container, test: (_) => true);
      expect(levels.current, 1);
      expect(levels.max, 20, reason: 'min(stack size, slot limit) per slot');
    });

    test('the address of a package in a plugin inventory is read', () async {
      final container = PluginInventoryContainer(
        vault()
          ..setStack(
            0,
            ItemValue(
              'create:cardboard_package_12x12',
              1,
              comps: [(packageAddressComponent, encodePackageAddress('Home'))],
            ),
          ),
      );
      expect((await container.slot(0, detail: true)).address, 'Home');
      expect((await container.slot(1, detail: true)).address, isNull, reason: 'an empty slot has no package');
      expect(
        (await PluginInventoryContainer(vault()..setStack(0, const ItemValue('minecraft:iron_ingot', 1)))
                .slot(0, detail: true))
            .address,
        isNull,
        reason: 'a plain item carries no address',
      );
    });
  });

  group('redstone link placement', () {
    test('the link hangs on the clicked block', () {
      // e.face already points from the new link to the clicked block.
      final replaceable = <Pos>{(0, 1, 0)};
      bool canBeReplaced(Pos p) => replaceable.contains(p);
      expect(linkCanSurvive((0, 0, 0), Direction.down, canBeReplaced), isTrue);
      expect(linkCanSurvive((0, 0, 0), Direction.south, canBeReplaced), isTrue);
      expect(linkCanSurvive((0, 0, 0), Direction.up, canBeReplaced), isFalse,
          reason: 'a replaceable block cannot carry the link');
    });
  });
}
