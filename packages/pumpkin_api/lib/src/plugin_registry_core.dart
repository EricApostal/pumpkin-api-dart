// Registration of block entity types, menu types and data component types,
// without host imports: the interfaces the host bindings implement and the
// check a plugin runs after registering. `plugin_registries.dart` connects
// them to the generated bindings.
import 'component_codec.dart';

/// Thrown when the host refuses a registration or a call of the block entity,
/// menu and custom component APIs, or an expectation about them does not hold.
final class PluginRegistryException implements Exception {
  final String message;

  const PluginRegistryException(this.message);

  @override
  String toString() => 'PluginRegistryException: $message';
}

/// A registered type and its network id.
final class RegisteredType {
  /// The full resource location (`namespace:path`).
  final String key;
  final int id;

  const RegisteredType(this.key, this.id);

  @override
  bool operator ==(Object other) => other is RegisteredType && other.key == key && other.id == id;

  @override
  int get hashCode => Object.hash(key, id);

  @override
  String toString() => '$key=$id';
}

/// The host's block entity type registry (`plugin-block-entity.wit`).
/// Registration needs `registry.block-entities` and is only possible while
/// the server loads.
abstract interface class BlockEntityTypeBackend {
  /// Registers a type for the blocks [validBlocks] and returns its id
  /// (`vanillaCount + n`). Throws a [PluginRegistryException] for an invalid
  /// or conflicting key, a missing permission, or when registration is closed.
  int register(String key, List<String> validBlocks);

  /// The id of a plugin type, or `null`.
  int? idOf(String key);

  /// The number of vanilla types; the id of the first plugin type.
  int get vanillaCount;

  /// All plugin types in id order.
  List<RegisteredType> get registered;
}

/// The host's menu type registry (`menus.wit`), permission `registry.menus`.
abstract interface class MenuTypeBackend {
  /// Registers a type and returns its id (`vanillaCount + n`).
  int register(String key);

  int? idOf(String key);

  int get vanillaCount;

  List<RegisteredType> get registered;
}

/// The host's custom data component registry (`custom-components.wit`),
/// permission `registry.components`.
abstract interface class ComponentTypeBackend {
  /// Registers a type whose values are encoded as [codec], and returns its id
  /// (`vanillaCount + n`). A [persistent] type is saved with the item stack.
  int register(String key, {required bool persistent, required ComponentCodec codec});

  int? idOf(String key);

  int get vanillaCount;

  List<RegisteredType> get registered;
}

/// Checks that go with the registries above.
abstract final class PluginRegistryChecks {
  /// Verifies that the plugin types [registered] by the host are exactly
  /// [expectedKeys], in this order, with the ids a registry sync announces to
  /// clients (`vanillaCount + position`). [registry] names the registry in
  /// the message. Throws a [PluginRegistryException] that lists every
  /// difference: a client would draw or open other things than the server
  /// means if the ids differ.
  static void checkSequence(
    String registry, {
    required int expectedVanillaCount,
    required int vanillaCount,
    required List<String> expectedKeys,
    required List<RegisteredType> registered,
  }) {
    final problems = <String>[];
    if (vanillaCount != expectedVanillaCount) {
      problems.add(
        'the host has $vanillaCount vanilla entries, the registry sync was built for $expectedVanillaCount',
      );
    }
    if (registered.length != expectedKeys.length) {
      problems.add(
        'the host has ${registered.length} plugin entries, the registry sync lists ${expectedKeys.length} '
        '(another plugin registered ${registered.length > expectedKeys.length ? 'entries' : 'fewer entries'}?)',
      );
    }
    for (var i = 0; i < expectedKeys.length; i++) {
      final key = expectedKeys[i];
      final id = expectedVanillaCount + i;
      RegisteredType? entry;
      for (final r in registered) {
        if (r.key == key) entry = r;
      }
      if (entry == null) {
        problems.add('`$key` is not registered');
      } else if (entry.id != id) {
        problems.add('`$key` has id ${entry.id} on the host, the registry sync tells the client $id');
      }
    }
    if (problems.isNotEmpty) {
      throw PluginRegistryException(
        'The `$registry` registry does not match the registry sync: ${problems.join('; ')}. '
        'Register in the order of the sync, before any other plugin does.',
      );
    }
  }
}
