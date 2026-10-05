import 'dart:typed_data';

import 'package:wasm_components/wasm_components.dart' show ErrorResult, OkResult;

import 'bindings.g.dart' as generated;
import 'component_codec.dart';
import 'messages.dart' show Messages;
import 'nbt_compound.dart';
import 'plugin_registry_core.dart';

/// The host's registries for block entity types, menu types and custom data
/// component types, for plugins that serve a client mod (see
/// `docs/host-features-for-client-mods.md`).
///
/// Like the item and block registries ([ItemRegistries], [BlockRegistries])
/// they are append only, closed when the server starts accepting connections
/// (plugin load and `ServerLoadEvent`), and give the n-th registered entry the
/// id `vanillaCount + n`. Register in the order of the mod's registry sync and
/// compare with [PluginRegistryChecks.checkSequence].
///
/// Permissions: [Permissions.registryBlockEntities], [Permissions.registryMenus]
/// and [Permissions.registryComponents] in `PluginInfo.permissions`.
abstract final class BlockEntityRegistries {
  /// The server's block entity type registry.
  static final BlockEntityTypeBackend host = const HostBlockEntityTypes();
}

/// See [BlockEntityRegistries].
abstract final class MenuRegistries {
  /// The server's menu type registry.
  static final MenuTypeBackend host = const HostMenuTypes();
}

/// See [BlockEntityRegistries]. (`ComponentRegistries` is the table of vanilla
/// component names of `DataComponentCodec`.)
abstract final class ComponentTypeRegistries {
  /// The server's custom data component type registry.
  static final ComponentTypeBackend host = const HostComponentTypes();
}

T _unwrap<T>(Object result, String what) => switch (result) {
  OkResult(:final value) => value as T,
  ErrorResult(:final value) => throw PluginRegistryException('$what failed: $value'),
  _ => throw StateError('Unexpected result $result'),
};

/// [BlockEntityTypeBackend] over the generated host bindings.
final class HostBlockEntityTypes implements BlockEntityTypeBackend {
  const HostBlockEntityTypes();

  @override
  int register(String key, List<String> validBlocks) => _unwrap(
    generated.pluginBlockEntity.registerBlockEntityType(key: key, validBlockKeys: validBlocks),
    'Registering the block entity type $key',
  );

  @override
  int? idOf(String key) => generated.pluginBlockEntity.getBlockEntityTypeId(key: key);

  @override
  int get vanillaCount => generated.pluginBlockEntity.getVanillaBlockEntityTypeCount();

  @override
  List<RegisteredType> get registered => [
    for (final e in generated.pluginBlockEntity.getRegisteredBlockEntityTypes()) RegisteredType(e.key, e.id),
  ];
}

/// [MenuTypeBackend] over the generated host bindings.
final class HostMenuTypes implements MenuTypeBackend {
  const HostMenuTypes();

  @override
  int register(String key) =>
      _unwrap(generated.menus.registerMenuType(key: key), 'Registering the menu type $key');

  @override
  int? idOf(String key) => generated.menus.getMenuTypeId(key: key);

  @override
  int get vanillaCount => generated.menus.getVanillaMenuTypeCount();

  @override
  List<RegisteredType> get registered => [
    for (final e in generated.menus.getRegisteredMenuTypes()) RegisteredType(e.key, e.id),
  ];
}

/// [ComponentTypeBackend] over the generated host bindings.
final class HostComponentTypes implements ComponentTypeBackend {
  const HostComponentTypes();

  @override
  int register(String key, {required bool persistent, required ComponentCodec codec}) => _unwrap(
    generated.customComponents.registerDataComponentType(
      key: key,
      persistent: persistent,
      codec: [for (final op in codec.ops) _toWire(op)],
    ),
    'Registering the data component type $key (${codec.toString()})',
  );

