import 'package:create/src/equipment/tools/tool_materials.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:test/test.dart';

void main() {
  test('cardboard tool material', () {
    const m = AllToolMaterials.cardboard;
    expect(m.durability, 0);
    expect(m.speed, 1);
    expect(m.attackDamageBonus, 2);
    expect(m.enchantmentValue, 1);
    expect(m.incorrectBlocksForDrops, '#minecraft:incorrect_for_wooden_tool');
    expect(m.repairItems, '#c:plates/cardboard');
  });

  test('sword tool rules match vanilla applySwordProperties', () {
    final tool = AllToolMaterials.cardboard.swordToolComponent;
    expect(tool['default_mining_speed'], 1.0);
    expect(tool['damage_per_block'], 2);
    expect(tool['can_destroy_blocks_in_creative'], false);
    final rules = tool['rules'] as List;
    expect(rules.length, 3);
    expect((rules[0] as Map)['blocks'], 'minecraft:cobweb');
    expect((rules[0] as Map)['speed'], 15.0);
    expect((rules[0] as Map)['correct_for_drops'], isTrue);
    expect((rules[1] as Map)['blocks'], '#minecraft:sword_instantly_mines');
    expect((rules[2] as Map)['blocks'], '#minecraft:sword_efficient');
    expect((rules[2] as Map)['speed'], 1.5);
  });

  test('sword attribute modifiers use the Java baselines', () {
    final modifiers = AllToolMaterials.cardboard.swordAttributeModifiers();
    expect(modifiers.length, 2);
    expect(modifiers[0]['type'], 'minecraft:attack_damage');
    expect(modifiers[0]['amount'], 5.0);
    expect(modifiers[0]['slot'], 'mainhand');
    expect(modifiers[1]['type'], 'minecraft:attack_speed');
    expect(modifiers[1]['amount'], 1.0);
  });

  test('sword components encode with the host codec', () {
    final components = AllToolMaterials.cardboard.swordComponents();
    expect(
      components.keys,
      containsAll(['minecraft:tool', 'minecraft:weapon', 'minecraft:attribute_modifiers', 'minecraft:repairable']),
    );
    final encoded = DataComponentCodec.encodeAll(components);
    expect(encoded.skipped, isEmpty);
    expect(encoded.encoded.map((c) => c.name), containsAll(components.keys));
    expect(encoded.byName['minecraft:tool']!.isNotEmpty, isTrue);
  });

  test('armor repairable and intrinsic enchantments encode', () {
    final encoded = DataComponentCodec.encodeAll({
      'minecraft:repairable': {'items': '#create:cardboard'},
      'minecraft:enchantments': {
        'levels': {'minecraft:aqua_affinity': 1},
        'show_in_tooltip': true,
      },
    });
    expect(encoded.skipped, isEmpty);
    expect(encoded.encoded.length, 2);
    expect(encoded.byName['minecraft:enchantments']!.isNotEmpty, isTrue);
  });

  test('fire resistance resolves to the host component', () {
    expect(DataComponentCodec.wireNameOf('minecraft:damage_resistant'), 'damage-resistant');
  });
}
