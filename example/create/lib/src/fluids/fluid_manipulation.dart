// `FluidManipulationBehaviour`, `FluidFillingBehaviour` and `FluidDrainingBehaviour` (pure):
// what the hose pulley does to the fluid blocks of the world. The draining search finds the
// connected fluid blocks and removes them from the top down; the filling search finds the free
// space around the root and fills it from the bottom up. The host behaviours own one of each
// and delegate to these.
import 'dart:math' as math;

import '../api/block_state.dart';
import '../common/bounds.dart';
import '../common/direction.dart';
import '../common/pos.dart';
import '../core/nbt.dart';
import 'binary_heap.dart';
import 'fluid_helper.dart';
import 'fluid_stack.dart';
import 'fluid_world.dart';
import 'nbt_util.dart';
import 'pipe_blocks.dart';

/// What the manipulation behaviours need of their block entity.
abstract interface class ManipulationHost {
  /// The world, `null` while it is unloaded.
  FluidWorld? get fluidWorld;

  /// `blockEntity.getBlockPos()`.
  Pos get hostPos;

  /// `blockEntity.sendData()`.
  void sendData();

  /// `blockEntity.award(advancement)`.
  void award(String advancement);
}

/// `BlockPosEntry`.
final class BlockPosEntry {
  final Pos pos;
  final int distance;

  const BlockPosEntry(this.pos, this.distance);
}

/// `ChunkNotLoadedException`.
final class ChunkNotLoadedException implements Exception {
  const ChunkNotLoadedException();
}

abstract class FluidManipulation {
  final ManipulationHost host;

  BlockBounds? affectedArea;
  Pos? rootPos;
  bool infinite = false;
  bool counterpartActed = false;

  // Search
  static const int searchedPerTick = 1024;
  static const int validationTimerMin = 160;
  final List<BlockPosEntry> frontier = [];
  final Set<Pos> visited = {};
  int revalidateIn = 0;

  FluidManipulation(this.host) {
    setValidationTimer();
  }

  FluidWorld get level => host.fluidWorld!;

  bool get isInfinite => infinite;

  /// `counterpartActed()`.
  void notifyCounterpartActed() => counterpartActed = true;

  int validationTimer() {
    final maxBlocks = this.maxBlocks();
    // Allow enough time for the server's infinite block threshold to be reached
    return maxBlocks < 0 ? validationTimerMin : math.max(validationTimerMin, maxBlocks ~/ searchedPerTick + 1);
  }

  int setValidationTimer() => revalidateIn = validationTimer();

  int setLongValidationTimer() => revalidateIn = validationTimer() * 2;

  int maxRange() => host.fluidWorld?.config.hosePulleyRange ?? 128;

  int maxBlocks() => host.fluidWorld?.config.hosePulleyBlockThreshold ?? 10000;

  bool fillInfinite() => host.fluidWorld?.config.fillInfinite ?? false;

  /// `reset()`.
  void reset() {
    if (affectedArea != null) scheduleUpdatesInAffectedArea();
    affectedArea = null;
    setValidationTimer();
    frontier.clear();
    visited.clear();
    infinite = false;
  }

  /// `destroy()`.
  void destroy() => reset();

  /// `scheduleUpdatesInAffectedArea()`.
  void scheduleUpdatesInAffectedArea() {
    final world = host.fluidWorld;
    final area = affectedArea;
    if (world == null || area == null) return;
    final box = area.inflatedBy(1);
    for (final pos in box.positions()) {
      final next = world.fluidAt(pos);
      if (next.isEmpty) continue;
      world.scheduleFluidTick(pos, next.fluid, world.nextInt(5));
    }
  }

  /// `comparePositions(e1, e2)`.
  int comparePositions(BlockPosEntry e1, BlockPosEntry e2) {
    final root = rootPos!;
    final centerOfRoot = root.center;
    final pos2 = e2.pos;
    final pos1 = e1.pos;

    if (pos1.y != pos2.y) return pos2.y.compareTo(pos1.y);

    final compareDistance = e2.distance.compareTo(e1.distance);
    if (compareDistance != 0) return compareDistance;

    return _distSqr(pos2.center, centerOfRoot).compareTo(_distSqr(pos1.center, centerOfRoot));
  }

