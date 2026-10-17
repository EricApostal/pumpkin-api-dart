// Approximations of vanilla game data the turtle commands need and the host
// does not expose to plugins (docs/host-requirements.md, "Turtles"):
//
// * fuel values: `FurnaceRefuelHandler` computes `burnTime * 5 / 100` from the
//   item's `cooking_fuel` component; the host has no such query, so this is a
//   table of the vanilla burn times (`FuelValues.vanillaBurnTimes`);
// * block drops: a turtle's `dig` collects what `Block.getDrops` returns for the
//   block and the tool; the host has no loot query for vanilla blocks, so
//   [blockDrops] returns the block's item with a table of the common
//   exceptions (stone gives cobblestone, ores give their raw item, ...);
// * block tags: `computercraft:turtle_{hoe,shovel,sword}_harvestable` include
//   vanilla tags (`#minecraft:mineable/hoe`, `#minecraft:wool`, ...) the host
//   cannot read; [turtleToolBreaks] approximates them with block names.
//
// Everything here is a best effort and says so; the real values are in the
// game's data pack.
import 'stack.dart';
import 'world.dart';

// -- Fuel ---------------------------------------------------------------------------

/// The furnace burn time of [item] in ticks (0 if it is not a fuel).
int burnTimeOf(String item) {
  final name = item.startsWith('minecraft:') ? item.substring(10) : item;
  const exact = <String, int>{
    'lava_bucket': 20000,
    'coal_block': 16000,
    'dried_kelp_block': 4001,
    'blaze_rod': 2400,
    'coal': 1600,
    'charcoal': 1600,
    'stick': 100,
    'bamboo': 50,
    'scaffolding': 50,
    'bowl': 100,
    'bow': 300,
    'crossbow': 300,
    'fishing_rod': 300,
    'ladder': 300,
    'chest': 300,
    'trapped_chest': 300,
    'barrel': 300,
    'crafting_table': 300,
    'bookshelf': 300,
    'lectern': 300,
    'loom': 300,
    'composter': 300,
    'note_block': 300,
    'jukebox': 300,
    'daylight_detector': 300,
    'cartography_table': 300,
    'fletching_table': 300,
    'smithing_table': 300,
    'dead_bush': 100,
    'wooden_pickaxe': 200,
    'wooden_axe': 200,
    'wooden_shovel': 200,
    'wooden_hoe': 200,
    'wooden_sword': 200,
    'shield': 300,
    'mangrove_roots': 300,
  };
  final known = exact[name];
  if (known != null) return known;
  if (name.contains('crimson') || name.contains('warped')) return 0;
  if (name.endsWith('_planks') || name.endsWith('_log') || name.endsWith('_wood') || name == 'bamboo_block' || name == 'bamboo_mosaic') {
    return 300;
  }
  if (name.endsWith('_stairs') && !_isStone(name) || name.endsWith('_fence') || name.endsWith('_fence_gate') ||
      name.endsWith('_trapdoor') || name.endsWith('_pressure_plate') && !_isStone(name)) {
    return 300;
  }
  if (name.endsWith('_slab') && !_isStone(name)) return 150;
  if (name.endsWith('_door') && !name.startsWith('iron')) return 200;
  if (name.endsWith('_sign') || name.endsWith('_hanging_sign')) return 200;
  if (name.endsWith('_button') && !_isStone(name)) return 100;
  if (name.endsWith('_boat') || name.endsWith('_raft') || name.endsWith('_chest_boat') || name.endsWith('_chest_raft')) return 1200;
  if (name.endsWith('_sapling') || name == 'azalea' || name == 'flowering_azalea') return 100;
  if (name.endsWith('_wool')) return 100;
  if (name.endsWith('_carpet') && !name.contains('moss')) return 67;
  if (name.endsWith('_banner')) return 300;
  return 0;
}

bool _isStone(String name) =>
    name.contains('stone') ||
    name.contains('brick') ||
    name.contains('cobble') ||
    name.contains('deepslate') ||
    name.contains('tuff') ||
    name.contains('copper') ||
    name.contains('quartz') ||
    name.contains('sandstone') ||
    name.contains('prismarine') ||
    name.contains('blackstone') ||
    name.contains('purpur') ||
    name.contains('granite') ||
    name.contains('diorite') ||
    name.contains('andesite') ||
    name.contains('mud') ||
    name.contains('resin') ||
    name.contains('polished') ||
    name.contains('iron') ||
    name.contains('gold') ||
    name.contains('netherite') ||
    name.contains('smooth') ||
    name.contains('cut_') ||
    name.contains('end_') ||
    name.contains('nether') ||
    name.contains('crimson') ||
    name.contains('warped') ||
    name.contains('prismarine') ||
    name.contains('weighted');

