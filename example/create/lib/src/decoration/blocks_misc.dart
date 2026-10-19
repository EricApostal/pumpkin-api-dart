// Behaviours of the smaller decoration blocks: metal ladders, metal scaffolding, cardboard
// blocks and the train trapdoors.
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/blocks.dart';
import '../api/placement.dart';
import '../common/direction.dart' as d;
import '../common/host_bridge.dart';
import '../common/pos.dart';
import 'behaviour_support.dart';
import 'door.dart';
import 'misc_blocks.dart';
import 'runtime.dart';

final math.Random _random = math.Random();

/// Places the block of a placement helper offset (`PlacementOffset.placeInWorld`).
Future<BlockUseResult> placeFromOffset(
  DecorationRuntime rt, {
  required World world,
  required Player player,
  required Hand hand,
  required String itemKey,
  required PlacementOffset offset,
}) async {
  final level = HostBlockGetter(world);
  if (!offset.success || !level.canBeReplaced(offset.pos)) return BlockUseResult.pass;
  final block = rt.blocks[itemKey];
  if (block == null) return BlockUseResult.pass;
  var state = offset.transform(BState(block.key, block.definition.defaultState));
  if (state.has('waterlogged')) state = state.setFlag('waterlogged', level.isWater(offset.pos));
  await setBlockState(world, offset.pos, state);
  rt.playSound(world, offset.pos, rt.placeSoundOf(itemKey), volume: 0.75, pitch: 0.8);
  if (!player.isCreative) await rt.shrinkHeld(player, hand);
  return BlockUseResult.success;
}

// -- Ladders -----------------------------------------------------------------------------------



BlockBehavior ladderBehavior(DecorationRuntime rt) => BlockBehavior(
  onPlaced: (server, e) async {
    if (!shouldFixPlacement(rt, e.block, e.oldStateId, e.player, e.pos.toPos())) return;
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final level = HostBlockGetter(world);
    final placed = rt.stateOf(e.block, e.stateIndex);
    final player = rt.playerOf(server, e.player);
    BState? state;
    if (player != null) {
      final click = rt.clickFor(e.player, pos);
      state = ladderStateForPlacement(
        level: level,
        pos: pos,
        defaultState: placed,
        nearestLooking: rt.nearestLooking(player),
        inWater: placed.flag('waterlogged'),
        replacingClickedOnBlock: click != null && click.clickedPos == pos,
        clickedFace: click?.face ?? d.Direction.up,
      );
    }
    state ??= ladderCanSurvive(level, pos, placed) ? placed : _anySurvivingFacing(level, pos, placed);
    if (state == null) {
      scheduleBreak(world, pos);
      return;
    }
    await fixPlacedState(world, pos, placed, state);
  },
  onUpdateShape: (server, e) async {
    final state = rt.stateOf(e.block, e.stateIndex);
    final pos = e.pos.toPos();
    if (state.flag('waterlogged')) updateWater(e.targetWorld, pos, state);
    if (!ladderCanSurvive(HostBlockGetter(e.targetWorld), pos, state)) scheduleBreak(e.targetWorld, pos);
    return null;
  },
  onScheduledTick: (server, e) async {
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final level = HostBlockGetter(world);
    final state = level.stateAt(pos);
    if (state.key == e.block && !ladderCanSurvive(level, pos, state)) await breakWithDrops(world, pos);
  },
  onUseWithItem: (server, e) async {
    // `MetalLadderBlock.useItemOn`: the placement helper stacks ladders.
    if (e.sneaking) return BlockUseResult.tryEmptyHand;
    final held = await e.item.getRegistryKey();
    if (!(held.startsWith('create:') && held.endsWith('_ladder'))) return BlockUseResult.tryEmptyHand;
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final state = rt.stateOf(e.block, e.stateIndex);
    final offset = ladderPlacementOffset(
      level: HostBlockGetter(world),
      state: state,
      pos: pos,
      playerPitch: e.player.getPitch(),
      range: rt.placementRange(),
    );
    return placeFromOffset(rt, world: world, player: e.player, hand: e.hand, itemKey: held, offset: offset);
  },
);

BState? _anySurvivingFacing(BlockGetter level, Pos pos, BState placed) {
  for (final f in d.Direction.planeHorizontal) {
    final s = placed.setValue('facing', f.serializedName);
    if (ladderCanSurvive(level, pos, s)) return s;
  }
  return null;
}

// -- Scaffolding -------------------------------------------------------------------------------



