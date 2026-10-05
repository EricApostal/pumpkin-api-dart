// Vanilla registry entries by numeric id, for encoding data components.
// Free of host imports (it is unit-tested on the Dart VM).
import 'registry_ids.g.dart';

/// The entries of one registry, in id order: the index is the numeric id the
/// host puts on the wire and reads from data components.
final class RegistryIds {
  /// The registry, without namespace (`sound_event`, `block`, ...).
  final String registry;

  /// Entry names without the `minecraft:` prefix, index = id.
  final List<String> names;

  final Map<String, int> _ids;

  RegistryIds(this.registry, Iterable<String> names)
    : names = List.unmodifiable(names),
      _ids = {} {
    for (var i = 0; i < this.names.length; i++) {
      _ids[this.names[i]] = i;
    }
  }

  /// The number of entries.
  int get length => names.length;

  /// The id of [key] (`minecraft:` prefix optional), or `null`.
  int? idOf(String key) => _ids[_bare(key)];

  /// The id of [key]; throws an [ArgumentError] naming the registry if there
  /// is no such entry.
  int require(String key) =>
      idOf(key) ??
      (throw ArgumentError.value(key, 'key', 'is not a vanilla $registry'));

  /// The full key (`minecraft:...`) with the id [id], or `null`.
  String? keyOf(int id) =>
      id >= 0 && id < names.length ? 'minecraft:${names[id]}' : null;

  static String _bare(String key) =>
      key.startsWith('minecraft:') ? key.substring('minecraft:'.length) : key;
}

/// The vanilla registries that data components refer to by id, generated from
/// Pumpkin's assets by `tool/generate_registry_ids.dart`.
abstract final class VanillaIds {
  static final Map<String, RegistryIds> _cache = {};

  static RegistryIds _of(String registry) => _cache.putIfAbsent(registry, () {
    final packed = generatedRegistryPacked(registry);
    if (packed == null) {
      throw StateError('No generated list for $registry');
    }
    return RegistryIds(registry, packed.split('\n'));
  });

  /// The registries a list exists for.
  static List<String> get registries => generatedRegistryNames;

  /// `minecraft:item` (the ids of vanilla items; custom items follow them).
  static RegistryIds get items => _of('item');

  /// `minecraft:block`.
  static RegistryIds get blocks => _of('block');

  /// `minecraft:sound_event`.
  static RegistryIds get sounds => _of('sound_event');

  /// `minecraft:attribute`.
  static RegistryIds get attributes => _of('attribute');

  /// `minecraft:mob_effect`.
  static RegistryIds get mobEffects => _of('mob_effect');

  /// `minecraft:entity_type`.
  static RegistryIds get entityTypes => _of('entity_type');

  /// `minecraft:data_component_type`: the ids of the data components
  /// (`hidden_components` of a tooltip display).
  static RegistryIds get dataComponentTypes => _of('data_component_type');

  /// `minecraft:damage_type`, ordered like Pumpkin's `DamageType::from_id`.
  static RegistryIds get damageTypes => _of('damage_type');

  /// `minecraft:enchantment`, ordered like Pumpkin's `Enchantment::from_id`.
  static RegistryIds get enchantments => _of('enchantment');
}
