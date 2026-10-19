// Behaviours of the placard: showing an item, matching it to give a redstone pulse.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/blocks.dart';
import '../common/host_bridge.dart';
import '../common/pos.dart';
import 'behaviour_support.dart';
import 'block_entities.dart';
import 'misc_blocks.dart';
import 'runtime.dart';



BlockBehavior placardBehavior(DecorationRuntime rt) {
  PlacardBlockEntity? be(World world, Pos pos) => rt.store.typed<PlacardBlockEntity>(world.getId(), pos.toBlockPos());

  return BlockBehavior(
    onPlaced: (server, e) async {
      if (!shouldFixPlacement(rt, e.block, e.oldStateId, e.player, e.pos.toPos())) return;
      final world = e.targetWorld;
      final pos = e.pos.toPos();
      final placed = rt.stateOf(e.block, e.stateIndex);
      final player = rt.playerOf(server, e.player);
      if (player == null) return;
      final level = HostBlockGetter(world);
      final fixed = placardStateForPlacement(
        level: level,
        pos: pos,
        defaultState: BState(placed.key, rt.blocks[e.block]!.definition.defaultState),
        nearestLooking: rt.nearestLooking(player),
        horizontalDirection: rt.horizontalDirection(player),
        inWater: placed.flag('waterlogged'),
      );
      if (fixed == null) {
        scheduleBreak(world, pos);
        return;
      }
      await fixPlacedState(world, pos, placed, fixed);
    },
    onUpdateShape: (server, e) async {
      final state = rt.stateOf(e.block, e.stateIndex);
      final world = e.targetWorld;
      final pos = e.pos.toPos();
      if (state.flag('waterlogged')) updateWater(world, pos, state);
      final next = placardUpdateShape(HostBlockGetter(world), pos, state, dirOf(e.direction));
      if (next.isAir) scheduleBreak(world, pos);
      return null;
    },
    onScheduledTick: (server, e) async {
      final world = e.targetWorld;
      final pos = e.pos.toPos();
      final level = HostBlockGetter(world);
      final state = level.stateAt(pos);
      if (state.key == e.block && !placardCanSurvive(level, pos, state)) await breakWithDrops(world, pos);
    },
    onWeakPower: (server, e) async => placardSignal(rt.stateOf(e.block, e.stateIndex)),
    onStrongPower: (server, e) async =>
        // The event's face looks at the reader; vanilla's side points from the reader to the block.
        placardDirectSignal(rt.stateOf(e.block, e.stateIndex), dirOf(e.face).opposite),
    onUseWithItem: (server, e) async {
      if (e.sneaking) return BlockUseResult.tryEmptyHand;
      final world = e.targetWorld;
      final pos = e.pos.toPos();
      final state = rt.stateOf(e.block, e.stateIndex);
      final entity = be(world, pos);
      if (entity == null) return BlockUseResult.tryEmptyHand;
      final inHand = await e.item.getRegistryKey();
      final inBlock = entity.heldItem;
      if (inHand == 'minecraft:air' || inBlock != null) {
        if (inBlock == null) return BlockUseResult.fail;
        if (inHand == 'minecraft:air') return BlockUseResult.fail;
        if (state.flag('powered')) return BlockUseResult.fail;
        // `FilterItemStack.test` for filters needs the filter's configuration; a plain placard
        // compares the item (and components in Java).
        final test = inHand == inBlock;
        if (!test) {
          rt.playCreateSound(world, pos, 'deny');
          return BlockUseResult.success;
        }
        rt.playCreateSound(world, pos, 'confirm');
        final powered = state.setFlag('powered', true);
        await setBlockState(world, pos, powered);
        await updatePlacardNeighbours(world, pos, state);
        entity.poweredTicks = placardPoweredTicks;
        entity.sendData();
        return BlockUseResult.success;
      }
      rt.playSound(world, pos, 'minecraft:entity.item_frame.add_item');
      entity.setHeldItem(inHand);
      if (!e.player.isCreative) await rt.shrinkHeld(e.player, e.hand);
      return BlockUseResult.success;
    },
    onAttack: (server, e) async {
      final world = e.targetWorld;
      final pos = e.pos.toPos();
      final entity = be(world, pos);
      final held = entity?.heldItem;
      if (entity == null || held == null) return;
      await rt.giveOrDrop(e.player, world, pos, held);
      rt.playSound(world, pos, 'minecraft:entity.item_frame.remove_item');
      entity.setHeldItem(null);
    },
    onStateReplaced: (server, e) async {
      // `affectNeighborsAfterRemoval`: a powered placard tells its neighbours it is gone.
      if (e.moved) return;
      final old = rt.stateOf(e.block, e.oldStateIndex);
      if (old.flag('powered')) await updatePlacardNeighbours(e.targetWorld, e.pos.toPos(), old);
    },
    onPlayerWillDestroy: (server, e) async {
      // The held item is dropped with the block (the block entity is gone afterwards).
      final entity = be(e.targetWorld, e.pos.toPos());
      final held = entity?.heldItem;
      if (held != null) await rt.dropItem(e.targetWorld, e.pos.toPos(), held);
      return true;
    },
  );
}
