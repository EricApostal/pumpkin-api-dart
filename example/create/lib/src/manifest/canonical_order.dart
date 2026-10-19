// Canonical registration order for the id-bearing registries.
//
// A real Create client has its own registries built from the Java mod: the
// numeric ids it uses for blocks, items, block entity types, entities, menus,
// data components, fluids, damage types, sounds, particles and recipe types are
// the Java registration order. NeoForge syncs the plugin's entries on top of the
// vanilla ones, so the order here has to match the Java mod exactly.
//
// The content manifest (`blocks.g.dart`, `items.g.dart`, `registries.g.dart`)
// was extracted from that Java tree and preserves the order, so it is the source
// of truth. Modules still register declaratively in any order; this reorders
// what they registered before the registry is applied to the host.
//
// The key lists live in `content/canonical_registry_order.dart`, which imports
// only the manifest, so the tests can check them without the host API.
import '../content/canonical_registry_order.dart';
import '../core/registry.dart';

/// Installs the Java registration order on every id-bearing registry.
void applyCanonicalOrder(CreateRegistry registry) {
  final order = canonicalRegistryOrder();
  final covered = <RegistryKind>{};

  for (final entry in order.entries) {
    final kind = RegistryKind.values.byName(entry.key);
    registry.useOrder(kind, entry.value);
    covered.add(kind);
  }

  // A kind without an order keeps its registration order, so a Create client would number its
  // entries differently. Fail loudly instead of producing a subtly broken client sync.
  final missing = [
    for (final kind in RegistryKind.values)
      if (!covered.contains(kind)) kind.name,
  ];
  if (missing.isNotEmpty) {
    throw StateError(
      'No canonical registration order for ${missing.join(', ')}; '
      'add it to canonicalRegistryOrder().',
    );
  }
}
