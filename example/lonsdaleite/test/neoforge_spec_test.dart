import 'package:lonsdaleite/src/manifest.dart';
import 'package:lonsdaleite/src/manifest.g.dart';
import 'package:lonsdaleite/src/neoforge_spec.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart'
    show RegisteredBlock, RegisteredItem;
import 'package:pumpkin_neoforge/lonsdaleite.dart' show lonsdaleiteSpec;
import 'package:pumpkin_neoforge/pumpkin_neoforge_core.dart';
import 'package:test/test.dart';

void main() {
  final manifest = Manifest.parse(lonsdaleiteManifestJson);
  final ordered = manifest.items.toList()
    ..sort((a, b) => a.registrationIndex.compareTo(b.registrationIndex));
  final items = [
    for (var i = 0; i < ordered.length; i++)
      RegisteredItem(ordered[i].id, 1658 + i),
  ];
  final wardframe = RegisteredBlock(
    key: manifest.block.id,
    id: 1286,
    baseStateId: vanillaBlockStateCount,
    stateCount: manifest.block.stateCount,
    itemId: 1658,
  );
  final spec = neoForgeSpecFor(manifest, items, blocks: [wardframe]);

  test(
    'the spec built from the manifest equals the library spec for Lonsdaleite',
    () {
      final library = lonsdaleiteSpec();
      expect(spec.registryKeys, library.registryKeys);
      for (final key in spec.registryKeys) {
        final a = spec.registries.firstWhere((r) => r.key == key).entries;
        final b = library.registries.firstWhere((r) => r.key == key).entries;
        expect(a, b, reason: key);
      }
      expect(spec.mods.single.id, library.mods.single.id);
      expect(spec.mods.single.version, library.mods.single.version);
      expect(spec.mods.single.displayName, library.mods.single.displayName);
    },
  );

  test(
    'item ids: 1658 vanilla entries, then the 32 items in registration order',
    () {
      final item = spec.registries.firstWhere((r) => r.key == 'minecraft:item');
      expect(item.length, 1658 + 32);
      expect(item.entries[1658], 'lonsdaleite:lonsdaleite_wardframe');
      expect(item.entries[1658 + 31], 'lonsdaleite:perfect_lonsdaleite_boots');
    },
  );

  test('the block registry lists the wardframe after all vanilla blocks', () {
    final block = spec.registries.firstWhere((r) => r.key == 'minecraft:block');
    final vanillaBlocks = VanillaRegistries.require('minecraft:block').length;
    expect(block.length, vanillaBlocks + 1);
    expect(block.entries.last, 'lonsdaleite:lonsdaleite_wardframe');
    expect(block.entries[1286], 'lonsdaleite:lonsdaleite_wardframe');
  });

  test('the wardframe states follow the vanilla states: 35723, 64 of them', () {
    expect(vanillaBlockStateCount, 35723);
    expect(wardframe.baseStateId, 35723);
    expect(wardframe.stateCount, 64);
    expect(wardframe.baseStateId + wardframe.stateCount, 35787);
  });

  test('the default negotiation is adhoc and vanilla clients are refused', () {
    const options = NeoForgeServerOptions();
    expect(options.negotiation, NeoForgeNegotiation.adhoc);
    expect(options.nonNeoForge, NonNeoForgePolicy.reject);
  });
}
