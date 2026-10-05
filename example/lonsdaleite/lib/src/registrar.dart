/// What the server needs to register the mod's items, behind an interface so
/// the host's registration API (still being designed) is one adapter away.
library;

import 'manifest.dart';

/// Everything a host needs to create one item.
final class ItemDefinition {
  /// `lonsdaleite:lonsdaleite_pickaxe`.
  final String id;

  final int maxStackSize;

  /// The default components, as vanilla-format JSON. These are the server's
  /// view: the mod's components with the server-only replacements applied.
  final Json components;

  /// The block this item places, if it is a block item.
  final String? block;

  const ItemDefinition({
    required this.id,
    required this.maxStackSize,
    required this.components,
    required this.block,
  });

  /// The definition of a manifest [item].
  factory ItemDefinition.fromManifest(ManifestItem item) => ItemDefinition(
    id: item.id,
    maxStackSize: item.components.maxStackSize ?? 64,
    components: item.serverView.raw,
    block: item.block,
  );
}

/// Registers items with the server. Implemented by the host adapter
/// (`host_adapter.dart`) and by fakes in tests.
abstract interface class ItemRegistrar {
  /// Registers [item] and returns the id the host gave it. Called in the mod's
  /// registration order, which decides the items' numeric ids.
  int register(ItemDefinition item);
}

/// Registers every item of [manifest] with [registrar], in registration order,
/// and returns the ids the host assigned, in that order.
List<int> registerManifestItems(Manifest manifest, ItemRegistrar registrar) {
  final ordered = [...manifest.items]
    ..sort((a, b) => a.registrationIndex.compareTo(b.registrationIndex));
  return [
    for (final item in ordered)
      registrar.register(ItemDefinition.fromManifest(item)),
  ];
}
