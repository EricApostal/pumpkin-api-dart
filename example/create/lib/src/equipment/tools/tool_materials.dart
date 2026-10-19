// `AllToolMaterials`: the 26.x `ToolMaterial` records Create's items are built with, and the
// components `Item.Properties.sword` derives from them. Pure: no host imports, so the numbers
// can be unit tested.
//
// Java references: `content/equipment/tool/AllToolMaterials.java` and
// `net.minecraft.world.item.ToolMaterial.applySwordProperties`.

/// A `ToolMaterial` record.
final class ToolMaterialData {
  /// `incorrectBlocksForDrops`: blocks this material cannot harvest (they drop nothing).
  final String incorrectBlocksForDrops;

  /// The item durability (0 means the item is not damageable).
  final int durability;

  /// `speed`: the mining speed of the material for tools that use the generic rules.
  final double speed;

  /// `attackDamageBonus`: added to the sword baseline attack damage.
  final double attackDamageBonus;

  /// `enchantmentValue`: the `minecraft:enchantable` value.
  final int enchantmentValue;

  /// `repairItems`: the item tag that repairs tools of this material.
  final String repairItems;

  const ToolMaterialData({
    required this.incorrectBlocksForDrops,
    required this.durability,
    required this.speed,
    required this.attackDamageBonus,
    required this.enchantmentValue,
    required this.repairItems,
  });

  /// `applySwordProperties`: the `minecraft:tool` component. The sword rules are fixed by
  /// vanilla (cobweb, instantly-mines, sword-efficient), independent of the material.
  Map<String, Object?> get swordToolComponent => {
    'rules': [
      {'blocks': 'minecraft:cobweb', 'speed': 15.0, 'correct_for_drops': true},
      {'blocks': '#minecraft:sword_instantly_mines', 'speed': floatMaxValue},
      {'blocks': '#minecraft:sword_efficient', 'speed': 1.5},
    ],
    'default_mining_speed': 1.0,
    'damage_per_block': 2,
    'can_destroy_blocks_in_creative': false,
  };

  /// `applySwordProperties`: the `minecraft:weapon` component (`new Weapon(1)`).
  static const Map<String, Object?> swordWeaponComponent = {'item_damage_per_attack': 1};

  /// `createSwordAttributes`: the `minecraft:attribute_modifiers` component (main hand). The
  /// host discards the value on registration, so this only documents the vanilla data; the
  /// server applies the same numbers itself where they matter.
  List<Map<String, Object?>> swordAttributeModifiers({
    double attackDamageBaseline = 3,
    double attackSpeedBaseline = 1,
  }) => [
    {
      'type': 'minecraft:attack_damage',
      'id': 'minecraft:base_attack_damage',
      'amount': attackDamageBaseline + attackDamageBonus,
      'operation': 'add_value',
      'slot': 'mainhand',
    },
    {
      'type': 'minecraft:attack_speed',
      'id': 'minecraft:base_attack_speed',
      'amount': attackSpeedBaseline,
      'operation': 'add_value',
      'slot': 'mainhand',
    },
  ];

  /// The components `Item.Properties.sword(material, 3, 1)` sets besides durability and the
  /// stack size. Durability 0 is not encodable (the host rejects `max_damage < 1`), which is
  /// also how the manifest represents a non-damageable item.
  Map<String, Object?> swordComponents({double attackDamageBaseline = 3, double attackSpeedBaseline = 1}) => {
    'minecraft:tool': swordToolComponent,
    'minecraft:weapon': swordWeaponComponent,
    'minecraft:attribute_modifiers': swordAttributeModifiers(
      attackDamageBaseline: attackDamageBaseline,
      attackSpeedBaseline: attackSpeedBaseline,
    ),
    'minecraft:repairable': {'items': repairItems},
  };
}

/// `Float.MAX_VALUE`, the speed of vanilla's `sword_instantly_mines` rule.
const double floatMaxValue = 3.4028234663852886e38;

/// `AllToolMaterials`.
abstract final class AllToolMaterials {
  /// `AllToolMaterials.CARDBOARD` (`new ToolMaterial(INCORRECT_FOR_WOODEN_TOOL, 0, 1, 2, 1,
  /// CARDBOARD_PLATES)`).
  static const ToolMaterialData cardboard = ToolMaterialData(
    incorrectBlocksForDrops: '#minecraft:incorrect_for_wooden_tool',
    durability: 0,
    speed: 1,
    attackDamageBonus: 2,
    enchantmentValue: 1,
    repairItems: '#c:plates/cardboard',
  );
}
