// How a mechanical pump distributes pressure over the pipes on one of its sides,
// its kinetic rules and the wrench flip (pure): `PumpBlockEntity.distributePressureTo`,
// `PumpBlock` and its helpers.
import '../api/block_state.dart';
import '../common/data.dart';
import '../common/direction.dart';
import '../common/pos.dart';
import '../kinetics/block_defs.dart';
import '../kinetics/geometry.dart';
import 'fluid_propagator.dart';
import 'fluid_world.dart';
import 'pipe_blocks.dart';

class PipeGraphEntry {
  final int distance;
  final Map<Direction, bool> faces = {};

  PipeGraphEntry(this.distance);
}

/// `PumpBlock`: an `ICogWheel` (a small cog) with no shaft faces. It rotates on
/// its facing axis and is driven by a cogwheel beside it; Java's `PumpBlock`
/// does not override `hasShaftTowards`, so shafts do not connect to it.
class PumpDef extends KineticBlockDef {
  const PumpDef();

  @override
  KAxis rotationAxis(KState state) => (state.dirOf('facing') ?? Dir.north).axis;

  @override
  bool hasShaftTowards(KState state, Dir face) => false;

  @override
  bool get isSmallCog => true;
}

/// `PumpBlock.getRotatedBlockState`: the wrench always flips the pump's facing,
/// whichever face was clicked (the default rotation would only cycle it).
BState pumpWrenchState(BState state) {
  final facing = state.dir('facing');
  if (facing == null) return state;
  return state.setDir('facing', facing.opposite);
}

abstract final class PumpLogic {
  /// `distributePressureTo(side)`: [pumpPos] faces [front]; its pressure is the absolute rotation
  /// [speed]. [isPullingOnSide] is `isPullingOnSide(isFront(side))` of the pump.
  static void distributePressureTo(
    FluidWorld level,
    Pos pumpPos,
    double speed,
    Direction side, {
    required bool pull,
  }) {
    if (speed == 0) return;

    final start = BlockFace(pumpPos, side);
    final targets = <BlockFace>{};
    final pipeGraph = <Pos, PipeGraphEntry>{};

    if (!pull) FluidPropagator.resetAffectedFluidNetworks(level, pumpPos, side.opposite);

    if (!hasReachedValidEndpoint(level, start, pull)) {
      pipeGraph.putIfAbsent(pumpPos, () => PipeGraphEntry(0)).faces[side] = pull;
      pipeGraph.putIfAbsent(start.connectedPos, () => PipeGraphEntry(1)).faces[side.opposite] = !pull;

      final frontier = <(int, Pos)>[(1, start.connectedPos)];
      final visited = <Pos>{};
      final maxDistance = FluidPropagator.getPumpRange(level);

      while (frontier.isNotEmpty) {
        final entry = frontier.removeAt(0);
        final distance = entry.$1;
        final currentPos = entry.$2;

        if (!level.isLoaded(currentPos)) continue;
        if (visited.contains(currentPos)) continue;
        visited.add(currentPos);

        final currentState = level.stateAt(currentPos);
        final pipe = FluidPropagator.getPipe(level, currentPos);
        if (pipe == null) continue;

        for (final face in FluidPropagator.getPipeConnections(currentState, pipe)) {
          final blockFace = BlockFace(currentPos, face);
          final connectedPos = blockFace.connectedPos;

          if (!level.isLoaded(connectedPos)) continue;
          if (blockFace.isEquivalent(start)) continue;
          if (hasReachedValidEndpoint(level, blockFace, pull)) {
            pipeGraph.putIfAbsent(currentPos, () => PipeGraphEntry(distance)).faces[face] = pull;
            targets.add(blockFace);
            continue;
          }

          final pipeBehaviour = FluidPropagator.getPipe(level, connectedPos);
          if (pipeBehaviour == null) continue;
          if (pipeBehaviour.isPumpNode) continue;
          if (visited.contains(connectedPos)) continue;
          if (distance + 1 >= maxDistance) {
            pipeGraph.putIfAbsent(currentPos, () => PipeGraphEntry(distance)).faces[face] = pull;
            targets.add(blockFace);
            continue;
          }

          pipeGraph.putIfAbsent(currentPos, () => PipeGraphEntry(distance)).faces[face] = pull;
          pipeGraph.putIfAbsent(connectedPos, () => PipeGraphEntry(distance + 1)).faces[face.opposite] = !pull;
          frontier.add((distance + 1, connectedPos));
        }
      }
    }

    // DFS
    final validFaces = <int, Set<BlockFace>>{};
    searchForEndpointRecursively(pipeGraph, targets, validFaces, BlockFace(start.pos, start.oppositeFace), pull);

    for (final set in validFaces.values) {
      final parallelBranches = set.length - 1 < 1 ? 1 : set.length - 1;
      for (final face in set) {
        final pipePos = face.pos;
        final pipeSide = face.face;
        if (pipePos == pumpPos) continue;

        final inbound = pipeGraph[pipePos]!.faces[pipeSide]!;
        final pipeBehaviour = FluidPropagator.getPipe(level, pipePos);
        if (pipeBehaviour == null) continue;
        // `Math.abs(getSpeed())`: a pump turning backwards pushes just as hard.
        pipeBehaviour.addPressure(
          pipeSide,
          inbound,
          speed.abs() / parallelBranches,
        );
      }
    }
  }

