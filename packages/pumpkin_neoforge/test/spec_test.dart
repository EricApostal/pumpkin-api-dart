// The registry specs, the generated vanilla data and the Lonsdaleite preset.
import 'dart:convert';
import 'dart:io';

import 'package:pumpkin_neoforge/lonsdaleite.dart';
import 'package:pumpkin_neoforge/pumpkin_neoforge_core.dart';
import 'package:test/test.dart';

void main() {
  group('generated vanilla registries', () {
    test('sizes match Pumpkin 26.3 assets', () {
      expect(VanillaRegistries.require('minecraft:item'), hasLength(1658));
      expect(VanillaRegistries.require('minecraft:block'), hasLength(1286));
      expect(
        VanillaRegistries.require('minecraft:entity_type'),
        hasLength(161),
      );
      expect(vanillaMinecraftVersion, '26.3');
      expect(vanillaBlockStateCount, 35723);
    });

    test(
      'ids are the indexes and the usual suspects are where they belong',
      () {
        final items = VanillaRegistries.require('minecraft:item');
        expect(items[0], 'minecraft:air');
        expect(items[1], 'minecraft:stone');
        final blocks = VanillaRegistries.require('minecraft:block');
        expect(blocks[0], 'minecraft:air');
        expect(blocks[1], 'minecraft:stone');
        expect(VanillaRegistries.require('minecraft:fluid'), [
          'minecraft:empty',
          'minecraft:flowing_water',
          'minecraft:water',
          'minecraft:flowing_lava',
          'minecraft:lava',
        ]);
      },
    );

    test('every list is valid: identifiers, no duplicates', () {
      for (final key in VanillaRegistries.keys) {
        final list = VanillaRegistries.require(key);
        expect(
          list.toSet(),
          hasLength(list.length),
          reason: '$key has duplicates',
        );
        for (final name in list) {
          expect(isValidIdentifier(name), isTrue, reason: '$key: $name');
          expect(name, startsWith('minecraft:'));
        }
      }
    });

    test('the JSON copy for the test client matches the Dart data', () {
      final json = jsonDecode(
        File('data/vanilla_registries.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final registries = (json['registries'] as Map<String, dynamic>)
          .cast<String, List<dynamic>>();
      expect(registries.keys.toSet(), VanillaRegistries.keys.toSet());
      for (final entry in registries.entries) {
        expect(
          entry.value,
          VanillaRegistries.require(entry.key),
          reason: entry.key,
        );
      }
    });

    test('unknown registries have no list', () {
      expect(VanillaRegistries.entries('minecraft:nope'), isNull);
      expect(
        () => VanillaRegistries.require('minecraft:nope'),
        throwsStateError,
      );
    });
  });

  group('RegistrySpec', () {
    test('rejects duplicates and invalid names', () {
      expect(() => RegistrySpec('a:r', ['a:x', 'a:x']), throwsArgumentError);
      expect(() => RegistrySpec('a:r', ['A:x']), throwsFormatException);
      expect(() => RegistrySpec('Bad', []), throwsFormatException);
    });

    test('vanillaPlus appends and requires a vanilla list', () {
      final item = RegistrySpec.vanillaPlus('minecraft:item', ['a:x']);
      expect(item.length, 1659);
      expect(item.entries.last, 'a:x');
      expect(
        () => RegistrySpec.vanillaPlus('minecraft:recipe_serializer', ['a:x']),
        throwsStateError,
      );
    });

    test('a mod entry that duplicates a vanilla one is refused', () {
      expect(
        () => RegistrySpec.vanillaPlus('minecraft:item', ['minecraft:stone']),
        throwsArgumentError,
      );
    });
  });

  group('NeoForgeServerSpec', () {
    test('rejects duplicate registries and channels', () {
      final r = RegistrySpec('a:r', ['a:x']);
      expect(() => NeoForgeServerSpec(registries: [r, r]), throwsArgumentError);
      final c = PayloadChannelSpec(id: 'a:c', version: '1');
      expect(() => NeoForgeServerSpec(channels: [c, c]), throwsArgumentError);
    });

    test('payload channels only exist in configuration and play', () {
      expect(
        () => PayloadChannelSpec(
          id: 'a:c',
          version: '1',
          phases: {NetworkPhase.login},
        ),
        throwsArgumentError,
      );
    });

    test('allChannels = NeoForge own + the mod channels', () {
      final spec = NeoForgeServerSpec(
        channels: [
          PayloadChannelSpec(
            id: 'a:c',
            version: '1',
            phases: {NetworkPhase.configuration},
            flow: PacketFlow.serverbound,
          ),
        ],
      );
      final config = spec.allChannels[NetworkPhase.configuration]!;
      expect(config.map((c) => c.id), contains('neoforge:frozen_registry'));
      expect(config.map((c) => c.id), contains('a:c'));
      expect(
        spec.allChannels[NetworkPhase.play]!.map((c) => c.id),
        isNot(contains('a:c')),
      );
      expect(spec.configurationChannelsToServer, ['a:c']);
    });

    test('NeoForge own registrations are all optional version 1', () {
      for (final list in neoForgeOwnRegistrations.values) {
        for (final c in list) {
          expect(c.optional, isTrue, reason: c.id);
          expect(c.version, '1', reason: c.id);
          expect(c.id, startsWith('neoforge:'));
        }
      }
      // what a client announces it can receive == own configuration
      // registrations flowing to the client, plus the builtins
      final receivable = [
        for (final c in neoForgeOwnRegistrations[NetworkPhase.configuration]!)
          if (c.flow != PacketFlow.serverbound) c.id,
      ];
      expect(NeoForgeChannels.clientConfigurationListening.toSet(), {
        ...NeoForgeChannels.builtin,
        ...receivable,
      });
      final sendable = [
        for (final c in neoForgeOwnRegistrations[NetworkPhase.configuration]!)
          if (c.flow != PacketFlow.clientbound) c.id,
      ];
      expect(NeoForgeChannels.serverConfigurationListening.toSet(), {
        ...NeoForgeChannels.builtin,
        ...sendable,
      });
    });
  });

  group('Lonsdaleite preset', () {
    test('32 items, one block, one tab', () {
      expect(lonsdaleiteItems, hasLength(32));
      expect(lonsdaleiteBlocks, ['lonsdaleite_wardframe']);
      expect(lonsdaleiteItems.first, 'lonsdaleite_wardframe');
      expect(lonsdaleiteCreativeTabs, ['lonsdaleite']);
    });

    test('the spec appends the entries after the vanilla ones', () {
      final spec = lonsdaleiteSpec();
      final item = spec.registries.firstWhere((r) => r.key == 'minecraft:item');
      expect(item.length, 1658 + 32);
      expect(item.entries[1658], 'lonsdaleite:lonsdaleite_wardframe');
      final block = spec.registries.firstWhere(
        (r) => r.key == 'minecraft:block',
      );
      expect(block.entries.last, 'lonsdaleite:lonsdaleite_wardframe');
      expect(spec.registryKeys, ['minecraft:block', 'minecraft:item']);
    });

    test('the wardframe is block 1286 and its 64 states start at 35723', () {
      final blocks = VanillaRegistries.require('minecraft:block');
      expect(blocks, hasLength(1286));
      expect(lonsdaleiteFirstStateId(0), 35723);
      expect(lonsdaleiteBlockStateCounts['lonsdaleite_wardframe'], 64);
      expect(lonsdaleiteWardframeStateProperties, ['down', 'east', 'north', 'south', 'up', 'west']);
      final spec = lonsdaleiteSpec();
      final block = spec.registries.firstWhere((r) => r.key == 'minecraft:block');
      expect(block.entries[1286], 'lonsdaleite:lonsdaleite_wardframe');
    });

    test('the vanilla state count is the sum of the states in blocks.json', () {
      final json = jsonDecode(
        File('data/vanilla_registries.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(json['block_state_count'], vanillaBlockStateCount);
    });

    test('the Python client mod file lists the same entries', () {
      final json = jsonDecode(
        File('../../example/modbridge/testclient/mods/lonsdaleite.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      final registries = json['registries'] as Map<String, dynamic>;
      expect(registries['minecraft:item'], [
        for (final n in lonsdaleiteItems) 'lonsdaleite:$n',
      ]);
      expect(registries['minecraft:block'], [
        for (final n in lonsdaleiteBlocks) 'lonsdaleite:$n',
      ]);
    });
  });

  group('identifiers', () {
    test('normalise and validate', () {
      expect(normalizeIdentifier('stone'), 'minecraft:stone');
      expect(normalizeIdentifier(':stone'), 'minecraft:stone');
      expect(normalizeIdentifier('a:b/c.d-e_f'), 'a:b/c.d-e_f');
      for (final bad in ['A:b', 'a:B', 'a:', '', 'a b:c', 'a:b:c']) {
        expect(isValidIdentifier(bad), isFalse, reason: bad);
      }
      expect(namespaceOf('a:b'), 'a');
      expect(pathOf('a:b/c'), 'b/c');
    });
  });
}