  static generated.CodecOp _toWire(ComponentCodecOp op) => switch (op.kind) {
    CodecOpKind.varInt => const generated.CodecOpVarInt(),
    CodecOpKind.varLong => const generated.CodecOpVarLong(),
    CodecOpKind.flag => const generated.CodecOpFlag(),
    CodecOpKind.byte => const generated.CodecOpByte(),
    CodecOpKind.short => const generated.CodecOpShort(),
    CodecOpKind.int32 => const generated.CodecOpInt(),
    CodecOpKind.long => const generated.CodecOpLong(),
    CodecOpKind.float32 => const generated.CodecOpFloat32(),
    CodecOpKind.float64 => const generated.CodecOpFloat64(),
    CodecOpKind.text => const generated.CodecOpText(),
    CodecOpKind.byteArray => const generated.CodecOpByteArray(),
    CodecOpKind.uuid => const generated.CodecOpUuid(),
    CodecOpKind.fixedBytes => generated.CodecOpFixedBytes(op.argument),
    CodecOpKind.nbt => const generated.CodecOpNbt(),
    CodecOpKind.stack => const generated.CodecOpStack(),
    CodecOpKind.componentPatch => const generated.CodecOpComponentPatch(),
    CodecOpKind.optional => const generated.CodecOpOptional(),
    CodecOpKind.repeated => const generated.CodecOpRepeated(),
    CodecOpKind.sequence => generated.CodecOpSequence(op.argument),
  };

  @override
  int? idOf(String key) => generated.customComponents.getDataComponentTypeId(key: key);

  @override
  int get vanillaCount => generated.customComponents.getVanillaDataComponentTypeCount();

  @override
  List<RegisteredType> get registered => [
    for (final e in generated.customComponents.getRegisteredDataComponentTypes()) RegisteredType(e.key, e.id),
  ];
}

// -- Block entities -------------------------------------------------------------

/// The data of a plugin block entity.
final class PluginBlockEntityState {
  /// The key of its type.
  final String typeKey;

  /// Saved with the chunk, never sent to clients.
  final NbtCompound save;

  /// Sent to the players watching the chunk (the "update tag"), or `null`.
  final NbtCompound? client;

  const PluginBlockEntityState(this.typeKey, this.save, this.client);

  @override
  String toString() => 'PluginBlockEntityState($typeKey)';
}

/// Block entities of plugin types (`plugin-block-entity.wit`) at positions of
/// a world. Placing a block does not create its entity: call
/// [setPluginBlockEntity] once the block is in the world.
extension PluginBlockEntities on generated.World {
  /// The plugin block entity at [pos], `null` if there is none (also when the
  /// chunk is not loaded).
  PluginBlockEntityState? pluginBlockEntityAt(generated.BlockPos pos) {
    final data = generated.pluginBlockEntity.getBlockEntityData(targetWorld: this, pos: pos);
    if (data == null) return null;
    final client = data.clientData;
    return PluginBlockEntityState(
      data.typeKey,
      NbtCompound.fromTree(data.saveData),
      client == null ? null : NbtCompound.fromTree(client),
    );
  }

  /// Creates the block entity at [pos], or replaces the data of the one that
  /// is there (of the same type), and sends [client] to the players watching
  /// the chunk. Throws a [PluginRegistryException] if the type is unknown, the
  /// chunk is not loaded or the position holds an entity of another type.
  void setPluginBlockEntity(
    generated.BlockPos pos,
    String typeKey,
    NbtCompound save, {
    NbtCompound? client,
  }) => _unwrap<void>(
    generated.pluginBlockEntity.setBlockEntityData(
      targetWorld: this,
      pos: pos,
      typeKey: typeKey,
      saveData: save.toTree(),
      clientData: client?.toTree(),
    ),
    'Setting the block entity data at (${pos.x}, ${pos.y}, ${pos.z})',
  );

  /// Resends the client data of the entity at [pos] and marks the chunk as
  /// changed. Throws if there is no such entity.
  void syncPluginBlockEntity(generated.BlockPos pos) => _unwrap<void>(
    generated.pluginBlockEntity.syncBlockEntity(targetWorld: this, pos: pos),
    'Syncing the block entity at (${pos.x}, ${pos.y}, ${pos.z})',
  );

  /// Removes the plugin block entity at [pos] with its saved data; whether
  /// there was one. Fires the unload event with `removed` true.
  bool removePluginBlockEntity(generated.BlockPos pos) =>
      generated.pluginBlockEntity.removeBlockEntity(targetWorld: this, pos: pos);
}

/// Reading the compound tags of the block entity events.
extension BlockEntityLoadData on generated.BlockEntityLoadEventData {
  /// The saved data as a compound.
  NbtCompound get save => NbtCompound.fromTree(saveData);

  /// The client data as a compound, `null` if the entity has none.
  NbtCompound? get client {
    final tree = clientData;
    return tree == null ? null : NbtCompound.fromTree(tree);
  }
}

