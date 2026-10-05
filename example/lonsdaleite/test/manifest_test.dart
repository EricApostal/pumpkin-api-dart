import 'dart:convert';
import 'dart:io';

import 'package:lonsdaleite/src/manifest.dart';
import 'package:lonsdaleite/src/manifest.g.dart';
import 'package:test/test.dart';

void main() {
  final manifest = Manifest.parse(lonsdaleiteManifestJson);
  ManifestItem item(String path) => manifest.item('lonsdaleite:$path')!;

  test('the embedded manifest is the one in data/', () {
    final onDisk = jsonDecode(File('data/manifest.json').readAsStringSync());
    expect(jsonDecode(lonsdaleiteManifestJson), onDisk);
  });

  test('mod info comes from the build files', () {
    expect(manifest.mod.id, 'lonsdaleite');
    expect(manifest.mod.version, '2.3.0');
    expect(manifest.mod.minecraftVersion, '26.3');
    expect(manifest.mod.license, 'CC0-1.0');
  });

  test('counts the items by kind', () {
    final counts = <ItemKind, int>{};
    for (final i in manifest.items) {
      counts.update(i.kind, (n) => n + 1, ifAbsent: () => 1);
    }
    expect(counts, {
      ItemKind.material: 4,
      ItemKind.pickaxe: 2,
      ItemKind.axe: 2,
      ItemKind.shovel: 2,
      ItemKind.hoe: 2,
      ItemKind.omnitool: 2,
      ItemKind.sword: 2,
      ItemKind.shortSword: 2,
      ItemKind.warAxe: 2,
      ItemKind.spear: 2,
      ItemKind.mace: 1,
      ItemKind.armor: 8,
      ItemKind.blockItem: 1,
    });
    expect(manifest.items, hasLength(32));
  });

  test('items are in registration order, the block item first', () {
    expect(manifest.items.first.id, 'lonsdaleite:lonsdaleite_wardframe');
    expect(manifest.items[1].id, 'lonsdaleite:raw_lonsdaleite');
    expect(manifest.items.last.id, 'lonsdaleite:perfect_lonsdaleite_boots');
  });

  test('the pickaxe gets its stats from the material and the builder', () {
    final c = item('lonsdaleite_pickaxe').components;
    expect(c.maxDamage, 2800);
    expect(c.maxStackSize, 1);
    expect(c.enchantable, 15);
    expect(c.repairable, '#lonsdaleite:repairs_lonsdaleite_tools');
    // pickaxe(material, 5, -2.8F): 5 + the material's 3.0 bonus.
    expect(c.modifier('minecraft:attack_damage')!.amount, 8.0);
    expect(c.modifier('minecraft:attack_speed')!.amount, closeTo(-2.8, 1e-6));
    final tool = c.tool!;
    expect(tool.damagePerBlock, 1);
    expect(tool.rules[0].blocks, '#minecraft:incorrect_for_netherite_tool');
    expect(tool.rules[0].correctForDrops, isFalse);
    expect(tool.rules[1].blocks, '#minecraft:mineable/pickaxe');
    expect(tool.rules[1].speed, 8.2);
    expect(c.weapon!.itemDamagePerAttack, 2);
    expect(c.blockTransformer, isNull);
  });

  test('axes, shovels and hoes carry a block transformer', () {
    expect(
      item('lonsdaleite_axe').components.blockTransformer,
      'minecraft:axe',
    );
    expect(
      item('lonsdaleite_shovel').components.blockTransformer,
      'minecraft:shovel',
    );
    expect(
      item('perfect_lonsdaleite_hoe').components.blockTransformer,
      'minecraft:hoe',
    );
    expect(
      item('lonsdaleite_axe').components.weapon!.disableBlockingForSeconds,
      5.0,
    );
    // The omnitool is built with pickaxe(), so it has none: its Java applies them.
    expect(item('lonsdaleite_omnitool').components.blockTransformer, isNull);
  });

  test('the hoe keeps the vanilla scheme of attack 0 plus the bonus', () {
    final c = item('perfect_lonsdaleite_hoe').components;
    expect(c.modifier('minecraft:attack_damage')!.amount, 3 + 4);
    expect(c.modifier('minecraft:attack_speed')!.amount, closeTo(0.2, 1e-6));
  });

  test('swords use the sword tool rules', () {
    final tool = item('perfect_lonsdaleite_sword').components.tool!;
    expect(tool.damagePerBlock, 2);
    expect(tool.canDestroyBlocksInCreative, isFalse);
    expect(tool.rules.map((r) => r.blocks), [
      'minecraft:cobweb',
      '#minecraft:sword_instantly_mines',
      '#minecraft:sword_efficient',
    ]);
    expect(
      item('perfect_lonsdaleite_sword').components
          .modifier('minecraft:attack_damage')!
          .amount,
      8 + 4,
    );
  });

  test('the spear has the kinetic and piercing components', () {
    final c = item('lonsdaleite_spear').components;
    final kinetic = c.kineticWeapon!;
    expect(kinetic.delayTicks, 8);
    expect(kinetic.dismount.maxDurationTicks, 50);
    expect(kinetic.dismount.speed, 9.0);
    expect(kinetic.knockback.maxDurationTicks, 110);
    expect(kinetic.knockback.speed, 5.1);
    expect(kinetic.damage.maxDurationTicks, 175);
    expect(kinetic.damage.relative, isTrue);
    expect(kinetic.damage.speed, 4.6);
    expect(kinetic.damageMultiplier, 1.25);
    expect(
      item('perfect_lonsdaleite_spear')
          .components
          .kineticWeapon!
          .damageMultiplier,
      1.35,
    );
    expect(c.piercingWeapon!.sound, 'minecraft:item.spear.attack');
    expect(c.raw['minecraft:attack_animation'], {
      'type': 'stab',
      'duration': 23,
    });
    expect(c.modifier('minecraft:attack_damage')!.amount, 3.0);
    expect(
      c.modifier('minecraft:attack_speed')!.amount,
      closeTo(1 / 1.15 - 4, 1e-6),
    );
  });

  test('the mace is hand-built', () {
    final c = item('lonsdaleite_mace').components;
    expect(c.rarity, 'epic');
    expect(c.maxDamage, 2640);
    expect(c.enchantable, 20);
    expect(c.repairable, '#lonsdaleite:repairs_perfect_lonsdaleite_tools');
    expect(c.modifier('minecraft:attack_damage')!.amount, 7.0);
    // A double literal in the Java, not the float -3.4F of the vanilla mace.
    expect(c.modifier('minecraft:attack_speed')!.amount, -3.4);
    expect(c.tool!.rules, isEmpty);
    expect(c.tool!.damagePerBlock, 2);
    expect(c.weapon!.itemDamagePerAttack, 1);
    expect(item('lonsdaleite_mace').behaviors, ['mace.smash_attack']);
  });

  test('armor derives from the material and the slot', () {
    final expected = {
      'helmet': (704 - 220, 3.0), // 44 * 11
      'chestplate': (704, 8.0), // 44 * 16
      'leggings': (660, 6.0), // 44 * 15
      'boots': (572, 3.0), // 44 * 13
    };
    expected.forEach((piece, values) {
      final c = item('lonsdaleite_$piece').components;
      expect(c.maxDamage, values.$1, reason: piece);
      expect(c.modifier('minecraft:armor')!.amount, values.$2, reason: piece);
      expect(c.modifier('minecraft:armor_toughness')!.amount, 2.0);
      expect(c.modifier('minecraft:knockback_resistance'), isNull);
      expect(c.equippable!.assetId, 'lonsdaleite:lonsdaleite');
      expect(c.equippable!.equipSound, 'minecraft:item.armor.equip_diamond');
    });
    final perfect = item('perfect_lonsdaleite_boots').components;
    expect(perfect.maxDamage, 60 * 13);
    expect(perfect.modifier('minecraft:armor_toughness')!.amount, 3.0);
    expect(
      perfect.modifier('minecraft:knockback_resistance')!.amount,
      closeTo(0.1, 1e-6),
    );
    expect(
      perfect.equippable!.equipSound,
      'minecraft:item.armor.equip_netherite',
    );
    expect(perfect.enchantable, 18);
  });

  test('nothing is fire resistant', () {
    for (final i in manifest.items) {
      expect(
        i.components.has('minecraft:damage_resistant'),
        isFalse,
        reason: i.id,
      );
    }
  });

  test('the omnitool differs on the server only by mining rules', () {
    final omnitool = item('lonsdaleite_omnitool');
    expect(omnitool.components.tool!.rules, hasLength(2));
    final server = omnitool.serverView.tool!;
    expect(server.rules.map((r) => r.blocks), [
      '#minecraft:incorrect_for_netherite_tool',
      '#minecraft:mineable/pickaxe',
      '#minecraft:mineable/axe',
      '#minecraft:mineable/shovel',
      '#minecraft:mineable/hoe',
      '#minecraft:sword_efficient',
    ]);
    expect(
      server.rules
          .skip(2)
          .every((r) => r.speed == 8.2 && r.correctForDrops == null),
      isTrue,
    );
    expect(item('lonsdaleite_pickaxe').serverComponents, isEmpty);
  });

  test('the wardframe block', () {
    final b = manifest.block;
    expect(b.id, 'lonsdaleite:lonsdaleite_wardframe');
    expect(b.destroyTime, 5.0);
    expect(b.explosionResistance, 1200.0);
    expect(b.soundType, 'amethyst');
    expect(b.canOcclude, isFalse);
    expect(b.requiresCorrectToolForDrops, isTrue);
    expect(b.lightLevel, 7);
    expect(b.properties, ['north', 'south', 'east', 'west', 'up', 'down']);
    expect(b.stateCount, 64);
    expect(b.defaultStateIndex, 63, reason: 'all false is the last state');
    expect(b.blockTags, [
      'minecraft:mineable/pickaxe',
      'minecraft:needs_diamond_tool',
    ]);
    expect(b.itemTags, ['minecraft:doors']);
    expect(item('lonsdaleite_wardframe').block, b.id);
    expect(
      item('lonsdaleite_wardframe').components.raw['minecraft:item_name'],
      {'translate': 'block.lonsdaleite.lonsdaleite_wardframe'},
    );
  });

  test('creative tab order and vanilla tab anchors', () {
    final tab = manifest.creativeTabs;
    expect(tab.id, 'lonsdaleite:lonsdaleite');
    expect(tab.icon, 'lonsdaleite:refined_lonsdaleite');
    expect(tab.items.take(6), [
      'lonsdaleite:raw_lonsdaleite',
      'lonsdaleite:prepared_lonsdaleite',
      'lonsdaleite:refined_lonsdaleite',
      'lonsdaleite:perfect_lonsdaleite',
      'lonsdaleite:lonsdaleite_wardframe',
      'lonsdaleite:lonsdaleite_pickaxe',
    ]);
    final combat = tab.insertions
        .where((i) => i.tab == 'minecraft:combat')
        .toList();
    expect(combat.first.after, 'minecraft:netherite_axe');
    expect(
      combat
          .firstWhere(
            (i) =>
                i.item.endsWith('lonsdaleite_helmet') &&
                !i.item.contains('perfect'),
          )
          .after,
      'minecraft:netherite_boots',
    );
    expect(
      tab.insertions.where((i) => i.tab == 'minecraft:tools_and_utilities'),
      hasLength(10),
    );
  });

  test('tags, recipes and loot tables', () {
    expect(
      manifest.tags['item']!['minecraft:axes']!.values,
      contains('lonsdaleite:lonsdaleite_omnitool'),
    );
    expect(
      manifest
          .tags['item']!['lonsdaleite:repairs_perfect_lonsdaleite_tools']!
          .values,
      ['lonsdaleite:perfect_lonsdaleite'],
    );
    expect(manifest.tags['block']!.keys, [
      'minecraft:mineable/pickaxe',
      'minecraft:needs_diamond_tool',
    ]);
    expect(manifest.recipes, hasLength(32));
    expect(
      {for (final r in manifest.recipes) r.type},
      {'minecraft:crafting_shaped', 'minecraft:blasting'},
    );
    final wardframe = manifest.recipes.firstWhere(
      (r) => r.id == 'lonsdaleite:lonsdaleite_wardframe',
    );
    expect(wardframe.resultCount, 8);
    expect(wardframe.ingredients, {'lonsdaleite:refined_lonsdaleite'});
    expect(manifest.lootTables.single.items, {
      'lonsdaleite:lonsdaleite_wardframe',
    });
  });

  test('behaviours cover every override the Java declares', () {
    final ids = manifest.behaviors.map((b) => b.id).toSet();
    expect(
      ids,
      containsAll([
        'omnitool.use_on',
        'omnitool.destroy_speed',
        'wardframe.collision',
        'mace.smash_attack',
        'weapon.hurt_enemy_durability',
      ]),
    );
    expect(
      manifest.behaviors.firstWhere((b) => b.id == 'omnitool.use_on').targets,
      hasLength(2),
    );
  });
}
