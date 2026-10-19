import 'package:create/src/content/material_content.dart';
import 'package:create/src/decoration/roles.dart';
import 'package:create/src/manifest/manifest.dart';
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
    'the food items exist but carry no food component the host cannot read',
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
      // `DataComponentCodec` has no encoder for `minecraft:food`; a registration that included it
      // would throw and abort the id-bearing registries.
      for (final r in createMaterialItems()) {
        expect(
          r.components.where((c) => c.name == 'minecraft:food'),
          isEmpty,
          reason: r.key,
        );
      }
    },
  );

  test('the ore blocks drop through their loot table', () {
    expect(materialLootTableBlocks, {'zinc_ore', 'deepslate_zinc_ore'});
    expect(materialLootTableBlocks.every(materialBlockKeys.contains), isTrue);
  });
}
