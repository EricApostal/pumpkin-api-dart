// Registration of custom items, without host imports: the interface the host
// binding implements, the value types, and the checks a plugin runs after
// registering. `item_registry.dart` connects it to the generated bindings.
import 'data_component_codec.dart';

/// Thrown when the host refuses an item or tag, or an expectation about the
/// registry does not hold.
final class ItemRegistryException implements Exception {
  final String message;

  const ItemRegistryException(this.message);

  @override
  String toString() => 'ItemRegistryException: $message';
}

/// An item and its network id.
final class RegisteredItem {
  /// The full resource location (`namespace:path`).
  final String key;
  final int id;

  const RegisteredItem(this.key, this.id);

  @override
  bool operator ==(Object other) =>
      other is RegisteredItem && other.key == key && other.id == id;

  @override
  int get hashCode => Object.hash(key, id);

  @override
  String toString() => '$key=$id';
}

/// A custom item to add to the host's item registry.
final class ItemRegistration {
  /// `namespace:path`, lowercase, `a-z 0-9 _ - .` (and `/` in the path). The
  /// `minecraft` namespace is reserved.
  final String key;

  /// The default components, encoded for the host. The host adds vanilla
  /// style defaults for the ones left out (see `item-registry.wit`).
  final List<EncodedComponent> components;

  /// Replaces a max-stack-size component if both are given.
  final int? maxStackSize;

  const ItemRegistration({
    required this.key,
    this.components = const [],
    this.maxStackSize,
  });
}

/// The host's item registry as plain Dart: what `item-registry.wit` offers.
/// Implemented over the generated bindings by `ItemRegistries.host`, and by
/// fakes in tests.
abstract interface class ItemRegistryBackend {
  /// Registers [item] and returns its id. Throws an [ItemRegistryException]
  /// for an invalid or duplicate key, a component that does not decode, a
  /// missing `registry.items` permission, or when registration is closed
  /// (after the server starts accepting connections).
  int register(ItemRegistration item);

  /// Adds [entries] (item keys or `#tag` references) to the item tag [tag],
  /// creating it. Same restrictions as [register].
  void registerTag(String tag, List<String> entries);

  /// The id of an item (`minecraft:` prefix optional), or `null`.
  int? idOf(String key);

  /// The full resource location of the item with [id], or `null`.
  String? keyOf(int id);

  /// The number of vanilla items; also the id of the first custom item.
  int get vanillaCount;

  /// All vanilla items in id order.
  List<RegisteredItem> get vanillaItems;

  /// All custom items in id order.
  List<RegisteredItem> get registeredItems;
}

/// Checks on a registry whose ids a client depends on.
abstract final class ItemRegistryChecks {
  /// Whether [key] is a valid custom item key, with the host's rules.
  static bool isValidKey(String key) {
    final colon = key.indexOf(':');
    if (colon <= 0 || colon == key.length - 1) return false;
    final namespace = key.substring(0, colon);
    final path = key.substring(colon + 1);
    return namespace != 'minecraft' &&
        _namespace.hasMatch(namespace) &&
        _path.hasMatch(path);
  }

  static final RegExp _namespace = RegExp(r'^[a-z0-9_.\-]+$');
  static final RegExp _path = RegExp(r'^[a-z0-9_.\-/]+$');

  /// Throws if the host's vanilla items are not [expected] (keys in id
  /// order): a count mismatch or the first key that differs. The client's
  /// registry sync assumes exactly these ids.
  static void checkVanillaItems(
    ItemRegistryBackend backend,
    List<String> expected,
  ) {
    final count = backend.vanillaCount;
    if (count != expected.length) {
      throw ItemRegistryException(
        'The server has $count vanilla items, but the registry sync was '
        'built for ${expected.length}. The ids of custom items would not '
        'match what clients are told, so the plugin refuses to continue. '
        'Run the server build this plugin was generated for, or regenerate '
        'the vanilla lists (packages/pumpkin_neoforge: '
        'tool/generate_vanilla_registries.dart).',
      );
    }
    final actual = backend.vanillaItems;
    if (actual.length != count) {
      throw ItemRegistryException(
        'The host reports $count vanilla items but lists ${actual.length}.',
      );
    }
    for (var i = 0; i < count; i++) {
      if (actual[i].id != i || actual[i].key != expected[i]) {
        throw ItemRegistryException(
          'Vanilla item $i is `${actual[i].key}` (id ${actual[i].id}) on the '
          'server, but the registry sync expects `${expected[i]}`.',
        );
      }
    }
  }

  /// Throws unless [assigned] (the custom items in registration order) have
  /// the ids `vanillaCount + index`: that is how a NeoForge server numbers
  /// them, and what the registry sync tells clients. A different start means
  /// another plugin registered items first.
  static void checkAssignedIds({
    required int vanillaCount,
    required List<RegisteredItem> assigned,
  }) {
    for (var i = 0; i < assigned.length; i++) {
      final expected = vanillaCount + i;
      if (assigned[i].id != expected) {
        throw ItemRegistryException(
          '`${assigned[i].key}` got id ${assigned[i].id}, but the registry '
          'sync tells clients $expected (vanilla items: $vanillaCount, '
          'registration index: $i). Another plugin has registered items '
          'before this one: load this plugin first, or include those items '
          'in the sync.',
        );
      }
    }
  }
}
