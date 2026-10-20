// The carriage side of the mail transfer: a contraption's `StoredStack` <-> the module's `LStack`,
// and the `PackageInventory` `GlobalStation.runMailTransfer` moves packages through.
import 'package:create/src/contraptions/core/nbt_map.dart';
import 'package:create/src/contraptions/storage/stacks.dart';
import 'package:create/src/core/nbt.dart';
import 'package:create/src/logistics/model/package.dart';
import 'package:create/src/logistics/model/stack.dart';
import 'package:create/src/logistics/model/stack_tags.dart';
import 'package:create/src/logistics/port/carriage_packages.dart';
import 'package:create/src/trains/station/global_package_port.dart';
import 'package:test/test.dart';

/// A package of the default style with contents and an address, built deterministically.
LStack packageAt(String address) {
  final box = PackageItem.withContents(PackageStyles.defaultBox(), [
    LStack.of('minecraft:iron_ingot', 3),
  ]);
  return PackageItem.addAddress(box, address);
}

void main() {
  group('carriage stacks', () {
    test('a package keeps its address and contents in the codec form', () {
      final box = packageAt('factory');
      final stored = carriageStoredStack(box);

      expect(stored.item, box.key);
      expect(stored.count, 1);
      // The address is plain text in Java's codec form (`AllDataComponents.PACKAGE_ADDRESS`), so a
      // Create client and the schedule conditions read it.
      expect(
        stored.components?.getString(PackageComponents.address),
        'factory',
      );
      // Everything else rides in the private copy.
      final private = stored.components
          ?.getCompoundOrNull(customDataComponent)
          ?.getString(privateDataKey);
      expect(private, isNotNull);
      expect(private, contains('create:package_contents'));

      final back = carriageLStack(stored);
      expect(back.sameItemSameComponents(box), isTrue);
      expect(back.count, 1);
      expect(PackageItem.isPackage(back), isTrue);
      expect(PackageItem.getAddress(back), 'factory');
      expect(PackageItem.contentsList(back).single.key, 'minecraft:iron_ingot');
      // A package is max stack 1 (Java's `PackageItem` properties); the contraption's own item
      // resolver does not know the package items.
      expect(back.maxStack, 1);
    });

    test('a package the Create mod wrote keeps the address of its codec form', () {
      final stored = StoredStack(
        PackageStyles.defaultBox().key,
        1,
        NbtMap()..putString(PackageComponents.address, 'factory'),
      );
      final box = carriageLStack(stored);
      expect(PackageItem.isPackage(box), isTrue);
      expect(PackageItem.getAddress(box), 'factory');
      expect(PackageItem.matchBoxAddress(box, 'factory'), isTrue);
      expect(PackageItem.matchBoxAddress(box, 'warehouse'), isFalse);
      expect(PackageItem.contentsList(box), isEmpty);
    });

    test('a plain item keeps its item and count', () {
      final stored = carriageStoredStack(LStack.of('minecraft:stone', 12));
      expect(stored.item, 'minecraft:stone');
      expect(stored.count, 12);
      expect(stored.components, isNull);
      expect(carriageLStack(stored).sameItemSameComponents(LStack.of('minecraft:stone', 12)), isTrue);
    });

    test('custom data next to the private copy survives the round trip', () {
      final box = packageAt(
        'factory',
      ).withComp(customDataComponent, NetworkNbt.encode(NbtValue.compound({
        'Foo': NbtValue.string('bar'),
      })));
      final back = carriageLStack(carriageStoredStack(box));

      final custom = back.compBytes(customDataComponent);
      expect(custom, isNotNull);
      final foo = NetworkNbt.decode(custom!)?.asCompound['Foo'];
      expect(foo?.kind, NbtKind.string);
      expect(foo?.value, 'bar');
      expect(PackageItem.getAddress(back), 'factory');
    });
  });

  group('carriage inventory', () {
    test('packages go to one slot each, a count does not merge them', () {
      final slots = ItemStackHandler(2);
      final inventory = CarriagePackageInventory(slots, OfflineBuffer.stackLimit);
      final tag = stackToCTag(packageAt('factory'))!;

      expect(inventory.insertItemStacked(tag), isNull);
      expect(inventory.insertItemStacked(tag), isNull);

      expect(slots.stackInSlot(0).count, 1);
      expect(slots.stackInSlot(1).count, 1);
      expect(inventory.getStackInSlot(0), isNotNull);
    });

    test('a full inventory hands the package back', () {
      final slots = ItemStackHandler(1);
      final inventory = CarriagePackageInventory(slots, OfflineBuffer.stackLimit);
      final tag = stackToCTag(packageAt('factory'))!;
      slots.setStackInSlot(0, carriageStoredStack(packageAt('warehouse')));

      final rest = inventory.insertItemStacked(tag);
      expect(rest, isNotNull);
      expect(stackFromCTag(rest).count, 1);
      expect(PackageItem.getAddress(carriageLStack(slots.stackInSlot(0))), 'warehouse');
    });

    test('the slots read back as the module stacks', () {
      final slots = ItemStackHandler(1);
      final inventory = CarriagePackageInventory(slots, OfflineBuffer.stackLimit);
      inventory.setStackInSlot(0, stackToCTag(packageAt('factory')));

      final read = stackFromCTag(inventory.getStackInSlot(0));
      expect(read.sameItemSameComponents(packageAt('factory')), isTrue);
      expect(PackageItem.matchBoxAddress(read, 'factory'), isTrue);
    });
  });
}