  /// `searchForEndpointRecursively`.
  static bool searchForEndpointRecursively(
    Map<Pos, PipeGraphEntry> pipeGraph,
    Set<BlockFace> targets,
    Map<int, Set<BlockFace>> validFaces,
    BlockFace currentFace,
    bool pull,
  ) {
    final currentPos = currentFace.pos;
    final entry = pipeGraph[currentPos];
    if (entry == null) return false;

    final distance = entry.distance;
    var atLeastOneBranchSuccessful = false;

    for (final nextFacing in Direction.values) {
      if (nextFacing == currentFace.face) continue;
      final map = entry.faces;
      if (!map.containsKey(nextFacing)) continue;

      final localTarget = BlockFace(currentPos, nextFacing);
      if (targets.contains(localTarget)) {
        validFaces.putIfAbsent(distance, () => <BlockFace>{}).add(localTarget);
        atLeastOneBranchSuccessful = true;
        continue;
      }

      if (map[nextFacing] != pull) continue;
      if (!searchForEndpointRecursively(
        pipeGraph,
        targets,
        validFaces,
        BlockFace(currentPos.relative(nextFacing), nextFacing.opposite),
        pull,
      )) {
        continue;
      }

      validFaces.putIfAbsent(distance, () => <BlockFace>{}).add(localTarget);
      atLeastOneBranchSuccessful = true;
    }

    if (atLeastOneBranchSuccessful) validFaces.putIfAbsent(distance, () => <BlockFace>{}).add(currentFace);
    return atLeastOneBranchSuccessful;
  }

  /// `hasReachedValidEndpoint(world, blockFace, pull)`.
  static bool hasReachedValidEndpoint(FluidWorld world, BlockFace blockFace, bool pull) {
    final connectedPos = blockFace.connectedPos;
    final connectedState = world.stateAt(connectedPos);
    final face = blockFace.face;

    // facing a pump
    final pump = world.pumpAt(connectedPos);
    if (PipeBlocks.isPump(connectedState) && PipeBlocks.pumpFacing(connectedState).axis == face.axis && pump != null) {
      return pump.isPullingOnSide(pump.isFront(blockFace.oppositeFace)) != pull;
    }

    // other pipe, no endpoint
    final pipe = FluidPropagator.getPipe(world, connectedPos);
    if (pipe != null && pipe.canHaveFlowToward(connectedState, blockFace.oppositeFace)) return false;

    // fluid handler endpoint
    if (world.hasBlockEntity(connectedPos) && world.fluidCapability(connectedPos, face.opposite) != null) return true;

    // open endpoint
    return FluidPropagator.isOpenEnd(world, blockFace.pos, face);
  }
}
