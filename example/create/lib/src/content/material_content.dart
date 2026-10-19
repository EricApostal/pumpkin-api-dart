// The plain materials of Create (`AllBlocks` ores and storage blocks, `AllItems` ingredients):
// the blocks and items no content package owns. They carry no behaviour; the data pack ships
// their loot tables and recipes. Pure: the module builds the blocks from the manifest.
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
/// The host has no network reader for `minecraft:food`, so the four food items are registered
/// without it (they exist for recipes and storage but cannot be eaten yet); the blaze cakes'
/// `minecraft:cooking_fuel` is skipped for the same reason.
List<ItemRegistration> createMaterialItems() => [
  for (final m in kItems)
    if (materialItemKeys.contains(m.key)) materialItem(m),
];

/// The registration of one material item: its stack size and its rarity.
ItemRegistration materialItem(ManifestItem m) {
  final components = <String, Object?>{};
  if (m.rarity != 'COMMON') {
    components['minecraft:rarity'] = m.rarity.toLowerCase();
  }
  final encoded = DataComponentCodec.encodeAll(components);
  return ItemRegistration(
    key: 'create:${m.key}',
    components: encoded.encoded,
    maxStackSize: m.maxStack,
  );
}
