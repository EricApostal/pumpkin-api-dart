// `SeatMovementBehaviour`: remembers which seat an actor is and lets a rider off when the seat
// passes over solid ground.
import '../../../common/common.dart';
import '../../core/movement.dart';
import '../../entity/contraption_entity.dart';

/// `SeatMovementBehaviour`.
final class SeatMovementBehaviour extends MovementBehaviour {
  const SeatMovementBehaviour();

  @override
  void startMoving(MovementContext context) {
    super.startMoving(context);
    final index = context.contraption.getSeats().indexOf(context.localPos);
    context.data.putInt('SeatIndex', index);
  }

  @override
  Future<void> visitNewPosition(MovementContext context, Pos pos) async {
    await super.visitNewPosition(context, pos);

    final entity = context.contraption.entity;
    if (entity is! AbstractContraptionEntity) return;
    final index = context.data.getInt('SeatIndex', 0);
    if (index == -1) return;

    final seatMapping = context.contraption.getSeatMapping();
    final state = context.level.stateAt(pos);
    final slab = state.key.endsWith('_slab') && state['type'] == 'bottom';
    final solid = context.level.isCollisionShapeFullBlock(pos) || slab;

    // Occupied?
    if (!seatMapping.values.contains(index)) return;
    if (!solid) return;

    ContraptionPassengerRef? toDismount;
    for (final entry in seatMapping.entries) {
      if (entry.value != index) continue;
      for (final passenger in entity.host.passengers) {
        if (passenger.uuid == entry.key) toDismount = passenger;
      }
    }
    if (toDismount == null) return;

    entity.host.removePassenger(toDismount);
    toDismount.teleportTo(pos.center + (0.0, slab ? .5 : 1.0, 0.0));
    toDismount.setPersistentData('ContraptionDismountLocation', null);
  }
}
