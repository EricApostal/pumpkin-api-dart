// The block definitions of the bearing family and their use behaviours: the three bearings, the
// sail frame and the dyed sails.
//
// Java: `content/contraptions/bearing/{BearingBlock,MechanicalBearingBlock,ClockworkBearingBlock,
// WindmillBearingBlock,SailBlock}`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../common/direction.dart';
import '../../api/wrenchable.dart';
import '../../core/blocks.dart';
import '../blocks/actuator_runtime.dart';
import 'bearing_block_entities.dart';
import 'bearing_placement.dart';
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
    placement: bearingPlacementRules,
    behavior: bearingBehavior(mechanicalBearing),
    blockEntityType: mechanicalBearing,
  ),
  manifestBlock(
    'windmill_bearing',
    placement: bearingPlacementRules,
    behavior: bearingBehavior(windmillBearing),
    blockEntityType: windmillBearing,
  ),
  manifestBlock(
    'clockwork_bearing',
    placement: bearingPlacementRules,
    behavior: bearingBehavior(clockworkBearing),
    blockEntityType: clockworkBearing,
  ),
];

/// `ClockworkBearingBlock.useItemOn` / `WindmillBearingBlock.useItemOn`: sneak clicks fail, a
/// running bearing disassembles, an idle one assembles on the next tick.
///
/// The host fires the `useWithoutItem` hook for every click the held item did not handle (with
/// the held stack in `event.item`, see `fire_use` in the host's `dynamic.rs`), so a click holding
/// a block reaches this handler too. Java returns `TRY_WITH_EMPTY_HAND` for a non-empty stack,
/// which is what lets the held block be placed against the bearing; returning `success` here
/// consumed the click and swallowed the placement.
BlockBehavior bearingBehavior(String blockKey) => BlockBehavior(
  onUseWithoutItem: (server, e) async {
    // `stack.isEmpty()`; the copy the host handed over is released with the callback.
    final holdingItem = await e.item.getCount() > 0;
    final mode = e.player.getGamemode();
    final use = bearingUse(
      // `player.mayBuild()`: adventure and spectator players cannot use a bearing.
      mayBuild: mode != GameMode.adventure && mode != GameMode.spectator,
      sneaking: e.sneaking,
      holdingItem: holdingItem,
    );
    switch (use) {
      case BearingUse.fail:
        return BlockUseResult.fail;
      case BearingUse.tryEmptyHand:
        return BlockUseResult.tryEmptyHand;
      case BearingUse.assemble:
        break;
    }
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
