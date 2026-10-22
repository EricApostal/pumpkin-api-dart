// A registry Create registers content into must be named in the NeoForge
// declaration (`lib/src/plugin/create_neoforge.dart`, `contentRegistries`).
//
// Why: the host numbers a plugin's entries in a registry it numbers itself
// (`vanilla count + registration index`) and writes those ids in chunk data and
// packets. A client that was not sent the registry's snapshot resolves each id
// against its *own* order — a different block or item, with no error anywhere
// (the "adding an item to my inventory gives a different item" divergence). And a
// host-numbered registry is sent whole or not at all: `syncable`
// (`crates/pumpkin-core/src/net/neoforge/registries.rs`) drops it as soon as one
// plugin registered an entry nobody vouched for, for *every* plugin.
//
// `contentRegistries` returns declaration types from `pumpkin_api`, which is
// wasm-only (`bindings.g.dart` uses `dart:wasm`), so this test reads the source the
// way the addon tests read their tables: every call in `lib/src` that registers an
// entry in a host-numbered registry must have its key in `contentRegistries`.
import 'dart:io';

import 'package:test/test.dart';

/// The registration call in `lib/src` and the registry key the declaration has to
/// name for it (the host's `HOST_NUMBERED`, plus the two registries `applyRegistry`
/// fills outside the `RegistryKind` buckets).
const Map<String, List<String>> _registrationSites = {
  'ItemRegistries.host.register(': ['minecraft:item'],
  'BlockRegistries.host.register(': ['minecraft:block'],
  'BlockEntityRegistries.host.register(': ['minecraft:block_entity_type'],
  'MenuRegistries.host.register(': ['minecraft:menu'],
  'ComponentTypeRegistries.host.register(': ['minecraft:data_component_type'],
  'FluidRegistries.register(': ['minecraft:fluid'],
  // Not `EntityRegistries.registerTag(`, which registers a tag and no entry.
  'EntityRegistries.register(e.': ['minecraft:entity_type'],
  'EntityRegistries.registerDataSerializer(': ['neoforge:entity_data_serializers'],
  'ExtraRegistries.registerSound(': ['minecraft:sound_event'],
  'ExtraRegistries.registerParticle(': ['minecraft:particle_type'],
  'ExtraRegistries.registerMobEffect(': ['minecraft:mob_effect'],
  'ExtraRegistries.registerMapDecoration(': ['minecraft:map_decoration_type'],
  // The recipe types go over `neoforge:recipe_content`, but the two registries they
  // add entries to are gated like every other one.
  'declareSyncedRecipeTypes(': ['minecraft:recipe_type', 'minecraft:recipe_serializer'],
};

/// `damageType` is a datapack registry: its entries travel with the registry data,
/// not with the frozen-registry snapshot.
const List<String> _notFrozenRegistry = ['DamageTypeRegistries.register('];

const String _declaration = 'lib/src/plugin/create_neoforge.dart';

String _read(String path) => File(path).readAsStringSync();

String _librarySource() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
  return [for (final f in files) f.readAsStringSync()].join('\n');
}

void main() {
  final declaration = _read(_declaration);
  final library = _librarySource();

  test('every registration in lib/src has its registry in contentRegistries', () {
    var checked = 0;
    for (final entry in _registrationSites.entries) {
      if (!library.contains(entry.key)) continue;
      checked++;
      for (final key in entry.value) {
        expect(
          declaration,
          contains("add('$key',"),
          reason: 'lib/src registers into $key (${entry.key}), so contentRegistries '
              'must name it: the host drops a host-numbered registry no declaration '
              'vouches for, for every plugin',
        );
      }
    }
    // The markers must keep matching the code they describe; a rename would
    // otherwise turn this into a test that checks nothing.
    expect(checked, greaterThanOrEqualTo(12), reason: 'markers found in lib/src');
    for (final marker in _registrationSites.keys) {
      expect(library, contains(marker), reason: 'marker `$marker` is stale');
    }
  });

  test('the datapack-only registries are not declared', () {
    // A damage type travels with the registry data (the declaration's datapack
    // entries), so naming `minecraft:damage_type` would ask for a snapshot of a
    // registry the host does not number that way.
    expect(library, contains(_notFrozenRegistry.single));
    expect(declaration, isNot(contains("add('minecraft:damage_type'")));
  });

  test('the two registries outside the RegistryKind buckets are declared', () {
    // `applyRegistry` registers the map decoration and the entity data serializers
    // (`registry.mapDecorations`, `registry.entityDataSerializers`) and the host
    // writes no id for either before the declaration names it.
    expect(library, contains('registry.mapDecorations'));
    expect(library, contains('registry.entityDataSerializers'));
    expect(declaration, contains("add('minecraft:map_decoration_type', registry.mapDecorations.length)"));
    expect(
      declaration,
      contains("add('neoforge:entity_data_serializers', registry.entityDataSerializers.length)"),
    );
  });
}