  static double _distSqr((double, double, double) a, (double, double, double) b) {
    final dx = a.$1 - b.$1, dy = a.$2 - b.$2, dz = a.$3 - b.$3;
    return dx * dx + dy * dy + dz * dz;
  }

  /// `search(fluid, frontier, visited, add, searchDownward)`: returns the fluid found (the still
  /// fluid key), `null` if none was seen yet.
  String? search(
    String? fluidIn,
    List<BlockPosEntry> frontier,
    Set<Pos> visited,
    void Function(Pos pos, int distance) add,
    bool searchDownward,
  ) {
    var fluid = fluidIn;
    final world = level;
    final maxBlocks = this.maxBlocks();
    final maxRange = this.maxRange();
    final maxRangeSq = maxRange * maxRange;
    final root = rootPos!;

    for (var i = 0; i < searchedPerTick && frontier.isNotEmpty && (visited.length <= maxBlocks || !canDrainInfinitely(fluid)); i++) {
      final entry = frontier.removeAt(0);
      final currentPos = entry.pos;
      if (visited.contains(currentPos)) continue;
      visited.add(currentPos);

      if (!world.isLoaded(currentPos)) throw const ChunkNotLoadedException();

      final fluidState = world.fluidAt(currentPos);
      if (fluidState.isEmpty) continue;

      final currentFluid = FluidHelper.convertToStill(fluidState.fluid);
      fluid ??= currentFluid;
      if (currentFluid != fluid) continue;

      add(currentPos, entry.distance);

      for (final side in Direction.values) {
        if (!searchDownward && side == Direction.down) continue;

        final offsetPos = currentPos.relative(side);
        if (!world.isLoaded(offsetPos)) throw const ChunkNotLoadedException();
        if (visited.contains(offsetPos)) continue;
        if (offsetPos.distSqr(root) > maxRangeSq) continue;

        final nextFluidState = world.fluidAt(offsetPos);
        if (nextFluidState.isEmpty) continue;
        final nextIsFlowing = !nextFluidState.isSource;
        if (nextIsFlowing && side == Direction.up && !(offsetPos.x == root.x && offsetPos.z == root.z)) continue;

        frontier.add(BlockPosEntry(offsetPos, entry.distance + 1));
      }
    }

    return fluid;
  }

  /// `playEffect(world, pos, fluid, fillSound)`.
  void playEffect(FluidWorld world, Pos? pos, String? fluid, bool fillSound) {
    if (fluid == null) return;
    final splooshPos = pos ?? host.hostPos;
    final stack = FStack(fluid, 1);
    final sound = fillSound ? FluidHelper.getFillSound(stack) : FluidHelper.getEmptySound(stack);
    world.playSound(splooshPos, sound, volume: 0.3, pitch: 1);
    world.splash(splooshPos, stack);
  }

  /// `canDrainInfinitely(fluid)`.
  bool canDrainInfinitely(String? fluid) {
    if (fluid == null) return false;
    final world = host.fluidWorld;
    if (world == null) return false;
    if (maxBlocks() == -1) return false;
    return switch (world.config.bottomlessFluidMode) {
      BottomlessFluidMode.allowAll => true,
      BottomlessFluidMode.denyAll => false,
      BottomlessFluidMode.allowByTag => world.fluidHasTag(fluid, 'create:bottomless/allow'),
      BottomlessFluidMode.denyByTag => !world.fluidHasTag(fluid, 'create:bottomless/deny'),
    };
  }

  /// `write(nbt, clientPacket)`: adds the data to [out].
  void write(Map<String, NbtValue> out) {
    if (infinite) out['Infinite'] = NbtValue.emptyCompound();
    final root = rootPos;
    if (root != null) out['LastPos'] = posToNbt(root);
    final area = affectedArea;
    if (area != null) {
      out['AffectedAreaFrom'] = posToNbt(area.minPos);
      out['AffectedAreaTo'] = posToNbt(area.maxPos);
    }
  }

  /// `read(nbt, clientPacket)`.
  void read(Map<String, NbtValue> nbt) {
    infinite = nbt.containsKey('Infinite');
    if (nbt.containsKey('LastPos')) rootPos = posFromNbt(nbt['LastPos']);
    if (nbt.containsKey('AffectedAreaFrom') && nbt.containsKey('AffectedAreaTo')) {
      final from = posFromNbt(nbt['AffectedAreaFrom']);
      final to = posFromNbt(nbt['AffectedAreaTo']);
      if (from != null && to != null) affectedArea = BlockBounds.fromCorners(from, to);
    }
  }
}

