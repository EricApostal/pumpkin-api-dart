// `PulleyBlock` and its rope blocks: the pulley assembles on an empty-hand click, and a broken
// rope breaks the rope above and below it and resets the pulley.
//
// Java: `content/contraptions/pulley/PulleyBlock` (+ its inner `RopeBlock`, `MagnetBlock`).
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../common/common.dart';
import '../../core/blocks.dart';
import '../blocks/actuator_runtime.dart';
import 'pulley_block_entity.dart';

const String ropePulleyKey = 'create:rope_pulley';

/// The pulley and rope block definitions.
List<CreateBlock> buildPulleyBlocks() => [
  manifestBlock(
    'rope_pulley',
    placement: const [PlacementRule.horizontalAxis('axis')],
    behavior: BlockBehavior(
      onUseWithoutItem: (server, e) async {
        if (e.sneaking) return BlockUseResult.pass;
        final runtime = ActuatorRuntime.maybe;
        final be = runtime?.store.at(e.targetWorld.getId(), e.pos);
        if (be is! PulleyBlockEntity) return BlockUseResult.pass;
        be.assembleNextTick = true;
        return BlockUseResult.success;
      },
      onBroken: (server, e) async {
        // `affectNeighborsAfterRemoval`: the rope below the pulley goes with it.
        final world = e.targetWorld;
        final below = (e.pos.x, e.pos.y - 1, e.pos.z);
        if (isRopeState(HostBlockGetter(world).stateAt(below))) {
          await world.breakBlock(
            BlockPos(x: below.$1, y: below.$2, z: below.$3),
            drop: true,
          );
        }
      },
    ),
  ),
  manifestBlock('rope', behavior: ropeBehavior()),
  manifestBlock('pulley_magnet', behavior: ropeBehavior()),
];

/// `RopeBlockBase.affectNeighborsAfterRemoval`: a broken rope breaks its neighbours and resets the
/// pulley it hangs from.
BlockBehavior ropeBehavior() => BlockBehavior(
  onStateReplaced: (server, e) async {
    final world = e.targetWorld;
    final pos = (e.pos.x, e.pos.y, e.pos.z);
    final above = pos.above;
    final below = pos.below;

    // Reset the pulley at the top of the rope.
    final pulley = ActuatorRuntime.maybe?.store.at(
      world.getId(),
      BlockPos(x: above.$1, y: above.$2, z: above.$3),
    );
    if (pulley is PulleyBlockEntity) {
      pulley.initialOffset = 0;
      pulley.onLengthBroken();
    }

    if (isRopeState(HostBlockGetter(world).stateAt(above))) {
      await world.breakBlock(
        BlockPos(x: above.$1, y: above.$2, z: above.$3),
        drop: true,
      );
    }
    if (isRopeState(HostBlockGetter(world).stateAt(below))) {
      await world.breakBlock(
        BlockPos(x: below.$1, y: below.$2, z: below.$3),
        drop: true,
      );
    }
  },
);
