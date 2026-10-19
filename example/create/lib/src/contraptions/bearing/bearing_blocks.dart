// The block definitions of the bearing family and their use behaviours: the three bearings, the
// sail frame and the dyed sails.
//
// Java: `content/contraptions/bearing/{BearingBlock,MechanicalBearingBlock,ClockworkBearingBlock,
// WindmillBearingBlock,SailBlock}`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../api/wrenchable.dart';
import '../../core/blocks.dart';
import '../blocks/actuator_runtime.dart';
import 'bearing_block_entities.dart';
import 'sail_block.dart';

const String mechanicalBearing = 'create:mechanical_bearing';
const String windmillBearing = 'create:windmill_bearing';
const String clockworkBearing = 'create:clockwork_bearing';

/// The three bearing block keys.
const List<String> bearingBlocks = [
  mechanicalBearing,
  windmillBearing,
  clockworkBearing,
];

/// The block definitions of the bearings.
List<CreateBlock> buildBearingBlocks() => [
  manifestBlock(
    'mechanical_bearing',
    placement: const [PlacementRule.clickedFace('facing')],
    behavior: bearingEmptyHandBehavior(mechanicalBearing),
  ),
  manifestBlock(
    'windmill_bearing',
    placement: const [PlacementRule.clickedFace('facing')],
    behavior: bearingEmptyHandBehavior(windmillBearing),
  ),
  manifestBlock(
    'clockwork_bearing',
    placement: const [PlacementRule.clickedFace('facing')],
    behavior: bearingEmptyHandBehavior(clockworkBearing),
  ),
];

/// `ClockworkBearingBlock.useItemOn` / `WindmillBearingBlock.useItemOn` for an empty hand: sneak
/// clicks fail, a running bearing disassembles, an idle one assembles on the next tick.
BlockBehavior bearingEmptyHandBehavior(String blockKey) => BlockBehavior(
  onUseWithoutItem: (server, e) async {
    if (e.sneaking) return BlockUseResult.fail;
    final runtime = ActuatorRuntime.maybe;
    if (runtime == null) return BlockUseResult.pass;
    final worldId = e.targetWorld.getId();
    final pos = e.pos;
    if (blockKey == clockworkBearing) {
      final be = runtime.store.typed<ClockworkBearingBlockEntity>(worldId, pos);
      if (be == null) return BlockUseResult.pass;
      if (be.running) {
        be.disassemble();
      } else {
        be.assembleNextTick = true;
      }
      return BlockUseResult.success;
    }
    final be = runtime.store.typed<MechanicalBearingBlockEntity>(worldId, pos);
    if (be == null) return BlockUseResult.pass;
    if (be.running) {
      be.disassemble();
    } else {
      be.assembleNextTick = true;
    }
    return BlockUseResult.success;
  },
);

/// `BearingBlock.onWrenched`: rotate the bearing, then let the block entity disassemble.
Wrenchable bearingWrenchable({
  required Future<void> Function(WrenchContext c) disassemble,
}) => CallbackWrenchable(
  onWrenchedOverride: (c) async {
    final result = await c.registry.defaultRotate(c);
    if (result == WrenchResult.success) await disassemble(c);
    return result;
  },
);

/// The sail definitions of this module.
List<CreateBlock> buildSails() => buildSailBlocks(
  behaviorOf: (key, frame) => sailBlockBehavior(key, frame: frame),
);