/// `FluidFillingBehaviour.SpaceType`.
enum SpaceType { fillable, filled, blocking }

class FluidFilling extends FluidManipulation {
  late final BinaryHeap<BlockPosEntry> queue = BinaryHeap<BlockPosEntry>((p, p2) => -comparePositions(p, p2));
  final List<BlockPosEntry> infinityCheckFrontier = [];
  final Set<Pos> infinityCheckVisited = {};

  FluidFilling(super.host) {
    revalidateIn = 1;
  }

  /// `tick()`.
  void tick() {
    final root = rootPos;
    if (infinityCheckFrontier.isNotEmpty && root != null && host.fluidWorld != null) {
      final fluid = level.fluidAt(root);
      if (!fluid.isEmpty) continueValidation(fluid.fluid);
    }
    if (revalidateIn > 0) revalidateIn--;
  }

  /// `continueValidation(fluid)`.
  void continueValidation(String fluid) {
    try {
      search(fluid, infinityCheckFrontier, infinityCheckVisited, (p, d) => infinityCheckFrontier.add(BlockPosEntry(p, d)), true);
    } on ChunkNotLoadedException {
      infinityCheckFrontier.clear();
      infinityCheckVisited.clear();
      setLongValidationTimer();
      return;
    }

    final maxBlocks = this.maxBlocks();
    if (infinityCheckVisited.length >= maxBlocks && maxBlocks != -1 && !fillInfinite()) {
      if (!infinite) {
        reset();
        infinite = true;
        host.sendData();
      }
      infinityCheckFrontier.clear();
      setLongValidationTimer();
      return;
    }

    if (infinityCheckFrontier.isNotEmpty) return;
    if (infinite) {
      reset();
      return;
    }
    infinityCheckVisited.clear();
  }

  /// `tryDeposit(fluid, root, simulate)`: places a source of [fluid] in the free space around
  /// [root]. Returns whether it was (or would be) placed.
  bool tryDeposit(String fluid, Pos root, {required bool simulate}) {
    if (root != rootPos) {
      reset();
      rootPos = root;
      queue.enqueue(BlockPosEntry(root, 0));
      affectedArea = BlockBounds.fromCorners(root, root);
      return false;
    }

    if (counterpartActed) {
      counterpartActed = false;
      softReset(root);
      return false;
    }

    affectedArea ??= BlockBounds.fromCorners(root, root);

    if (revalidateIn == 0) {
      visited.clear();
      infinityCheckFrontier.clear();
      infinityCheckVisited.clear();
      infinityCheckFrontier.add(BlockPosEntry(root, 0));
      setValidationTimer();
      softReset(root);
    }

    final world = level;
    final maxRange = this.maxRange();
    final maxRangeSq = maxRange * maxRange;
    final maxBlocks = this.maxBlocks();

    final evaporate = world.waterEvaporates && FluidHelper.isWaterTag(world, fluid);
    final canPlaceSources = world.config.fluidFillPlaceFluidSourceBlocks;

    if ((!fillInfinite() && infinite) || evaporate || !canPlaceSources) {
      final fluidState = world.fluidAt(root);
      final equivalentTo = !fluidState.isEmpty && FluidHelper.convertToStill(fluidState.fluid) == FluidHelper.convertToStill(fluid);
      if (!equivalentTo && !evaporate && canPlaceSources) return false;
      if (simulate) return true;
      playEffect(world, root, fluid, false);
      if (evaporate) {
        final r = world.nextDouble() - world.nextDouble();
        world.playSound(root, 'minecraft:block.fire.extinguish', volume: 0.5, pitch: 2.6 + r * 0.8);
      } else if (!canPlaceSources) {
        host.award('hose_pulley');
      }
      return true;
    }

    var success = false;
    for (var i = 0; !success && queue.isNotEmpty && i < FluidManipulation.searchedPerTick; i++) {
      final entry = queue.first;
      final currentPos = entry.pos;
      if (visited.contains(currentPos)) {
        queue.dequeue();
        continue;
      }

      if (!simulate) visited.add(currentPos);

      if (visited.length >= maxBlocks && maxBlocks != -1) {
        infinite = true;
        if (!fillInfinite()) {
          visited.clear();
          queue.clear();
          return false;
        }
      }

      final spaceType = getAtPos(world, currentPos, fluid);
      if (spaceType == SpaceType.blocking) continue;

      if (spaceType == SpaceType.fillable) {
        success = true;
        if (!simulate) {
          playEffect(world, currentPos, fluid, false);
          final blockState = world.stateAt(currentPos);
          if (blockState.has('waterlogged') && FluidHelper.isWater(fluid)) {
            world.setBlock(currentPos, updatePostWaterlogging(blockState.setFlag('waterlogged', true)), quiet: true);
          } else {
            replaceBlock(world, currentPos, blockState);
            world.placeFluidSource(currentPos, FluidHelper.convertToStill(fluid));
          }
          affectedArea = affectedArea!.encapsulatePos(currentPos);
        }
      }

      if (simulate && success) return true;
      visited.add(currentPos);
      queue.dequeue();

      for (final side in Direction.values) {
        if (side == Direction.up) continue;

        final offsetPos = currentPos.relative(side);
        if (visited.contains(offsetPos)) continue;
        if (offsetPos.distSqr(root) > maxRangeSq) continue;

        final nextSpaceType = getAtPos(world, offsetPos, fluid);
        if (nextSpaceType != SpaceType.blocking) queue.enqueue(BlockPosEntry(offsetPos, entry.distance + 1));
      }
    }

    if (!simulate && success) host.award('hose_pulley');
    return success;
  }

