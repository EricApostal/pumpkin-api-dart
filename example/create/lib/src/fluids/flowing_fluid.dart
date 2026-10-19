// The flow physics of Create's placeable fluids, honey and chocolate (pure): vanilla's
// `FlowingFluid` (tick, spread, slope search) over the `level` property of their `LiquidBlock`s
// (0 source, 1 to 7 flowing, 8 and more falling). The host has no flow physics for registered
// fluids, so the fluid blocks call [FlowingFluidLogic.tick] from their scheduled ticks.
import '../api/block_state.dart';
import '../common/direction.dart';
import '../common/pos.dart';
import 'fluid_stack.dart';
import 'fluid_world.dart';

/// The parameters of a flowing fluid (`BaseFlowingFluid.Properties`).
final class FlowingFluidDef {
  /// The still fluid (`create:honey`).
  final String still;
  final String flowing;

  /// The `LiquidBlock` that holds it.
  final String blockKey;
  final int tickRate;
  final int levelDecreasePerBlock;
  final int slopeFindDistance;
  final bool canConvertToSource;

  const FlowingFluidDef({
    required this.still,
    required this.flowing,
    required this.blockKey,
    this.tickRate = 5,
    this.levelDecreasePerBlock = 1,
    this.slopeFindDistance = 4,
    this.canConvertToSource = false,
  });

  /// Honey: slow and sticky.
  static const FlowingFluidDef honey = FlowingFluidDef(
    still: FluidKeys.honey,
    flowing: FluidKeys.flowingHoney,
    blockKey: 'create:honey',
    tickRate: 25,
    levelDecreasePerBlock: 2,
    slopeFindDistance: 3,
  );

  static const FlowingFluidDef chocolate = FlowingFluidDef(
    still: FluidKeys.chocolate,
    flowing: FluidKeys.flowingChocolate,
    blockKey: 'create:chocolate',
    tickRate: 25,
    levelDecreasePerBlock: 2,
    slopeFindDistance: 3,
  );

  /// Both fluids by their block key.
  static const Map<String, FlowingFluidDef> byBlock = {'create:honey': honey, 'create:chocolate': chocolate};
}

/// The `level` property of a fluid block as a fluid state.
FluidInfo fluidInfoOfBlock(BState state, FlowingFluidDef def) {
  if (state.key != def.blockKey) return FluidInfo.none;
  final level = state.intValue('level');
  if (level == 0) return FluidInfo(def.still, 8, isSource: true);
  final falling = level >= 8;
  return FluidInfo(def.still, falling ? 8 : 8 - level, isFalling: falling);
}

/// `LiquidBlock.getLegacyLevel`: the `level` property of a fluid state.
int legacyLevel(FluidInfo info) => info.isSource ? 0 : 8 - (info.level > 8 ? 8 : info.level) + (info.isFalling ? 8 : 0);

/// The state of the fluid block for [info] (`FluidState.createLegacyBlock`).
BState fluidBlockState(FlowingFluidDef def, FluidInfo info) =>
    info.isEmpty ? BState.air : BState(def.blockKey, {'level': '${legacyLevel(info)}'});

class FlowingFluidLogic {
  final FlowingFluidDef def;
  final FluidWorld world;

  FlowingFluidLogic(this.def, this.world);

  static const List<Direction> _horizontal = [Direction.north, Direction.east, Direction.south, Direction.west];

  /// The fluid state at [pos] as this fluid sees it: its own block's level, the host's fluid
  /// state for everything else.
  FluidInfo infoAt(Pos pos) {
    final own = fluidInfoOfBlock(world.stateAt(pos), def);
    if (!own.isEmpty) return own;
    return world.fluidAt(pos);
  }

  bool _isSame(FluidInfo f) => !f.isEmpty && FluidKeys.still(f.fluid) == def.still;

  /// `FlowingFluid.tick(level, pos, fluidState)`.
  void tick(Pos pos) {
    var fluidState = infoAt(pos);
    if (!_isSame(fluidState)) return;
    if (!fluidState.isSource) {
      final newState = getNewLiquid(pos, world.stateAt(pos));
      if (newState.isEmpty) {
        fluidState = newState;
        world.setBlock(pos, BState.air);
      } else if (!_equal(newState, fluidState)) {
        fluidState = newState;
        world.setBlock(pos, fluidBlockState(def, newState), quiet: true);
        world.scheduleFluidTick(pos, def.still, def.tickRate);
        world.neighboursChanged(pos);
      }
    }
    spread(pos, fluidState);
  }

  static bool _equal(FluidInfo a, FluidInfo b) =>
      a.fluid == b.fluid && a.level == b.level && a.isSource == b.isSource && a.isFalling == b.isFalling;

