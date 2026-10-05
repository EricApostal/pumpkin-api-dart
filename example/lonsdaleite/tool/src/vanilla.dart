/// A model of what vanilla's `Item.Properties` builders (Minecraft 26.3) put
/// into an item's default components, in the JSON shape the vanilla data
/// extractor (and so Pumpkin's `assets/items.json`) uses: fields equal to
/// their codec default are omitted, `float` fields print as the shortest
/// decimal of the float and `double` fields as the widened float.
///
/// The semantics were read off the extracted vanilla items (netherite and the
/// other tiers) and are checked against every vanilla tool, spear and armor
/// piece by `generate_manifest.dart --verify-vanilla <items.json>`.
library;

import 'java_text.dart';

/// A JSON object.
typedef Json = Map<String, Object?>;

/// `float` value as the decimal the extractor prints: the shortest decimal
/// string that parses back to the same 32-bit float.
double floatField(double value) {
  final f = toFloat32(value);
  for (var digits = 1; digits <= 9; digits++) {
    final candidate = double.parse(f.toStringAsPrecision(digits));
    if (toFloat32(candidate) == f) return candidate;
  }
  return f;
}

/// A vanilla or modded `ToolMaterial`.
final class ToolMaterialSpec {
  /// Tag of blocks this tier cannot harvest, e.g. `minecraft:incorrect_for_netherite_tool`.
  final String incorrectBlocksForDrops;
  final int durability;
  final double speed;
  final double attackDamageBonus;
  final int enchantmentValue;

  /// Tag of items that repair the tools, e.g. `lonsdaleite:repairs_lonsdaleite_tools`.
  final String repairItems;

  /// Wooden tools use different spear sounds.
  final bool woodSounds;

  const ToolMaterialSpec({
    required this.incorrectBlocksForDrops,
    required this.durability,
    required this.speed,
    required this.attackDamageBonus,
    required this.enchantmentValue,
    required this.repairItems,
    this.woodSounds = false,
  });

  Json toJson() => {
    'incorrect_blocks_for_drops': '#$incorrectBlocksForDrops',
    'durability': durability,
    'speed': floatField(speed),
    'attack_damage_bonus': floatField(attackDamageBonus),
    'enchantment_value': enchantmentValue,
    'repair_items': '#$repairItems',
  };
}

/// The slot an armor piece goes in plus its durability factor
/// (`net.minecraft.world.item.equipment.ArmorType`).
enum ArmorType {
  helmet('head', 11),
  chestplate('chest', 16),
  leggings('legs', 15),
  boots('feet', 13);

  /// The `minecraft:equippable` slot name.
  final String slot;

  /// Multiplied by the material's durability factor.
  final int durabilityMultiplier;

  const ArmorType(this.slot, this.durabilityMultiplier);

  /// The type name used in attribute modifier ids (`minecraft:armor.helmet`).
  String get typeName => name;

  static ArmorType fromJava(String constant) =>
      values.firstWhere(
        (t) => t.name == constant.toLowerCase(),
        orElse: () => throw JavaParseError('Unknown ArmorType $constant'),
      );
}

/// A vanilla or modded `ArmorMaterial`.
final class ArmorMaterialSpec {
  final int durability;
  final Map<ArmorType, int> defense;
  final int enchantmentValue;
  final String equipSound;
  final double toughness;
  final double knockbackResistance;
  final String repairItems;
  final String assetId;

  const ArmorMaterialSpec({
    required this.durability,
    required this.defense,
    required this.enchantmentValue,
    required this.equipSound,
    required this.toughness,
    required this.knockbackResistance,
    required this.repairItems,
    required this.assetId,
  });

  Json toJson() => {
    'durability': durability,
    'defense': {for (final t in ArmorType.values) t.name: defense[t]},
    'enchantment_value': enchantmentValue,
    'equip_sound': equipSound,
    'toughness': floatField(toughness),
    'knockback_resistance': floatField(knockbackResistance),
    'repair_items': '#$repairItems',
    'asset_id': assetId,
  };
}

