// Registration data of the equipment items from the manifest: stack size, durability, rarity,
// enchantability and the equippable slot of armor. Nothing is retyped: the numbers come from
// `kItems`; only what the manifest keeps as text (equippable slot, enchantment value) is mapped here.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../manifest/manifest.dart';
import 'tools/tool_materials.dart';

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

/// Enchantments the item class reports without them being stored (`DivingHelmetItem` returns
/// Aqua Affinity level 1 from `getAllEnchantments`/`getEnchantmentLevel`).
const Map<String, Map<String, int>> _intrinsicEnchantments = {
  'copper_diving_helmet': {'minecraft:aqua_affinity': 1},
  'netherite_diving_helmet': {'minecraft:aqua_affinity': 1},
};

/// Durability the item class sets in Java but the manifest extractor does not record
/// (`ExtendoGripItem` calls `properties.durability(200)`).
const Map<String, int> _classDurability = {'extendo_grip': 200};

/// The `repairable` component of the armor items: `BaseArmorItem` uses the material's repair
/// ingredient. Copper and cardboard use Create's own tags; the netherite gear uses vanilla's.
const Map<String, String> _armorRepairTags = {
  'copper_backtank': '#c:ingots/copper',
  'copper_diving_helmet': '#c:ingots/copper',
  'copper_diving_boots': '#c:ingots/copper',
  'netherite_backtank': '#minecraft:repairs_netherite_armor',
  'netherite_diving_helmet': '#minecraft:repairs_netherite_armor',
  'netherite_diving_boots': '#minecraft:repairs_netherite_armor',
  'cardboard_helmet': '#c:plates/cardboard',
  'cardboard_chestplate': '#c:plates/cardboard',
  'cardboard_leggings': '#c:plates/cardboard',
  'cardboard_boots': '#c:plates/cardboard',
};

/// `Equippable#equipSound` of the wearables: `BaseArmorItem` copies it from the `ArmorMaterial`
/// (`create:copper_armor_equip` for copper, leather's for cardboard, netherite's for netherite).
/// `GogglesItem` sets no sound, so it keeps the codec's generic default.
const Map<String, String> _equipSounds = {
  'copper_backtank': 'create:copper_armor_equip',
  'copper_diving_helmet': 'create:copper_armor_equip',
  'copper_diving_boots': 'create:copper_armor_equip',
  'netherite_backtank': 'minecraft:item.armor.equip_netherite',
  'netherite_diving_helmet': 'minecraft:item.armor.equip_netherite',
  'netherite_diving_boots': 'minecraft:item.armor.equip_netherite',
  'cardboard_helmet': 'minecraft:item.armor.equip_leather',
  'cardboard_chestplate': 'minecraft:item.armor.equip_leather',
  'cardboard_leggings': 'minecraft:item.armor.equip_leather',
  'cardboard_boots': 'minecraft:item.armor.equip_leather',
};

final Map<String, ManifestItem> _byKey = {for (final i in kItems) i.key: i};

/// The registration of the item `create:<path>`.
ItemRegistration equipmentItem(String path) {
  final m = _byKey[path] ?? (throw ArgumentError.value(path, 'path', 'not in the item manifest'));
  final components = <String, Object?>{};
  final durability = m.durability;
  if (durability != null && durability > 0) {
    components['minecraft:max_damage'] = durability;
  } else {
    final extra = _classDurability[path];
    if (extra != null) components['minecraft:max_damage'] = extra;
  }
  if (m.rarity != 'COMMON') {
    components['minecraft:rarity'] = m.rarity.toLowerCase();
  }
  final w = _wearables[path];
  if (w != null) {
    components['minecraft:equippable'] = {
      'slot': w.$1,
      if (w.$2 != null) 'asset_id': w.$2,
      if (_equipSounds[path] != null) 'equip_sound': _equipSounds[path],
    };
    if (w.$3 > 0) components['minecraft:enchantable'] = {'value': w.$3};
  }
  final repair = _armorRepairTags[path];
  if (repair != null) components['minecraft:repairable'] = {'items': repair};
  final intrinsic = _intrinsicEnchantments[path];
  if (intrinsic != null) {
    components['minecraft:enchantments'] = {'levels': intrinsic, 'show_in_tooltip': true};
  }
  if (path == 'sand_paper' || path == 'red_sand_paper' || path == 'cardboard_sword') {
    components['minecraft:enchantable'] = {'value': 1};
  }
  if (path == 'cardboard_sword') {
    // `AllItems.CARDBOARD_SWORD`: `properties(p -> p.sword(AllToolMaterials.CARDBOARD, 3, 1))`.
    components.addAll(AllToolMaterials.cardboard.swordComponents());
  }
  final encoded = DataComponentCodec.encodeAll(components);
  final all = [...encoded.encoded];
  if (m.fireResistant) {
    // `Properties.fireResistant()` sets `DamageResistant(DamageTypeTags.IS_FIRE)`; its stream
    // codec is a holder set, so the tag is `0` followed by its name. The host knows the
    // component but `DataComponentCodec` has no encoder for it.
    all.add(
      EncodedComponent(
        'minecraft:damage_resistant',
        PacketBuffer.encode((w) {
          w.writeVarInt(0);
          w.writeString('minecraft:is_fire');
        }),
      ),
    );
  }
  // `Item.Properties.durability` also sets the max stack size to 1; the manifest records that
  // for the items whose extractor saw the call, and [_classDurability] covers the others.
  final maxStack = components.containsKey('minecraft:max_damage') ? 1 : m.maxStack;
  return ItemRegistration(key: 'create:$path', components: all, maxStackSize: maxStack);
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
