// `FluidPropagator` (pure): the pipe network updates. When a pipe changes, the pressure of every
// pipe connected to it is wiped and the pumps that reach it distribute theirs again.
import '../api/block_state.dart';
import '../common/direction.dart';
import '../common/pos.dart';
import 'fluid_world.dart';
import 'pipe_blocks.dart';
import 'vanilla_fluid_targets.dart';

abstract final class FluidPropagator {
  /// `getSharedTriggers()`: the advancements the pipe blocks can award.
  static const List<String> sharedTriggers = ['water_supply', 'cross_streams', 'honey_drain'];

  /// `propagateChangedPipe(world, pipePos, pipeState)`.
  static void propagateChangedPipe(FluidWorld world, Pos pipePos, BState pipeState) {
    final frontier = <(int, Pos)>[(0, pipePos)];
    final visited = <Pos>{};
    final discoveredPumps = <(PumpPeer, Direction)>[];

    // Visit all connected pumps to update their network
    while (frontier.isNotEmpty) {
      final pair = frontier.removeAt(0);
      final currentPos = pair.$2;
      if (visited.contains(currentPos)) continue;
      visited.add(currentPos);

      final currentState = currentPos == pipePos ? pipeState : world.stateAt(currentPos);
      final pipe = getPipe(world, currentPos);
      if (pipe == null) continue;
      pipe.wipePressure();

      for (final direction in getPipeConnections(currentState, pipe)) {
        final target = currentPos.relative(direction);
        if (!world.isLoaded(target)) continue;

        final targetState = world.stateAt(target);
        final pump = world.pumpAt(target);
        if (pump != null) {
          if (!PipeBlocks.isPump(targetState) || PipeBlocks.pumpFacing(targetState).axis != direction.axis) continue;
          if (!discoveredPumps.any((e) => identical(e.$1, pump) && e.$2 == direction.opposite)) {
            discoveredPumps.add((pump, direction.opposite));
          }
          continue;
        }

        if (visited.contains(target)) continue;
        final targetPipe = getPipe(world, target);
        if (targetPipe == null) continue;
        final distance = pair.$1;
        if (distance >= getPumpRange(world) && !targetPipe.hasAnyPressure) continue;
        if (targetPipe.canHaveFlowToward(targetState, direction.opposite)) frontier.add((distance + 1, target));
      }
    }

    for (final p in discoveredPumps) {
      p.$1.updatePipesOnSide(p.$2);
    }
  }

  /// `resetAffectedFluidNetworks(world, start, side)`.
  static void resetAffectedFluidNetworks(FluidWorld world, Pos start, Direction side) {
    final frontier = <Pos>[start];
    final visited = <Pos>{};

    while (frontier.isNotEmpty) {
      final pos = frontier.removeAt(0);
      if (visited.contains(pos)) continue;
      visited.add(pos);

      final pipe = getPipe(world, pos);
      if (pipe == null) continue;

      for (final d in Direction.values) {
        if (pos == start && d != side) continue;
        final target = pos.relative(d);
        if (visited.contains(target)) continue;

        final connection = pipe.getConnection(d);
        if (connection == null) continue;
        if (!connection.hasFlow) continue;

        final flow = connection.flow!;
        if (!flow.inbound) continue;

        connection.resetNetwork();
        frontier.add(target);
      }
    }
  }

  /// `validateNeighbourChange(state, world, pos, otherBlock, neighborPos, isMoving)`: the side of
  /// [pos] the changed neighbour is on, or `null` when the change does not matter.
  static Direction? validateNeighbourChange(BState state, FluidWorld world, Pos pos, Pos neighborPos) {
    final other = world.stateAt(neighborPos);
    if (PipeBlocks.isPipe(other)) return null;
    if (PipeBlocks.isAxisPipe(other)) return null;
    if (PipeBlocks.isPump(other)) return null;
    if (PipeBlocks.isLiquidBlock(other)) return null;
    if (getStraightPipeAxis(state) == null && !PipeBlocks.isEncased(state)) return null;

    for (final d in Direction.values) {
      if (pos.relative(d) != neighborPos) continue;
      return d;
    }
    return null;
  }

  /// `getPipe(reader, pos)`.
  static PipeNodeView? getPipe(FluidWorld world, Pos pos) => world.pipeAt(pos);

  /// `isOpenEnd(reader, pos, side)`.
  static bool isOpenEnd(FluidWorld reader, Pos pos, Direction side) {
    final connectedPos = pos.relative(side);
    final connectedState = reader.stateAt(connectedPos);
    final pipe = getPipe(reader, connectedPos);

    if (pipe != null && pipe.canHaveFlowToward(connectedState, side.opposite)) return false;
    if (PipeBlocks.isPump(connectedState) && PipeBlocks.pumpFacing(connectedState).axis == side.axis) return false;
    if (VanillaFluidTargets.canProvideFluidWithoutCapability(connectedState)) return true;
    // `BlockHelper.hasBlockSolidSide`: not leaves, and a sturdy face.
    if (_hasBlockSolidSide(reader, connectedPos, connectedState, side.opposite) &&
        !reader.hasTag(connectedPos, 'create:fan_transparent')) {
      return false;
    }
    if (hasFluidCapability(reader, connectedPos, side.opposite)) return false;
    if (!(reader.canBeReplaced(connectedPos) && !reader.isUnbreakable(connectedPos)) && !connectedState.has('waterlogged')) {
      return false;
    }
    return true;
  }

  static bool _hasBlockSolidSide(FluidWorld world, Pos pos, BState state, Direction side) =>
      !world.hasTag(pos, 'minecraft:leaves') && world.isFaceSturdy(pos, side);

  /// `getPipeConnections(state, pipe)`.
  static List<Direction> getPipeConnections(BState state, PipeNodeView pipe) => [
    for (final d in Direction.values)
      if (pipe.canHaveFlowToward(state, d)) d,
  ];

  /// `getPumpRange()`.
  static int getPumpRange(FluidWorld world) => world.config.mechanicalPumpRange;

  /// `hasFluidCapability(world, pos, side)`.
  static bool hasFluidCapability(FluidWorld world, Pos pos, Direction side) =>
      world.hasBlockEntity(pos) && world.fluidCapability(pos, side) != null;

  /// `getStraightPipeAxis(state)`.
  static Axis? getStraightPipeAxis(BState state) => PipeBlocks.straightPipeAxis(state);
}
