// `SlidingDoorMovementBehaviour`: a sliding door that is carried by a contraption opens while the
// contraption stands still at a station or an elevator floor, and closes again when it moves on.
//
// Java: `content/decoration/slidingDoor/SlidingDoorMovementBehaviour.java`. The client half of
// Java's `tick` (the lerped animation and the local closing sound) is not needed here; the server
// opens and closes the carried door and the matching door left in the world.
import '../api/contraptions.dart';
import '../common/common.dart';
import '../common/host_bridge.dart';
import '../contraptions/elevator/elevator_column.dart';
import '../contraptions/elevator/elevator_contraption.dart';
import '../trains/manager/create.dart';
import 'door.dart';
import 'runtime.dart';
import 'sliding_doors.dart';

/// `SlidingDoorMovementBehaviour`.
final class SlidingDoorMovementBehaviour extends MovementBehaviour {
  const SlidingDoorMovementBehaviour();

  /// `mustTickWhileDisabled`: a disabled door still has to close.
  @override
  bool mustTickWhileDisabled() => true;

  @override
  Future<void> tick(MovementContext context) async {
    final info = context.contraption.blocks[context.localPos];
    if (info == null) return;
    final open = info.state.flag('open');
    await _tickOpen(context, open);
  }

  /// `tickOpen`: follows the door control the contraption is standing at.
  Future<void> _tickOpen(MovementContext context, bool currentlyOpen) async {
    final shouldOpen = _shouldOpen(context);
    if (!_shouldUpdate(context, shouldOpen)) return;
    if (currentlyOpen == shouldOpen) return;

    final pos = context.localPos;
    final info = context.contraption.blocks[pos];
    if (info == null || !info.state.has('open')) return;
    _toggleDoor(context, pos);

    // The door that was left in the world at the contraption's position follows as well.
    final position = context.position;
    if (position == null) return;
    final inWorldDoor = _blockPosOf(position).relative(_doorFacing(context));
    final inWorldState = context.level.stateAt(inWorldDoor);
    if (!inWorldState.has('open')) return;
    if (inWorldState.dir('facing')?.axis != _doorFacing(context).axis) return;
    final action = slidingDoorSetOpen(
      context.level,
      inWorldDoor,
      inWorldState,
      shouldOpen,
    );
    for (final (p, s) in action.changes) {
      await context.level.placeBlock(p, s);
    }
  }

  /// `toggleDoor`: flips both halves of the carried door and rebuilds the colliders.
  void _toggleDoor(MovementContext context, Pos pos) {
    final contraption = context.contraption;
    final info = contraption.blocks[pos];
    if (info == null) return;
    final newState = info.state.cycleFlag('open');
    _setContraptionBlock(
      contraption,
      pos,
      StructureBlockInfo(info.pos, newState, info.nbt),
    );

    final otherPos = newState['half'] == 'lower' ? pos.above : pos.below;
    final other = contraption.blocks[otherPos];
    if (other == null || !other.state.has('open')) return;
    final otherNewState = other.state.cycleFlag('open');
    _setContraptionBlock(
      contraption,
      otherPos,
      StructureBlockInfo(other.pos, otherNewState, other.nbt),
    );
    contraption.invalidateColliders();
  }

  /// `contraption.entity.setBlock`: without an entity (a structure that is not moving yet) the
  /// structure itself is updated so the next tick sees the new state.
  void _setContraptionBlock(
    Contraption contraption,
    Pos pos,
    StructureBlockInfo info,
  ) {
    final entity = contraption.entity;
    if (entity != null) {
      entity.setBlock(pos, info);
    } else {
      contraption.blocks[pos] = info;
    }
  }

  /// `shouldUpdate`: only when the target state changed; the first movement is recorded silently.
  bool _shouldUpdate(MovementContext context, bool shouldOpen) {
    if (context.firstMovement && shouldOpen) return false;
    if (!context.data.contains('Open')) {
      context.data.putBool('Open', shouldOpen);
      return true;
    }
    final wasOpen = context.data.getBool('Open');
    context.data.putBool('Open', shouldOpen);
    return wasOpen != shouldOpen;
  }

