/// Registers the mod's items and item tags with the host and checks the ids
/// the host gave them. Binding-free (it works on an [ItemRegistryBackend]), so
/// it is tested with a fake backend; `host_adapter.dart` supplies the real one.
library;

import 'package:pumpkin_api/pumpkin_api_core.dart';

import 'component_codec.dart';
import 'manifest.dart';
import 'registrar.dart';

/// An [ItemRegistrar] that encodes the components and registers through an
/// [ItemRegistryBackend].
class BackendItemRegistrar implements ItemRegistrar {
  final ItemRegistryBackend backend;

  /// What was left out because the host cannot read it.
  final SkippedComponentsLog skipped = SkippedComponentsLog();

  final ComponentRegistries _registries;

  BackendItemRegistrar(this.backend)
    : _registries = ComponentRegistries.vanilla(item: backend.idOf);

  @override
  int register(ItemDefinition item) {
    final encoded = encodeItem(item, registries: _registries);
    skipped.add(item.id, encoded.skipped);
    return backend.register(encoded.registration);
  }
}

/// The outcome of [installManifestItems].
final class ItemInstallation {
  /// The mod's items with their ids, in registration (and id) order.
  final List<RegisteredItem> items;

  /// The host's vanilla item count, which is also the id of the first item.
  final int vanillaCount;

  /// The item tags that were registered.
  final List<String> itemTags;

  /// The components that were left out, by component.
  final SkippedComponentsLog skippedComponents;

  const ItemInstallation({
    required this.items,
    required this.vanillaCount,
    required this.itemTags,
    required this.skippedComponents,
  });
}

/// Registers every item of [manifest] with [registrar] (in registration
/// order), then the item tags, and verifies the result:
///
/// * the host's vanilla items are exactly [expectedVanillaItems] (the list the
///   NeoForge registry sync is built from; Pumpkin's `items.json`), because
///   the ids of the mod's items are `vanillaCount + index` and the client is
///   told so;
/// * every item got the id `vanillaCount + registrationIndex`, and the host
///   reports the same ids when asked again.
///
/// Throws an [ItemRegistryException] (or the [ComponentEncodeException] of an
/// item) with a message that says what to do; the plugin must not go on
/// then, or clients would be told the wrong ids.
ItemInstallation installManifestItems(
  Manifest manifest,
  BackendItemRegistrar registrar, {
  required List<String> expectedVanillaItems,
}) {
  final backend = registrar.backend;
  ItemRegistryChecks.checkVanillaItems(backend, expectedVanillaItems);
  final vanillaCount = backend.vanillaCount;

  final ordered = [...manifest.items]
    ..sort((a, b) => a.registrationIndex.compareTo(b.registrationIndex));
  for (final item in ordered) {
    if (!ItemRegistryChecks.isValidKey(item.id)) {
      throw ItemRegistryException('`${item.id}` is not a valid item key.');
    }
  }

  final ids = registerManifestItems(manifest, registrar);
  final assigned = [
    for (var i = 0; i < ordered.length; i++)
      RegisteredItem(ordered[i].id, ids[i]),
  ];
  ItemRegistryChecks.checkAssignedIds(
    vanillaCount: vanillaCount,
    assigned: assigned,
  );

  // Ask the host again: what it reports is what the packets will carry.
  final readBack = {for (final e in backend.registeredItems) e.key: e.id};
  for (final item in assigned) {
    final id = readBack[item.key];
    if (id != item.id) {
      throw ItemRegistryException(
        '`${item.key}` was registered with id ${item.id}, but the host '
        'reports ${id ?? 'no such item'}.',
      );
    }
  }

  final itemTags = <String>[];
  for (final tag in manifest.tags['item']?.values ?? const <TagFile>[]) {
    if (tag.replace) {
      throw ItemRegistryException(
        'The tag `${tag.id}` has "replace": true, which the host cannot do '
        '(it only adds entries to tags).',
      );
    }
    backend.registerTag(tag.id, tag.values);
    itemTags.add(tag.id);
  }

  return ItemInstallation(
    items: assigned,
    vanillaCount: vanillaCount,
    itemTags: itemTags,
    skippedComponents: registrar.skipped,
  );
}