/// One attribute modifier of the `minecraft:attribute_modifiers` component.
Json attributeModifier({
  required String attribute,
  required String id,
  required double amount,
  String operation = 'add_value',
  required String slot,
}) => {
  'type': attribute,
  'id': id,
  'amount': amount,
  'operation': operation,
  'slot': slot,
};

/// The `damage_per_block` and `can_destroy_blocks_in_creative` of vanilla's
/// `MaceItem.createToolProperties()`: no rules, 2 durability per block, and
/// creative players cannot break blocks with it.
Json maceToolProperties() => {
  'rules': <Object?>[],
  'damage_per_block': 2,
  'can_destroy_blocks_in_creative': false,
};

/// `new Weapon(itemDamagePerAttack)`; the codec omits the default of 1.
Json weapon(int itemDamagePerAttack, {double disableBlockingSeconds = 0}) => {
  if (itemDamagePerAttack != 1) 'item_damage_per_attack': itemDamagePerAttack,
  if (disableBlockingSeconds != 0)
    'disable_blocking_for_seconds': floatField(disableBlockingSeconds),
};

/// `net.minecraft.world.item.Item.Properties` as far as the mod uses it. All
/// the state is the default component map the finished item gets.
final class ItemProperties {
  /// The item's own id, `namespace:path`.
  final String id;

  final Json components;

  /// `Item.Properties` defaults: what every item has before a builder runs.
  ItemProperties(this.id)
    : components = {
        'minecraft:lore': <Object?>[],
        'minecraft:interact_animation': <String, Object?>{},
        'minecraft:repair_cost': 0,
        'minecraft:item_model': id,
        'minecraft:break_sound': 'minecraft:entity.item.break',
        'minecraft:tooltip_display': <String, Object?>{},
        'minecraft:use_effects': <String, Object?>{},
        'minecraft:item_name': {'translate': _descriptionKey('item', id)},
        'minecraft:attribute_modifiers': <Object?>[],
        'minecraft:rarity': 'common',
        'minecraft:attack_animation': <String, Object?>{},
        'minecraft:max_stack_size': 64,
        'minecraft:enchantments': <String, Object?>{},
      };

  static String _descriptionKey(String kind, String id) {
    final [namespace, path] = id.split(':');
    return '$kind.$namespace.${path.replaceAll('/', '.')}';
  }

  /// `useBlockDescriptionPrefix()`: the name is the block's translation key.
  void useBlockDescriptionPrefix() {
    components['minecraft:item_name'] = {
      'translate': _descriptionKey('block', id),
    };
  }

  void rarity(String name) => components['minecraft:rarity'] = name;

  /// `durability(n)`: also makes the item unstackable.
  void durability(int uses) {
    components['minecraft:max_damage'] = uses;
    components['minecraft:max_stack_size'] = 1;
    components['minecraft:damage'] = 0;
  }

  void repairable(String tag) =>
      components['minecraft:repairable'] = {'items': '#$tag'};

  void enchantable(int value) =>
      components['minecraft:enchantable'] = {'value': value};

  void attributes(List<Json> modifiers) =>
      components['minecraft:attribute_modifiers'] = modifiers;

  void component(String key, Object? value) => components[key] = value;

  // -- Tools ------------------------------------------------------------------

  /// What pickaxe/axe/shovel/hoe share: `ToolMaterial#applyToolProperties`.
  void _tool(
    ToolMaterialSpec material,
    String mineableTag,
    double attackDamage,
    double attackSpeed, {
    required Json weaponComponent,
    String? transformer,
  }) {
    durability(material.durability);
    repairable(material.repairItems);
    enchantable(material.enchantmentValue);
    components['minecraft:tool'] = {
      'rules': [
        {
          'blocks': '#${material.incorrectBlocksForDrops}',
          'correct_for_drops': false,
        },
        {
          'blocks': '#$mineableTag',
          'speed': floatField(material.speed),
          'correct_for_drops': true,
        },
      ],
    };
    components['minecraft:weapon'] = weaponComponent;
    if (transformer != null) {
      components['minecraft:block_transformer'] = transformer;
    }
    attributes(_meleeAttributes(
      toFloat32(toFloat32(attackDamage) + toFloat32(material.attackDamageBonus)),
      toFloat32(attackSpeed),
    ));
  }

