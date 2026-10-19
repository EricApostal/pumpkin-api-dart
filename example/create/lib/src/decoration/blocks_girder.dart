// Behaviours of the girders: `GirderBlock` and `GirderEncasedShaftBlock`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/blocks.dart';
import '../common/direction.dart' as d;
import '../common/host_bridge.dart';
import '../common/pos.dart';
import 'behaviour_support.dart';
import 'blocks_misc.dart';
import 'bracketed_behaviour.dart';
import 'girder.dart';
import 'runtime.dart';







/// The bracket lookup the girder logic needs, over the block entities of [world].
BracketFacingLookup bracketLookup(DecorationRuntime rt, World world) {
  final worldId = world.getId();
  return (Pos p) =>
      BracketedBlockEntityBehaviour.at(rt.store, worldId, p)?.bracket?.dir('facing');
}

BlockBehavior girderBehavior(DecorationRuntime rt) => BlockBehavior(
  onPlaced: (server, e) async {
    if (!shouldFixPlacement(rt, e.block, e.oldStateId, e.player, e.pos.toPos())) return;
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final placed = rt.stateOf(e.block, e.stateIndex);
    final click = rt.clickFor(e.player, pos);
    final face = click?.face ?? d.Direction.fromAxisAndDirection(placed.axisOf('axis') ?? d.Axis.y, d.AxisDirection.positive);
    final fixed = girderStateForPlacement(
      HostBlockGetter(world),
      bracketLookup(rt, world),
      pos,
      BState(placed.key, rt.blocks[e.block]!.definition.defaultState),
      face,
      inWater: placed.flag('waterlogged'),
    );
    await fixPlacedState(world, pos, placed, fixed);
  },
  onUpdateShape: (server, e) async {
    final block = rt.blocks[e.block]!;
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final state = rt.stateOf(e.block, e.stateIndex);
    if (state.flag('waterlogged')) updateWater(world, pos, state);
    final next = girderUpdateShape(HostBlockGetter(world), bracketLookup(rt, world), pos, state, dirOf(e.direction));
    return shapeAnswer(block, state, next);
  },
  onScheduledTick: (server, e) async {
    // `tick`: `Block.updateOrDestroy(state, updateFromNeighbourShapes(state))`.
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final level = HostBlockGetter(world);
    final state = level.stateAt(pos);
    if (state.key != e.block) return;
    final next = girderUpdateFromNeighbourShapes(level, bracketLookup(rt, world), pos, state);
    if (next != state) await setBlockState(world, pos, next);
  },
  onUseWithItem: (server, e) async {
    final held = await e.item.getRegistryKey();
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final level = HostBlockGetter(world);
    final state = rt.stateOf(e.block, e.stateIndex);
    if (held == 'create:shaft') {
      // Encase a shaft into the girder.
      final encased = rt.blocks[girderEncasedShaftKey]!;
      final target = girderEncaseShaft(
        state,
        BState(encased.key, encased.definition.defaultState),
        dirOf(e.face),
      );
      final stateId = stateIdOf(target);
      if (stateId == null) return BlockUseResult.tryEmptyHand;
      final switcher = rt.wrench?.stateSwitcher;
      if (switcher != null) {
        await switcher(world, e.pos, stateId);
      } else {
        await setBlockState(world, pos, target);
      }
      rt.playSound(world, pos, 'minecraft:block.netherite_block.hit', volume: 0.5, pitch: 1.25);
      if (!e.player.isCreative) await rt.shrinkHeld(e.player, e.hand);
      return BlockUseResult.success;
    }
    if (held == 'create:wrench' && !e.sneaking) {
      final changes = girderWrenchClick(level, pos, _hit(e));
      if (changes == null) return BlockUseResult.fail;
      for (final (p, s) in changes) {
        await setBlockState(world, p, s, flags: const {BlockFlagsFlag.notifyListeners, BlockFlagsFlag.skipShapeUpdate});
      }
      return BlockUseResult.success;
    }
    if (held == girderKey && !e.sneaking) {
      final offset = girderPlacementOffset(
        level: level,
        state: state,
        pos: pos,
        hit: _hit(e),
        range: rt.placementRange(),
        fixup: (newPos, placed) {
          final lookup = bracketLookup(rt, world);
          return girderUpdateFromNeighbourShapes(level, lookup, newPos, placed);
        },
      );
      return placeFromOffset(rt, world: world, player: e.player, hand: e.hand, itemKey: held, offset: offset);
    }
    return BlockUseResult.tryEmptyHand;
  },
);

(double, double, double) _hit(CustomBlockUseEventData e) =>
    (e.pos.x + e.cursor.$1, e.pos.y + e.cursor.$2, e.pos.z + e.cursor.$3);

BlockBehavior girderEncasedBehavior(DecorationRuntime rt) => BlockBehavior(
  onUpdateShape: (server, e) async {
    final block = rt.blocks[e.block]!;
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final state = rt.stateOf(e.block, e.stateIndex);
    if (state.flag('waterlogged')) updateWater(world, pos, state);
    final next = girderEncasedShaftUpdateShape(
      HostBlockGetter(world),
      bracketLookup(rt, world),
      pos,
      state,
      dirOf(e.direction),
      HostBlockGetter.stateOfId(e.neighborStateId),
    );
    return shapeAnswer(block, state, next);
  },
);
