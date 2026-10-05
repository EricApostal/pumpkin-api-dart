import 'dart:convert';
import 'dart:io';

import 'package:lonsdaleite/src/component_codec.dart';
import 'package:lonsdaleite/src/manifest.dart';
import 'package:lonsdaleite/src/manifest.g.dart';
import 'package:lonsdaleite/src/registrar.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:test/test.dart';

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final manifest = Manifest.parse(lonsdaleiteManifestJson);

  // Written by tool/golden_components.py, an encoder made from Pumpkin's Rust
  // readers independently of the Dart codec; regenerate it with that script.
  final golden = (jsonDecode(
    File('test/fixtures/component_bytes.json').readAsStringSync(),
  ) as Map).cast<String, Map<String, Object?>>();

  test('every item encodes to the bytes of the independent encoder', () {
    for (final item in manifest.items) {
      final encoded = encodeItem(ItemDefinition.fromManifest(item));
      final actual = {
        for (final c in encoded.registration.components) c.name: hex(c.bytes),
      };
      expect(actual, golden[item.id], reason: item.id);
    }
  });

  test('the golden file covers all 32 items', () {
    expect(golden.keys.toSet(), manifest.items.map((i) => i.id).toSet());
  });

  test('exactly block_transformer and interact_animation are skipped', () {
    final log = SkippedComponentsLog();
    for (final item in manifest.items) {
      log.add(item.id, encodeItem(ItemDefinition.fromManifest(item)).skipped);
    }
    expect(log.components, [
      'minecraft:block_transformer',
      'minecraft:interact_animation',
    ]);
    // The six axes, hoes and shovels carry a block transformer.
    expect(log.itemsOf('minecraft:block_transformer'), hasLength(6));
    expect(
      log.itemsOf('minecraft:block_transformer'),
      containsAll([
        'lonsdaleite:lonsdaleite_axe',
        'lonsdaleite:perfect_lonsdaleite_hoe',
        'lonsdaleite:lonsdaleite_shovel',
      ]),
    );
    expect(log.itemsOf('minecraft:interact_animation'), hasLength(32));
    expect(
      log.reasonOf('minecraft:block_transformer'),
      contains('static item tags'),
    );
  });

  test(
    'every component of the manifest is encoded or skipped, none is unknown',
    () {
      final names = <String>{
        for (final item in manifest.items) ...item.serverView.raw.keys,
      };
      for (final name in names) {
        expect(
          DataComponentCodec.supported.contains(name) ||
              DataComponentCodec.notReadByHost.containsKey(name),
          isTrue,
          reason: name,
        );
      }
      expect(names, hasLength(26));
    },
  );

  test('component names map onto the WIT data-component enum', () {
    // The generated enum lists the components in the order of
    // vanilla's registry; wire names are the kebab-case names.
    expect(
      DataComponentCodec.wireNameOf('minecraft:kinetic_weapon'),
      'kinetic-weapon',
    );
    expect(
      DataComponentCodec.wireNameOf('minecraft:attribute_modifiers'),
      'attribute-modifiers',
    );
  });

  test('an invalid component names the item', () {
    final item = ItemDefinition(
      id: 'lonsdaleite:broken',
      maxStackSize: 1,
      components: {'minecraft:rarity': 'mythic'},
      block: null,
    );
    expect(
      () => encodeItem(item),
      throwsA(
        isA<ComponentEncodeException>().having(
          (e) => e.message,
          'message',
          allOf(contains('lonsdaleite:broken'), contains('mythic')),
        ),
      ),
    );
  });

  test('the omnitool registers its server tool rules, not the mod ones', () {
    final omnitool = manifest.item('lonsdaleite:lonsdaleite_omnitool')!;
    final encoded = encodeItem(ItemDefinition.fromManifest(omnitool));
    final tool = encoded.registration.components.firstWhere(
      (c) => c.name == 'minecraft:tool',
    );
    final pickaxe = encodeItem(
      ItemDefinition.fromManifest(
        manifest.item('lonsdaleite:lonsdaleite_pickaxe')!,
      ),
    ).registration.components.firstWhere((c) => c.name == 'minecraft:tool');
    // 6 rules (pickaxe: 2): the server's extra speed-only rules for the
    // axe, shovel, hoe and sword tags.
    expect(tool.bytes.first, 6);
    expect(pickaxe.bytes.first, 2);
  });
}
