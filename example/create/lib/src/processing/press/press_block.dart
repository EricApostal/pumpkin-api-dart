// `MechanicalPressBlock`: the block, its shape and its placement rule. The press cannot be
// placed right above a basin (the operating machines need two blocks of space).
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/host_bridge.dart';
import '../../common/pos.dart' hide pos;
import '../basin/basin_block.dart';
import '../processing_runtime.dart';
import '../../core/blocks.dart';
import '../support/kinetics_bridge.dart';
import 'press_block_entity.dart';

/// `MechanicalPressBlock`.
abstract final class MechanicalPressBlock {
  static const String key = 'create:mechanical_press';

  /// `AllShapes.MECHANICAL_PROCESSOR_SHAPE`: a full block with a 8x8 shaft hole.
  static final BlockShape shape = BlockShape.boxes(const [
    BlockBox(0, 0, 0, 4 / 16, 1, 1),
    BlockBox(12 / 16, 0, 0, 1, 1, 1),
    BlockBox(4 / 16, 0, 0, 12 / 16, 1, 4 / 16),
    BlockBox(4 / 16, 0, 12 / 16, 12 / 16, 1, 1),
  ]);

  static CreateBlock build() => createBlockFromManifest(
    'mechanical_press',
    blockEntityType: MechanicalPressBlockEntity.type,
    // `HorizontalKineticBlock.getPreferredHorizontalFacing` inspects the neighbours' shafts;
    // the host's placement rules cannot, so the player-facing fallback is used.
    placement: const [PlacementRule.horizontalFacing('facing', opposite: true)],
    collisionShape: shape,
    selectionShape: shape,
    behavior: BlockBehavior(
      // `canSurvive`: no basin right below.
      onCanPlace: (server, e) => !BasinBlock.isBasin(
        ProcessingRuntime.instance.store,
        ProcessingRuntime.instance.worlds.touch(e.targetWorld),
        e.pos.toPos().below,
      ),
      isPathfindable: (server, e) => false,
    ),
  );
}