BlockBehavior scaffoldingBehavior(DecorationRuntime rt) => BlockBehavior(
  onPlaced: (server, e) async {
    if (!shouldFixPlacement(rt, e.block, e.oldStateId, e.player, e.pos.toPos())) return;
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final placed = rt.stateOf(e.block, e.stateIndex);
    final fixed = scaffoldingStateForPlacement(HostBlockGetter(world), pos, placed);
    await fixPlacedState(world, pos, placed, fixed);
  },
  onUpdateShape: (server, e) async {
    final block = rt.blocks[e.block]!;
    final state = rt.stateOf(e.block, e.stateIndex);
    final pos = e.pos.toPos();
    if (state.flag('waterlogged')) updateWater(e.targetWorld, pos, state);
    final next = scaffoldingUpdateShape(HostBlockGetter(e.targetWorld), pos, state, dirOf(e.direction));
    return shapeAnswer(block, state, next);
  },
  onUseWithItem: (server, e) async {
    // `MetalScaffoldingBlockItem.updatePlacementContext`: stack scaffolding along a line.
    final held = await e.item.getRegistryKey();
    if (held != e.block) return BlockUseResult.tryEmptyHand;
    final world = e.targetWorld;
    final level = HostBlockGetter(world);
    final target = scaffoldingItemTarget(
      level: level,
      blockKey: e.block,
      clickedPos: e.pos.toPos(),
      clickedFace: dirOf(e.face),
      horizontalDirection: rt.horizontalDirection(e.player),
      secondaryUse: e.sneaking,
      minY: world.getMinY(),
      maxY: rt.maxY(world),
    );
    if (target == null) return BlockUseResult.fail;
    final block = rt.blocks[e.block]!;
    final state = scaffoldingStateForPlacement(level, target, BState(block.key, block.definition.defaultState));
    await setBlockState(world, target, state);
    rt.playSound(world, target, rt.placeSoundOf(e.block), volume: 0.75, pitch: 0.8);
    if (!e.player.isCreative) await rt.shrinkHeld(e.player, e.hand);
    return BlockUseResult.success;
  },
);

// -- Cardboard ---------------------------------------------------------------------------------

BlockBehavior cardboardBehavior(DecorationRuntime rt) => BlockBehavior(
  onPlaced: (server, e) async {
    if (!shouldFixPlacement(rt, e.block, e.oldStateId, e.player, e.pos.toPos())) return;
    final player = rt.playerOf(server, e.player);
    if (player == null) return;
    // `getStateForPlacement`: the horizontal axis of the direction the player faces.
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final placed = rt.stateOf(e.block, e.stateIndex);
    final fixed = placed.setValue('axis', rt.horizontalDirection(player).axis.serializedName);
    await fixPlacedState(world, pos, placed, fixed);
  },
  onFireSpread: (server, e) => (spreadChance: cardboardFireSpread, burnChance: cardboardFlammability),
);

// -- Train trapdoors ---------------------------------------------------------------------------



BlockBehavior trapdoorBehavior(DecorationRuntime rt) => BlockBehavior(
  onPlaced: (server, e) async {
    if (!shouldFixPlacement(rt, e.block, e.oldStateId, e.player, e.pos.toPos())) return;
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final placed = rt.stateOf(e.block, e.stateIndex);
    final player = rt.playerOf(server, e.player);
    final click = rt.clickFor(e.player, pos);
    var state = placed;
    if (player != null && click != null) {
      final replacing = click.clickedPos == pos;
      if (!replacing && click.face.axis.isHorizontal) {
        state = state
            .setValue('facing', click.face.serializedName)
            .setValue('half', click.cursor.$2 > 0.5 ? 'top' : 'bottom');
      } else {
        state = state
            .setValue('facing', rt.horizontalDirection(player).opposite.serializedName)
            .setValue('half', click.face == d.Direction.up ? 'bottom' : 'top');
      }
    }
    final signal = await hasNeighborSignal(world, pos);
    if (signal) state = state.setFlag('open', true).setFlag('powered', true);
    state = state.setFlag('waterlogged', placed.flag('waterlogged'));
    await fixPlacedState(world, pos, placed, state);
  },
  onUseWithoutItem: (server, e) async {
    // `TrainTrapdoorBlock.useWithoutItem`
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final state = rt.stateOf(e.block, e.stateIndex).cycleFlag('open');
    await setBlockState(world, pos, state, flags: BlockUpdateFlags.clientsOnly);
    if (state.flag('waterlogged')) updateWater(world, pos, state);
    _playTrapdoorSound(rt, world, pos, state.flag('open'));
    return BlockUseResult.success;
  },
  onNeighborUpdate: (server, e) async {
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    var state = rt.stateOf(e.block, e.stateIndex);
    final signal = await hasNeighborSignal(world, pos);
    if (signal == state.flag('powered')) return;
    if (state.flag('open') != signal) {
      state = state.setFlag('open', signal);
      _playTrapdoorSound(rt, world, pos, signal);
    }
    await setBlockState(world, pos, state.setFlag('powered', signal), flags: BlockUpdateFlags.clientsOnly);
    if (state.flag('waterlogged')) updateWater(world, pos, state);
  },
  onUpdateShape: (server, e) async {
    final state = rt.stateOf(e.block, e.stateIndex);
    if (state.flag('waterlogged')) updateWater(e.targetWorld, e.pos.toPos(), state);
    return null;
  },
);

void _playTrapdoorSound(DecorationRuntime rt, World world, Pos pos, bool opening) {
  rt.playSound(
    world,
    pos,
    opening ? trapdoorOpenSound : trapdoorCloseSound,
    pitch: _random.nextDouble() * 0.1 + 0.9,
  );
}