  /// `shouldOpen`: only while the contraption stands still, and only when a door control at the
  /// current station or elevator floor matches the door's side.
  bool _shouldOpen(MovementContext context) {
    if (context.disabled) return false;
    final contraption = context.contraption;
    final canOpen =
        (context.motion.length < 1 / 128 && !contraption.stalled) ||
        (contraption is ElevatorContraption && contraption.arrived);
    if (!canOpen) {
      context.temporaryData = null;
      return false;
    }

    final cached = context.temporaryData;
    if (cached is DoorControlBehaviour) {
      if (!cached.owner.removed) return _shouldOpenAt(cached, context);
      context.temporaryData = null;
    }

    final controls =
        _elevatorDoorControl(context) ?? _trainDoorControl(context);
    if (controls == null) return false;
    context.temporaryData = controls;
    return _shouldOpenAt(controls, context);
  }

  /// `shouldOpenAt`.
  bool _shouldOpenAt(DoorControlBehaviour controller, MovementContext context) {
    if (controller.mode == DoorControl.all) return true;
    if (controller.mode == DoorControl.none) return false;
    return controller.mode.matches(_doorFacing(context));
  }

  /// `getElevatorDoorControl`: the contact at the elevator's current target floor.
  DoorControlBehaviour? _elevatorDoorControl(MovementContext context) {
    final contraption = context.contraption;
    if (contraption is! ElevatorContraption) return null;
    final targetY = contraption.getCurrentTargetY();
    if (targetY == null) return null;
    final coords = contraption.getGlobalColumn();
    if (coords == null) return null;
    final column = ElevatorColumn.get(context.worldId, coords);
    if (column == null) return null;
    return _doorControlAt(context.worldId, column.contactAt(targetY));
  }

  /// `getTrainStationDoorControl`: the station the train carrying this contraption waits at.
  DoorControlBehaviour? _trainDoorControl(MovementContext context) {
    final entityId = context.contraption.entity?.entityId;
    if (entityId == null) return null;
    for (final train in Create.RAILWAYS.trains.values) {
      for (final carriage in train.carriages) {
        for (final dimensional in carriage.dimensionalEntities) {
          if (dimensional.entity?.id != entityId) continue;
          final station = train.getCurrentStation();
          if (station == null) return null;
          final pos = station.getBlockEntityPos();
          if (pos == null) return null;
          // `getBlockEntityDimension()` is a dimension key; `_doorControlAt` keys the block
          // entity store, which is keyed by the world id. `Worlds.byId` resolves both strings.
          final stationWorldId =
              DecorationHost.rt.ctx.worlds.worldIdOf(station.getBlockEntityDimension()) ??
              station.getBlockEntityDimension();
          return _doorControlAt(stationWorldId, pos);
        }
      }
    }
    return null;
  }

  /// `BlockEntityBehaviour.get(level, pos, DoorControlBehaviour.TYPE)`.
  DoorControlBehaviour? _doorControlAt(String worldId, Pos pos) =>
      DecorationHost.rt.store
          .at(worldId, pos.toBlockPos())
          ?.getBehaviour<DoorControlBehaviour>();

  /// `getDoorFacing`: the door's facing rotated into the world by the contraption's rotation,
  /// flipped when the door sits on the side of the contraption that faces away from its centre.
  Direction _doorFacing(MovementContext context) {
    final stateFacing = context.state.dir('facing') ?? Direction.north;
    var originalFacing = stateFacing.axis.positive;
    final center = context.contraption.bounds?.center ?? vec3Zero;
    final localCenter = context.localPos.center;
    final diff = (
      localCenter.$1 - stateFacing.stepX * .45 - center.$1,
      localCenter.$2 - stateFacing.stepY * .45 - center.$2,
      localCenter.$3 - stateFacing.stepZ * .45 - center.$3,
    );
    if (originalFacing.axis.choose(diff.$1, diff.$2, diff.$3) < 0) {
      originalFacing = originalFacing.opposite;
    }
    final rotated = context.rotation(originalFacing.unitVec3);
    return Direction.nearest(rotated.$1, rotated.$2, rotated.$3);
  }
}

/// `BlockPos.containing(Vec3)`.
Pos _blockPosOf(Vec3 v) => (v.$1.floor(), v.$2.floor(), v.$3.floor());

/// Registers the behaviour for every sliding door.
void registerSlidingDoorMovementBehaviour() {
  MovementBehaviours.registerAll(
    slidingDoorKeys,
    const SlidingDoorMovementBehaviour(),
  );
}
