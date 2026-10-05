/// The registry additions of Lonsdaleite
/// (<https://github.com/kestalkayden/Lonsdaleite>, CC0), the first mod this
/// library targets: NeoForge 26.3.0.7-beta, registers items, one block (and
/// its block item) and a creative tab with `DeferredRegister`. It has no
/// custom payloads, data components, registries or data maps, so the registry
/// synchronisation is all a server needs to do.
///
/// The names are in registration order (`Lonsdaleite.java`): that is the order
/// a NeoForge server numbers them after the vanilla entries.
library;

import 'pumpkin_neoforge_core.dart';

/// The mod id.
const String lonsdaleiteModId = 'lonsdaleite';

/// The block names (without namespace), in registration order.
const List<String> lonsdaleiteBlocks = ['lonsdaleite_wardframe'];

/// The wardframe's block state properties in the order that numbers its
/// states: sorted by name, the first the most significant, the last one
/// changing fastest, `true` before `false` (Java's `StateDefinition`; the
/// declaration order `north south east west up down` does not matter).
const List<String> lonsdaleiteWardframeStateProperties = [
  'down',
  'east',
  'north',
  'south',
  'up',
  'west',
];

/// The number of states of each block, by block name: the wardframe has six
/// boolean properties, so 64.
const Map<String, int> lonsdaleiteBlockStateCounts = {
  'lonsdaleite_wardframe': 64,
};

/// The state id of the first state of the mod's block number [blockIndex]
/// (registration order): a client numbers the states of the block registry by
/// walking it in id order, so the mod's blocks, appended after the vanilla
/// ones, start at [vanillaBlockStateCount] and follow each other.
int lonsdaleiteFirstStateId(int blockIndex) {
  var id = vanillaBlockStateCount;
  for (var i = 0; i < blockIndex; i++) {
    id += lonsdaleiteBlockStateCounts[lonsdaleiteBlocks[i]]!;
  }
  return id;
}

/// The item names (without namespace), in registration order. The first is the
/// block item of the block.
const List<String> lonsdaleiteItems = [
  'lonsdaleite_wardframe',
  'raw_lonsdaleite',
  'prepared_lonsdaleite',
  'refined_lonsdaleite',
  'perfect_lonsdaleite',
  'lonsdaleite_pickaxe',
  'perfect_lonsdaleite_pickaxe',
  'lonsdaleite_axe',
  'perfect_lonsdaleite_axe',
  'lonsdaleite_shovel',
  'perfect_lonsdaleite_shovel',
  'lonsdaleite_hoe',
  'perfect_lonsdaleite_hoe',
  'lonsdaleite_omnitool',
  'perfect_lonsdaleite_omnitool',
  'lonsdaleite_sword',
  'perfect_lonsdaleite_sword',
  'lonsdaleite_short_sword',
  'perfect_lonsdaleite_short_sword',
  'lonsdaleite_war_axe',
  'perfect_lonsdaleite_war_axe',
  'lonsdaleite_spear',
  'perfect_lonsdaleite_spear',
  'lonsdaleite_mace',
  'lonsdaleite_helmet',
  'lonsdaleite_chestplate',
  'lonsdaleite_leggings',
  'lonsdaleite_boots',
  'perfect_lonsdaleite_helmet',
  'perfect_lonsdaleite_chestplate',
  'perfect_lonsdaleite_leggings',
  'perfect_lonsdaleite_boots',
];

/// The creative mode tab. Tabs are not synchronised by NeoForge; they are
/// built by the client's own code.
const List<String> lonsdaleiteCreativeTabs = ['lonsdaleite'];

/// The server spec for Lonsdaleite: the vanilla item and block registries
/// (from Pumpkin's assets) with the mod's entries appended.
NeoForgeServerSpec lonsdaleiteSpec() => NeoForgeServerSpec.vanillaPlus(
  mods: const [
    NeoForgeModInfo(
      id: lonsdaleiteModId,
      version: '2.3.0',
      displayName: 'Lonsdaleite Tools',
    ),
  ],
  additions: {
    'minecraft:block': [
      for (final n in lonsdaleiteBlocks) '$lonsdaleiteModId:$n',
    ],
    'minecraft:item': [
      for (final n in lonsdaleiteItems) '$lonsdaleiteModId:$n',
    ],
  },
);
