// `ArmBlock`: the block definition, its kinetic rules (`KineticBlock`), the placement state
// (`ceiling`) and the right-click handling (goggles, taking the held item back).
//
// Ported from `content/kinetics/mechanicalArm/ArmBlock.java`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/payloads.dart' show PayloadBus;
import '../../core/blocks.dart';
import '../support/kinetics_bridge.dart';
import '../common/stack.dart';
import '../crafter/machine_support.dart' show giveToPlayerStack;
import '../processing_runtime.dart';
import 'arm_block_entity.dart';
import 'arm_model.dart';

/// `KineticBlock` with `getRotationAxis == Axis.Y` and no shafts.
class ArmKineticDef extends KineticBlockDef {
  const ArmKineticDef();

  @override
  KAxis rotationAxis(KState state) => KAxis.y;

  @override
  bool hasShaftTowards(KState state, Dir face) => false;

  // `ArmBlock implements ICogWheel`, and `ICogWheel.isSmallCog()` defaults to
  // `!isLargeCog()` = true. With no shaft faces this is the ONLY way it receives rotation
  // (`connectedByGears` / large-to-small in the propagator); without it the arm is inert.
  @override
  bool get isSmallCog => true;
}

/// `ArmBlock.getStateForPlacement`: a ceiling arm is placed on the underside of a block.
KState armPlacement(
  PlacementContext ctx,
  KState placed,
  UseRecord? use,
  World world,
) => KState('create:mechanical_arm', {
  'ceiling': '${ctx.clickedFace == Dir.down}',
});

/// `ArmBlock.useItemOn`: goggles open the point display; a held item is taken back.
Future<BlockUseResult> armUse(HookCtx c, CustomBlockUseEventData e) async {
  final be = c.beOf<ArmBlockEntity>();
  if (be == null) return BlockUseResult.pass;

  final key = await _heldItemKey(e);
  if (key == 'create:goggles') {
    if (be.goggles) return BlockUseResult.tryEmptyHand;
    be.goggles = true;
    be.markDirty();
    be.sendData();
    return BlockUseResult.success;
  }

  if (be.heldItem.isEmpty) return BlockUseResult.tryEmptyHand;
  await giveToPlayerStack(e.player, c.world, be.heldItem);
  be.heldItem = PStack.empty;
  be.phase = ArmPhase.searchInputs;
  be.markDirty();
  be.sendData();
  return BlockUseResult.success;
}

Future<String> _heldItemKey(CustomBlockUseEventData e) async {
  try {
    return await e.item.getRegistryKey();
  } catch (_) {
    return airKey;
  }
}

/// `ArmItem.place`: after a player places the arm, ask their client to flush the points it
/// selected (`ArmInteractionPointHandler.flushSettings`), which then sends `create:place_arm`.
/// Without this request the arm keeps no interaction points and never moves an item.
void _requestArmPoints(HookCtx c, CustomBlockPlacedEventData e) {
  final uuid = e.player;
  if (uuid == null || !ProcessingRuntime.isLoaded) return;
  final bus = ProcessingRuntime.instance.services.find<PayloadBus>();
  if (bus == null) return;
  final player = c.server.getPlayerByUuid(id: uuid);
  if (player == null) return;
  try {
    bus.sendClientbound('create:s_place_arm', player, {
      'pos': (e.pos.x, e.pos.y, e.pos.z),
    });
  } finally {
    player.dispose();
  }
}

/// The block and block entity type of the mechanical arm.
KineticBlockSpec armSpec() {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  block = createBlockFromManifest(
    'mechanical_arm',
    blockEntityType: 'create:mechanical_arm',
    behavior: buildKineticBehavior(
      () => block,
      specRef: () => spec,
      pathfindable: false,
      use: armUse,
      neighbor: (c, e) => c.beOf<ArmBlockEntity>()?.redstoneUpdate(),
      afterPlaced: (c, e) {
        c.beOf<ArmBlockEntity>()?.redstoneUpdate();
        _requestArmPoints(c, e);
      },
    ),
  );
  spec = KineticBlockSpec(
    block,
    def: const ArmKineticDef(),
    placement: armPlacement,
  );
  return spec;
}