  static List<Json> _meleeAttributes(double damage, double speed) => [
    attributeModifier(
      attribute: 'minecraft:attack_damage',
      id: 'minecraft:base_attack_damage',
      amount: damage,
      slot: 'mainhand',
    ),
    attributeModifier(
      attribute: 'minecraft:attack_speed',
      id: 'minecraft:base_attack_speed',
      amount: speed,
      slot: 'mainhand',
    ),
  ];

  void pickaxe(ToolMaterialSpec m, double damage, double speed) => _tool(
    m,
    'minecraft:mineable/pickaxe',
    damage,
    speed,
    weaponComponent: weapon(2),
  );

  void axe(ToolMaterialSpec m, double damage, double speed) => _tool(
    m,
    'minecraft:mineable/axe',
    damage,
    speed,
    weaponComponent: weapon(2, disableBlockingSeconds: 5),
    transformer: 'minecraft:axe',
  );

  void shovel(ToolMaterialSpec m, double damage, double speed) => _tool(
    m,
    'minecraft:mineable/shovel',
    damage,
    speed,
    weaponComponent: weapon(2),
    transformer: 'minecraft:shovel',
  );

  void hoe(ToolMaterialSpec m, double damage, double speed) => _tool(
    m,
    'minecraft:mineable/hoe',
    damage,
    speed,
    weaponComponent: weapon(2),
    transformer: 'minecraft:hoe',
  );

  /// Swords mine cobwebs and bamboo-like blocks fast instead of having a
  /// per-tier rule set; the speed of the material does not matter.
  void sword(ToolMaterialSpec m, double damage, double speed) {
    durability(m.durability);
    repairable(m.repairItems);
    enchantable(m.enchantmentValue);
    components['minecraft:tool'] = {
      'rules': [
        {
          'blocks': 'minecraft:cobweb',
          'speed': 15.0,
          'correct_for_drops': true,
        },
        {'blocks': '#minecraft:sword_instantly_mines', 'speed': 3.4028235e+38},
        {'blocks': '#minecraft:sword_efficient', 'speed': 1.5},
      ],
      'damage_per_block': 2,
      'can_destroy_blocks_in_creative': false,
    };
    components['minecraft:weapon'] = weapon(1);
    attributes(_meleeAttributes(
      toFloat32(toFloat32(damage) + toFloat32(m.attackDamageBonus)),
      toFloat32(speed),
    ));
  }

