// The NeoForge declaration has to name every host-numbered registry this plugin
// registers content into.
//
// Why this is not cosmetic: the host numbers the plugin entries of a registry in
// registration order (`vanilla count + index`) and writes those ids in chunk data
// and packets, and a client that is not sent the snapshot resolves each id against
// *its own* order — a different item or block, silently (the "adding an item to my
// inventory gives a different item" bug). A host-numbered registry is sent whole or
// not at all (`crates/pumpkin-core/src/net/neoforge/registries.rs`, `syncable`), so
// a registry this plugin registers into but does not name is dropped from the sync
// for *every* plugin, not only for this one.
//
// `CcRegistries` has no host imports, so the VM can read the key list
// (`declaredRegistryKeys`); the declaration types (`pumpkin_api`) are wasm-only, so
// the source that turns the list into the declaration and the plugin's registration
// sites are checked by marker in `lib/src` (the way `dimension_key_test.dart` reads
// the source).
import 'dart:io';

import 'package:cc_tweaked/src/protocol/registries.dart';
import 'package:test/test.dart';

/// Every host-numbered registry the plugin can register content into, and a marker
/// of the registration in `lib/src`. A marker is a call into the API class whose
/// `.host`/`.register` puts the entry in the host's dynamic registry; a new
/// registration that uses one of them without a matching declaration entry fails
/// [every registration site is declared].
const Map<String, List<String>> _registrationSites = {
  'minecraft:item': ['ItemRegistries.host'],
  'minecraft:block': ['BlockRegistries.host'],
  'minecraft:block_entity_type': ['BlockEntityRegistries.host'],
  'minecraft:menu': ['MenuRegistries.host'],
  'minecraft:data_component_type': ['ComponentTypeRegistries.host'],
  // Registries the plugin does not register into today; the markers are here so
  // that adding the call without naming the registry fails the test.
  'minecraft:fluid': ['FluidRegistries.register'],
  'minecraft:entity_type': ['EntityRegistries.register('],
  'neoforge:entity_data_serializers': ['EntityRegistries.registerDataSerializer'],
  'minecraft:sound_event': ['ExtraRegistries.registerSound'],
  'minecraft:particle_type': ['ExtraRegistries.registerParticle'],
  'minecraft:mob_effect': ['ExtraRegistries.registerMobEffect'],
  'minecraft:map_decoration_type': ['ExtraRegistries.registerMapDecoration'],
};

/// The source of every Dart file under `lib/`.
String _librarySource() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
  return [for (final f in files) f.readAsStringSync()].join('\n');
}

void main() {
  test('the five registries the plugin registers into are declared', () {
    // `plugin.dart` registers into exactly these: `_registerItems`
    // (`minecraft:item`), `_registerBlocks` (`minecraft:block`) and
    // `_registerRegistries` (`minecraft:block_entity_type`, `minecraft:menu`,
    // `minecraft:data_component_type`).
    for (final key in [
      'minecraft:item',
      'minecraft:block',
      'minecraft:block_entity_type',
      'minecraft:menu',
      'minecraft:data_component_type',
    ]) {
      expect(
        CcRegistries.declaredRegistryKeys,
        contains(key),
        reason: '$key is registered through the host and must be named in the '
            'declaration, or the host drops it from the registry sync for every plugin',
      );
    }
  });

  test('the mod registry the host does not know is declared whole', () {
    expect(CcRegistries.declaredRegistryKeys, contains('computercraft:recipe_function'));
    expect(CcRegistries.recipeFunctions, isNotEmpty);
  });

  test('every registry the plugin synchronises is declared', () {
    // `synchronised` is [additions] without the keys that have no vanilla list
    // (`minecraft:recipe_serializer`, `minecraft:command_argument_type`): the host
    // writes no id of those for a CC entry, so they are not named.
    expect(CcRegistries.synchronised.keys, isNotEmpty);
    for (final key in CcRegistries.synchronised.keys) {
      expect(CcRegistries.declaredRegistryKeys, contains(key), reason: key);
    }
    expect(CcRegistries.declaredRegistryKeys, isNot(contains('minecraft:recipe_serializer')));
    expect(CcRegistries.declaredRegistryKeys, isNot(contains('minecraft:command_argument_type')));
  });

  test('every registration site is declared', () {
    final source = _librarySource();
    for (final entry in _registrationSites.entries) {
      if (!entry.value.any(source.contains)) continue;
      expect(
        CcRegistries.declaredRegistryKeys,
        contains(entry.key),
        reason: 'lib/ registers into ${entry.key} (${entry.value.join(' / ')}), '
            'so the declaration has to name it',
      );
    }
  });

  test('the declaration names nothing the client would not have', () {
    // The host-numbered keys all exist on a NeoForge client; a key no mod registers
    // makes it refuse the whole sync ("Tried to applied snapshot with registry name
    // ... but was not found").
    for (final key in CcRegistries.declaredRegistryKeys) {
      expect(
        key == 'computercraft:recipe_function' || key.startsWith('minecraft:'),
        isTrue,
        reason: key,
      );
    }
  });
}