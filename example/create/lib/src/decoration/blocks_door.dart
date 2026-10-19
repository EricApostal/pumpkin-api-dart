// Behaviours of the sliding doors (`SlidingDoorBlock`).
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/blocks.dart';
import '../common/host_bridge.dart';
import '../common/pos.dart';
import 'behaviour_support.dart';
import 'block_entities.dart';
import 'door.dart';
import 'door_host.dart';
import 'runtime.dart';



BlockBehavior slidingDoorBehavior(DecorationRuntime rt) => BlockBehavior(
  onCanPlace: (server, e) async {
    // `DoorBlock.getStateForPlacement` needs room above; `canSurvive` needs a floor.
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final level = HostBlockGetter(world);
    if (pos.$2 >= rt.maxY(world) || !level.canBeReplaced(pos.above)) return false;
    return e.canPlace;
  },
  onPlaced: (server, e) async {
    if (!shouldFixPlacement(rt, e.block, e.oldStateId, e.player, e.pos.toPos())) return;
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final level = HostBlockGetter(world);
    var placed = rt.stateOf(e.block, e.stateIndex);
    if (placed['half'] == 'upper') return;
    final block = rt.blocks[e.block]!;
    final player = rt.playerOf(server, e.player);
    final click = rt.clickFor(e.player, pos);
    var state = placed;
    if (player != null) {
      final horizontal = rt.horizontalDirection(player);
      final location = click?.location ?? (pos.$1 + .5, pos.$2 + .5, pos.$3 + .5);
      final powered = await hasNeighborSignal(world, pos) || await hasNeighborSignal(world, pos.above);
      state = doorStateForPlacement(
            level: level,
            pos: pos,
            defaultState: BState(block.key, block.definition.defaultState),
            horizontalDirection: horizontal,
            clickLocation: location,
            powered: powered,
            maxY: rt.maxY(world),
            sliding: true,
          ) ??
          placed;
    } else if (state.flag('open')) {
      state = state.setFlag('open', false).setFlag('powered', false);
    }
    if (state != placed) await setBlockState(world, pos, state);
    // `SlidingDoorBlock.onPlace` -> `deferUpdate`; the block entity checks redstone on its first tick.
    final entity = rt.store.createAt(world, e.pos, SlidingDoorBlockEntity.type);
    if (entity is SlidingDoorBlockEntity) entity.deferUpdate = true;
    // `DoorBlock.setPlacedBy`: the upper half.
    await setBlockState(world, pos.above, state.setValue('half', 'upper'));
  },
  onNeighborUpdate: (server, e) =>
      slidingDoorNeighborChange(rt, e.targetWorld, e.pos.toPos(), sourceIsSameBlock: e.sourceBlock == e.block),
  onUseWithoutItem: (server, e) async {
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final state = rt.stateOf(e.block, e.stateIndex);
    final action = slidingDoorUse(HostBlockGetter(world), pos, state);
    await applyDoorAction(rt, world, action);
    return BlockUseResult.success;
  },
  onUpdateShape: (server, e) async {
    final block = rt.blocks[e.block]!;
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final state = rt.stateOf(e.block, e.stateIndex);
    final next = doorUpdateShape(
      HostBlockGetter(world),
      pos,
      state,
      dirOf(e.direction),
      HostBlockGetter.stateOfId(e.neighborStateId),
      sliding: true,
    );
    if (next.isAir) {
      scheduleBreak(world, pos);
      return null;
    }
    return shapeAnswer(block, state, next);
  },
  onScheduledTick: (server, e) async {
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final level = HostBlockGetter(world);
    final state = level.stateAt(pos);
    if (state.key != e.block) return;
    final lower = state['half'] == 'lower';
    final ok = lower
        ? doorCanSurvive(level, pos, state)
        : level.stateAt(pos.below).key == state.key && level.stateAt(pos.below)['half'] == 'lower';
    if (!ok) await breakWithDrops(world, pos);
  },
  onPlayerWillDestroy: (server, e) async {
    // `DoublePlantBlock.preventDropFromBottomPart`: creative players break the upper half without
    // the lower half dropping its item.
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final state = rt.stateOf(e.block, e.stateIndex);
    if (state['half'] == 'upper' && e.player.isCreative) {
      final below = pos.below;
      final level = HostBlockGetter(world);
      final lowerState = level.stateAt(below);
      if (lowerState.key == state.key && lowerState['half'] == 'lower') {
        await setBlockState(
          world,
          below,
          BState.air,
          flags: const {BlockFlagsFlag.notifyNeighbors, BlockFlagsFlag.notifyListeners, BlockFlagsFlag.skipDrops},
        );
      }
    }
    return true;
  },
);
