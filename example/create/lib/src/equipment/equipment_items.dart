// Registration data of the equipment items from the manifest: stack size, durability, rarity,
// enchantability and the equippable slot of armor. Nothing is retyped: the numbers come from
// `kItems`; only what the manifest keeps as text (equippable slot, enchantment value) is mapped here.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../manifest/manifest.dart';

/// Items registered by this module (all but the block items of toolboxes, bells and the clipboard).
const List<String> equipmentItemKeys = [
  'builders_tea',
  'cardboard_sword',
  'goggles',
  'crafting_blueprint',
  'copper_backtank_placeable',
  'netherite_backtank_placeable',
  'copper_backtank',
  'netherite_backtank',
  'copper_diving_helmet',
  'netherite_diving_helmet',
  'copper_diving_boots',
  'netherite_diving_boots',
  'cardboard_helmet',
  'cardboard_chestplate',
  'cardboard_leggings',
  'cardboard_boots',
  'sand_paper',
  'red_sand_paper',
  'wrench',
  'potato_cannon',
  'extendo_grip',
  'wand_of_symmetry',
  'handheld_worldshaper',
  'tree_fertilizer',
];

/// (equipment slot, equipment asset id, enchantment value) of the wearables.
const Map<String, (String, String?, int)> _wearables = {
  'goggles': ('head', null, 0),
  'copper_backtank': ('chest', 'create:copper', 7),
  'netherite_backtank': ('chest', 'minecraft:netherite', 15),
  'copper_diving_helmet': ('head', 'create:copper', 7),
  'netherite_diving_helmet': ('head', 'minecraft:netherite', 15),
  'copper_diving_boots': ('feet', 'create:copper', 7),
  'netherite_diving_boots': ('feet', 'minecraft:netherite', 15),
  'cardboard_helmet': ('head', 'create:cardboard', 4),
  'cardboard_chestplate': ('chest', 'create:cardboard', 4),
  'cardboard_leggings': ('legs', 'create:cardboard', 4),
  'cardboard_boots': ('feet', 'create:cardboard', 4),
};

final Map<String, ManifestItem> _byKey = {for (final i in kItems) i.key: i};

/// The registration of the item `create:<path>`.
ItemRegistration equipmentItem(String path) {
  final m = _byKey[path] ?? (throw ArgumentError.value(path, 'path', 'not in the item manifest'));
  final components = <String, Object?>{};
  final durability = m.durability;
  if (durability != null && durability > 0) components['minecraft:max_damage'] = durability;
  if (m.rarity != 'COMMON') components['minecraft:rarity'] = m.rarity.toLowerCase();
  final w = _wearables[path];
  if (w != null) {
    components['minecraft:equippable'] = {
      'slot': w.$1,
      if (w.$2 != null) 'asset_id': w.$2,
    };
    if (w.$3 > 0) components['minecraft:enchantable'] = {'value': w.$3};
  }
  if (path == 'sand_paper' || path == 'red_sand_paper' || path == 'cardboard_sword') {
    components['minecraft:enchantable'] = {'value': 1};
  }
  final encoded = DataComponentCodec.encodeAll(components);
  return ItemRegistration(key: 'create:$path', components: encoded.encoded, maxStackSize: m.maxStack);
}

/// The entity type spec of `create:<path>` from the manifest.
EntityTypeSpec equipmentEntityType(String path) {
  final d = kEntityTypes.firstWhere((e) => e.key == path);
  return EntityTypeSpec(
    key: 'create:${d.key}',
    width: d.width,
    height: d.height,
    eyeHeight: d.eyeHeight,
    fireImmune: d.fireImmune,
    trackingRange: d.trackingRange,
    updateInterval: d.updateInterval.clamp(1, 1000),
    trackDeltas: d.sendVelocity,
    summonable: d.summonable,
    spawnDataChannel: d.complexSpawnData ? 'neoforge:advanced_add_entity' : null,
  );
}
