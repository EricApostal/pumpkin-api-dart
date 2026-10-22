// The plain materials of Create (`AllBlocks` ores and storage blocks, `AllItems` ingredients):
// the blocks and items no content package owns. They carry no behaviour, apart from the experience
// nugget's use (`experience_nugget_host.dart`); the data pack ships their loot tables and recipes.
// Pure: the module builds the blocks from the manifest.
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../manifest/manifest.dart';

/// The material blocks (`AllBlocks`): the zinc ores, the storage blocks and the rose quartz set.
const List<String> materialBlockKeys = [
  'zinc_ore',
  'deepslate_zinc_ore',
  'raw_zinc_block',
  'zinc_block',
  'andesite_alloy_block',
  'industrial_iron_block',
  'weathered_iron_block',
  'brass_block',
  'experience_block',
  'rose_quartz_block',
  'rose_quartz_tiles',
  'small_rose_quartz_tiles',
];

/// The blocks whose drops come from their loot table (the ores).
const Set<String> materialLootTableBlocks = {'zinc_ore', 'deepslate_zinc_ore'};

/// The material items of `AllItems`: ingredients, sheets, nuggets and the legacy items.
const Set<String> materialItemKeys = {
  // ingredients
  'wheat_flour',
  'dough',
  'cinder_flour',
  'powdered_obsidian',
  'sturdy_sheet',
  'propeller',
  'whisk',
  'brass_hand',
  'crafter_slot_cover',
  'electron_tube',
  'transmitter',
  'pulp',
  'precision_mechanism',
  'cardboard',
  'rose_quartz',
  'polished_rose_quartz',
  // blaze cakes and food
  'blaze_cake_base',
  'blaze_cake',
  'creative_blaze_cake',
  'bar_of_chocolate',
  'sweet_roll',
  'chocolate_glazed_berries',
  'honeyed_apple',
  // metals
  'raw_zinc',
  'andesite_alloy',
  'zinc_ingot',
  'brass_ingot',
  'copper_nugget',
  'zinc_nugget',
  'brass_nugget',
  'copper_sheet',
  'brass_sheet',
  'iron_sheet',
  'golden_sheet',
  'crushed_raw_iron',
  'crushed_raw_gold',
  'crushed_raw_copper',
  'crushed_raw_zinc',
  'experience_nugget',
  // the compat crushed ores of the other metals (`TagDependentIngredientItem`)
  'crushed_raw_osmium',
  'crushed_raw_platinum',
  'crushed_raw_silver',
  'crushed_raw_tin',
  'crushed_raw_lead',
  'crushed_raw_quicksilver',
  'crushed_raw_aluminum',
  'crushed_raw_uranium',
  'crushed_raw_nickel',
  // legacy
  'chromatic_compound',
  'shadow_steel',
  'refined_radiance',
};

/// The registrations of the material items, in manifest order.
///
/// The four food items get the `minecraft:food` component of their `AllItems` entry and the
/// `minecraft:consumable` that `Item.Properties#food` adds beside it; the blaze cakes'
/// `minecraft:cooking_fuel` is skipped (the host has no reader for it). The experience nugget gets
/// its foil (`minecraft:enchantment_glint_override`); its `use` is in `experience_nugget_host.dart`.
List<ItemRegistration> createMaterialItems() => [
  for (final m in kItems)
    if (materialItemKeys.contains(m.key)) materialItem(m),
];

/// Nutrition and saturation modifier of the food items (`FoodProperties` of the `AllItems`
/// entry). The manifest records the unchanged builder source, not the numbers.
const Map<String, (int, double)> _materialFoods = {
  'bar_of_chocolate': (6, 0.3), // AllItems.java:138 BAR_OF_CHOCOLATE
  'sweet_roll': (6, 0.8), // AllItems.java:146 SWEET_ROLL
  'chocolate_glazed_berries': (7, 0.8), // AllItems.java:153 CHOCOLATE_BERRIES
  'honeyed_apple': (8, 0.8), // AllItems.java:160 HONEYED_APPLE
};

