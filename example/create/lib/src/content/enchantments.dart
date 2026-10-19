// The two enchantments of Create (`AllEnchantments`).
import 'package:pumpkin_api/pumpkin_api.dart';

import 'enchantment_data.dart';

/// `create:potato_recovery`, `create:capacity`.
abstract final class CreateEnchantments {
  static const String potatoRecovery = 'create:potato_recovery';
  static const String capacity = 'create:capacity';

  /// The `CustomEnchantment` records for the registry, in registration order
  /// (`AllEnchantments.bootstrap`): weight 10, max level 3, anvil cost 1, mainhand.
  static List<CustomEnchantment> definitions() => [
    _def(potatoRecovery, 'enchantment.create.potato_recovery', 'create:potato_cannon'),
    _def(capacity, 'enchantment.create.capacity', '#create:pressurized_air_sources'),
  ];

  static CustomEnchantment _def(String id, String translationKey, String supportedItems) => CustomEnchantment(
    id: id,
    description: TextComponent.translate(key: translationKey, with_: const []),
    maxLevel: 3,
    anvilCost: 1,
    supportedItems: supportedItems,
    weight: 10,
    slots: const [AttributeModifierSlot.mainHand],
    exclusiveSet: const [],
  );

  /// `Enchantment.dynamicCost(15, 15)` / `dynamicCost(45, 15)`.
  static const int minCostBase = 15, minCostPerLevel = 15, maxCostBase = 45, maxCostPerLevel = 15;

  static List<int> potatoRecoveryAmmoUseNbt() => potatoRecoveryAmmoUse();

  /// Registers costs and effects with the host (after the enchantments exist).
  static Future<void> configure(Context context) async {
    final manager = context.getServer().getEnchantmentManager();
    for (final id in [potatoRecovery, capacity]) {
      await manager.setCosts(
        id,
        minBase: minCostBase,
        minPerLevel: minCostPerLevel,
        maxBase: maxCostBase,
        maxPerLevel: maxCostPerLevel,
      );
    }
    await manager.setEffects(potatoRecovery, [EnchantmentEffectSpec('minecraft:ammo_use', potatoRecoveryAmmoUseNbt())]);
  }

  /// `getEnchantmentLevel(POTATO_RECOVERY)` of a stack.
  static Future<int> potatoRecoveryLevel(ItemStack stack) => stack.enchantmentLevelOf(potatoRecovery);

  /// `getEnchantmentLevel(CAPACITY)` of a stack.
  static Future<int> capacityLevel(ItemStack stack) => stack.enchantmentLevelOf(capacity);
}
