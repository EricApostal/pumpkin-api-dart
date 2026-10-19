// `PortableStorageInterfaceMovement`: the interface on a contraption looks for the stationary
// interface in front of it, stops the contraption while the two are connected and lets it go once
// the transfer is done.
import '../../../api/block_state.dart';
import '../../../common/common.dart';
import '../../../common/host_bridge.dart';
import '../../core/movement.dart';
import '../actor_runtime.dart';
import 'portable_storage_interface_block.dart';

/// `PortableStorageInterfaceMovement`.
final class PortableStorageInterfaceMovement extends MovementBehaviour {
  const PortableStorageInterfaceMovement();

  static const String workingPos = 'WorkingPos';
  static const String clientPrevPos = 'ClientPrevPos';

  @override
  Vec3 getActiveAreaOffset(MovementContext context) {
    final facing = context.state.dir('facing') ?? Direction.north;
    return facing.unitVec3 * 1.85;
  }

  @override
  bool disableBlockEntityRendering() => true;

  @override
  Future<void> visitNewPosition(MovementContext context, Pos pos) async {
    if (context.motion.length > 1 / 4) return;
    if (!findInterface(context, pos)) context.data.remove(workingPos);
  }

  @override
  Future<void> tick(MovementContext context) async {
    if (context.motion.length > 1 / 4) return;

    if (!context.data.contains(workingPos)) {
      if (context.stall) cancelStall(context);
      return;
    }

    final pos = context.data.getBlockPos(workingPos);
    final target = pos.center;
    final position = context.position;
    if (!context.stall &&
        position != null &&
        (target - position).length <
            (target - (position + context.motion)).length) {
      context.stall = true;
    }

    final facing = getCurrentFacingIfValid(context);
    if (facing == null) {
      reset(context);
      return;
    }

    final psi = getStationaryInterfaceAt(context, pos, context.state, facing);
    if (psi == null) {
      reset(context);
      return;
    }

    if (psi.connectedEntity == null) {
      psi.startTransferringTo(context.contraption, psi.distance);
    }

    final timerBelow = psi.transferTimer <= psiAnimation;
    psi.keepAlive = 2;
    if (context.stall && timerBelow) context.stall = false;
  }

  @override
  void cancelStall(MovementContext context) => reset(context);

  /// `reset`.
  void reset(MovementContext context) {
    context.data.remove(clientPrevPos);
    context.data.remove(workingPos);
    context.stall = false;
  }

  /// `findInterface`.
  bool findInterface(MovementContext context, Pos pos) {
    final facing = getCurrentFacingIfValid(context);
    if (facing == null) return false;

    final psi = findStationaryInterface(context, pos, context.state, facing);
    if (psi == null) return false;
    if (psi.isPowered()) return false;

    context.data.putBlockPos(workingPos, psi.pos.toPos());
    final position = context.position;
    if (position != null) {
      var diff = psi.pos.toPos().center - position;
      diff = VecHelper.project(diff, facing.unitVec3);
      psi.startTransferringTo(context.contraption, diff.length + 1.85 - 1);
    }
    return true;
  }

  /// `findStationaryInterface`: the interface at [pos] or one block further along [facing].
  PortableStorageInterfaceBlockEntity? findStationaryInterface(
    MovementContext context,
    Pos pos,
    BState state,
    Direction facing,
  ) {
    for (var i = 0; i < 2; i++) {
      final at = getStationaryInterfaceAt(
        context,
        pos.relative(facing, i),
        state,
        facing,
      );
      if (at != null) return at;
    }
    return null;
  }

  /// `getStationaryInterfaceAt`.
  PortableStorageInterfaceBlockEntity? getStationaryInterfaceAt(
    MovementContext context,
    Pos pos,
    BState state,
    Direction facing,
  ) {
    final be = actors?.blockEntities.typed<PortableStorageInterfaceBlockEntity>(
      context.worldId,
      pos.toBlockPos(),
    );
    if (be == null) return null;
    final blockState = context.level.stateAt(pos);
    if (blockState.key != state.key) return null;
    if (blockState.dir('facing') != facing.opposite) return null;
    if (be.isPowered()) return null;
    return be;
  }

  /// `getCurrentFacingIfValid`: the facing turned into the world, `null` if it is not axis aligned.
  Direction? getCurrentFacingIfValid(MovementContext context) {
    final facing = context.state.dir('facing') ?? Direction.north;
    final directionVec = context.rotation(facing.unitVec3);
    final nearest = Direction.nearest(
      directionVec.$1,
      directionVec.$2,
      directionVec.$3,
    );
    if ((directionVec - nearest.unitVec3).length > 1 / 2) return null;
    return nearest;
  }
}