/// The fuel a turtle gets from one [item]: `burnTime * 5 / 100`.
int fuelPerItem(String item) => (burnTimeOf(item) * 5) ~/ 100;

/// What an item leaves behind when it is used up as fuel
/// (`getCraftingRemainingItem`), or null.
String? fuelRemainder(String item) => item == 'minecraft:lava_bucket' ? 'minecraft:bucket' : null;

// -- Block drops -----------------------------------------------------------------------

String _bare(String key) => key.startsWith('minecraft:') ? key.substring(10) : key;

/// What breaking [block] gives a turtle with a tool (an approximation of
/// `Block.getDrops`): the block's own item unless the block drops something
/// else or nothing.
List<TurtleStack> blockDrops(BlockInfo block) {
  if (block.isAir || block.isLiquid) return const [];
  final name = _bare(block.name);
  TurtleStack one(String item, [int count = 1]) => TurtleStack('minecraft:$item', count);

  const nothing = {
    'glass', 'glass_pane', 'tinted_glass', 'ice', 'packed_ice', 'blue_ice', 'spawner', 'trial_spawner', 'budding_amethyst',
    'tall_grass', 'short_grass', 'grass', 'fern', 'large_fern', 'seagrass', 'tall_seagrass', 'vine', 'kelp_plant', 'fire',
    'soul_fire', 'light', 'barrier', 'structure_void', 'moving_piston', 'bubble_column', 'frogspawn', 'infested_stone',
    'infested_cobblestone', 'infested_stone_bricks', 'infested_deepslate', 'sculk_vein',
  };
  if (nothing.contains(name) || name.endsWith('_stained_glass') || name.endsWith('_stained_glass_pane') || name.endsWith('_leaves')) {
    return const [];
  }
  if (name.endsWith('_wall_sign') || name.endsWith('_wall_hanging_sign')) return const [];

  switch (name) {
    case 'stone':
      return [one('cobblestone')];
    case 'deepslate':
      return [one('cobbled_deepslate')];
    case 'grass_block':
    case 'mycelium':
    case 'podzol':
    case 'dirt_path':
    case 'farmland':
    case 'rooted_dirt':
      return [one('dirt')];
    case 'coal_ore':
    case 'deepslate_coal_ore':
      return [one('coal')];
    case 'iron_ore':
    case 'deepslate_iron_ore':
      return [one('raw_iron')];
    case 'copper_ore':
    case 'deepslate_copper_ore':
      return [one('raw_copper', 3)];
    case 'gold_ore':
    case 'deepslate_gold_ore':
      return [one('raw_gold')];
    case 'diamond_ore':
    case 'deepslate_diamond_ore':
      return [one('diamond')];
    case 'emerald_ore':
    case 'deepslate_emerald_ore':
      return [one('emerald')];
    case 'lapis_ore':
    case 'deepslate_lapis_ore':
      return [one('lapis_lazuli', 6)];
    case 'redstone_ore':
    case 'deepslate_redstone_ore':
      return [one('redstone', 4)];
    case 'nether_gold_ore':
      return [one('gold_nugget', 4)];
    case 'nether_quartz_ore':
      return [one('quartz')];
    case 'ancient_debris':
      return [one('ancient_debris')];
    case 'clay':
      return [one('clay_ball', 4)];
    case 'snow_block':
      return [one('snowball', 4)];
    case 'snow':
      return [one('snowball', int.tryParse(block.properties['layers'] ?? '1') ?? 1)];
    case 'glowstone':
      return [one('glowstone_dust', 3)];
    case 'sea_lantern':
      return [one('prismarine_crystals', 3)];
    case 'melon':
      return [one('melon_slice', 5)];
    case 'bookshelf':
      return [one('book', 3)];
    case 'ender_chest':
      return [one('obsidian', 8)];
    case 'wheat':
      return block.properties['age'] == '7' ? [one('wheat'), one('wheat_seeds')] : [one('wheat_seeds')];
    case 'carrots':
      return [one('carrot', block.properties['age'] == '7' ? 3 : 1)];
    case 'potatoes':
      return [one('potato', block.properties['age'] == '7' ? 3 : 1)];
    case 'beetroots':
      return block.properties['age'] == '3' ? [one('beetroot'), one('beetroot_seeds')] : [one('beetroot_seeds')];
    case 'nether_wart':
      return [one('nether_wart', block.properties['age'] == '3' ? 3 : 1)];
    case 'cocoa':
      return [one('cocoa_beans', block.properties['age'] == '2' ? 3 : 1)];
    case 'sweet_berry_bush':
      return (int.tryParse(block.properties['age'] ?? '0') ?? 0) >= 2 ? [one('sweet_berries', 2)] : const [];
    case 'redstone_wire':
      return [one('redstone')];
    case 'tripwire':
      return [one('string')];
    case 'water_cauldron':
    case 'lava_cauldron':
    case 'powder_snow_cauldron':
      return [one('cauldron')];
    case 'big_dripleaf_stem':
      return [one('big_dripleaf')];
    case 'cave_vines':
    case 'cave_vines_plant':
      return const [];
  }
  if (name.endsWith('_slab') && block.properties['type'] == 'double') {
    return [TurtleStack(block.itemKey ?? block.name, 2)];
  }
  final item = block.itemKey;
  if (item == null) return const [];
  return [TurtleStack(item, 1)];
}