/// Vanilla's `Consumables.DEFAULT_FOOD`, the consumable `Item.Properties#food` attaches: 1.6 s
/// (32 ticks) of eating with the eat sound and particles.
const Map<String, Object?> _defaultFoodConsumable = {
  'consume_seconds': 1.6,
  'animation': 'eat',
  'sound': 'minecraft:entity.generic.eat',
  'has_consume_particles': true,
};

/// The registration of one material item: its stack size, its rarity and, for food, what makes
/// it edible.
ItemRegistration materialItem(ManifestItem m) {
  final components = <String, Object?>{};
  if (m.rarity != 'COMMON') {
    components['minecraft:rarity'] = m.rarity.toLowerCase();
  }
  final food = _materialFoods[m.key];
  if (food != null) {
    components['minecraft:food'] = {
      'nutrition': food.$1,
      'saturation': food.$2,
      'can_always_eat': false,
    };
    components['minecraft:consumable'] = _defaultFoodConsumable;
  }
  final encoded = DataComponentCodec.encodeAll(components);
  final all = [...encoded.encoded];
  if (m.key == 'experience_nugget') {
    // `ExperienceNuggetItem.isFoil` returns true (`ExperienceNuggetItem.java:23-26`); in 1.21+ that
    // is the `minecraft:enchantment_glint_override` component. `DataComponentCodec` has no encoder
    // for it, but the host decodes it as one `bool`
    // (`crates/pumpkin-protocol/src/codec/data_component.rs:2078-2081`), the same byte
    // `ItemSpec.glint` writes (`item_builder.dart:238-239`), so it is added raw.
    all.add(
      EncodedComponent(
        'minecraft:enchantment_glint_override',
        PacketBuffer.encode((w) => w.writeBool(true)),
      ),
    );
  }
  return ItemRegistration(
    key: 'create:${m.key}',
    components: all,
    maxStackSize: m.maxStack,
  );
}

/// `ExperienceNuggetItem.use` (ExperienceNuggetItem.java:38): `Mth.ceil(3f * amountUsed)`.
///
/// `3f * amountUsed` is exact for every count a stack can have, so the ceiling is the integer
/// product; the port awards this many points for one activation (see [experienceNuggetOrbs]).
int experienceNuggetXp(int amountUsed) => 3 * amountUsed;

/// The values of the `ExperienceOrb`s `ExperienceNuggetItem.use` spawns for [amountUsed] nuggets
/// (ExperienceNuggetItem.java:37-48).
///
/// `total = ceil(3f * amountUsed)`, `maxOrbs` is 1 for a single nugget and 5 otherwise and
/// `valuePer = max(1, 1 + total ~/ maxOrbs)`; orb `i` is worth `min(valuePer, total - i * valuePer)`,
/// a value of zero meaning that no orb is spawned.
///
/// Java's loop only skips exact zeros, so when `total < maxOrbs * valuePer` its last term is
/// negative (two nuggets: `2, 2, 2, -2`); an orb of a non-positive value awards nothing when it is
/// picked up (`ExperienceOrb.playerTouch` gives the points only `if (remaining > 0)`,
/// `ExperienceOrb.java:288`, which the host mirrors at
/// `crates/pumpkin-core/src/entity/experience_orb.rs:121`). The values therefore stop at the first
/// non-positive one, and their sum is exactly [experienceNuggetXp] — the experience the player
/// gains in Java.
List<int> experienceNuggetOrbs(int amountUsed) {
  if (amountUsed < 1) return const [];
  final total = experienceNuggetXp(amountUsed);
  final maxOrbs = amountUsed == 1 ? 1 : 5;
  final valuePer = math.max(1, 1 + total ~/ maxOrbs);
  final values = <int>[];
  for (var i = 0; i < maxOrbs; i++) {
    final value = math.min(valuePer, total - i * valuePer);
    if (value <= 0) break;
    values.add(value);
  }
  return values;
}
