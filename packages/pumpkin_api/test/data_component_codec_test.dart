// Golden bytes for DataComponentCodec.
//
// Derivation: each expected byte string was written by reading the matching
// `DataComponentCodec::deserialize` in Pumpkin's
// crates/pumpkin-protocol/src/codec/data_component.rs (the reader the host
// runs on `data-component-value.value`) and laying out the fields it reads, in
// order. Notation: `vi(n)` a VarInt, `f32(x)`/`f64(x)` big endian IEEE floats,
// `str(s)` a VarInt byte length and the UTF-8 bytes. Ids come from Pumpkin's
// assets: sounds.json list index + 1 for a `Holder<SoundEvent>`, blocks.json,
// attributes.json `id`, and the damage_type directory (sorted, spear = 37).
// The float and VarInt bytes were computed independently with Python `struct`.
import 'dart:convert';
import 'dart:typed_data';

import 'package:pumpkin_api/src/data_component_codec.dart';
import 'package:pumpkin_api/src/registry_ids.dart';
import 'package:test/test.dart';

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// `str(s)`: VarInt length (< 128 here) and the UTF-8 bytes.
List<int> str(String s) {
  final bytes = utf8.encode(s);
  assert(bytes.length < 128);
  return [bytes.length, ...bytes];
}

List<int> h(String hexString) => [
  for (var i = 0; i < hexString.length; i += 2)
    int.parse(hexString.substring(i, i + 2), radix: 16),
];

void expectEncoded(String name, Object? json, List<int> expected) {
  final bytes = DataComponentCodec.encode(name, json);
  expect(hex(bytes), hex(expected), reason: name);
}

