// `DeployerBlock`: the block definition, its kinetic rules (`DirectionalAxisKineticBlock`), the
// placement state and the right-click handling (swapping the held item with the fake player's
// hand; a wrench click away from the front changes the mode).
//
// Ported from `content/kinetics/deployer/DeployerBlock.java`. The host has no placement helper
// for the deployer's "place another deployer next to it" shortcut, so that shortcut is not
// ported; the wrench mode change and the item swap are.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/wrenchable.dart';
import '../../core/blocks.dart';
import '../common/stack.dart';
import '../host/stack_host.dart';
import '../processing_runtime.dart';
import '../support/kinetics_bridge.dart';
import '../saw/saw_spec.dart' show casing12Rules;
import '../crafter/machine_support.dart';
import 'deployer_block_entity.dart';

/// `DirectionalAxisKineticBlock`, which is what `DeployerBlock` extends.
///
/// `hasShaftTowards` is the inherited one — `face.getAxis() == getRotationAxis(state)`
/// (`DirectionalAxisKineticBlock.java:143-145`), the same rule `DirectionalAxisBlockDef` uses.
/// It used to return `false` for every face, which meant no shaft could ever connect to a
/// deployer (`kinetics/propagator.dart` needs `hasShaftTowards` on both sides), so a deployer
/// never turned and no `create:deploying` recipe could ever run.
class DeployerKineticDef extends KineticBlockDef {
  const DeployerKineticDef();

  Dir facing(KState state) => state.dirOf('facing') ?? Dir.north;

  @override
  KAxis rotationAxis(KState state) {
    final axis = facing(state).axis;
    final alongFirst = state.flag('axis_along_first');
    if (axis == KAxis.x) return alongFirst ? KAxis.y : KAxis.z;
    if (axis == KAxis.y) return alongFirst ? KAxis.x : KAxis.z;
    return alongFirst ? KAxis.x : KAxis.y;
  }

  @override
  bool hasShaftTowards(KState state, Dir face) =>
      face.axis == rotationAxis(state);
}

/// `DeployerBlock.getStateForPlacement` (`DirectionalAxisKineticBlock`).
KState deployerPlacement(
  PlacementContext ctx,
  KState placed,
  UseRecord? use,
  World world,
) {
  var facing = ctx.nearestLooking.opposite;
  if (ctx.hasPlayer && ctx.sneaking) facing = facing.opposite;

  var alongFirst = false;
  final faceAxis = facing.axis;

  bool prefers(Dir dir, bool shaftAxis) {
    if (!shaftAxis) return false;
    final state = ctx.stateAt(ctx.pos.relative(dir));
    final def = ctx.blocks.defFor(state);
    return def != null && def.hasShaftTowards(state, dir.opposite);
  }

  if (faceAxis.isHorizontal) {
    alongFirst = faceAxis == KAxis.z;
    final positivePerpendicular = faceAxis == KAxis.x ? Dir.south : Dir.east;

    final shaftAbove = prefers(Dir.up, true);
    final shaftBelow = prefers(Dir.down, true);
    final preferLeft = prefers(positivePerpendicular, false);
    final preferRight = prefers(positivePerpendicular.opposite, false);

    if (shaftAbove || shaftBelow || preferLeft || preferRight) {
      alongFirst = faceAxis == KAxis.x;
    }
  }

  if (faceAxis.isVertical) {
    alongFirst = ctx.horizontal.axis == KAxis.x;
    Dir? preferredSide;
    for (final side in Dir.horizontals) {
      if (!prefers(side, true) && !prefers(side.clockWise(KAxis.y), false)) {
        continue;
      }
      if (preferredSide != null && preferredSide.axis != side.axis) {
        preferredSide = null;
        break;
      }
      preferredSide = side;
    }
    if (preferredSide != null) alongFirst = preferredSide.axis == KAxis.x;
  }

  return KState('create:deployer', {
    'facing': facing.name,
    'axis_along_first': '$alongFirst',
  });
}