// -- Tool tags -------------------------------------------------------------------------

/// Whether a tool with the `breakable` tag [tag] may break [block]
/// (`computercraft:turtle_hoe_harvestable`, `..._shovel_...`, `..._sword_...`):
/// an approximation by block name of the tags, which include vanilla tags. Any
/// block with hardness 0 ("instabreak") is breakable by every tool anyway
/// (`TurtleTool.isTriviallyBreakable`); that check is the caller's.
bool turtleToolBreaks(String tag, BlockInfo block) {
  final name = _bare(block.name);
  switch (tag) {
    case 'computercraft:turtle_hoe_harvestable':
      return _hoeBlocks.contains(name) || name.endsWith('_leaves') || name.endsWith('_wart_block') || name.endsWith('_carpet') && name.contains('moss');
    case 'computercraft:turtle_shovel_harvestable':
      return _shovelBlocks.contains(name) || name.endsWith('_concrete_powder');
    case 'computercraft:turtle_sword_harvestable':
      return name.endsWith('_wool') || name == 'cobweb' || name == 'bamboo' || name == 'bamboo_sapling';
  }
  return true;
}

const Set<String> _hoeBlocks = {
  // #minecraft:crops
  'wheat', 'carrots', 'potatoes', 'beetroots', 'melon_stem', 'pumpkin_stem', 'attached_melon_stem', 'attached_pumpkin_stem',
  'torchflower_crop', 'pitcher_crop',
  // #minecraft:mineable/hoe (the common ones)
  'hay_block', 'sponge', 'wet_sponge', 'moss_block', 'shroomlight', 'target', 'sculk', 'sculk_catalyst', 'sculk_sensor',
  'sculk_shrieker', 'sculk_vein', 'dried_kelp_block', 'nether_wart', 'nether_wart_block', 'warped_wart_block',
  // the ones the tag lists itself
  'cactus', 'melon', 'pumpkin', 'carved_pumpkin', 'jack_o_lantern',
};

const Set<String> _shovelBlocks = {
  // #minecraft:mineable/shovel
  'dirt', 'grass_block', 'podzol', 'mycelium', 'coarse_dirt', 'rooted_dirt', 'farmland', 'dirt_path', 'sand', 'red_sand',
  'gravel', 'clay', 'snow', 'snow_block', 'powder_snow', 'soul_sand', 'soul_soil', 'mud', 'muddy_mangrove_roots',
  'suspicious_sand', 'suspicious_gravel',
  // the ones the tag lists itself
  'melon', 'pumpkin', 'carved_pumpkin', 'jack_o_lantern',
};

/// `computercraft:turtle_always_breakable` (any tool breaks them): the leaves,
/// bamboo and bamboo saplings (`data/computercraft/tags/block/
/// turtle_always_breakable.json`).
bool turtleAlwaysBreakable(BlockInfo block) {
  final name = _bare(block.name);
  return name.endsWith('_leaves') || name == 'bamboo' || name == 'bamboo_sapling';
}

// -- Attack damage ------------------------------------------------------------------------

/// The attack damage a player gets with [item] in the main hand (the
/// `ATTACK_DAMAGE` attribute: 1 for a fist plus the tool's modifier), which a
/// turtle multiplies by the tool's `damageMultiplier`. The vanilla tool
/// values of 1.21; 1 for anything else.
double toolAttackDamage(String item) {
  final name = _bare(item);
  const tiers = ['wooden', 'golden', 'stone', 'iron', 'diamond', 'netherite'];
  const bonus = {'wooden': 0.0, 'golden': 0.0, 'stone': 1.0, 'iron': 2.0, 'diamond': 3.0, 'netherite': 4.0};
  for (final tier in tiers) {
    if (!name.startsWith('${tier}_')) continue;
    final tool = name.substring(tier.length + 1);
    final extra = bonus[tier]!;
    switch (tool) {
      case 'sword':
        return 4 + extra;
      case 'axe':
        return switch (tier) {
          'wooden' || 'golden' => 7,
          'netherite' => 10,
          _ => 9,
        };
      case 'pickaxe':
        return 2 + extra;
      case 'shovel':
        return 2.5 + extra;
      case 'hoe':
        return 1;
    }
  }
  return 1;
}
