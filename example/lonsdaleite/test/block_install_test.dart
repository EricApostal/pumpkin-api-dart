import 'package:lonsdaleite/src/block_definition.dart';
import 'package:lonsdaleite/src/block_install.dart';
import 'package:lonsdaleite/src/component_codec.dart';
import 'package:lonsdaleite/src/item_install.dart';
import 'package:lonsdaleite/src/manifest.dart';
import 'package:lonsdaleite/src/manifest.g.dart';
import 'package:lonsdaleite/src/neoforge_spec.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:pumpkin_neoforge/lonsdaleite.dart' show lonsdaleiteSpec;
import 'package:pumpkin_neoforge/pumpkin_neoforge_core.dart'
    show VanillaRegistries, vanillaBlockStateCount;
import 'package:test/test.dart';

/// A host that behaves like Pumpkin's `DynamicBlockRegistry` (ids from the
/// vanilla counts in registration order, states appended, `get-state-id`
/// computed by changing one property at a time from the default state) and
/// records the calls.
final class _FakeHost implements BlockRegistryBackend {
  @override
  int vanillaBlockCount = 1286;
  @override
  int vanillaStateCount = 35723;

  /// Blocks registered by someone else before the plugin.
  final List<BlockDefinition> definitions = [];
  final links = <String, String>{};
  final tags = <String, List<String>>{};
  final calls = <String>[];
  final customItems = <String, int>{};

  /// Registration is closed: new things fail like the host's message says.
  bool closed = false;
  bool permissionMissing = false;

  /// Skews the state ids `get-state-id` reports.
  int Function(int stateIndex)? stateSkew;

  _FakeHost();

  @override
  int register(BlockDefinition block) {
    calls.add('register-block ${block.key}');
    if (permissionMissing) {
      throw const BlockRegistryException(
        "Registering lonsdaleite:lonsdaleite_wardframe failed: registering blocks needs the 'registry.blocks' permission",
      );
    }
    block.check();
    final existing = definitions.indexWhere((d) => d.key == block.key);
    if (existing >= 0) return vanillaBlockCount + existing;
    if (closed) {
      throw BlockRegistryException(
        'Registering ${block.key} failed: blocks can only be registered before players connect',
      );
    }
    definitions.add(block);
    return vanillaBlockCount + definitions.length - 1;
  }

  @override
  void registerTag(String tag, List<String> entries) {
    calls.add('register-block-tag $tag');
    tags.putIfAbsent(tag, () => []).addAll(entries);
  }

  @override
  void setBlockItem(String itemKey, String blockKey) {
    calls.add('set-block-item $itemKey $blockKey');
    if (!customItems.containsKey(itemKey)) {
      throw BlockRegistryException(
        'Linking the item $itemKey failed: unknown item',
      );
    }
    links[blockKey] = itemKey;
  }

  @override
  int? idOf(String key) {
    final i = definitions.indexWhere((d) => d.key == key);
    return i < 0 ? null : vanillaBlockCount + i;
  }

  @override
  String? keyOf(int id) => null;

  @override
  List<RegisteredBlock> get registeredBlocks {
    final entries = BlockRegistryChecks.expectedEntries(
      definitions,
      vanillaBlockCount: vanillaBlockCount,
      vanillaStateCount: vanillaStateCount,
    );
    return [
      for (final e in entries)
        RegisteredBlock(
          key: e.key,
          id: e.id,
          baseStateId: e.baseStateId,
          stateCount: e.stateCount,
          itemId: links.containsKey(e.key) ? customItems[links[e.key]] : null,
        ),
    ];
  }

  @override
  int? stateId(String block, Map<String, String> properties) {
    final i = definitions.indexWhere((d) => d.key == block);
    if (i < 0) return null;
    final d = definitions[i];
    final sorted = [...d.properties]..sort((a, b) => a.name.compareTo(b.name));
    var stride = 1;
    final strides = <String, int>{};
    for (final p in sorted.reversed) {
      strides[p.name] = stride;
      stride *= p.valueCount;
    }
    int idx(BlockProperty p, String? v) => p.valueIndex(v ?? p.values.first)!;
    var index = 0;
    for (final p in sorted) {
      index += idx(p, d.defaultState[p.name]) * strides[p.name]!;
    }
    for (final e in properties.entries) {
      final p = sorted.where((p) => p.name == e.key).firstOrNull;
      final next = p?.valueIndex(e.value);
      if (p == null || next == null) return null;
      index += (next - idx(p, d.defaultState[p.name])) * strides[p.name]!;
    }
    return registeredBlocks[i].baseStateId +
        index +
        (stateSkew?.call(index) ?? 0);
  }
}