/// `DeployerBlock.useItemOn`: the front of the deployer swaps the held item with its fake player.
Future<BlockUseResult> deployerUse(HookCtx c, CustomBlockUseEventData e) async {
  final itemKey = await _heldItemKey(e);
  if (isWrenchItem(ProcessingRuntime.instance, itemKey)) {
    return BlockUseResult.tryEmptyHand;
  }

  final facing = c.state.dirOf('facing') ?? Dir.up;
  final normal = (
    facing.dx.toDouble(),
    facing.dy.toDouble(),
    facing.dz.toDouble(),
  );
  final local = (
    (e.cursor.$1 - .5 + normal.$1 * .5) * normal.$1,
    (e.cursor.$2 - .5 + normal.$2 * .5) * normal.$2,
    (e.cursor.$3 - .5 + normal.$3 * .5) * normal.$3,
  );
  if (local.length < .75) return BlockUseResult.tryEmptyHand;

  final be = c.beOf<DeployerBlockEntity>();
  final heldByDeployer = be?.heldItem ?? PStack.empty;
  final heldByPlayer = await HostStacks.read(e.item);
  if (heldByDeployer.isEmpty && heldByPlayer.isEmpty) {
    return BlockUseResult.success;
  }

  await _setHeld(e, heldByDeployer);
  if (be != null) {
    be.heldItem = heldByPlayer;
    await be.setHeld(heldByPlayer);
    be.markDirty();
    be.sendData();
  }
  return BlockUseResult.success;
}

Future<String> _heldItemKey(CustomBlockUseEventData e) async {
  try {
    return await e.item.getRegistryKey();
  } catch (_) {
    return airKey;
  }
}

Future<void> _setHeld(CustomBlockUseEventData e, PStack stack) async {
  if (stack.isEmpty) {
    await e.player.setItemInHand(hand: e.hand, stack: null);
    return;
  }
  final item = await HostStacks.write(stack);
  if (item == null) return;
  await e.player.setItemInHand(hand: e.hand, stack: item);
}

/// `DeployerBlock.onWrenched`: a wrench click on the extended hand changes the mode, otherwise
/// the default rotation runs.
Future<WrenchResult?> deployerWrenched(WrenchContext c) async {
  final facing = Dir.fromName(c.properties['facing']) ?? Dir.up;
  final normal = (
    facing.dx.toDouble(),
    facing.dy.toDouble(),
    facing.dz.toDouble(),
  );
  final local = (
    (c.cursor.$1 - .5 + normal.$1 * .5) * normal.$1,
    (c.cursor.$2 - .5 + normal.$2 * .5) * normal.$2,
    (c.cursor.$3 - .5 + normal.$3 * .5) * normal.$3,
  );
  if (local.length <= .75) return null;

  final rt = ProcessingRuntime.instance;
  final worldId = rt.worlds.touch(c.world);
  rt.store.typed<DeployerBlockEntity>(worldId, c.pos)?.changeMode();
  return WrenchResult.success;
}

/// The block and block entity type of the mechanical deployer.
KineticBlockSpec deployerSpec() {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  block = createBlockFromManifest(
    'deployer',
    blockEntityType: 'create:deployer',
    shapeRules: casing12Rules(),
    // `DirectionalAxisKineticBlock.getFacingForPlacement` (javap-verified; DeployerBlock's own
    // override only returns `down` for an assembly-operator context): the player's nearest
    // looking direction, or its opposite when the player does not sneak.
    placement: const [
      PlacementRule.lookingDirection('facing', whenSneaking: true),
      PlacementRule.lookingDirection('facing', opposite: true, whenSneaking: false),
    ],
    behavior: buildKineticBehavior(
      () => block,
      specRef: () => spec,
      pathfindable: false,
      use: deployerUse,
      neighbor: (c, e) => c.beOf<DeployerBlockEntity>()?.redstoneUpdate(),
      afterPlaced: (c, e) async {
        final be = c.beOf<DeployerBlockEntity>();
        be?.redstoneUpdate();
        final owner = e.player;
        if (be != null && owner != null) {
          be.owner = owner.asString;
          be.markDirty();
        }
      },
    ),
  );
  spec = KineticBlockSpec(
    block,
    def: const DeployerKineticDef(),
    placement: deployerPlacement,
  );
  return spec;
}