  /// `Item.Properties#spear(material, swing, damageMultiplier, delay,
  /// dismountTime, dismountSpeed, knockbackTime, knockbackSpeed, damageTime,
  /// damageRelativeSpeed)`. Times are in seconds and become ticks (x20, cut
  /// to an int).
  void spear(
    ToolMaterialSpec m, {
    required double swingSeconds,
    required double damageMultiplier,
    required double delaySeconds,
    required double dismountSeconds,
    required double dismountSpeed,
    required double knockbackSeconds,
    required double knockbackSpeed,
    required double damageSeconds,
    required double damageRelativeSpeed,
  }) {
    durability(m.durability);
    repairable(m.repairItems);
    enchantable(m.enchantmentValue);
    final sound = m.woodSounds ? 'minecraft:item.spear_wood' : 'minecraft:item.spear';
    components['minecraft:weapon'] = weapon(1);
    components['minecraft:damage_type'] = 'minecraft:spear';
    components['minecraft:minimum_attack_charge'] = 1.0;
    components['minecraft:piercing_weapon'] = {
      'sound': '$sound.attack',
      'hit_sound': '$sound.hit',
    };
    components['minecraft:kinetic_weapon'] = {
      'delay_ticks': ticks(delaySeconds),
      'dismount_conditions': {
        'max_duration_ticks': ticks(dismountSeconds),
        'min_speed': floatField(dismountSpeed),
      },
      'knockback_conditions': {
        'max_duration_ticks': ticks(knockbackSeconds),
        'min_speed': floatField(knockbackSpeed),
      },
      'damage_conditions': {
        'max_duration_ticks': ticks(damageSeconds),
        'min_relative_speed': floatField(damageRelativeSpeed),
      },
      'forward_movement': 0.38,
      'damage_multiplier': floatField(damageMultiplier),
      'sound': '$sound.use',
      'hit_sound': '$sound.hit',
    };
    components['minecraft:use_effects'] = {
      'can_sprint': true,
      'interact_vibrations': false,
      'speed_multiplier': 1.0,
    };
    components['minecraft:attack_range'] = {
      'min_reach': 2.0,
      'max_reach': 4.5,
      'min_creative_reach': 2.0,
      'max_creative_reach': 6.5,
      'hitbox_margin': 0.125,
      'mob_factor': 0.5,
    };
    components['minecraft:attack_animation'] = {
      'type': 'stab',
      'duration': ticks(swingSeconds),
    };
    attributes(_meleeAttributes(
      toFloat32(m.attackDamageBonus),
      // A float division widened to double before the subtraction.
      toFloat32(1.0 / toFloat32(swingSeconds)) - 4.0,
    ));
  }

  /// `humanoidArmor(material, type)`.
  void humanoidArmor(ArmorMaterialSpec m, ArmorType type) {
    durability(m.durability * type.durabilityMultiplier);
    repairable(m.repairItems);
    enchantable(m.enchantmentValue);
    components['minecraft:equippable'] = {
      'slot': type.slot,
      'equip_sound': m.equipSound,
      'asset_id': m.assetId,
    };
    final id = 'minecraft:armor.${type.typeName}';
    attributes([
      attributeModifier(
        attribute: 'minecraft:armor',
        id: id,
        amount: m.defense[type]!.toDouble(),
        slot: type.slot,
      ),
      attributeModifier(
        attribute: 'minecraft:armor_toughness',
        id: id,
        amount: toFloat32(m.toughness),
        slot: type.slot,
      ),
      if (m.knockbackResistance > 0)
        attributeModifier(
          attribute: 'minecraft:knockback_resistance',
          id: id,
          amount: toFloat32(m.knockbackResistance),
          slot: type.slot,
        ),
    ]);
  }
}

/// Seconds to ticks the way vanilla does it: a float product cut to an int.
int ticks(double seconds) => toFloat32(toFloat32(seconds) * 20).truncate();

/// The vanilla tool tiers (`ToolMaterial`), for the verification and for
/// materials the mod derives from them (`ToolMaterial.NETHERITE.incorrectBlocksForDrops()`).
const vanillaToolMaterials = <String, ToolMaterialSpec>{
  'wooden': ToolMaterialSpec(
    incorrectBlocksForDrops: 'minecraft:incorrect_for_wooden_tool',
    durability: 59,
    speed: 2,
    attackDamageBonus: 0,
    enchantmentValue: 15,
    repairItems: 'minecraft:wooden_tool_materials',
    woodSounds: true,
  ),
  'stone': ToolMaterialSpec(
    incorrectBlocksForDrops: 'minecraft:incorrect_for_stone_tool',
    durability: 131,
    speed: 4,
    attackDamageBonus: 1,
    enchantmentValue: 5,
    repairItems: 'minecraft:stone_tool_materials',
  ),
  'copper': ToolMaterialSpec(
    incorrectBlocksForDrops: 'minecraft:incorrect_for_copper_tool',
    durability: 190,
    speed: 5,
    attackDamageBonus: 1,
    enchantmentValue: 13,
    repairItems: 'minecraft:copper_tool_materials',
  ),
  'iron': ToolMaterialSpec(
    incorrectBlocksForDrops: 'minecraft:incorrect_for_iron_tool',
    durability: 250,
    speed: 6,
    attackDamageBonus: 2,
    enchantmentValue: 14,
    repairItems: 'minecraft:iron_tool_materials',
  ),
  'golden': ToolMaterialSpec(
    incorrectBlocksForDrops: 'minecraft:incorrect_for_gold_tool',
    durability: 32,
    speed: 12,
    attackDamageBonus: 0,
    enchantmentValue: 22,
    repairItems: 'minecraft:gold_tool_materials',
  ),
  'diamond': ToolMaterialSpec(
    incorrectBlocksForDrops: 'minecraft:incorrect_for_diamond_tool',
    durability: 1561,
    speed: 8,
    attackDamageBonus: 3,
    enchantmentValue: 10,
    repairItems: 'minecraft:diamond_tool_materials',
  ),
  'netherite': ToolMaterialSpec(
    incorrectBlocksForDrops: 'minecraft:incorrect_for_netherite_tool',
    durability: 2031,
    speed: 9,
    attackDamageBonus: 4,
    enchantmentValue: 15,
    repairItems: 'minecraft:netherite_tool_materials',
  ),
};

