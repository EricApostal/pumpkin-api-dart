// Pure tests of `TrainCargoManager`: the cargo a carriage starts with, its fuel, its idle tracker
// and the saved form the train reads. The host is not involved.
import 'package:create/src/contraptions/storage/mounted_storage.dart';
import 'package:create/src/contraptions/storage/stacks.dart';
import 'package:create/src/contraptions/storage/train_cargo_manager.dart';
import 'package:create/src/trains/util/ctag.dart';
import 'package:test/test.dart';

TrainCargoManager _cargoWith(List<StoredStack> stacks) {
  final cargo = TrainCargoManager();
  cargo.addItemStorage(
    SimpleMountedStorage(
      MountedStorages.chest,
      ItemStackHandler.of(stacks),
    ),
    (0, 0, 0),
  );
  cargo.initialize();
  return cargo;
}

void main() {
  setUpAll(MountedStorages.installDefaults);

  group('TrainCargoManager', () {
    test('reads the mounted storages as cargo', () {
      final cargo = _cargoWith([
        const StoredStack('minecraft:iron_ingot', 7),
        StoredStack.empty,
      ]);
      final items = cargo.getAllItems();
      expect(items.length, 2);
      expect(items[0].id, 'minecraft:iron_ingot');
      expect(items[0].count, 7);
      expect(items[1].isEmpty, isTrue);
    });

    test('marks packages and their address', () {
      final cargo = _cargoWith([
        StoredStack('create:cardboard_package_12x12', 1),
      ]);
      final item = cargo.getAllItems().first;
      expect(item.isPackage, isTrue);
      expect(item.packageAddress, '');
    });

    test('an empty manager stays usable before the blocks are mounted', () {
      final cargo = TrainCargoManager();
      expect(cargo.getAllItems(), isEmpty);
      expect(cargo.getFluids(), isEmpty);
      expect(cargo.extractFuel(), 0);
      // Still open for the assembly that mounts the blocks.
      expect(cargo.isInitialized, isFalse);
    });

    test('extractFuel takes one coal and reports its burn time', () {
      final cargo = _cargoWith([
        const StoredStack('minecraft:coal', 3),
        StoredStack.empty,
      ]);
      expect(cargo.extractFuel(), 1600);
      expect(cargo.allItems.stackInSlot(0).count, 2);
      expect(cargo.extractFuel(), 1600);
      expect(cargo.extractFuel(), 1600);
      expect(cargo.extractFuel(), 0);
    });

    test('extractFuel puts the crafting remainder back', () {
      final cargo = _cargoWith([const StoredStack('minecraft:lava_bucket', 1)]);
      expect(cargo.extractFuel(), 20000);
      expect(cargo.allItems.stackInSlot(0).item, 'minecraft:bucket');
    });

    test('extractFuel skips non fuels', () {
      final cargo = _cargoWith([
        const StoredStack('minecraft:stone', 5),
        const StoredStack('minecraft:charcoal', 1),
      ]);
      expect(cargo.extractFuel(), 1600);
      expect(cargo.allItems.stackInSlot(0).item, 'minecraft:stone');
      expect(cargo.allItems.stackInSlot(1).isEmpty, isTrue);
    });

    test('the version and the idle tracker follow a change', () {
      final cargo = _cargoWith([const StoredStack('minecraft:stone', 1)]);
      final first = cargo.getVersion();
      cargo.tickIdleCargoTracker();
      cargo.tickIdleCargoTracker();
      expect(cargo.getTicksSinceLastExchange(), 2);
      expect(cargo.getVersion(), first, reason: 'nothing changed');

      cargo.allItems.setStackInSlot(0, const StoredStack('minecraft:stone', 4));
      expect(cargo.getVersion(), greaterThan(first));
      expect(
        cargo.getTicksSinceLastExchange(),
        0,
        reason: 'changeDetected resets the tracker',
      );
    });

    test('write and read round trip the idle tracker', () {
      final cargo = _cargoWith([const StoredStack('minecraft:coal', 2)]);
      cargo.tickIdleCargoTracker();
      final tag = CTag();
      cargo.writeCargo(tag, false);

      final copy = TrainCargoManager();
      copy.readCargo(tag, false);
      expect(copy.getTicksSinceLastExchange(), 1);
      expect(copy.allItems.stackInSlot(0).item, 'minecraft:coal');
    });
  });
}
