// Behaviours of the vanilla-like block families of the palettes: stairs, slabs, walls, panes
// and bars, connected pillars and the weathering copper.
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/blocks.dart';
import '../common/data.dart';
import '../common/direction.dart' as d;
import '../common/host_bridge.dart';
import '../common/pos.dart';
import 'behaviour_support.dart';
import 'connected_pillar.dart';
import 'misc_blocks.dart';
import 'runtime.dart';
import 'vanilla_blocks.dart';

final math.Random _random = math.Random();

// -- Shape rules -------------------------------------------------------------------------------







// -- Common pieces -----------------------------------------------------------------------------

/// The `update-shape` answer for a neighbour-recomputed state of the block that raised the event.
Future<int?> _updateShapeFor(
  DecorationRuntime rt,
  CustomBlockUpdateShapeEventData e,
  BState Function(HostBlockGetter level, Pos pos, BState state, d.Direction direction) update,
) async {
  final block = rt.blocks[e.block]!;
  final state = rt.stateOf(e.block, e.stateIndex);
  final pos = e.pos.toPos();
  final level = HostBlockGetter(e.targetWorld);
  if (state.has('waterlogged')) updateWater(e.targetWorld, pos, state);
  final next = update(level, pos, state, dirOf(e.direction));
  return shapeAnswer(block, state, next);
}

// -- Stairs ------------------------------------------------------------------------------------

BlockBehavior stairBehavior(DecorationRuntime rt, {bool weathering = false, bool copper = false}) => BlockBehavior(
  onPlaced: (server, e) async {
    if (!shouldFixPlacement(rt, e.block, e.oldStateId, e.player, e.pos.toPos())) return;
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final placed = rt.stateOf(e.block, e.stateIndex);
    final fixed = stairsStateForPlacement(HostBlockGetter(world), pos, placed);
    await fixPlacedState(world, pos, placed, fixed);
  },
  onUpdateShape: (server, e) =>
      _updateShapeFor(rt, e, (level, pos, state, direction) => stairsUpdateShape(level, pos, state, direction)),
  onRandomTick: weathering ? (server, e) => copperRandomTick(rt, e) : null,
  onUseWithItem: copper ? (server, e) async => (await copperInteraction(rt, e)) ?? BlockUseResult.tryEmptyHand : null,
);

// -- Slabs -------------------------------------------------------------------------------------

BlockBehavior slabBehavior(DecorationRuntime rt, {bool weathering = false}) => BlockBehavior(
  onUpdateShape: (server, e) async {
    // Slabs only keep their water ticking.
    final state = rt.stateOf(e.block, e.stateIndex);
    if (state.flag('waterlogged')) updateWater(e.targetWorld, e.pos.toPos(), state);
    return null;
  },
  onRandomTick: weathering ? (server, e) => copperRandomTick(rt, e) : null,
  onUseWithItem: (server, e) async {
    final copper = await copperInteraction(rt, e);
    if (copper != null) return copper;
    // A slab item on a half slab makes a double slab (`SlabBlock.canBeReplaced` + placement).
    final state = rt.stateOf(e.block, e.stateIndex);
    final held = await e.item.getRegistryKey();
    if (held != e.block) return BlockUseResult.tryEmptyHand;
    if (!slabCanBeReplaced(state['type'] ?? 'double', clickedFace: dirOf(e.face), cursorY: e.cursor.$2)) {
      return BlockUseResult.tryEmptyHand;
    }
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    await setBlockState(world, pos, slabMerged(state));
    rt.playSound(world, pos, rt.placeSoundOf(e.block), volume: 1, pitch: 0.8);
    if (!e.player.isCreative) await rt.shrinkHeld(e.player, e.hand);
    return BlockUseResult.success;
  },
);

// -- Walls -------------------------------------------------------------------------------------

BlockBehavior wallBehavior(DecorationRuntime rt) {
  final cache = <int, (List<BlockBox>, List<BlockBox>)>{};
  return BlockBehavior(
    onPlaced: (server, e) async {
      if (!shouldFixPlacement(rt, e.block, e.oldStateId, e.player, e.pos.toPos())) return;
      final world = e.targetWorld;
      final pos = e.pos.toPos();
      final placed = rt.stateOf(e.block, e.stateIndex);
      final fixed = wallStateForPlacement(HostBlockGetter(world), pos, placed, inWater: placed.flag('waterlogged'));
      await fixPlacedState(world, pos, placed, fixed);
    },
    onUpdateShape: (server, e) =>
        _updateShapeFor(rt, e, (level, pos, state, direction) => wallUpdateShape(level, pos, state, direction)),
    onShape: (server, e) async {
      final shapes = cache.putIfAbsent(e.stateIndex, () {
        final s = rt.stateOf(e.block, e.stateIndex);
        return (wallShapeOf(s, collision: true), wallShapeOf(s));
      });
      return e.kind == BlockShapeKind.collision ? shapes.$1 : shapes.$2;
    },
  );
}

// -- Panes and bars -----------------------------------------------------------------------------

BlockBehavior paneBehavior(DecorationRuntime rt) => BlockBehavior(
  onPlaced: (server, e) async {
    if (!shouldFixPlacement(rt, e.block, e.oldStateId, e.player, e.pos.toPos())) return;
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final placed = rt.stateOf(e.block, e.stateIndex);
    final fixed = barsStateForPlacement(HostBlockGetter(world), pos, placed, inWater: placed.flag('waterlogged'));
    await fixPlacedState(world, pos, placed, fixed);
  },
  onUpdateShape: (server, e) =>
      _updateShapeFor(rt, e, (level, pos, state, direction) => barsUpdateShape(level, pos, state, direction)),
);

