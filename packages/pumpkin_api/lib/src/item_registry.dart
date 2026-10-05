import 'package:wasm_components/wasm_components.dart' show ErrorResult, OkResult;

import 'bindings.g.dart' as generated;
import 'item_registry_core.dart';

/// The host's item registry (`item-registry.wit`), for plugins that add items.
///
/// Registration needs the `registry.items` permission ([Permissions.registryItems]
/// in `PluginInfo.permissions`) and is only possible while the server loads
/// (`Plugin.onLoad` and `ServerLoadEvent`); once it accepts connections the
/// registry is closed. Custom items get the ids `vanillaCount + n`, `n` being
/// the order of registration across all plugins.
///
/// Encode the components with `DataComponentCodec` (JSON in the vanilla
/// format -> bytes), then register:
///
/// ```dart
/// final encoded = DataComponentCodec.encodeAll({
///   'minecraft:max_damage': 250,
///   'minecraft:enchantable': {'value': 10},
/// });
/// final id = ItemRegistries.host.register(
///   ItemRegistration(key: 'my_plugin:ruby_sword', components: encoded.encoded),
/// );
/// ```
abstract final class ItemRegistries {
  /// The server's item registry.
  static final ItemRegistryBackend host = const HostItemRegistry();
}

/// [ItemRegistryBackend] over the generated host bindings.
final class HostItemRegistry implements ItemRegistryBackend {
  const HostItemRegistry();

  @override
  int register(ItemRegistration item) {
    final components = <generated.DataComponentValue>[];
    for (final c in item.components) {
      final component = generated.DataComponent.fromWireName(c.wireName);
      if (component == null) {
        throw ItemRegistryException(
          '`${c.name}` is not a data component the host knows (${c.wireName}).',
        );
      }
      components.add(
        generated.DataComponentValue(component: component, value: c.bytes),
      );
    }
    final result = generated.itemRegistry.registerItem(
      definition: generated.ItemDefinition(
        key: item.key,
        components: components,
        maxStackSize: item.maxStackSize,
      ),
    );
    return switch (result) {
      OkResult(:final value) => value,
      ErrorResult(:final value) => throw ItemRegistryException(
        'Registering ${item.key} failed: $value',
      ),
    };
  }

  @override
  void registerTag(String tag, List<String> entries) {
    final result = generated.itemRegistry.registerItemTag(
      tag: tag,
      entries: entries,
    );
    if (result case ErrorResult(:final value)) {
      throw ItemRegistryException('Registering the item tag $tag failed: $value');
    }
  }

  @override
  int? idOf(String key) => generated.itemRegistry.getItemId(key: key);

  @override
  String? keyOf(int id) => generated.itemRegistry.getItemKey(id: id);

  @override
  int get vanillaCount => generated.itemRegistry.getVanillaItemCount();

  @override
  List<RegisteredItem> get vanillaItems => _entries(
    generated.itemRegistry.getVanillaItems(),
  );

  @override
  List<RegisteredItem> get registeredItems => _entries(
    generated.itemRegistry.getRegisteredItems(),
  );

  static List<RegisteredItem> _entries(List<generated.ItemEntry> entries) => [
    for (final e in entries) RegisteredItem(e.key, e.id),
  ];
}
