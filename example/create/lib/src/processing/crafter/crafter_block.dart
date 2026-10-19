// `MechanicalCrafterBlock`: the block definition, its kinetic rules, the placement state and the
// right-click handling (slot cover, inserting into the group, taking the slot item, and the
// wrench connection of neighbouring crafters).
//
// Ported from `content/kinetics/crafter/MechanicalCrafterBlock.java`. Create connects crafters
// through an edge interaction; the host has no edge interactions, so a wrench clicking the side
// of a crafter towards a compatible neighbour toggles the connection instead.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/common.dart';
import '../../common/host_bridge.dart';
import '../../core/blocks.dart';
import '../support/kinetics_bridge.dart';
import '../common/stack.dart';
import '../common/storage.dart';
import '../host/stack_host.dart';
import '../processing_runtime.dart';
import 'crafter_model.dart';
import 'machine_support.dart';
import 'mechanical_crafter_block_entity.dart';

/// `ICogWheel` / `HorizontalKineticBlock`: the crafter turns around its front face's axis and has
/// no shafts.
class CrafterKineticDef extends KineticBlockDef {
  const CrafterKineticDef();

  @override
  KAxis rotationAxis(KState state) => (state.dirOf('facing') ?? Dir.north).axis;

  @override
  bool hasShaftTowards(KState state, Dir face) => false;
}

Direction _direction(Dir dir) => Direction.byName(dir.name) ?? Direction.north;

/// `MechanicalCrafterBlock.getStateForPlacement`.
KState crafterPlacement(
  PlacementContext ctx,
  KState placed,
  UseRecord? use,
  World world,
) {
  final face = ctx.clickedFace;
  final placedOn = ctx.placedOnPos;
  final blockState = ctx.stateAt(placedOn);
  final sneaking = ctx.hasPlayer && ctx.sneaking;

  if (blockState.block != crafterBlockKey || sneaking) {
    // `super.getStateForPlacement`: the horizontal direction, opposite the player.
    final direction = ctx.horizontal.opposite;
    var state = KState(crafterBlockKey, {
      'facing': direction.name,
      'pointing': CrafterPointing.up.name,
    });
    if (direction != face) {
      final pointing = pointingFromFacing(
        _direction(face),
        _direction(direction),
      );
      state = state.set('pointing', pointing.name);
    }
    return state;
  }

  final otherFacing = Dir.fromName(blockState['facing']) ?? Dir.north;
  final pointing = pointingFromFacing(
    _direction(face),
    _direction(otherFacing),
  );
  return KState(crafterBlockKey, {
    'facing': otherFacing.name,
    'pointing': pointing.name,
  });
}

/// `MechanicalCrafterBlock.useItemOn`.
Future<BlockUseResult> crafterUse(HookCtx c, CustomBlockUseEventData e) async {
  final be = c.beOf<MechanicalCrafterBlockEntity>();
  if (be == null) return BlockUseResult.tryEmptyHand;

  final facing = c.state.dirOf('facing') ?? Dir.north;
  final itemKey = await _heldItemKey(e);
  final isHand = !e.withItem && e.hand == Hand.right;
  final wrenched = isWrenchItem(ProcessingRuntime.instance, itemKey);

  // The wrench connection: click the side towards a compatible crafter.
  if (wrenched && e.face.name != facing.name) {
    final direction = e.face.toDirection();
    final neighbourState = c.level.stateAt(c.kpos.relative(_dirOf(direction)));
    if (shouldConnectCrafter(
      bStateOf(c.state),
      bStateOf(neighbourState),
      direction,
    )) {
      MechanicalCrafterBlockEntity.toggleConnection(
        c.rt.store,
        c.worldId,
        c.pos.toPos(),
        c.pos.toPos().relative(direction),
      );
      return BlockUseResult.success;
    }
    return BlockUseResult.pass;
  }

  if (e.face.name != facing.name) return BlockUseResult.tryEmptyHand;

  if (be.phase != CrafterPhase.idle && !wrenched) {
    await be.ejectWholeGrid();
    return BlockUseResult.success;
  }

  if (be.phase == CrafterPhase.idle && !isHand && !wrenched) {
    if (itemKey == 'create:crafter_slot_cover') {
      if (be.covered) return BlockUseResult.tryEmptyHand;
      if (be.inventory.stackIn(0).isNotEmpty) {
        return BlockUseResult.tryEmptyHand;
      }
      be.covered = true;
      be.markDirty();
      be.sendData();
      if (!e.player.isCreative) await consumeFromHand(e.player, e.hand, 1);
      return BlockUseResult.success;
    }

    final storage = be.itemStorage(null);
    if (storage == null) return BlockUseResult.tryEmptyHand;
    final held = await HostStacks.read(e.item);
    final remainder = ItemStorages.insertStacked(storage, held);
    if (remainder.count != held.count) {
      await _setHeld(e, remainder);
    }
    return BlockUseResult.success;
  }

  final inSlot = be.inventory.stackIn(0);
  if (inSlot.isEmpty) {
    if (be.covered && !wrenched) {
      be.covered = false;
      be.markDirty();
      be.sendData();
      if (!e.player.isCreative) {
        await giveToPlayerStack(
          e.player,
          c.world,
          const PStack('create:crafter_slot_cover', 1),
        );
      }
      return BlockUseResult.success;
    }
    return BlockUseResult.tryEmptyHand;
  }

  if (!isHand) {
    final held = await HostStacks.read(e.item);
    if (!held.sameItemSameComponents(inSlot)) {
      return BlockUseResult.tryEmptyHand;
    }
  }
  await giveToPlayerStack(e.player, c.world, inSlot);
  be.inventory.setStack(0, PStack.empty);
  return BlockUseResult.success;
}

Future<String> _heldItemKey(CustomBlockUseEventData e) async {
  try {
    return await e.item.getRegistryKey();
  } catch (_) {
    return airKey;
  }
}

/// `player.setItemInHand(hand, remainder)` for a pure stack.
Future<void> _setHeld(CustomBlockUseEventData e, PStack remainder) async {
  if (remainder.isEmpty) {
    await e.player.setItemInHand(hand: e.hand, stack: null);
    return;
  }
  final item = await HostStacks.write(remainder);
  if (item == null) return;
  await e.player.setItemInHand(hand: e.hand, stack: item);
}

Dir _dirOf(Direction d) => Dir.fromName(d.name) ?? Dir.north;

/// The block and block entity type of the mechanical crafter.
KineticBlockSpec crafterSpec() {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  block = createBlockFromManifest(
    'mechanical_crafter',
    blockEntityType: 'create:mechanical_crafter',
    placement: const [PlacementRule.horizontalFacing('facing', opposite: true)],
    behavior: buildKineticBehavior(
      () => block,
      specRef: () => spec,
      pathfindable: false,
      use: crafterUse,
    ),
  );
  spec = KineticBlockSpec(
    block,
    def: const CrafterKineticDef(),
    placement: crafterPlacement,
  );
  return spec;
}
