// `MechanicalPressBlock`: the block, its shape and its placement rule. The press cannot be
// placed right above a basin (the operating machines need two blocks of space).
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
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

  static CreateBlock build() {
    late final CreateBlock block;
    block = createBlockFromManifest(
      'mechanical_press',
      blockEntityType: MechanicalPressBlockEntity.type,
      // `HorizontalKineticBlock.getPreferredHorizontalFacing` inspects the neighbours' shafts;
      // the host's placement rules cannot, so the player-facing fallback is used here and
      // [_fixFacing] applies the preferred side afterwards (`MechanicalPressBlock`).
      placement: const [PlacementRule.horizontalFacing('facing', opposite: true)],
      collisionShape: shape,
      selectionShape: shape,
      behavior: BlockBehavior(
        onPlaced: (server, e) => _fixFacing(server, block, e),
        // `canSurvive`: no basin right below.
        onCanPlace: (server, e) => !BasinBlock.isBasin(
          ProcessingRuntime.instance.store,
          ProcessingRuntime.instance.worlds.touch(e.targetWorld),
          e.pos.toPos().below,
        ),
        isPathfindable: (server, e) => false,
      ),
    );
    return block;
  }

  /// `MechanicalPressBlock.getStateForPlacement`: a neighbouring horizontal shaft
  /// decides the facing (`getPreferredHorizontalFacing`); without one the host's
  /// `horizontalFacing(opposite: true)` rule already gives
  /// `getHorizontalDirection().getOpposite()`. Player placements only, like
  /// `getStateForPlacement` (the host's `placed` event also fires for moves).
  static Future<void> _fixFacing(
    Server server,
    CreateBlock block,
    CustomBlockPlacedEventData e,
  ) async {
    final playerId = e.player;
    if (playerId == null || !KineticsRuntime.isLoaded) return;
    final player = server.getPlayerByUuid(id: playerId);
    if (player == null) return;
    final rt = KineticsRuntime.instance;
    final worldId = rt.worlds.touch(e.targetWorld);
    final state = block.stateOf(e.stateIndex);
    final ctx = PlacementContext(
      pos: KPos(e.pos.x, e.pos.y, e.pos.z),
      clickedFace: clickedFaceForPlacedState(
        KState(key, state),
      ),
      nearestLooking: nearestLookingDirection(player.getYaw(), player.getPitch()),
      horizontal: horizontalDirection(player.getYaw()),
      sneaking: player.asEntity().isSneaking(),
      stateAt: rt.level(worldId).stateAt,
      blocks: rt.blocks,
    );
    final preferred = preferredHorizontalFacing(ctx);
    if (preferred == null || state['facing'] == preferred.name) return;
    await setBlockState(
      e.targetWorld,
      e.pos.toPos(),
      BState(key, {...state, 'facing': preferred.name}),
    );
  }
}