  /// `softReset(root)`.
  void softReset(Pos root) {
    visited.clear();
    queue.clear();
    queue.enqueue(BlockPosEntry(root, 0));
    infinite = false;
    setValidationTimer();
    host.sendData();
  }

  /// `getAtPos(world, pos, toFill)`.
  SpaceType getAtPos(FluidWorld world, Pos pos, String toFill) {
    final blockState = world.stateAt(pos);
    final fluidState = world.fluidAt(pos);

    if (blockState.has('waterlogged')) {
      return FluidHelper.isWater(toFill)
          ? (blockState.flag('waterlogged') ? SpaceType.filled : SpaceType.fillable)
          : SpaceType.blocking;
    }

    if (PipeBlocks.isLiquidBlock(blockState)) {
      return blockState.intValue('level') == 0
          ? (FluidHelper.convertToStill(toFill) == FluidHelper.convertToStill(fluidState.fluid) ? SpaceType.filled : SpaceType.blocking)
          : SpaceType.fillable;
    }

    if (!fluidState.isEmpty && world.collisionShapeEmpty(pos)) {
      return FluidHelper.convertToStill(toFill) == FluidHelper.convertToStill(fluidState.fluid) ? SpaceType.filled : SpaceType.blocking;
    }

    return canBeReplacedByFluid(world, pos, blockState) ? SpaceType.fillable : SpaceType.blocking;
  }

  /// `replaceBlock(world, pos, state)`: the old block drops its resources.
  void replaceBlock(FluidWorld world, Pos pos, BState state) {
    if (!state.isAir) world.dropResources(pos);
  }

  /// From `FlowingFluidBlock#isBlocked`.
  bool canBeReplacedByFluid(FluidWorld world, Pos pos, BState state) {
    final isDoor = world.hasTag(pos, 'minecraft:doors');
    if (!isDoor &&
        !world.hasTag(pos, 'minecraft:all_signs') &&
        state.key != 'minecraft:ladder' &&
        state.key != 'minecraft:sugar_cane' &&
        state.key != 'minecraft:bubble_column') {
      if (state.key != 'minecraft:nether_portal' &&
          state.key != 'minecraft:end_portal' &&
          state.key != 'minecraft:end_gateway' &&
          state.key != 'minecraft:structure_void') {
        return !world.isCollisionShapeFullBlock(pos);
      }
      return false;
    }
    return false;
  }

  /// `updatePostWaterlogging(state)`.
  BState updatePostWaterlogging(BState state) => state.has('lit') ? state.setFlag('lit', false) : state;

  @override
  void reset() {
    super.reset();
    queue.clear();
    infinityCheckFrontier.clear();
    infinityCheckVisited.clear();
  }
}

/// `FluidDrainingBehaviour.FluidBlockType`.
enum FluidBlockType { none, source, flowing }

