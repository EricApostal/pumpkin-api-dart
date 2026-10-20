// The host side of mounted storage menus: opens the container of a contraption block for a
// player (Java `MountedItemStorage.handleInteraction` + `MountedStorageMenus`), keeps the plugin
// inventory and the mounted storage in step while the menu is open, and plays the opening and
// closing sounds.
//
// Java's menu is backed by the storage handler directly. The host opens a window of a vanilla
// screen type over a plugin inventory it owns, so the contents are mirrored: the slots are filled
// when the menu opens and read back every tick and on close.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:wasm_components/wasm_components.dart' show ResourceKeep;

import '../../common/common.dart';
import '../../core/module.dart';
import '../../core/nbt.dart';
import '../core/contraption.dart';
import '../core/movement.dart';
import '../entity/contraption_entity.dart';
import '../entity/host_contraption_entities.dart';
import 'mounted_storage.dart';
import 'stacks.dart';

/// A menu of a mounted storage that is open for one player.
final class _OpenStorage {
  final String worldId;
  final Contraption contraption;
  final Pos localPos;
  final MountedItemStorage storage;
  final Inventory inventory;
  final Screen screen;

  /// What the storage held when the menu last synced; it is what gives a stack its components
  /// back after the round trip through the host (see `carryStackComponents`).
  final List<StoredStack> view;

  _OpenStorage({
    required this.worldId,
    required this.contraption,
    required this.localPos,
    required this.storage,
    required this.inventory,
    required this.screen,
    required this.view,
  });
}

/// `MountedItemStorage.handleInteraction` on the host: the menus of the mounted storages.
final class MountedStorageHost {
  final ContraptionHost host;
  final CreateContext ctx;

  /// player uuid -> the mounted storage menu they have open.
  final Map<String, _OpenStorage> _open = {};

  MountedStorageHost(this.host, this.ctx);

  /// Subscribes to the tick that mirrors the open menus and to the close that plays the closing
  /// sound. Called once from the module's `onLoad`.
  void install() {
    ctx.onWorldTick((t) {
      if (_open.isEmpty) return;
      tick(t.worldId);
    });
    ctx.listen(Events.inventoryClose, (server, e) => _onInventoryClose(e));
  }

  /// `ContraptionEntityHooks.openStorage`: opens the storage at [localPos].
  Future<bool> openStorage(
    Contraption contraption,
    InteractingPlayer interacting,
    Pos localPos,
  ) async {
    final hostPlayer = interacting.hostPlayer;
    if (hostPlayer is! Player) {
      // not a server player: the sync told the client which positions are interactable
      return contraption.storage.isInteractable(localPos);
    }
    if (!contraption.storage.handlePlayerStorageInteraction(
      contraption,
      interacting,
      localPos,
    ))
      return false;

    final storage = contraption.storage.storageAt(localPos);
    final layout = storage?.menuLayout;
    final info = contraption.blocks[localPos];
    final entity = contraption.entity;
    if (storage == null || layout == null || info == null) return false;
    if (entity is! AbstractContraptionEntity) return false;

    final player = hostPlayer;
    final screen = _screenFor(layout);
    final title = _menuTitle(storage.menuBlockName(info));

    final gui = Gui.create(type: screen, title: title);
    await gui.setAllowGrabItems(allow: true);
    await gui.setAllowPutItems(allow: true);

    final view = <StoredStack>[];
    for (var i = 0; i < storage.slots; i++) {
      final stack = storage.stackInSlot(i);
      view.add(stack);
      final item = await _toHost(stack);
      if (item == null) continue;
      try {
        await gui.setItem(slot: i, item: item);
      } on Object catch (error) {
        item.dispose();
        ctx.log.warn('Could not fill mounted storage slot $i: $error');
      }
    }

    final inventory = (await gui.getInventory()).keep();
    try {
      await player.openGui(guiRef: gui);
    } on Object catch (error) {
      ctx.log.warn('Could not open the mounted storage menu: $error');
      inventory.dispose();
      return false;
    }

    final uuid = player.getId().asString;
    final previous = _open.remove(uuid);
    if (previous != null) previous.inventory.dispose();
    _open[uuid] = _OpenStorage(
      worldId: entity.host.level.worldId,
      contraption: contraption,
      localPos: localPos,
      storage: storage,
      inventory: inventory,
      screen: screen,
      view: view,
    );

    final sound = storage.openingSound;
    if (sound != null) {
      entity.host.playSound(
        sound,
        entity.toGlobalVector(_center(localPos), 0),
        volume: 0.75,
      );
    }
    return true;
  }

  /// `tick`: mirrors the plugin inventory of the open menus into their storages.
  void tick(String worldId) {
    for (final entry in _open.entries.toList()) {
      final menu = entry.value;
      if (menu.worldId != worldId) continue;
      if (!_stillValid(entry.key, menu)) {
        // the entity, the storage or the player is gone; the host closes the window itself
        _open.remove(entry.key);
        menu.inventory.dispose();
        continue;
      }
      unawaited(_sync(menu));
    }
  }

