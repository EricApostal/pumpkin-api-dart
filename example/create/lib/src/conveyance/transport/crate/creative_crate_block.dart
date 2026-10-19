// `CreativeCrateBlock`: the crate shape and the facing rotation.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../api/blocks.dart';
import '../../../api/wrenchable.dart';
import '../../../core/block_entity.dart';
import '../../../core/registry.dart';
import '../../shapes.dart';
import '../transport_support.dart';
import 'creative_crate_block_entity.dart';

/// Phase 1: the creative crate block and its block entity.
void registerCrates(CreateRegistry registry) {
  final block = manifestBlock(
    'creative_crate',
    blockEntityType: 'create:creative_crate',
    collisionShape: BlockShape.boxes(crateShape),
    selectionShape: BlockShape.boxes(crateShape),
  );
  registry.block(block);
  transportBlocks[block.key] = block;
  registry.blockEntityType(
    BlockEntityTypeSpec(
      key: 'create:creative_crate',
      validBlocks: const ['create:creative_crate'],
      create: CreativeCrateBlockEntity.new,
      tickInterval: 0,
    ),
  );
}

/// Phase 3: the creative crate rotates like a directional block.
void registerCrateWrench(WrenchRegistry wrench) {
  wrench.registerDefault(const ['create:creative_crate']);
}