class FluidDraining extends FluidManipulation {
  String? fluid;

  // Execution
  Set<Pos> validationSet = {};
  late final BinaryHeap<BlockPosEntry> queue = BinaryHeap<BlockPosEntry>(comparePositions);
  bool isValid = false;

  // Validation
  final List<BlockPosEntry> validationFrontier = [];
  final Set<Pos> validationVisited = {};
  Set<Pos> newValidationSet = {};

  FluidDraining(super.host);

  /// `pullNext(root, simulate)`: removes the next fluid block (or checks that there is one).
  bool pullNext(Pos root, {required bool simulate}) {
    if (frontier.isNotEmpty) return false;
    if (root != rootPos) {
      rebuildContext(root);
      return false;
    }

    if (counterpartActed) {
      counterpartActed = false;
      softReset(root);
      return false;
    }

    affectedArea ??= BlockBounds.fromCorners(root, root);

    final world = level;
    if (queue.isNotEmpty && !isValid) {
      rebuildContext(root);
      return false;
    }

    if (validationFrontier.isEmpty && queue.isNotEmpty && !simulate && revalidateIn == 0) revalidate(root);

    if (infinite) {
      host.award('hose_pulley');
      if (fluid != null && FluidHelper.isLava(fluid!)) host.award('hose_pulley_lava');
      playEffect(world, root, fluid, true);
      return true;
    }

    while (queue.isNotEmpty) {
      // Don't dequeue here, so we can decide not to dequeue a valid entry when simulating
      final currentPos = queue.first.pos;
      final blockState = world.stateAt(currentPos);
      var emptied = blockState;
      String? found;

      if (blockState.has('waterlogged') && blockState.flag('waterlogged')) {
        emptied = blockState.setFlag('waterlogged', false);
        found = FluidKeys.water;
      } else if (PipeBlocks.isLiquidBlock(blockState)) {
        emptied = BState.air;
        if (blockState.intValue('level') == 0) {
          found = FluidHelper.convertToStill(blockState.key);
        } else {
          affectedArea = affectedArea!.encapsulatePos(currentPos);
          world.setBlock(currentPos, emptied, quiet: true);
          queue.dequeue();
          if (queue.isEmpty) {
            isValid = checkValid(world, rootPos!);
            reset();
          }
          continue;
        }
      } else if (!world.fluidAt(currentPos).isEmpty && world.collisionShapeEmpty(currentPos)) {
        found = world.fluidAt(currentPos).fluid;
        emptied = BState.air;
      }

      fluid ??= found;
      if (fluid == null || found == null || FluidHelper.convertToStill(fluid!) != FluidHelper.convertToStill(found)) {
        queue.dequeue();
        if (queue.isEmpty) {
          isValid = checkValid(world, rootPos!);
          reset();
        }
        continue;
      }

      if (simulate) return true;

      playEffect(world, currentPos, found, true);
      host.award('hose_pulley');
      world.setBlock(currentPos, emptied, quiet: true);
      final above = currentPos.above;
      final stateAbove = world.stateAt(above);
      if (world.fluidAt(above).isEmpty && !stateAbove.isAir && !world.canSurvive(above)) {
        world.setBlock(above, BState.air, quiet: true);
      }

      affectedArea = affectedArea!.encapsulatePos(currentPos);
      queue.dequeue();

      if (queue.isEmpty) {
        isValid = checkValid(world, rootPos!);
        reset();
      } else if (!validationSet.contains(currentPos)) {
        reset();
      }
      return true;
    }

    if (rootPos == null) return false;
    if (isValid) rebuildContext(root);
    return false;
  }

  /// `softReset(root)`.
  void softReset(Pos root) {
    queue.clear();
    validationSet.clear();
    newValidationSet.clear();
    validationFrontier.clear();
    validationVisited.clear();
    visited.clear();
    infinite = false;
    setValidationTimer();
    frontier.add(BlockPosEntry(root, 0));
    host.sendData();
  }