// -- Connected pillars --------------------------------------------------------------------------

BlockBehavior pillarBehavior(DecorationRuntime rt) => BlockBehavior(
  onPlaced: (server, e) async {
    if (!shouldFixPlacement(rt, e.block, e.oldStateId, e.player, e.pos.toPos())) return;
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final level = HostBlockGetter(world);
    var placed = rt.stateOf(e.block, e.stateIndex);
    var state = placed;
    final click = rt.clickFor(e.player, pos);
    if (click != null) {
      // `LayeredBlock.getStateForPlacement`: continue the axis of the pillar we were placed on.
      final against = level.stateAt(pos.relative(click.face.opposite));
      state = state.setValue(
        'axis',
        pillarPlacementAxis(clickedFace: click.face, placedOn: against, selfKey: e.block, sneaking: click.sneaking),
      );
    }
    state = pillarUpdateColumn(level, pos, state);
    await fixPlacedState(world, pos, placed, state);
    // `onPlace`: re-check the column one tick later.
    world.scheduleBlockTick(pos: pos.toBlockPos(), delayTicks: 1, priority: TickPriority.normal);
  },
  onScheduledTick: (server, e) async {
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final level = HostBlockGetter(world);
    final state = level.stateAt(pos);
    if (state.key != e.block) return;
    final axis = state.axisOf('axis');
    if (axis == null) return;
    final below = pos.relative(d.Direction.fromAxisAndDirection(axis, d.AxisDirection.negative));
    if (!pillarCanConnect(state, level.stateAt(below))) {
      await setBlockState(world, pos, pillarUpdateColumn(level, pos, state));
    }
  },
  onUpdateShape: (server, e) async {
    final block = rt.blocks[e.block]!;
    final state = rt.stateOf(e.block, e.stateIndex);
    final neighbour = HostBlockGetter.stateOfId(e.neighborStateId);
    final next = pillarUpdateShape(state, dirOf(e.direction), neighbour);
    return shapeAnswer(block, state, next);
  },
  onStateReplaced: (server, e) async {
    // `affectNeighborsAfterRemoval`
    if (e.moved) return;
    final world = e.targetWorld;
    final pos = e.pos.toPos();
    final level = HostBlockGetter(world);
    final old = rt.stateOf(e.block, e.oldStateIndex);
    final axis = old.axisOf('axis');
    if (axis == null) return;
    for (final dir in Iterate.directionsInAxis(axis)) {
      final rel = pos.relative(dir);
      final adjacent = level.stateAt(rel);
      if (pillarCanConnect(old, adjacent)) {
        await setBlockState(world, rel, pillarUpdateColumn(level, rel, adjacent));
      }
    }
  },
);

// -- Weathering copper ------------------------------------------------------------------------

/// `WeatheringCopperFullBlock.randomTick` -> `ChangeOverTimeBlock.changeOverTime`.
Future<void> copperRandomTick(DecorationRuntime rt, CustomBlockTickEventData e) async {
  if (_random.nextDouble() >= copperChangeChance) return;
  final key = e.block;
  final path = key.substring(key.indexOf(':') + 1);
  final age = copperWeatherAge(key);
  final nextPath = createCopperNext(path);
  if (age == null || nextPath == null) return;
  final world = e.targetWorld;
  final pos = e.pos.toPos();
  final level = HostBlockGetter(world);
  if (!copperShouldAdvance(level, pos, age, _random.nextDouble())) return;
  final state = rt.stateOf(key, e.stateIndex);
  await setBlockState(world, pos, BState('create:$nextPath', state.props));
}

/// Honeycomb waxes and axes scrape or unwax a Create copper block (the NeoForge oxidizable and
/// waxable data maps that `CopperRegistries` fills). Returns `null` when the item does nothing here.
Future<BlockUseResult?> copperInteraction(DecorationRuntime rt, CustomBlockUseEventData e) async {
  final key = e.block;
  if (!key.contains('copper')) return null;
  final path = key.substring(key.indexOf(':') + 1);
  final held = await e.item.getRegistryKey();
  final world = e.targetWorld;
  final pos = e.pos.toPos();
  final state = rt.stateOf(key, e.stateIndex);
  if (held == 'minecraft:honeycomb') {
    final waxed = createCopperWaxed(path);
    if (waxed == null) return null;
    await setBlockState(world, pos, BState('create:$waxed', state.props));
    rt.playSound(world, pos, 'minecraft:item.honeycomb.wax_on');
    if (!e.player.isCreative) await rt.shrinkHeld(e.player, e.hand);
    return BlockUseResult.success;
  }
  if (isAxeItem(held)) {
    final previous = createCopperPrevious(path);
    if (previous != null) {
      await setBlockState(world, pos, BState('create:$previous', state.props));
      rt.playSound(world, pos, 'minecraft:item.axe.scrape');
      return BlockUseResult.success;
    }
    final unwaxed = createCopperUnwaxed(path);
    if (unwaxed != null) {
      await setBlockState(world, pos, BState('create:$unwaxed', state.props));
      rt.playSound(world, pos, 'minecraft:item.axe.wax_off');
      return BlockUseResult.success;
    }
  }
  return null;
}