  /// `spread(level, pos, fluidState)`.
  void spread(Pos pos, FluidInfo fluidState) {
    if (fluidState.isEmpty) return;
    final blockState = world.stateAt(pos);
    final below = pos.below;
    final belowState = world.stateAt(below);
    final newBelowFluid = getNewLiquid(below, belowState);
    if (canSpreadTo(pos, blockState, Direction.down, below, belowState, infoAt(below), newBelowFluid)) {
      spreadTo(below, belowState, newBelowFluid);
      if (sourceNeighborCount(pos) >= 3) spreadToSides(pos, fluidState, blockState);
    } else if (fluidState.isSource || !isWaterHole(pos, blockState, below, belowState)) {
      spreadToSides(pos, fluidState, blockState);
    }
  }

  /// `spreadToSides(level, pos, fluidState, blockState)`.
  void spreadToSides(Pos pos, FluidInfo fluidState, BState blockState) {
    var newAmount = fluidState.level - def.levelDecreasePerBlock;
    if (fluidState.isFalling) newAmount = 7;
    if (newAmount <= 0) return;

    final map = getSpread(pos, blockState);
    for (final entry in map.entries) {
      final direction = entry.key;
      final newFluid = entry.value;
      final relative = pos.relative(direction);
      if (canSpreadTo(pos, blockState, direction, relative, world.stateAt(relative), infoAt(relative), newFluid)) {
        spreadTo(relative, world.stateAt(relative), newFluid);
      }
    }
  }

  /// `getNewLiquid(level, pos, blockState)`.
  FluidInfo getNewLiquid(Pos pos, BState blockState) {
    var highest = 0;
    var neighbors = 0;

    for (final dir in _horizontal) {
      final relative = pos.relative(dir);
      final relState = world.stateAt(relative);
      final relFluid = infoAt(relative);
      if (_isSame(relFluid) && canPassThroughWall(dir, pos, blockState, relative, relState)) {
        if (relFluid.isSource && def.canConvertToSource) neighbors++;
        if (relFluid.level > highest) highest = relFluid.level;
      }
    }

    if (def.canConvertToSource && neighbors >= 2) {
      final below = pos.below;
      final belowState = world.stateAt(below);
      final belowFluid = infoAt(below);
      if (!world.collisionShapeEmpty(below) && belowState.key != blockState.key || (_isSame(belowFluid) && belowFluid.isSource)) {
        return FluidInfo(def.still, 8, isSource: true);
      }
    }

    final above = pos.above;
    final aboveState = world.stateAt(above);
    final aboveFluid = infoAt(above);
    if (!aboveFluid.isEmpty && _isSame(aboveFluid) && canPassThroughWall(Direction.up, pos, blockState, above, aboveState)) {
      return FluidInfo(def.still, 8, isFalling: true);
    }

    final newAmount = highest - def.levelDecreasePerBlock;
    if (newAmount <= 0) return FluidInfo.none;
    return FluidInfo(def.still, newAmount);
  }

  /// `sourceNeighborCount(level, pos)`.
  int sourceNeighborCount(Pos pos) {
    var count = 0;
    for (final dir in _horizontal) {
      final f = infoAt(pos.relative(dir));
      if (_isSame(f) && f.isSource) count++;
    }
    return count;
  }

  /// `getSpread(level, pos, blockState)`: the sides the fluid flows to, the shortest slope first.
  Map<Direction, FluidInfo> getSpread(Pos pos, BState blockState) {
    var best = 1000;
    final map = <Direction, FluidInfo>{};
    final cache = <Pos, bool>{};
    for (final dir in _horizontal) {
      final relPos = pos.relative(dir);
      final relState = world.stateAt(relPos);
      final relFluid = infoAt(relPos);
      final newFluid = getNewLiquid(relPos, relState);
      if (canPassThrough(pos, blockState, dir, relPos, relState, relFluid)) {
        final int j;
        final belowRel = relPos.below;
        if (isWaterHole(relPos, relState, belowRel, world.stateAt(belowRel))) {
          j = 0;
        } else {
          j = getSlopeDistance(relPos, 1, dir.opposite, relState, pos, cache);
        }
        if (j < best) map.clear();
        if (j <= best) {
          map[dir] = newFluid;
          best = j;
        }
      }
    }
    return map;
  }