void main() {
  final manifest = Manifest.parse(lonsdaleiteManifestJson);
  final ordered = manifest.items.toList()
    ..sort((a, b) => a.registrationIndex.compareTo(b.registrationIndex));
  final items = [
    for (var i = 0; i < ordered.length; i++)
      RegisteredItem(ordered[i].id, 1658 + i),
  ];
  ItemInstallation itemInstallation([List<RegisteredItem>? list]) =>
      ItemInstallation(
        items: list ?? items,
        vanillaCount: 1658,
        itemTags: const [],
        skippedComponents: SkippedComponentsLog(),
      );
  final vanillaBlocks = VanillaRegistries.require('minecraft:block').length;

  _FakeHost host() =>
      _FakeHost()..customItems['lonsdaleite:lonsdaleite_wardframe'] = 1658;

  BlockInstallation install(_FakeHost h, {ItemInstallation? itemsDone}) =>
      installManifestBlock(
        manifest,
        h,
        items: itemsDone ?? itemInstallation(),
        expectedVanillaBlocks: vanillaBlocks,
        expectedVanillaStates: vanillaBlockStateCount,
      );

  group('the definition from the manifest', () {
    final d = blockDefinitionFor(manifest);

    test('properties of the mod\'s BlockBehaviour.Properties', () {
      expect(d.key, 'lonsdaleite:lonsdaleite_wardframe');
      expect(d.hardness, 5.0);
      expect(d.blastResistance, 1200.0);
      expect(d.requiresCorrectTool, isTrue);
      expect(d.soundType, 'amethyst');
      expect(d.luminance, 7);
      expect(d.canOcclude, isFalse);
      expect(d.suffocating, isFalse);
      expect(d.replaceable, isFalse);
      expect(d.collisionShape, isA<FullCubeShape>());
      expect(d.selectionShape, isA<FullCubeShape>());
      expect(d.drops, isA<DropsSelfItem>());
      expect(d.validate(), isEmpty);
    });

    test('six boolean properties that start false, one same-block rule per direction', () {
      expect(d.properties.map((p) => p.name), [
        'north',
        'south',
        'east',
        'west',
        'up',
        'down',
      ]);
      expect(d.properties.every((p) => p.isBoolean), isTrue);
      expect(d.defaultState, {
        for (final n in ['north', 'south', 'east', 'west', 'up', 'down'])
          n: 'false',
      });
      expect(d.connectRules, hasLength(6));
      for (final rule in d.connectRules) {
        expect(
          rule.direction.name,
          rule.property,
          reason: 'property name = direction',
        );
        expect(rule.target, isA<ConnectSameBlock>());
      }
      expect(
        d.connectRules.map((r) => r.direction).toSet(),
        ConnectDirection.values.toSet(),
      );
    });

    test('the tags go through register-block-tag, not the definition', () {
      expect(d.tags, isEmpty);
    });

    test('the state numbering equals the mod\'s block_state table', () {
      expect(blockStateIssues(manifest), isEmpty);
      expect(d.layout.stateCount, 64);
      expect(d.layout.defaultStateIndex, 63);
      expect(d.layout.propertyNames, manifest.block.stateOrder);
    });

    test('a manifest whose state table differs is reported', () {
      final tampered = Manifest.parse(
        lonsdaleiteManifestJson.replaceFirst(
          '"default_state_index":63',
          '"default_state_index":0',
        ),
      );
      expect(blockStateIssues(tampered).single, contains('default state'));
    });
  });

  group('installManifestBlock', () {
    test('registers the block after the items with the computed ids', () {
      final h = host();
      final result = install(h);
      expect(result.block.key, 'lonsdaleite:lonsdaleite_wardframe');
      expect(result.block.id, 1286);
      expect(result.vanillaBlockCount, 1286);
      expect(result.vanillaStateCount, 35723);
      expect(result.block.baseStateId, 35723);
      expect(result.block.stateCount, 64);
      expect(result.block.itemId, 1658);
      expect(result.defaultStateId, 35723 + 63);
      expect(result.stateId({'east': 'true', 'up': 'true'}), 35723 + 45);
      expect(h.stateId('lonsdaleite:lonsdaleite_wardframe', const {}), 35786);
    });

    test('the calls: register-block, set-block-item, then the block tags', () {
      final h = host();
      install(h);
      expect(h.calls, [
        'register-block lonsdaleite:lonsdaleite_wardframe',
        'set-block-item lonsdaleite:lonsdaleite_wardframe lonsdaleite:lonsdaleite_wardframe',
        'register-block-tag minecraft:mineable/pickaxe',
        'register-block-tag minecraft:needs_diamond_tool',
      ]);
      expect(h.tags, {
        'minecraft:mineable/pickaxe': ['lonsdaleite:lonsdaleite_wardframe'],
        'minecraft:needs_diamond_tool': ['lonsdaleite:lonsdaleite_wardframe'],
      });
    });

    test('registering again (a reloaded plugin) gives the same ids', () {
      final h = host();
      final first = install(h);
      h.closed = true;
      final second = install(h);
      expect(second.block, first.block);
    });

    test('the block item has to be registered first', () {
      expect(
        () => install(host(), itemsDone: itemInstallation(items.sublist(1))),
        throwsA(
          isA<BlockRegistryException>().having(
            (e) => e.message,
            'm',
            contains('Register the items first'),
          ),
        ),
      );
    });

    test('registers nothing when the host has other vanilla counts', () {
      final h = host()..vanillaBlockCount = 1200;
      expect(
        () => install(h),
        throwsA(
          isA<BlockRegistryException>().having(
            (e) => e.message,
            'm',
            allOf(contains('1200 vanilla blocks'), contains('for 1286')),
          ),
        ),
      );
      expect(h.calls, isEmpty);
      final s = host()..vanillaStateCount = 35000;
      expect(
        () => install(s),
        throwsA(
          isA<BlockRegistryException>().having(
            (e) => e.message,
            'm',
            allOf(contains('35000 vanilla block states'), contains('35723')),
          ),
        ),
      );
      expect(s.calls, isEmpty);
    });

    test('fails when another plugin registered a block first', () {
      final h = host();
      h.register(
        const BlockDefinition(
          key: 'other:block',
          hardness: 1,
          blastResistance: 1,
        ),
      );
      h.calls.clear();
      expect(
        () => install(h),
        throwsA(
          isA<BlockRegistryException>().having(
            (e) => e.message,
            'm',
            allOf(contains('Another plugin'), contains('other:block')),
          ),
        ),
      );
    });

    test('fails loudly when the host numbers the states differently', () {
      final h = host()..stateSkew = (i) => i == 45 ? 1 : 0;
      expect(
        () => install(h),
        throwsA(
          isA<BlockRegistryException>().having(
            (e) => e.message,
            'm',
            allOf(contains('east=true'), contains('disagree')),
          ),
        ),
      );
    });

    test('a failing registration carries the host\'s message', () {
      final denied = host()..permissionMissing = true;
      expect(
        () => install(denied),
        throwsA(
          isA<BlockRegistryException>().having(
            (e) => e.message,
            'm',
            contains("'registry.blocks' permission"),
          ),
        ),
      );
      final closed = host()..closed = true;
      expect(
        () => install(closed),
        throwsA(
          isA<BlockRegistryException>().having(
            (e) => e.message,
            'm',
            contains('before players connect'),
          ),
        ),
      );
    });

    test('a block tag with replace: true is refused', () {
      final tampered = Manifest.parse(
        lonsdaleiteManifestJson.replaceFirst(
          '"minecraft:mineable/pickaxe":{"replace":false',
          '"minecraft:mineable/pickaxe":{"replace":true',
        ),
      );
      expect(
        () => installManifestBlock(
          tampered,
          host(),
          items: itemInstallation(),
          expectedVanillaBlocks: vanillaBlocks,
          expectedVanillaStates: vanillaBlockStateCount,
        ),
        throwsA(
          isA<BlockRegistryException>().having(
            (e) => e.message,
            'm',
            contains('replace'),
          ),
        ),
      );
    });
  });

  group('the NeoForge spec', () {
    test('the block registry gets the wardframe at 1286, its states start at 35723', () {
      final result = install(host());
      final spec = neoForgeSpecFor(manifest, items, blocks: [result.block]);
      final block = spec.registries.firstWhere(
        (r) => r.key == 'minecraft:block',
      );
      expect(block.length, vanillaBlocks + 1);
      expect(
        block.entries[result.block.id],
        'lonsdaleite:lonsdaleite_wardframe',
      );
      expect(result.block.baseStateId, vanillaBlockStateCount);
    });

    test('equals the library spec of the preset', () {
      final result = install(host());
      final spec = neoForgeSpecFor(manifest, items, blocks: [result.block]);
      final library = lonsdaleiteSpec();
      for (final key in library.registryKeys) {
        expect(
          spec.registries.firstWhere((r) => r.key == key).entries,
          library.registries.firstWhere((r) => r.key == key).entries,
        );
      }
    });

    test('a block with another id or other first state is refused', () {
      final good = install(host()).block;
      expect(
        () => neoForgeSpecFor(
          manifest,
          items,
          blocks: [
            RegisteredBlock(
              key: good.key,
              id: good.id + 1,
              baseStateId: good.baseStateId,
              stateCount: 64,
            ),
          ],
        ),
        throwsA(
          isA<BlockRegistryException>().having(
            (e) => e.message,
            'm',
            contains('block id 1287'),
          ),
        ),
      );
      expect(
        () => neoForgeSpecFor(
          manifest,
          items,
          blocks: [
            RegisteredBlock(
              key: good.key,
              id: good.id,
              baseStateId: good.baseStateId + 1,
              stateCount: 64,
            ),
          ],
        ),
        throwsA(
          isA<BlockRegistryException>().having(
            (e) => e.message,
            'm',
            contains('start at id 35724'),
          ),
        ),
      );
    });
  });
}