/// The `ToolMaterial` constants the mod can name, mapped to the tag
/// `incorrectBlocksForDrops()` returns for them.
const vanillaIncorrectTags = <String, String>{
  'WOOD': 'minecraft:incorrect_for_wooden_tool',
  'STONE': 'minecraft:incorrect_for_stone_tool',
  'COPPER': 'minecraft:incorrect_for_copper_tool',
  'IRON': 'minecraft:incorrect_for_iron_tool',
  'GOLD': 'minecraft:incorrect_for_gold_tool',
  'DIAMOND': 'minecraft:incorrect_for_diamond_tool',
  'NETHERITE': 'minecraft:incorrect_for_netherite_tool',
};

/// Vanilla armor tiers that have no extra components, for the verification.
const vanillaArmorMaterials = <String, ArmorMaterialSpec>{
  'iron': ArmorMaterialSpec(
    durability: 15,
    defense: {
      ArmorType.helmet: 2,
      ArmorType.chestplate: 6,
      ArmorType.leggings: 5,
      ArmorType.boots: 2,
    },
    enchantmentValue: 9,
    equipSound: 'minecraft:item.armor.equip_iron',
    toughness: 0,
    knockbackResistance: 0,
    repairItems: 'minecraft:repairs_iron_armor',
    assetId: 'minecraft:iron',
  ),
  'golden': ArmorMaterialSpec(
    durability: 7,
    defense: {
      ArmorType.helmet: 2,
      ArmorType.chestplate: 5,
      ArmorType.leggings: 3,
      ArmorType.boots: 1,
    },
    enchantmentValue: 25,
    equipSound: 'minecraft:item.armor.equip_gold',
    toughness: 0,
    knockbackResistance: 0,
    repairItems: 'minecraft:repairs_gold_armor',
    assetId: 'minecraft:gold',
  ),
  'diamond': ArmorMaterialSpec(
    durability: 33,
    defense: {
      ArmorType.helmet: 3,
      ArmorType.chestplate: 8,
      ArmorType.leggings: 6,
      ArmorType.boots: 3,
    },
    enchantmentValue: 10,
    equipSound: 'minecraft:item.armor.equip_diamond',
    toughness: 2,
    knockbackResistance: 0,
    repairItems: 'minecraft:repairs_diamond_armor',
    assetId: 'minecraft:diamond',
  ),
  'netherite': ArmorMaterialSpec(
    durability: 37,
    defense: {
      ArmorType.helmet: 3,
      ArmorType.chestplate: 8,
      ArmorType.leggings: 6,
      ArmorType.boots: 3,
    },
    enchantmentValue: 15,
    equipSound: 'minecraft:item.armor.equip_netherite',
    toughness: 3,
    knockbackResistance: 0.1,
    repairItems: 'minecraft:repairs_netherite_armor',
    assetId: 'minecraft:netherite',
  ),
};