  /// Reads the plugin inventory of [menu] back into its storage.
  ///
  /// The host stack carries the item and the count but no saved-form components (the WIT
  /// `item-stack` resource only exposes the network form), so the components of a slot are
  /// taken from what the menu held before: the same slot while it keeps its item, otherwise
  /// the one stack the player moved there. A stack that entered the menu from the player's
  /// inventory keeps the components the host holds for it; they are written back through
  /// `set-component` when the menu is opened again.
  Future<void> _sync(_OpenStorage menu) async {
    final next = <StoredStack>[];
    for (var i = 0; i < menu.storage.slots; i++) {
      final hostStack = menu.inventory.getItem(slot: i);
      if (hostStack == null) {
        next.add(StoredStack.empty);
        continue;
      }
      try {
        final key = await hostStack.getRegistryKey();
        final count = await hostStack.getCount();
        next.add(count <= 0 ? StoredStack.empty : StoredStack(key, count));
      } finally {
        hostStack.dispose();
      }
    }
    carryStackComponents(menu.view, next);
    for (var i = 0; i < next.length; i++) {
      if (next[i] == menu.view[i]) continue;
      menu.storage.setStackInSlot(i, next[i]);
      menu.view[i] = next[i];
    }
  }

  /// `isMenuValid`: the contraption entity is alive, the storage is still mounted there and the
  /// player is within eight blocks.
  bool _stillValid(String uuid, _OpenStorage menu) {
    final entity = menu.contraption.entity;
    if (entity is! AbstractContraptionEntity) return false;
    if (!entity.host.isAlive) return false;
    if (menu.contraption.storage.storageAt(menu.localPos) != menu.storage)
      return false;
    final roster = ContraptionHost.bus?.roster;
    if (roster == null) return true;
    Player? player;
    for (final p in roster.players) {
      if (p.getId().asString == uuid) player = p;
    }
    if (player == null) return false;
    final pos = entity.toGlobalVector(_center(menu.localPos), 0);
    final at = player.asEntity().position;
    final dx = at.$1 - pos.$1, dy = at.$2 - pos.$2, dz = at.$3 - pos.$3;
    return dx * dx + dy * dy + dz * dz < 8 * 8;
  }

  /// `onClose`: mirrors the last contents and plays the closing sound at the current position.
  void _onInventoryClose(InventoryCloseEventData e) {
    final uuid = e.player.getId().asString;
    final menu = _open[uuid];
    if (menu == null) return;
    if (e.windowType != null && e.windowType != menu.screen) return;
    _open.remove(uuid);
    unawaited(_sync(menu));
    menu.inventory.dispose();

    final entity = menu.contraption.entity;
    final sound = menu.storage.closingSound;
    if (entity is AbstractContraptionEntity && sound != null) {
      entity.host.playSound(
        sound,
        entity.toGlobalVector(_center(menu.localPos), 0),
        volume: 0.75,
      );
    }
  }

  /// Forgets the open menus (plugin unload).
  void clear() {
    for (final menu in _open.values) {
      menu.inventory.dispose();
    }
    _open.clear();
  }

  static Screen _screenFor(({bool dispenser, int rows}) layout) {
    if (layout.dispenser) return Screen.generic3x3;
    return switch (layout.rows) {
      1 => Screen.generic9x1,
      2 => Screen.generic9x2,
      3 => Screen.generic9x3,
      4 => Screen.generic9x4,
      5 => Screen.generic9x5,
      _ => Screen.generic9x6,
    };
  }

  /// `CreateLang.translateDirect("contraptions.moving_container", blockName)`.
  static TextComponent _menuTitle(String blockKey) => TextComponent.translate(
    key: 'create.contraptions.moving_container',
    with_: [
      TextComponent.translate(
        key: 'block.${blockKey.replaceFirst(':', '.')}',
        with_: const [],
      ),
    ],
  );

  static Vec3 _center(Pos pos) => (pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5);

  /// The host stack for [stack]. Components travel as network NBT; a component the host cannot
  /// parse is dropped (the host does not expose the saved form).
  static Future<ItemStack?> _toHost(StoredStack stack) async {
    if (stack.isEmpty) return null;
    final item = ItemStack.create(
      registryKey: stack.item,
      count: stack.count > 255 ? 255 : stack.count,
    );
    final components = stack.components;
    if (components == null) return item;
    for (final entry in components.map.entries) {
      try {
        final bytes = NetworkNbt.encode(entry.value);
        if (entry.key.startsWith('create:')) {
          item.setCustomComponent(entry.key, bytes);
        } else {
          final component = DataComponent.fromWireName(entry.key);
          if (component != null) {
            await item.setComponent(component: component, value: bytes);
          }
        }
      } on Object {
        // a component the host does not accept is dropped
      }
    }
    return item;
  }
}