  /// `getSlopeDistance(level, pos, i, from, blockState, originalPos, cache)`.
  int getSlopeDistance(Pos pos, int i, Direction from, BState blockState, Pos originalPos, Map<Pos, bool> cache) {
    var j = 1000;
    for (final dir in _horizontal) {
      if (dir == from) continue;
      final relPos = pos.relative(dir);
      final relState = world.stateAt(relPos);
      final relFluid = infoAt(relPos);
      if (canPassThrough(pos, blockState, dir, relPos, relState, relFluid)) {
        final belowRel = relPos.below;
        if (isWaterHole(relPos, relState, belowRel, world.stateAt(belowRel))) return i;
        if (i < def.slopeFindDistance) {
          final k = getSlopeDistance(relPos, i + 1, dir.opposite, relState, originalPos, cache);
          if (k < j) j = k;
        }
      }
    }
    return j;
  }

  /// `canPassThrough(level, fluid, fromPos, fromBlockState, direction, toPos, toBlockState, toFluidState)`.
  bool canPassThrough(Pos fromPos, BState fromState, Direction direction, Pos toPos, BState toState, FluidInfo toFluid) =>
      !(_isSame(toFluid) && toFluid.isSource) &&
      canPassThroughWall(direction, fromPos, fromState, toPos, toState) &&
      canHoldFluid(toPos, toState);

  /// `isWaterHole(level, fluid, pos, blockState, belowPos, belowState)`.
  bool isWaterHole(Pos pos, BState blockState, Pos belowPos, BState belowState) {
    if (!canPassThroughWall(Direction.down, pos, blockState, belowPos, belowState)) return false;
    return _isSame(infoAt(belowPos)) ? true : canHoldFluid(belowPos, belowState);
  }

  /// `canPassThroughWall(direction, level, pos, state, relPos, relState)`: neither block closes
  /// the face between them.
  bool canPassThroughWall(Direction direction, Pos pos, BState state, Pos relPos, BState relState) {
    if (state.isAir && relState.isAir) return true;
    final closes = world.isFaceSturdy(pos, direction) || world.isFaceSturdy(relPos, direction.opposite);
    return !closes;
  }

  /// `canSpreadTo(level, fromPos, fromBlockState, direction, toPos, toBlockState, toFluidState, fluid)`.
  bool canSpreadTo(Pos fromPos, BState fromState, Direction direction, Pos toPos, BState toState, FluidInfo toFluid, FluidInfo newFluid) {
    // `FluidState.canBeReplacedWith`: no fluid there, or another fluid than this one from above.
    final replaceable = toFluid.isEmpty || (direction == Direction.down && !_isSame(toFluid));
    return replaceable && canPassThroughWall(direction, fromPos, fromState, toPos, toState) && canHoldFluid(toPos, toState);
  }

  /// `canHoldFluid(level, pos, state, fluid)`.
  bool canHoldFluid(Pos pos, BState state) {
    if (state.key == 'minecraft:kelp' ||
        state.key == 'minecraft:kelp_plant' ||
        state.key == 'minecraft:seagrass' ||
        state.key == 'minecraft:tall_seagrass') {
      return false;
    }
    if (state.has('waterlogged')) return false;
    if (world.hasTag(pos, 'minecraft:doors') ||
        world.hasTag(pos, 'minecraft:all_signs') ||
        state.key == 'minecraft:ladder' ||
        state.key == 'minecraft:sugar_cane' ||
        state.key == 'minecraft:bubble_column') {
      return false;
    }
    if (state.key == 'minecraft:nether_portal' ||
        state.key == 'minecraft:end_portal' ||
        state.key == 'minecraft:end_gateway' ||
        state.key == 'minecraft:structure_void') {
      return false;
    }
    return world.collisionShapeEmpty(pos);
  }

  /// `spreadTo(level, pos, blockState, direction, fluidState)`.
  void spreadTo(Pos pos, BState blockState, FluidInfo fluidState) {
    if (!blockState.isAir && !blockState.has('level')) world.dropResources(pos);
    world.setBlock(pos, fluidBlockState(def, fluidState));
  }

  /// The lava interactions of the fluid (`AllFluids.registerFluidInteractions`): lava next to
  /// the fluid hardens into obsidian (a source) or the fluid's stone (flowing lava). Returns the
  /// positions that changed.
  List<Pos> reactWithLava(Pos pos) {
    final changed = <Pos>[];
    for (final dir in Direction.values) {
      if (dir == Direction.down) continue;
      final other = pos.relative(dir);
      final f = world.fluidAt(other);
      if (f.isEmpty || FluidKeys.still(f.fluid) != FluidKeys.lava) continue;
      final BState result = f.isSource
          ? const BState('minecraft:obsidian')
          : (def.still == FluidKeys.honey ? const BState('create:limestone') : const BState('create:scoria'));
      world.setBlock(other, result);
      world.playSound(other, 'minecraft:block.lava.extinguish', volume: 0.5, pitch: 2.6);
      changed.add(other);
    }
    return changed;
  }
}