  /// `checkValid(world, root)`: the root must connect to a source (going up flowing fluid).
  bool checkValid(FluidWorld world, Pos root) {
    var currentPos = root;
    for (var timeout = 1000; timeout > 0 && root != host.hostPos; timeout--) {
      final canPullFluidsFrom = fluidBlockTypeAt(world, currentPos);
      if (canPullFluidsFrom == FluidBlockType.flowing) {
        for (final d in Direction.values) {
          final side = currentPos.relative(d);
          if (fluidBlockTypeAt(world, side) == FluidBlockType.source) return true;
        }
        currentPos = currentPos.above;
        continue;
      }
      if (canPullFluidsFrom == FluidBlockType.source) return true;
      break;
    }
    return false;
  }

  /// `canPullFluidsFrom(blockState, pos)`.
  FluidBlockType fluidBlockTypeAt(FluidWorld world, Pos pos) {
    final blockState = world.stateAt(pos);
    if (blockState.has('waterlogged') && blockState.flag('waterlogged')) return FluidBlockType.source;
    if (PipeBlocks.isLiquidBlock(blockState)) {
      return blockState.intValue('level') == 0 ? FluidBlockType.source : FluidBlockType.flowing;
    }
    if (!world.fluidAt(pos).isEmpty && world.collisionShapeEmpty(pos)) return FluidBlockType.source;
    return FluidBlockType.none;
  }

  /// `read`: after a load from disk the search starts again.
  @override
  void read(Map<String, NbtValue> nbt) {
    super.read(nbt);
    if (affectedArea != null && rootPos != null) frontier.add(BlockPosEntry(rootPos!, 0));
  }

  /// `tick()`.
  void tick() {
    final root = rootPos;
    if (root != null && host.fluidWorld != null) isValid = checkValid(level, root);

    if (frontier.isNotEmpty) {
      continueSearch();
      return;
    }

    if (validationFrontier.isNotEmpty) {
      continueValidation();
      return;
    }

    if (revalidateIn > 0) revalidateIn--;
  }

  /// `rebuildContext(root)`.
  void rebuildContext(Pos root) {
    reset();
    rootPos = root;
    affectedArea = BlockBounds.fromCorners(root, root);
    if (isValid) frontier.add(BlockPosEntry(root, 0));
  }

  /// `revalidate(root)`.
  void revalidate(Pos root) {
    validationFrontier.clear();
    validationVisited.clear();
    newValidationSet.clear();
    validationFrontier.add(BlockPosEntry(root, 0));
    setValidationTimer();
  }

  void continueSearch() {
    try {
      fluid = search(fluid, frontier, visited, (e, d) {
        queue.enqueue(BlockPosEntry(e, d));
        validationSet.add(e);
      }, false);
    } on ChunkNotLoadedException {
      host.sendData();
      frontier.clear();
      visited.clear();
    }

    final maxBlocks = this.maxBlocks();
    if (visited.length >= maxBlocks && canDrainInfinitely(fluid) && queue.isNotEmpty) {
      infinite = true;
      final firstValid = queue.first.pos;
      frontier.clear();
      visited.clear();
      queue.clear();
      queue.enqueue(BlockPosEntry(firstValid, 0));
      host.sendData();
      return;
    }

    if (frontier.isNotEmpty) return;
    host.sendData();
    visited.clear();
  }

  void continueValidation() {
    try {
      search(fluid, validationFrontier, validationVisited, (e, d) => newValidationSet.add(e), false);
    } on ChunkNotLoadedException {
      validationFrontier.clear();
      validationVisited.clear();
      setLongValidationTimer();
      return;
    }

    final maxBlocks = this.maxBlocks();
    if (validationVisited.length >= maxBlocks && canDrainInfinitely(fluid)) {
      if (!infinite) reset();
      validationFrontier.clear();
      setLongValidationTimer();
      return;
    }

    if (validationFrontier.isNotEmpty) return;
    if (infinite) {
      reset();
      return;
    }

    validationSet = newValidationSet;
    newValidationSet = {};
    validationVisited.clear();
  }

  @override
  void reset() {
    super.reset();
    fluid = null;
    rootPos = null;
    queue.clear();
    validationSet.clear();
    newValidationSet.clear();
    validationFrontier.clear();
    validationVisited.clear();
    host.sendData();
  }

  bool get isSearching => frontier.isNotEmpty;

  /// `getDrainableFluid(rootPos)`.
  FStack getDrainableFluid(Pos rootPos) =>
      fluid == null || isSearching || !pullNext(rootPos, simulate: true) ? FStack.empty : FStack(fluid!, 1000);
}
