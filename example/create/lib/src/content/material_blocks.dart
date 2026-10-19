// The material blocks of `AllBlocks` as host block descriptions: the zinc ores, the storage
// blocks and the rose quartz set. Their recipes, tags and loot tables come from the data pack.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/blocks.dart';
import '../core/blocks.dart';
import 'material_content.dart';

/// The material blocks in manifest order (`AllBlocks.ZINC_ORE`, ... `SMALL_ROSE_QUARTZ_TILES`).
List<CreateBlock> createMaterialBlocks() => [
  for (final key in materialBlockKeys)
    manifestBlock(
      key,
      drops: materialLootTableBlocks.contains(key) ? lootTableOf(key) : null,
      // `RotatedPillarBlock` (rose quartz block): the axis follows the clicked face.
      placement:
          manifestBlocksByKey[key]!.properties.any((p) => p.name == 'axis')
          ? const [PlacementRule.clickedAxis('axis')]
          : const [],
    ),
];
