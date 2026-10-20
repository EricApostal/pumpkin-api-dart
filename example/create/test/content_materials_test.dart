import 'package:create/src/content/material_content.dart';
import 'package:create/src/decoration/roles.dart';
import 'package:create/src/manifest/manifest.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:test/test.dart';

void main() {
  final blocks = {for (final b in kBlocks) b.key: b};
  final items = {for (final i in kItems) i.key: i};

  test('the material blocks are manifest blocks owned by no other module', () {
    expect(materialBlockKeys.toSet().length, materialBlockKeys.length);
    for (final key in materialBlockKeys) {
      final m = blocks[key];
      expect(m, isNotNull, reason: key);
      // The decoration palettes are the other module that registers manifest blocks by class.
      expect(ownsBlock(m!), isFalse, reason: '$key is a decoration block');
      expect(m.blockItem, isNotNull, reason: '$key needs a block item');
    }
  });

  test('the material items are non-block manifest items', () {
    expect(materialItemKeys.length, materialItemKeys.toSet().length);
    for (final key in materialItemKeys) {
      final m = items[key];
      expect(m, isNotNull, reason: key);
      expect(m!.isBlockItem, isFalse, reason: '$key is a block item');
    }
  });

  test('every material item is registered once, in manifest order', () {
    final registrations = createMaterialItems();
    expect(registrations.map((r) => r.key), [
      for (final i in kItems)
        if (materialItemKeys.contains(i.key)) 'create:${i.key}',
    ]);
    expect(registrations.length, materialItemKeys.length);
    expect(
      registrations.map((r) => r.key).toSet().length,
      materialItemKeys.length,
    );
  });

  test('the registrations carry the manifest stack size and rarity', () {
    for (final r in createMaterialItems()) {
      final m = items[r.key.substring('create:'.length)]!;
      expect(r.maxStackSize, m.maxStack, reason: r.key);
      final rarity = r.components
          .where((c) => c.name == 'minecraft:rarity')
          .toList();
      if (m.rarity == 'COMMON') {
        expect(rarity, isEmpty, reason: r.key);
      } else {
        expect(rarity, hasLength(1), reason: r.key);
      }
    }
  });

  test(
    'the food items are edible and only they are',
    () {
      final food = [
        for (final k in materialItemKeys)
          if (items[k]!.food) k,
      ];
      expect(food.toSet(), {
        'bar_of_chocolate',
        'sweet_roll',
        'chocolate_glazed_berries',
        'honeyed_apple',
      });
      // `Item.Properties#food` sets `minecraft:food` and `minecraft:consumable`; without them the
      // host never lets the item be eaten (`prepare_hand_item_for_use` in `use_item.rs`).
      const nutrition = {
        'bar_of_chocolate': (6, 0.3), // AllItems.java:138
        'sweet_roll': (6, 0.8), // AllItems.java:146
        'chocolate_glazed_berries': (7, 0.8), // AllItems.java:153
        'honeyed_apple': (8, 0.8), // AllItems.java:160
      };
      for (final r in createMaterialItems()) {
        final byName = {for (final c in r.components) c.name: c.bytes};
        final expected = nutrition[r.key.replaceFirst('create:', '')];
        if (expected == null) {
          expect(byName, isNot(contains('minecraft:food')), reason: r.key);
          expect(byName, isNot(contains('minecraft:consumable')), reason: r.key);
          continue;
        }
        final f = PacketReader(byName['minecraft:food']!);
        expect(f.readVarInt(), expected.$1, reason: r.key);
        expect(f.readFloat(), closeTo(expected.$2, 1e-6), reason: r.key);
        expect(f.readBool(), isFalse, reason: '${r.key} is not always edible');
        f.expectEnd();
        final c = PacketReader(byName['minecraft:consumable']!);
        expect(c.readFloat(), closeTo(1.6, 1e-6), reason: '${r.key}: 32 ticks');
        expect(c.readVarInt(), 1, reason: '${r.key}: UseAnimation.EAT');
        expect(
          c.readVarInt(),
          VanillaIds.sounds.idOf('entity.generic.eat')! + 1,
          reason: '${r.key}: the default food sound',
        );
        expect(c.readBool(), isTrue, reason: '${r.key}: consume particles');
        expect(c.readVarInt(), 0, reason: '${r.key}: no consume effects');
        c.expectEnd();
      }
    },
  );

  test('the ore blocks drop through their loot table', () {
    expect(materialLootTableBlocks, {'zinc_ore', 'deepslate_zinc_ore'});
    expect(materialLootTableBlocks.every(materialBlockKeys.contains), isTrue);
  });
}
