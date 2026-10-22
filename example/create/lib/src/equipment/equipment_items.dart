// Registration data of the equipment items from the manifest: stack size, durability, rarity,
// enchantability and the equippable slot of armor. Nothing is retyped: the numbers come from
// `kItems`; only what the manifest keeps as text (equippable slot, enchantment value) is mapped here.
//
// Only `pumpkin_api_core` is imported, so the registration of every item is unit tested on the
// plain VM; the entity type spec, which needs the host's `EntityTypeSpec`, lives in the module.
import 'package:pumpkin_api/pumpkin_api_core.dart';

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
/// (copper's for copper, leather's for cardboard, netherite's for netherite).
/// `GogglesItem` sets no sound, so it keeps the codec's generic default.
///
/// Copper's `create:copper_armor_equip` is a *wrapped* sound event whose only
/// entry is `minecraft:item.armor.equip_gold` (`AllSoundEvents.COPPER_ARMOR_EQUIP`,
/// `assets/create/sounds.json`). The plugin never registers sound events with
/// the host registry — [CreateSounds] only maps names onto vanilla events — so
/// the component must name the vanilla event the wrapper delegates to. The
/// audible result is identical; only the subtitle differs.
const Map<String, String> _equipSounds = {
  'copper_backtank': 'minecraft:item.armor.equip_gold',
  'copper_diving_helmet': 'minecraft:item.armor.equip_gold',
  'copper_diving_boots': 'minecraft:item.armor.equip_gold',
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
    // `CardboardSwordItem.java:43-45` restricts the sword to Knockback:
    // `supportsEnchantment` returns true only for `Enchantments.KNOCKBACK`. The host has no
    // per-item enchant gate (`minecraft:enchantable` is only the enchantability *value*, the
    // offers come from the enchantment's own `supported_items` tag), and the one hook the host
    // does offer is not enough to reproduce it:
    // - `cardboard_sword` is in no `minecraft:enchantable/*` tag - not in this port's tag
    //   manifest (only `minecraft:enchantable/bow` and `/durability` name Create items) nor in
    //   Create's Java datagen - so the host's offer generation
    //   (`pumpkin-inventory/src/enchanting/enchanting_screen_handler.rs:100-160`, which filters
    //   with `enchantment.can_enchant(item)`, i.e. the `supported_items` tag) offers the sword
    //   *nothing*; there is no offer to filter down to Knockback.
    // - `PrepareItemEnchantEventData.offers` (`events.g.dart`) carries three positional
    //   `EnchantmentOffer`s whose `enchantmentId` is a raw registry number (no `Enchantment`
    //   handle, `-1` meaning none), and the host writes the list back into its three slots
    //   (`pumpkin-wasm-host-v0_1/src/events/enchantment.rs:55-75`), so a handler could clear
    //   offers but not grant the Knockback offer Java grants - its level comes from the vanilla
    //   enchantability roll, which the host does not expose.
    // - The other half of `supportsEnchantment` (the anvil's book combining, per the comment at
    //   `CardboardSwordItem.java:47-48`) has no hook either: `prepare-anvil-event-data` carries
    //   only the rename text and the repair cost, and the host's `use_anvil` has no enchantment
    //   logic.
    // A host `ItemStack.supports-enchantment`-style check (or a per-item enchantment gate on
    // `item-definition`) would be the reproduction; until then the sword keeps the generic
    // enchantability of its Java properties and gets no table offers at all.
    components['minecraft:enchantable'] = {'value': 1};
  }
  if (path == 'builders_tea') {
    // `AllItems.BUILDERS_TEA`: `stacksTo(16)`, then
    // `food(nutrition 1, saturation .6, alwaysEdible)` with a consumable of
    // haste 3:00. `BuildersTeaItem` overrides the use duration to 42 ticks
    // (`getUseDuration`) and the animation to DRINK; the host takes both from
    // the component, so `consume_seconds` is 42/20. The sound stays vanilla's
    // `entity.generic.eat`, the one the item never overrides. The glass bottle
    // of `finishUsingItem` is granted by the module (`MiscItemsHost`), not here.
    components['minecraft:food'] = {
      'nutrition': 1,
      'saturation': 0.6,
      'can_always_eat': true,
    };
    components['minecraft:consumable'] = {
      'consume_seconds': 2.1,
      'animation': 'drink',
      'sound': 'minecraft:entity.generic.eat',
      'has_consume_particles': true,
      'on_consume_effects': [
        {
          'type': 'minecraft:apply_effects',
          'effects': [
            {
              'id': 'minecraft:haste',
              'amplifier': 0,
              'duration': 3 * 60 * 20,
              'ambient': false,
              'show_particles': false,
              'show_icon': false,
            },
          ],
          'probability': 1.0,
        },
      ],
    };
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