/// Reading the compound tag of the block entity unload event.
extension BlockEntityUnloadData on generated.BlockEntityUnloadEventData {
  /// The saved data as a compound.
  NbtCompound get save => NbtCompound.fromTree(saveData);
}

// -- Menus ------------------------------------------------------------------------

/// The plugin menu a player has open.
final class PluginMenuInfo {
  /// The container id the client's messages carry.
  final int containerId;

  /// The key of the menu type.
  final String menuType;

  /// The number of slots the server tracks.
  final int slotCount;

  const PluginMenuInfo(this.containerId, this.menuType, this.slotCount);

  @override
  String toString() => 'PluginMenuInfo($menuType, container $containerId)';
}

/// Menus of plugin defined types (`menus.wit`) for a [generated.Player].
///
/// A menu has no behaviour: clicks arrive as `Events.menuClick`, the end as
/// `Events.menuClosed`. With `extraData` the host sends the NeoForge payload
/// `neoforge:advanced_open_screen` instead of the vanilla open screen packet
/// (the bytes are whatever the mod's menu factory reads); you decide per
/// player whether the connection can take it.
extension PluginMenus on generated.Player {
  /// Opens a menu of type [typeKey] with [slots] server-tracked slots (0 for
  /// a terminal style GUI that only talks through payloads) and returns its
  /// container id. [title] is a `String` with color codes, a `Text` or a
  /// `TextComponent`. Closes the screen the player has open. Java players
  /// only.
  int openPluginMenu(
    String typeKey,
    Object title, {
    List<int>? extraData,
    int slots = 0,
  }) {
    final component = Messages.component(title);
    final bytes = extraData == null ? null : List<int>.of(extraData);
    final result = slots == 0
        ? generated.menus.openMenu(player: this, menuTypeKey: typeKey, title: component, extraData: bytes)
        : generated.menus.openMenuWithSlots(
            player: this,
            menuTypeKey: typeKey,
            title: component,
            extraData: bytes,
            slotCount: slots,
          );
    return _unwrap(result, 'Opening the menu $typeKey');
  }

  /// Closes the player's plugin menu, if they have one open.
  bool closePluginMenu() => generated.menus.closeMenu(player: this);

  /// The plugin menu the player has open, `null` if the open screen is not
  /// one.
  PluginMenuInfo? get currentPluginMenu {
    final info = generated.menus.getOpenMenu(player: this);
    return info == null ? null : PluginMenuInfo(info.containerId, info.menuType, info.slotCount);
  }

  /// Puts a copy of [stack] into [slot] of the open plugin menu.
  void setPluginMenuSlot(int slot, generated.ItemStack stack) => _unwrap<void>(
    generated.menus.setMenuSlot(player: this, slot: slot, stack: stack),
    'Setting menu slot $slot',
  );

  /// Empties [slot] of the open plugin menu.
  void clearPluginMenuSlot(int slot) =>
      _unwrap<void>(generated.menus.clearMenuSlot(player: this, slot: slot), 'Clearing menu slot $slot');

  /// Sends the data slot [id] (a 16 bit number the client's menu shows) of the
  /// open plugin menu with `ClientboundContainerSetData`.
  void setPluginMenuData(int id, int value) => _unwrap<void>(
    generated.menus.setMenuData(player: this, id: id, value: value),
    'Setting menu data $id',
  );
}

// -- Custom item components ----------------------------------------------------------

/// Values of custom data components (`custom-components.wit`) on an item
/// stack. The vanilla `getComponents`/`setComponent` do not see them.
///
/// The value is the component's network encoding, as many bytes as
/// `ComponentCodec` describes; build them with `PacketBuffer.encode`.
extension CustomItemComponents on generated.ItemStack {
  /// The value of the custom component [key], `null` if the stack has none.
  Uint8List? customComponent(String key) {
    final value = generated.customComponents.getCustomComponent(stack: this, key: key);
    return value == null ? null : Uint8List.fromList(value);
  }

  /// Sets the custom component [key] to [value] (exactly one value of the
  /// type's codec, otherwise this throws a [PluginRegistryException] and
  /// nothing changes).
  void setCustomComponent(String key, List<int> value) => _unwrap<void>(
    generated.customComponents.setCustomComponent(stack: this, key: key, value: List<int>.of(value)),
    'Setting the component $key',
  );

  /// Removes the custom component [key].
  void removeCustomComponent(String key) => _unwrap<void>(
    generated.customComponents.removeCustomComponent(stack: this, key: key),
    'Removing the component $key',
  );
}
