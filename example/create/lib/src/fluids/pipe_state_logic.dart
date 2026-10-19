// The neighbour dependent state of the pipe blocks (pure): `FluidPipeBlock.canConnectTo` and
// `updateBlockState`, and the placement preferences of the pump, the valve and the smart pipe.
import '../api/block_state.dart';
import '../common/direction.dart';
import '../common/pos.dart';
import 'fluid_propagator.dart';
import 'fluid_world.dart';
import 'pipe_blocks.dart';
import 'vanilla_fluid_targets.dart';

abstract final class PipeStateLogic {
  /// `FluidPipeBlock.canConnectTo(world, neighbourPos, neighbour, direction)`.
  static bool canConnectTo(FluidWorld world, Pos neighbourPos, BState neighbour, Direction direction) {
    if (FluidPropagator.hasFluidCapability(world, neighbourPos, direction.opposite)) return true;
    if (VanillaFluidTargets.canProvideFluidWithoutCapability(neighbour)) return true;

    final transport = world.pipeAt(neighbourPos);

    if (PipeBlocks.isPipe(neighbour)) {
      return !world.hasBracket(neighbourPos) || FluidPropagator.getStraightPipeAxis(neighbour) == direction.axis;
    }
    if (transport == null) return false;
    return transport.canHaveFlowToward(neighbour, direction.opposite);
  }

  /// `FluidPipeBlock.updateBlockState(state, preferredDirection, ignore, world, pos)`.
  static BState updateBlockState(BState stateIn, Direction preferredDirection, Direction? ignore, FluidWorld world, Pos pos) {
    if (world.hasBracket(pos)) return stateIn;

    var state = stateIn;
    final prevState = state;
    final prevStateSides = Direction.values.where((d) => prevState.flag(d.serializedName)).length;

    // Update sides that are not ignored
    for (final d in Direction.values) {
      if (d == ignore) continue;
      final shouldConnect = canConnectTo(world, pos.relative(d), world.stateAt(pos.relative(d)), d);
      state = state.setFlag(d.serializedName, shouldConnect);
    }

    // See if it has enough connections
    Direction? connectedDirection;
    for (final d in Direction.values) {
      if (PipeBlocks.isOpenAtSixWay(state, d)) {
        if (connectedDirection != null) return state;
        connectedDirection = d;
      }
    }

    // Add opposite end if only one connection
    if (connectedDirection != null) return state.setFlag(connectedDirection.opposite.serializedName, true);

    // If we can't connect to anything and weren't connected before, do nothing
    if (prevStateSides == 2) return prevState;

    // Use preferred
    return state.setFlag(preferredDirection.serializedName, true).setFlag(preferredDirection.opposite.serializedName, true);
  }

  /// `AxisPipeBlock.toRegularPipe`: the fluid pipe equivalent of a glass pipe.
  static BState toRegularPipe(FluidWorld world, Pos pos, BState glass, BState pipeDefault) {
    final side = Direction.fromAxisAndDirection(glass.axisOf('axis') ?? Axis.y, AxisDirection.positive);
    return updateBlockState(
      pipeDefault.setFlag(side.serializedName, true).setFlag(side.opposite.serializedName, true),
      side,
      null,
      world,
      pos,
    );
  }

  /// `PumpBlock.getStateForPlacement`: the facing the pump prefers next to pipes.
  static Direction? pumpPreferredFacing(FluidWorld level, Pos pos, Direction nearestLookingDirection, bool sneaking) {
    final targetDirection = sneaking ? nearestLookingDirection : nearestLookingDirection.opposite;
    Direction? bestConnectedDirection;
    var bestDistance = double.maxFinite;
    for (final d in Direction.values) {
      final adjPos = pos.relative(d);
      final adjState = level.stateAt(adjPos);
      if (!canConnectTo(level, adjPos, adjState, d)) continue;
      final dx = (d.stepX - targetDirection.stepX).toDouble();
      final dy = (d.stepY - targetDirection.stepY).toDouble();
      final dz = (d.stepZ - targetDirection.stepZ).toDouble();
      final distance = dx * dx + dy * dy + dz * dz;
      // distanceTo is the square root; the comparison is the same on the squares.
      if (distance > bestDistance) continue;
      bestDistance = distance;
      bestConnectedDirection = d;
    }
    if (bestConnectedDirection != null && bestConnectedDirection.axis != targetDirection.axis && !sneaking) {
      return bestConnectedDirection;
    }
    return null;
  }

  /// `SmartFluidPipeBlock.getStateForPlacement` preferred axis: the axis of the neighbouring pipes
  /// when they all agree on one.
  static Axis? smartPipePreferredAxis(FluidWorld world, Pos pos) {
    Axis? preferred;
    for (final side in Direction.values) {
      final offset = pos.relative(side);
      if (!canConnectTo(world, offset, world.stateAt(offset), side)) continue;
      if (preferred != null && preferred != side.axis) {
        preferred = null;
        break;
      }
      preferred = side.axis;
    }
    return preferred;
  }

  /// `HosePulleyBlock.getPreferredHorizontalFacing` (the pipe side part): the horizontal side
  /// with a pipe to connect to, `null` if there is none or several axes.
  static Direction? hosePulleyPreferredSide(FluidWorld world, Pos pos) {
    Direction? preferredSide;
    for (final facing in Direction.horizontals) {
      final p = pos.relative(facing);
      final state = world.stateAt(p);
      if (canConnectTo(world, p, state, facing)) {
        if (preferredSide != null && preferredSide.axis != facing.axis) {
          preferredSide = null;
          break;
        }
        preferredSide = facing;
      }
    }
    return preferredSide?.opposite;
  }
}
