// `MountedStorageMenus` (pure): the menu a mounted storage opens for a player. Java returns a
// vanilla `MenuProvider` for `GENERIC_9xN` / `DispenserMenu`; this port returns the layout and
// the [StorageInteractionWrapper] that validates the player, so the host layer can open the
// matching menu (the host opens plugin menus with a slot count).
//
// The rules are Java's: a generic chest menu needs full rows of nine slots and 1 to 6 rows; the
// dispenser menu needs exactly nine slots.
import '../../../contraptions/storage/stacks.dart';
import 'mounted_storage_wrappers.dart';

/// Which vanilla layout a mounted storage uses.
enum MountedMenuType {
  /// `MenuType.GENERIC_9x<rows>`.
  genericChest,

  /// `DispenserMenu` (`MenuType.GENERIC_3x3`).
  dispenser,
}

/// What [MountedStorageMenus] builds: the title, the layout and the validated container.
final class MountedStorageMenu<P> {
  /// The vanilla menu family.
  final MountedMenuType type;

  /// `GENERIC_9x<rows>` rows; 0 for [MountedMenuType.dispenser].
  final int rows;

  /// `Component` menu title, as a plain string (the host parses `&` colour codes).
  final String title;

  /// `new StorageInteractionWrapper(handler, stillValid, onClose)`.
  final StorageInteractionWrapper<P> container;

  const MountedStorageMenu(this.type, this.rows, this.title, this.container);

  /// The number of slots the menu shows.
  int get slots => container.containerSize;

  /// The vanilla layout key (`minecraft:generic_9x3` / `minecraft:generic_3x3`). It names the
  /// layout for reference; the host opens a plugin menu type with [slots] slots.
  String get vanillaMenuType => switch (type) {
    MountedMenuType.genericChest => 'minecraft:generic_9x$rows',
    MountedMenuType.dispenser => 'minecraft:generic_3x3',
  };
}

/// `MountedStorageMenus`.
abstract final class MountedStorageMenus {
  /// `GENERIC_CHEST_MENUS.size`: the largest `GENERIC_9xN` menu.
  static const int maxChestRows = 6;

  /// `GENERIC_CHEST_MENUS`: the menu types, smallest first.
  static const List<String> genericChestMenus = [
    'minecraft:generic_9x1',
    'minecraft:generic_9x2',
    'minecraft:generic_9x3',
    'minecraft:generic_9x4',
    'minecraft:generic_9x5',
    'minecraft:generic_9x6',
  ];

  /// `createGeneric(name, handler, stillValid, onClose)`: a chest menu of 1 to 6 full rows,
  /// `null` when the handler does not fit.
  static MountedStorageMenu<P>? createGeneric<P>(
    String title,
    ItemSlots handler, {
    required bool Function(P) stillValid,
    required void Function(P) onClose,
  }) {
    final slots = handler.slots;
    final rows = slots ~/ 9;
    if (rows < 1 || rows > maxChestRows) return null;
    // Rows must be full, like Java.
    if (slots % 9 != 0) return null;
    return MountedStorageMenu<P>(
      MountedMenuType.genericChest,
      rows,
      title,
      StorageInteractionWrapper<P>(
        handler,
        stillValid: stillValid,
        onClose: onClose,
      ),
    );
  }

  /// `createGeneric9x9(name, handler, stillValid, onClose)`: the dispenser menu, `null` when the
  /// handler does not have exactly nine slots.
  static MountedStorageMenu<P>? createGeneric9x9<P>(
    String title,
    ItemSlots handler, {
    required bool Function(P) stillValid,
    required void Function(P) onClose,
  }) {
    if (handler.slots != 9) return null;
    return MountedStorageMenu<P>(
      MountedMenuType.dispenser,
      0,
      title,
      StorageInteractionWrapper<P>(
        handler,
        stillValid: stillValid,
        onClose: onClose,
      ),
    );
  }
}
