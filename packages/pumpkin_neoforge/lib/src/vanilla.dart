// Access to the generated vanilla registry lists. Binding-free.
import 'vanilla_registries.g.dart';

export 'vanilla_registries.g.dart'
    show vanillaBlockStateCount, vanillaMinecraftVersion, vanillaRegistryKeys;

/// The vanilla registries as generated from Pumpkin's assets by
/// `tool/generate_vanilla_registries.dart`: every entry name (with the
/// `minecraft:` prefix) in network id order, so the index is the id Pumpkin
/// uses on the wire.
abstract final class VanillaRegistries {
  static final Map<String, List<String>> _cache = {};

  /// The registries a list exists for.
  static List<String> get keys => vanillaRegistryKeys;

  /// The entries of [registry] (e.g. `minecraft:item`) in id order, or null if
  /// there is no generated list. The list is unmodifiable.
  static List<String>? entries(String registry) {
    final cached = _cache[registry];
    if (cached != null) return cached;
    final packed = vanillaRegistryPacked(registry);
    if (packed == null) return null;
    final list = List<String>.unmodifiable([
      for (final name in packed.split('\n')) 'minecraft:$name',
    ]);
    return _cache[registry] = list;
  }

  /// Like [entries], but throws a [StateError] if there is no list.
  static List<String> require(String registry) =>
      entries(registry) ??
      (throw StateError(
        'No vanilla list for $registry; generated: ${keys.join(', ')}',
      ));
}
