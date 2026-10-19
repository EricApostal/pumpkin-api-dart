import 'package:create/src/api/contraption/storage/mounted_storage_menus.dart';
import 'package:create/src/contraptions/storage/stacks.dart';
import 'package:test/test.dart';

void main() {
  test('createGeneric needs 1 to 6 full rows of nine slots', () {
    for (final slots in [9, 18, 27, 36, 45, 54]) {
      final menu = MountedStorageMenus.createGeneric<String>(
        'Title',
        ItemStackHandler(slots),
        stillValid: (_) => true,
        onClose: (_) {},
      );
      expect(menu, isNotNull, reason: '$slots slots');
      expect(menu!.type, MountedMenuType.genericChest);
      expect(menu.rows, slots ~/ 9);
      expect(menu.slots, slots);
      expect(menu.vanillaMenuType, 'minecraft:generic_9x${slots ~/ 9}');
    }

    for (final slots in [0, 8, 10, 17, 55, 63]) {
      expect(
        MountedStorageMenus.createGeneric<String>(
          'Title',
          ItemStackHandler(slots),
          stillValid: (_) => true,
          onClose: (_) {},
        ),
        isNull,
        reason: '$slots slots does not fill whole rows',
      );
    }
  });

  test('createGeneric9x9 needs exactly nine slots', () {
    final menu = MountedStorageMenus.createGeneric9x9<String>(
      'Title',
      ItemStackHandler(9),
      stillValid: (_) => true,
      onClose: (_) {},
    );
    expect(menu, isNotNull);
    expect(menu!.type, MountedMenuType.dispenser);
    expect(menu.rows, 0);
    expect(menu.vanillaMenuType, 'minecraft:generic_3x3');
    expect(
      MountedStorageMenus.createGeneric9x9<String>(
        'Title',
        ItemStackHandler(10),
        stillValid: (_) => true,
        onClose: (_) {},
      ),
      isNull,
    );
  });

  test('the container validates the player and runs the close callback', () {
    var valid = true;
    String? closed;
    final menu = MountedStorageMenus.createGeneric<String>(
      'Title',
      ItemStackHandler(9),
      stillValid: (_) => valid,
      onClose: (player) => closed = player,
    )!;
    expect(menu.container.stillValid('player'), isTrue);
    valid = false;
    expect(menu.container.stillValid('player'), isFalse);
    expect(menu.container.maxStackSize, 64);
    menu.container.stopOpen('player');
    expect(closed, 'player');
  });
}