void main() {
  group('simple components', () {
    test('max_stack_size, max_damage, damage, repair_cost, enchantable', () {
      // MaxStackSizeImpl: vi(size). 64 = 0x40, 1 = 0x01.
      expectEncoded('minecraft:max_stack_size', 64, [0x40]);
      expectEncoded('minecraft:max_stack_size', 1, [0x01]);
      // MaxDamageImpl: vi(2800) = 0xF0 0x15 (2800 = 21 * 128 + 112).
      expectEncoded('minecraft:max_damage', 2800, [0xF0, 0x15]);
      // DamageImpl, RepairCostImpl: vi(0).
      expectEncoded('minecraft:damage', 0, [0]);
      expectEncoded('minecraft:repair_cost', 0, [0]);
      // EnchantableImpl: vi(value).
      expectEncoded('minecraft:enchantable', {'value': 15}, [15]);
    });

    test('rarity', () {
      // RarityImpl: vi(id), common 0, uncommon 1, rare 2, epic 3.
      expectEncoded('minecraft:rarity', 'common', [0]);
      expectEncoded('minecraft:rarity', 'epic', [3]);
      expect(
        () => DataComponentCodec.encode('minecraft:rarity', 'legendary'),
        throwsA(isA<ComponentEncodeException>()),
      );
    });

    test('item_model, item_name, lore, enchantments', () {
      // ItemModelImpl: str(id).
      expectEncoded('minecraft:item_model', 'lonsdaleite:raw_lonsdaleite', [
        ...str('lonsdaleite:raw_lonsdaleite'),
      ]);
      // ItemNameImpl::deserialize: str(translation key), not NBT.
      expectEncoded(
        'minecraft:item_name',
        {'translate': 'item.lonsdaleite.raw_lonsdaleite'},
        str('item.lonsdaleite.raw_lonsdaleite'),
      );
      // LoreImpl: vi(0) lines.
      expectEncoded('minecraft:lore', <Object?>[], [0]);
      // EnchantmentsImpl: vi(0) entries.
      expectEncoded('minecraft:enchantments', <String, Object?>{}, [0]);
      // One entry: vi(count 1), vi(enchantment id), vi(level); the id is
      // looked up in the generated enchantment table.
      final sharpness = VanillaIds.enchantments.idOf('minecraft:sharpness')!;
      expectEncoded(
        'minecraft:enchantments',
        {'minecraft:sharpness': 3},
        [1, sharpness, 3],
      );
    });

    test('tooltip_display, use_effects, break_sound, glider', () {
      // TooltipDisplayImpl: bool, vi(count).
      expectEncoded('minecraft:tooltip_display', <String, Object?>{}, [0, 0]);
      // UseEffectsImpl: bool can_sprint, bool interact_vibrations, f32.
      // Default: false, true, 0.2f = 3e4ccccd.
      expectEncoded('minecraft:use_effects', <String, Object?>{}, [
        0, 1, ...h('3e4ccccd'), //
      ]);
      expectEncoded(
        'minecraft:use_effects',
        {'can_sprint': true, 'interact_vibrations': false, 'speed_multiplier': 1.0},
        [1, 0, ...h('3f800000')],
      );
      // BreakSoundImpl: vi(sound id + 1): entity.item.break is index 914.
      expectEncoded('minecraft:break_sound', 'minecraft:entity.item.break', [
        0x93,
        0x07, // 915 = 7 * 128 + 19
      ]);
      // GliderImpl: nothing.
      expectEncoded('minecraft:glider', <String, Object?>{}, []);
    });

    test('attack_animation, attack_range, minimum_attack_charge, damage_type', () {
      // SwingAnimationImpl: vi(type), vi(duration). whack 0, stab 1, none 2
      // (SwingAnimationType::from_id); default whack, 6.
      expectEncoded('minecraft:attack_animation', <String, Object?>{}, [0, 6]);
      expectEncoded(
        'minecraft:attack_animation',
        {'type': 'stab', 'duration': 23},
        [1, 23],
      );
      // AttackRangeImpl: six f32: min_reach, max_reach, min_creative_reach,
      // max_creative_reach, hitbox_margin, mob_factor.
      expectEncoded(
        'minecraft:attack_range',
        {
          'min_reach': 2.0,
          'max_reach': 4.5,
          'min_creative_reach': 2.0,
          'max_creative_reach': 6.5,
          'hitbox_margin': 0.125,
          'mob_factor': 0.5,
        },
        h('40000000' '40900000' '40000000' '40d00000' '3e000000' '3f000000'),
      );
      // MinimumAttackChargeImpl: f32.
      expectEncoded('minecraft:minimum_attack_charge', 1.0, h('3f800000'));
      // DamageTypeImpl: vi(id), spear is 37.
      expectEncoded('minecraft:damage_type', 'minecraft:spear', [37]);
    });
  });

  group('holder sets', () {
    test('repairable with a tag', () {
      // RepairableImpl: IDSet: vi(0), str(tag without #).
      expectEncoded(
        'minecraft:repairable',
        {'items': '#lonsdaleite:repairs_lonsdaleite_tools'},
        [0, ...str('lonsdaleite:repairs_lonsdaleite_tools')],
      );
    });

    test('repairable with items: vi(count + 1) then the ids', () {
      final registries = ComponentRegistries.vanilla(
        item: (key) => const {'x:y': 300, 'minecraft:breeze_rod': 1373}[key],
      );
      // 300 = 0xAC 0x02, 1373 = 0xDD 0x0A.
      expect(
        hex(
          DataComponentCodec.encode(
            'minecraft:repairable',
            {'items': 'x:y'},
            registries: registries,
          ),
        ),
        hex([2, 0xAC, 0x02]),
      );
      expect(
        hex(
          DataComponentCodec.encode(
            'minecraft:repairable',
            {
              'items': ['x:y', 'minecraft:breeze_rod'],
            },
            registries: registries,
          ),
        ),
        hex([3, 0xAC, 0x02, 0xDD, 0x0A]),
      );
    });

    test('vanilla item ids agree with the assets', () {
      expect(VanillaIds.items.idOf('minecraft:breeze_rod'), 1373);
      expect(VanillaIds.items.length, 1658);
    });

    test('an unknown item is an error', () {
      expect(
        () => DataComponentCodec.encode('minecraft:repairable', {
          'items': 'nope:nothing',
        }),
        throwsA(
          isA<ComponentEncodeException>().having(
            (e) => e.message,
            'message',
            contains('nope:nothing'),
          ),
        ),
      );
    });
  });

  group('tool', () {
    test('pickaxe of the Lonsdaleite tier', () {
      // ToolImpl: vi(rule count); per rule: IDSet blocks, bool + f32 speed,
      // bool + bool correct_for_drops; then f32 default_mining_speed,
      // vi(damage_per_block), bool can_destroy_blocks_in_creative.
      expectEncoded(
        'minecraft:tool',
        {
          'rules': [
            {
              'blocks': '#minecraft:incorrect_for_netherite_tool',
              'correct_for_drops': false,
            },
            {
              'blocks': '#minecraft:mineable/pickaxe',
              'speed': 8.2,
              'correct_for_drops': true,
            },
          ],
        },
        [
          2,
          // rule 1: tag, no speed, correct_for_drops false
          0, ...str('minecraft:incorrect_for_netherite_tool'),
          0,
          1, 0,
          // rule 2: tag, speed 8.2f, correct_for_drops true
          0, ...str('minecraft:mineable/pickaxe'),
          1, ...h('41033333'),
          1, 1,
          // default speed 1.0, damage per block 1, creative true
          ...h('3f800000'), 1, 1,
        ],
      );
    });

    test('sword: a direct block, the maximum speed, no creative mining', () {
      // cobweb is block id 139 (blocks.json): vi(1 + 1), vi(139) = 0x8B 0x01.
      // 3.4028235e38 is Float.MAX_VALUE = 7f7fffff.
      expectEncoded(
        'minecraft:tool',
        {
          'rules': [
            {'blocks': 'minecraft:cobweb', 'speed': 15.0, 'correct_for_drops': true},
            {'blocks': '#minecraft:sword_instantly_mines', 'speed': 3.4028235e+38},
            {'blocks': '#minecraft:sword_efficient', 'speed': 1.5},
          ],
          'damage_per_block': 2,
          'can_destroy_blocks_in_creative': false,
        },
        [
          3,
          2, 0x8B, 0x01, 1, ...h('41700000'), 1, 1,
          0, ...str('minecraft:sword_instantly_mines'), 1, ...h('7f7fffff'), 0,
          0, ...str('minecraft:sword_efficient'), 1, ...h('3fc00000'), 0,
          ...h('3f800000'), 2, 0,
        ],
      );
    });

    test('the mace has a tool without rules', () {
      expectEncoded(
        'minecraft:tool',
        {'rules': <Object?>[], 'damage_per_block': 2, 'can_destroy_blocks_in_creative': false},
        [0, ...h('3f800000'), 2, 0],
      );
    });

    test('a misspelled field is an error, not ignored', () {
      expect(
        () => DataComponentCodec.encode('minecraft:tool', {'rule': <Object?>[]}),
        throwsA(isA<ComponentEncodeException>()),
      );
    });
  });

  group('weapon', () {
    test('weapon', () {
      // WeaponImpl: vi(item_damage_per_attack), f32 (discarded by the host).
      expectEncoded(
        'minecraft:weapon',
        {'item_damage_per_attack': 2, 'disable_blocking_for_seconds': 5.0},
        [2, ...h('40a00000')],
      );
      expectEncoded('minecraft:weapon', <String, Object?>{}, [1, 0, 0, 0, 0]);
    });

    test('piercing_weapon', () {
      // PiercingWeaponImpl: bool knockback (default true), bool dismounts
      // (default false), bool + Holder sound, bool + Holder hit sound.
      // item.spear.attack is sound 1532 (wire 1533 = 0xFD 0x0B), item.spear.hit
      // 1531 (wire 1532 = 0xFC 0x0B).
      expectEncoded(
        'minecraft:piercing_weapon',
        {
          'sound': 'minecraft:item.spear.attack',
          'hit_sound': 'minecraft:item.spear.hit',
        },
        [1, 0, 1, 0xFD, 0x0B, 1, 0xFC, 0x0B],
      );
      expectEncoded('minecraft:piercing_weapon', <String, Object?>{}, [1, 0, 0, 0]);
    });

    test('kinetic_weapon of the Lonsdaleite spear', () {
      // KineticWeaponImpl: vi(contact_cooldown 10), vi(delay), three
      // optional conditions (bool, vi(max_duration), f32 min_speed, f32
      // min_relative_speed), f32 forward_movement, f32 damage_multiplier,
      // optional sound, optional hit sound.
      expectEncoded(
        'minecraft:kinetic_weapon',
        {
          'delay_ticks': 8,
          'dismount_conditions': {'max_duration_ticks': 50, 'min_speed': 9.0},
          'knockback_conditions': {'max_duration_ticks': 110, 'min_speed': 5.1},
          'damage_conditions': {'max_duration_ticks': 175, 'min_relative_speed': 4.6},
          'forward_movement': 0.38,
          'damage_multiplier': 1.25,
          'sound': 'minecraft:item.spear.use',
          'hit_sound': 'minecraft:item.spear.hit',
        },
        [
          10, 8,
          1, 50, ...h('41100000'), ...h('00000000'),
          1, 110, ...h('40a33333'), ...h('00000000'),
          1, 0xAF, 0x01, ...h('00000000'), ...h('40933333'),
          ...h('3ec28f5c'), ...h('3fa00000'),
          1, 0xFB, 0x0B, // item.spear.use 1530 -> 1531
          1, 0xFC, 0x0B, // item.spear.hit 1531 -> 1532
        ],
      );
    });
  });

  group('equippable and attributes', () {
    test('helmet of the Lonsdaleite tier', () {
      // EquippableImpl: vi(slot index, head 4), Holder equip sound
      // (item.armor.equip_diamond 68 -> 69), bool + str asset_id, bool
      // camera_overlay, bool allowed_entities, dispensable, swappable,
      // damage_on_hurt, equip_on_interact, can_be_sheared, Holder shearing
      // sound (item.shears.snip 1447 -> 1448 = 0xA8 0x0B).
      expectEncoded(
        'minecraft:equippable',
        {
          'slot': 'head',
          'equip_sound': 'minecraft:item.armor.equip_diamond',
          'asset_id': 'lonsdaleite:lonsdaleite',
        },
        [
          4,
          69,
          1, ...str('lonsdaleite:lonsdaleite'),
          0,
          0,
          1, 1, 1, 0, 0,
          0xA8, 0x0B,
        ],
      );
    });

    test('slots and netherite boots', () {
      final boots = DataComponentCodec.encode('minecraft:equippable', {
        'slot': 'feet',
        'equip_sound': 'minecraft:item.armor.equip_netherite',
        'asset_id': 'lonsdaleite:perfect_lonsdaleite',
      });
      expect(boots.first, 1); // feet
      expect(boots[1], 76); // equip_netherite 75 + 1
      for (final entry in const {
        'mainhand': 0, 'feet': 1, 'legs': 2, 'chest': 3, 'head': 4,
        'offhand': 5, 'body': 6, 'saddle': 7,
      }.entries) {
        expect(
          DataComponentCodec.encode('minecraft:equippable', {'slot': entry.key}).first,
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('attribute modifiers', () {
      // AttributeModifiersImpl: vi(count); per modifier: vi(attribute id),
      // str(id), f64 amount, vi(operation), vi(slot), vi(display type).
      // armor is attribute 1, armor_toughness 2, knockback_resistance 20,
      // attack_damage 3, attack_speed 5; head is slot 7, mainhand 1.
      expectEncoded(
        'minecraft:attribute_modifiers',
        [
          {
            'type': 'minecraft:armor',
            'id': 'minecraft:armor.helmet',
            'amount': 3.0,
            'operation': 'add_value',
            'slot': 'head',
          },
          {
            'type': 'minecraft:knockback_resistance',
            'id': 'minecraft:armor.helmet',
            'amount': 0.10000000149011612,
            'operation': 'add_value',
            'slot': 'head',
          },
        ],
        [
          2,
          1, ...str('minecraft:armor.helmet'), ...h('4008000000000000'), 0, 7, 0,
          20, ...str('minecraft:armor.helmet'), ...h('3fb99999a0000000'), 0, 7, 0,
        ],
      );
      expectEncoded(
        'minecraft:attribute_modifiers',
        [
          {
            'type': 'minecraft:attack_speed',
            'id': 'minecraft:base_attack_speed',
            'amount': -2.799999952316284,
            'operation': 'add_value',
            'slot': 'mainhand',
          },
        ],
        [
          1,
          5, ...str('minecraft:base_attack_speed'), ...h('c006666660000000'), 0, 1, 0,
        ],
      );
      expectEncoded('minecraft:attribute_modifiers', <Object?>[], [0]);
    });
  });

  group('encodeAll', () {
    test('skips the components the host cannot read and says why', () {
      final result = DataComponentCodec.encodeAll({
        'minecraft:max_stack_size': 1,
        'minecraft:block_transformer': 'minecraft:axe',
        'minecraft:interact_animation': <String, Object?>{},
      });
      expect(result.encoded.map((c) => c.name), ['minecraft:max_stack_size']);
      expect(result.skipped.map((c) => c.name), [
        'minecraft:block_transformer',
        'minecraft:interact_animation',
      ]);
      expect(result.skipped.first.reason, contains('static item tags'));
      expect(result.byName['minecraft:max_stack_size'], Uint8List.fromList([1]));
    });

    test('a readable component without an encoder is an error', () {
      expect(
        () => DataComponentCodec.encodeAll({'minecraft:food': <String, Object?>{}}),
        throwsA(
          isA<ComponentEncodeException>().having(
            (e) => e.message,
            'message',
            contains('no encoder'),
          ),
        ),
      );
    });

    test('names map onto the WIT data-component cases', () {
      expect(DataComponentCodec.wireNameOf('minecraft:max_stack_size'), 'max-stack-size');
      expect(DataComponentCodec.wireNameOf('minecraft:cushion/color'), 'cushion-color');
      // Every encoder has a component id in Pumpkin's data component list, in
      // the same order as the WIT enum (checked against the assets by
      // tool/generate_registry_ids.dart).
      for (final name in DataComponentCodec.supported) {
        expect(VanillaIds.dataComponentTypes.idOf(name), isNotNull, reason: name);
      }
      for (final name in DataComponentCodec.notReadByHost.keys) {
        expect(VanillaIds.dataComponentTypes.idOf(name), isNotNull, reason: name);
      }
    });
  });

  group('registry ids', () {
    test('the generated tables have the ids the host uses', () {
      expect(VanillaIds.sounds.idOf('item.spear.attack'), 1532);
      expect(VanillaIds.sounds.keyOf(1532), 'minecraft:item.spear.attack');
      expect(VanillaIds.blocks.idOf('minecraft:cobweb'), 139);
      expect(VanillaIds.attributes.idOf('minecraft:attack_damage'), 3);
      expect(VanillaIds.damageTypes.idOf('minecraft:spear'), 37);
      expect(VanillaIds.items.idOf('stone'), 1);
      expect(VanillaIds.items.keyOf(0), 'minecraft:air');
      expect(VanillaIds.items.idOf('lonsdaleite:x'), isNull);
      expect(() => VanillaIds.items.require('nope'), throwsArgumentError);
    });
  });
}
